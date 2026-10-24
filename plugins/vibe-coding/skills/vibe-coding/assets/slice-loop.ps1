#Requires -Version 7
<#
.SYNOPSIS
Builds the open round slice by slice, each slice in a fresh headless Claude session, then closes the round.
Stops for plan approval unless -Yes; stops on NEEDS-DECISION, red tests or a blocked slice.

.EXAMPLE
pwsh .claude/scripts/slice-loop.ps1                  # ask for every plan
pwsh .claude/scripts/slice-loop.ps1 -Yes             # approve plans without asking
pwsh .claude/scripts/slice-loop.ps1 -Parallel        # build ready slices side by side (experimental)
pwsh .claude/scripts/slice-loop.ps1 -DryRun          # only print the slices that are ready now
pwsh .claude/scripts/slice-loop.ps1 -MaxSlices 3     # stop after 3 built slices if slices are left (exit 0; run again to continue)
Env: SLICE_PERMISSION_MODE (default: auto) – passed to claude --permission-mode.
#>
param(
    [switch]$Yes,
    [switch]$Parallel,
    [switch]$DryRun,
    [string]$MaxSlices
)
$ErrorActionPreference = 'Stop'

$SlicesFile = 'work/_slices.json'
$ChecklistFile = 'work/checklist.md'
$RoundsDir = 'work/rounds'
$LogDir = '.slice-loop'
$PermissionMode = if ($env:SLICE_PERMISSION_MODE) { $env:SLICE_PERMISSION_MODE } else { 'auto' }
$Usage = 'use -Yes, -Parallel, -DryRun, -MaxSlices N'
$SliceCap = 0   # 0 = no cap
$Built = 0

function Stop-Loop([string]$Message) {
    [Console]::Error.WriteLine("slice-loop: $Message")
    exit 1
}

function Get-Slices {
    Get-Content $SlicesFile -Raw -Encoding utf8 | ConvertFrom-Json | ForEach-Object {
        [pscustomobject]@{ Nr = $_.nr; Deps = @([regex]::Matches([string]$_.deps, '\d{2,}') | ForEach-Object Value) }
    }
}

# A slice is done when its checklist row has at least one ☑ and no ☐.
function Test-Done([string]$Nr) {
    $row = Get-Content $ChecklistFile -Encoding utf8 | Where-Object { $_ -match "^\|\s*$Nr(\D|$)" } | Select-Object -First 1
    return [bool]$row -and $row.Contains('☑') -and -not $row.Contains('☐')
}

function Get-ReadySlices {
    foreach ($slice in Get-Slices) {
        if (Test-Done $slice.Nr) { continue }
        $blocked = @($slice.Deps | Where-Object { -not (Test-Done $_) }).Count -gt 0
        if (-not $blocked) { $slice.Nr }
    }
}

function Test-AllDone { -not @(Get-Slices | Where-Object { -not (Test-Done $_.Nr) }) }

function Get-OpenCount { @(Get-Slices | Where-Object { -not (Test-Done $_.Nr) }).Count }

# Id (R01, R02 …) of the first round record in $RoundsDir whose first line is "Status: open"; nothing if none is open.
function Get-OpenRound {
    $file = Get-ChildItem -Path $RoundsDir -Filter '*.md' -File -ErrorAction SilentlyContinue | Sort-Object Name |
        Where-Object { (Get-Content $_.FullName -TotalCount 1 -Encoding utf8) -ceq 'Status: open' } |
        Select-Object -First 1
    if ($file) { return [regex]::Match($file.Name, '^R\d+').Value }
}

# Runs one claude turn; output goes to the log and is returned for marker parsing.
function Invoke-ClaudeTurn([string]$Log, [string[]]$Arguments) {
    $output = & $script:ClaudeExe -p --permission-mode $PermissionMode @Arguments 2>&1 | Out-String
    Add-Content -Path $Log -Value $output -Encoding utf8
    if ($LASTEXITCODE -ne 0) { Stop-Loop "claude exited with $LASTEXITCODE – see $Log" }
    return $output
}

# Always returns an array (the leading comma stops PowerShell from unrolling a single line).
function Get-MarkerLines([string]$Output, [string]$Marker) {
    return , [string[]]@($Output -split "`r?`n" | Where-Object { $_.StartsWith($Marker) })
}

# Plans one slice and waits for approval. Returns the message for the build turn.
function Request-Plan([string]$Nr, [string]$Session, [string]$Log) {
    Write-Host "[slice $Nr] planning (session $Session, log $Log)"
    $output = Invoke-ClaudeTurn $Log @('--session-id', $Session, "/slice $Nr plan auto")
    $approval = "Approved. Build slice $Nr and close it (auto)."
    while ($true) {
        $plan = Get-MarkerLines $output 'PLAN:'
        if (-not $plan) { Stop-Loop "slice ${Nr}: no PLAN line – see $Log" }
        $decisions = Get-MarkerLines $output 'NEEDS-DECISION:'
        Write-Host "[slice $Nr] $($plan[-1])"
        if ($Yes -and -not $decisions) { return $approval }
        $decisions | ForEach-Object { Write-Host $_ }
        if ([Console]::IsInputRedirected) { Stop-Loop "slice ${Nr}: approval needs a terminal – see $Log" }
        $answer = Read-Host "[slice $Nr] Enter = approve, text = change request / answers, q = stop"
        if ($answer -eq 'q') { Stop-Loop "stopped by user before building slice $Nr" }
        if (-not $answer) { return $approval }
        if ($decisions) { return "Approved with these answers: $answer. Build slice $Nr and close it (auto)." }
        $output = Invoke-ClaudeTurn $Log @('--resume', $Session,
            "Change request: $answer. Revise the plan, save it and end again with the PLAN line (auto).")
    }
}

function Get-BuildMessage([string]$Approval) {
    if (-not $Parallel) { return $Approval }
    return "$Approval Other slices are built in parallel: if git is locked or the integration branch moved, wait and retry; in conflicts keep every tick in work/checklist.md."
}

function Assert-SliceDone([string]$Nr, [string]$Output, [string]$Log) {
    if (-not ((Get-MarkerLines $Output 'SLICE-DONE:') -cmatch "^SLICE-DONE: $Nr(\D|$)")) {
        $open = Get-MarkerLines $Output 'SLICE-OPEN:'
        Stop-Loop "slice $Nr not finished: $(if ($open) { $open[-1] } else { 'no SLICE-DONE line' }) – see $Log"
    }
    if (-not (Test-Done $Nr)) { Stop-Loop "slice $Nr reported done but is not ticked in $ChecklistFile – check it before running again" }
    Write-Host "[slice $Nr] done"
}

function Invoke-Round {
    $ready = @(Get-ReadySlices)
    if (-not $ready) { Stop-Loop "no slice is ready – check $ChecklistFile (/slice status)" }
    if (-not $Parallel) { $ready = @($ready[0]) }
    if ($SliceCap -gt 0) { $ready = @($ready | Select-Object -First ($SliceCap - $Built)) }
    $runs = foreach ($nr in $ready) {
        $session = [guid]::NewGuid().ToString()
        $log = Join-Path $LogDir "slice-$nr-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
        [pscustomobject]@{ Nr = $nr; Session = $session; Log = $log; Message = Get-BuildMessage (Request-Plan $nr $session $log) }
    }
    if (-not $Parallel) {
        $run = $runs[0]
        Write-Host "[slice $($run.Nr)] building – this can take a while (log $($run.Log))"
        Assert-SliceDone $run.Nr (Invoke-ClaudeTurn $run.Log @('--resume', $run.Session, $run.Message)) $run.Log
        $script:Built++
        return
    }
    # Thread jobs run in this process; Start-Job's child processes hung on Linux CI runners.
    $jobs = foreach ($run in $runs) {
        Write-Host "[slice $($run.Nr)] building in parallel (log $($run.Log))"
        Start-ThreadJob -ArgumentList $script:ClaudeExe, (Get-Location).Path, $run.Session, $run.Message, $PermissionMode -ScriptBlock {
            param($Exe, $Directory, $Session, $Message, $Mode)
            Set-Location $Directory
            & $Exe -p --permission-mode $Mode --resume $Session $Message 2>&1 | Out-String
        }
    }
    for ($i = 0; $i -lt $runs.Count; $i++) {
        $output = Receive-Job -Job $jobs[$i] -Wait -AutoRemoveJob
        Add-Content -Path $runs[$i].Log -Value $output -Encoding utf8
        Assert-SliceDone $runs[$i].Nr $output $runs[$i].Log
    }
    $script:Built += $runs.Count
}

# Closes the round in one more fresh session and prints its ROUND-DONE line.
function Close-Round {
    $log = Join-Path $LogDir "close-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    Write-Host "[round $OpenRound] all slices done – closing the round (log $log)"
    $output = Invoke-ClaudeTurn $log @('--session-id', [guid]::NewGuid().ToString(), '/slice close auto')
    $done = Get-MarkerLines $output 'ROUND-DONE:'
    if (-not $done) {
        $open = Get-MarkerLines $output 'ROUND-OPEN:'
        Stop-Loop "round $OpenRound not closed: $(if ($open) { $open[-1] } else { 'no ROUND-DONE line' }) – see $log"
    }
    Write-Host $done[-1]
    Write-Host "Round closed. Next: test with the manual test list in $RoundsDir/, then start the next round with the vibe-coding skill."
}

if ($PSBoundParameters.ContainsKey('MaxSlices') -and -not ([int]::TryParse($MaxSlices, [ref]$SliceCap) -and $SliceCap -gt 0)) {
    Stop-Loop "-MaxSlices needs a positive integer ($Usage)"
}
if (-not ((Test-Path $SlicesFile) -and (Test-Path $ChecklistFile))) {
    Stop-Loop "run from the repo root (needs $SlicesFile and $ChecklistFile)"
}
if ($DryRun) { Get-ReadySlices; exit 0 }
$OpenRound = Get-OpenRound
if (-not $OpenRound) {
    Write-Host "slice-loop: no open round in $RoundsDir – start a round with the vibe-coding skill first"
    exit 0
}
$ClaudeExe = (Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $ClaudeExe) { Stop-Loop 'claude CLI not found' }
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$exclude = '.git/info/exclude'
if ((Test-Path $exclude) -and -not (Select-String -Path $exclude -Pattern "^$LogDir/$" -Quiet)) {
    Add-Content -Path $exclude -Value "$LogDir/"
}
while (-not (Test-AllDone)) {
    Invoke-Round
    if ($SliceCap -gt 0 -and $Built -ge $SliceCap -and -not (Test-AllDone)) {
        Write-Host "slice-loop: stopped after $Built slice(s) – $(Get-OpenCount) still open"
        exit 0
    }
}
Close-Round
