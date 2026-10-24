#Requires -Version 7
<#
.SYNOPSIS
Runs the rebuild slice by slice, each slice in a fresh headless Claude session.
Stops for plan approval unless -Yes; stops on NEEDS-DECISION, red tests or a blocked slice.

.EXAMPLE
pwsh .claude/scripts/rebuild-loop.ps1            # ask for every plan
pwsh .claude/scripts/rebuild-loop.ps1 -Yes       # approve plans without asking
pwsh .claude/scripts/rebuild-loop.ps1 -Parallel  # build ready slices side by side (experimental)
pwsh .claude/scripts/rebuild-loop.ps1 -DryRun    # only print the slices that are ready now
Env: REBUILD_PERMISSION_MODE (default: auto) – passed to claude --permission-mode.
#>
param(
    [switch]$Yes,
    [switch]$Parallel,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'

$SlicesFile = 'rebuild/_slices.json'
$ChecklistFile = 'rebuild/checklist.md'
$LogDir = '.rebuild-loop'
$PermissionMode = if ($env:REBUILD_PERMISSION_MODE) { $env:REBUILD_PERMISSION_MODE } else { 'auto' }

function Stop-Loop([string]$Message) {
    [Console]::Error.WriteLine("rebuild-loop: $Message")
    exit 1
}

function Get-Slices {
    Get-Content $SlicesFile -Raw -Encoding utf8 | ConvertFrom-Json | ForEach-Object {
        [pscustomobject]@{ Nr = $_.nr; Deps = @([regex]::Matches([string]$_.deps, '\d{2}') | ForEach-Object Value) }
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
    $output = Invoke-ClaudeTurn $Log @('--session-id', $Session, "/rebuild $Nr plan auto")
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
    return "$Approval Other slices are built in parallel: if git is locked or main moved, wait and retry; in conflicts keep every tick in rebuild/checklist.md."
}

function Assert-SliceDone([string]$Nr, [string]$Output, [string]$Log) {
    if (-not (Get-MarkerLines $Output "SLICE-DONE: $Nr")) {
        $open = Get-MarkerLines $Output 'SLICE-OPEN:'
        Stop-Loop "slice $Nr not finished: $(if ($open) { $open[-1] } else { 'no SLICE-DONE line' }) – see $Log"
    }
    if (-not (Test-Done $Nr)) { Stop-Loop "slice $Nr reported done but is not ticked in $ChecklistFile – check it before running again" }
    Write-Host "[slice $Nr] done"
}

function Invoke-Round {
    $ready = @(Get-ReadySlices)
    if (-not $ready) { Stop-Loop 'no slice is ready – check rebuild/checklist.md (/rebuild status)' }
    if (-not $Parallel) { $ready = @($ready[0]) }
    $runs = foreach ($nr in $ready) {
        $session = [guid]::NewGuid().ToString()
        $log = Join-Path $LogDir "slice-$nr-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
        [pscustomobject]@{ Nr = $nr; Session = $session; Log = $log; Message = Get-BuildMessage (Request-Plan $nr $session $log) }
    }
    if (-not $Parallel) {
        $run = $runs[0]
        Write-Host "[slice $($run.Nr)] building – this can take a while (log $($run.Log))"
        Assert-SliceDone $run.Nr (Invoke-ClaudeTurn $run.Log @('--resume', $run.Session, $run.Message)) $run.Log
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
}

if (-not ((Test-Path $SlicesFile) -and (Test-Path $ChecklistFile))) {
    Stop-Loop "run from the repo root (needs $SlicesFile and $ChecklistFile)"
}
if ($DryRun) { Get-ReadySlices; exit 0 }
$ClaudeExe = (Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $ClaudeExe) { Stop-Loop 'claude CLI not found' }
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$exclude = '.git/info/exclude'
if ((Test-Path $exclude) -and -not (Select-String -Path $exclude -Pattern "^$LogDir/$" -Quiet)) {
    Add-Content -Path $exclude -Value "$LogDir/"
}
while (-not (Test-AllDone)) { Invoke-Round }
Write-Host 'All slices done. Next: type /rebuild in Claude Code to turn the plan README into the product README.'
