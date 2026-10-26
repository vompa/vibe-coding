#Requires -Version 7
<#
.SYNOPSIS
Builds the open round slice by slice, each slice in a fresh headless Claude session, then closes the round.
A slice that ends with SLICE-READY is squashed by the merge queue: one slice-NN branch after another, in this
checkout, with the message from .slice-loop/slice-NN.msg. Conflicts in work/checklist.md and the open round record
are resolved by rule and checked; a conflict in any other file stops the loop and names the files.
Stops for plan approval unless -Yes; stops on NEEDS-DECISION, red tests or a blocked slice.

.EXAMPLE
pwsh .claude/scripts/slice-loop.ps1                  # ask for every plan
pwsh .claude/scripts/slice-loop.ps1 -Yes             # approve plans without asking
pwsh .claude/scripts/slice-loop.ps1 -Parallel        # build ready slices side by side (experimental)
pwsh .claude/scripts/slice-loop.ps1 -DryRun          # only print the slices that are ready now
pwsh .claude/scripts/slice-loop.ps1 -MaxSlices 3     # stop after 3 built slices if slices are left (exit 0; run again to continue)
pwsh .claude/scripts/slice-loop.ps1 -Merge           # only run the merge queue: squash every slice-NN branch ticked through Checks, then exit (starts no session, needs no open round)
Env: SLICE_PERMISSION_MODE (default: auto) – passed to claude --permission-mode.
#>
param(
    [switch]$Yes,
    [switch]$Parallel,
    [switch]$DryRun,
    [switch]$Merge,
    [string]$MaxSlices
)
$ErrorActionPreference = 'Stop'

$SlicesFile = 'work/_slices.json'
$ChecklistFile = 'work/checklist.md'
$RoundsDir = 'work/rounds'
$LogDir = '.slice-loop'
$PermissionMode = if ($env:SLICE_PERMISSION_MODE) { $env:SLICE_PERMISSION_MODE } else { 'auto' }
$Usage = 'use -Yes, -Parallel, -DryRun, -MaxSlices N, -Merge'
$SliceCap = 0   # 0 = no cap
$Built = 0

function Stop-Loop([string]$Message) {
    [Console]::Error.WriteLine("slice-loop: $Message")
    exit 1
}

function Get-Slices {
    Get-Content $SlicesFile -Raw -Encoding utf8 | ConvertFrom-Json | ForEach-Object {
        [pscustomobject]@{
            Nr = $_.nr; Deps = @([regex]::Matches([string]$_.deps, '\d{2,}') | ForEach-Object Value)
            Model = [string]$_.model; Name = [string]$_.name; Source = [string]$_.source
        }
    }
}

# Model of a slice – its "model" field, empty when the entry has none. Every turn of the slice runs on it, never on the caller's default.
function Get-SliceModel([string]$Nr) {
    return [string](Get-Slices | Where-Object { $_.Nr -eq $Nr } | Select-Object -First 1).Model
}

# A slice is done when its checklist row has at least one ☑ and no ☐.
function Test-Done([string]$Nr) {
    $row = Get-Content $ChecklistFile -Encoding utf8 | Where-Object { $_ -match "^\|\s*$Nr(\D|$)" } | Select-Object -First 1
    return [bool]$row -and $row.Contains('☑') -and -not $row.Contains('☐')
}

# Git's output as lines, decoded as UTF-8: the console's code page would garble ☑ and ☐.
function Get-GitLines([string[]]$Arguments) {
    $previous = [Console]::OutputEncoding
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
    try { return @(& git @Arguments 2>$null) } finally { [Console]::OutputEncoding = $previous }
}

# Ready for the merge queue: the slice's row on branch slice-NN has a ☑ and no ☐ outside its last cell (Commit).
function Test-BranchReady([string]$Nr) {
    $row = Get-GitLines @('show', "slice-${Nr}:$ChecklistFile") | Where-Object { $_ -match "^\|\s*$Nr(\D|$)" } | Select-Object -First 1
    if (-not $row) { return $false }
    $body = $row.Substring(0, $row.LastIndexOf('|'))   # without the closing pipe
    if ($body.LastIndexOf('|') -lt 0) { return $false }
    $body = $body.Substring(0, $body.LastIndexOf('|'))  # without the last cell
    return $body.Contains('☑') -and -not $body.Contains('☐')
}

# Writes text as UTF-8 without a byte order mark; .NET resolves relative paths against the process, not this location.
function Write-Utf8File([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText((Join-Path (Get-Location).Path $Path), $Text, [Text.UTF8Encoding]::new($false))
}

# Ticks the last open box of the slice's row – its Commit column – keeping the file's line endings.
function Set-CommitTick([string]$Nr) {
    $text = [IO.File]::ReadAllText((Join-Path (Get-Location).Path $ChecklistFile))
    Write-Utf8File $ChecklistFile ([regex]::Replace($text, "(?m)^(\|\s*$Nr(?!\d)[^\r\n]*)☐", '$1☑'))
}

# Path of the squash message: the file /slice wrote, else one written from the slice's name and source.
function Get-SquashMessageFile([string]$Nr) {
    $file = Join-Path $LogDir "slice-$Nr.msg"
    if (Test-Path $file) { return $file }
    $slice = Get-Slices | Where-Object { $_.Nr -eq $Nr } | Select-Object -First 1
    $file = Join-Path $LogDir "slice-$Nr.fallback.msg"
    $text = if ($slice.Source) { "Slice ${Nr}: $($slice.Name) ($($slice.Source))" } else { "Slice ${Nr}: $($slice.Name)" }
    Write-Utf8File $file "$text`n"
    return $file
}

# Path of the worktree that has the branch checked out; nothing when none has.
function Get-WorktreeOf([string]$Branch) {
    $path = ''
    foreach ($line in Get-GitLines @('worktree', 'list', '--porcelain')) {
        if ($line.StartsWith('worktree ')) { $path = $line.Substring(9) }
        elseif ($line -eq "branch refs/heads/$Branch") { return $path }
    }
}

# Removes the squashed branch slice-NN and its worktree; a worktree git will not remove is reported and kept with its branch.
function Remove-SliceBranch([string]$Nr) {
    $branch = "slice-$Nr"
    $path = Get-WorktreeOf $branch
    if ($path) {
        git worktree remove $path *> $null
        if ($LASTEXITCODE -ne 0) { Write-Host "[slice $Nr] worktree $path could not be removed – it and $branch are left"; return }
    }
    # -D: a squash merge leaves the branch unmerged in git's eyes; the squash commit made just now is the proof.
    git branch -D $branch *> $null
    if ($LASTEXITCODE -ne 0) { Write-Host "[slice $Nr] branch $branch could not be removed" }
}

# Slice number of a checklist row; nothing for any other line.
function Get-RowNumber([string]$Line) {
    if ($Line -match '^\|\s*(\d{2,})(\D|$)') { return $Matches[1] }
}

# Row $Ours with every cell ticked that row $Theirs – the same slice's row on the other side – has ticked: the union of ticks.
function Merge-RowTicks([string]$Ours, [string]$Theirs) {
    $cells = $Ours.TrimEnd([char]13).Split('|')
    $other = $Theirs.TrimEnd([char]13).Split('|')
    for ($i = 0; $i -lt $cells.Count; $i++) {
        if ($i -lt $other.Count -and $other[$i].Contains('☑')) { $cells[$i] = $cells[$i].Replace('☐', '☑') }
    }
    return $cells -join '|'
}

# The checklist after a squash conflict, built from both committed versions: the integration branch's lines in their
# order, a row the branch also has with the union of both rows' ticks, rows only the branch has appended in its order.
function Resolve-Checklist([string]$Branch) {
    $theirs = [ordered]@{}
    foreach ($line in Get-GitLines @('show', "${Branch}:$ChecklistFile")) {
        $nr = Get-RowNumber $line
        if ($nr) { $theirs[$nr] = $line }
    }
    $oursHas = @{}
    $out = foreach ($line in Get-GitLines @('show', "HEAD:$ChecklistFile")) {
        $nr = Get-RowNumber $line
        if ($nr) {
            $oursHas[$nr] = $true
            if ($theirs.Contains($nr)) { $line = Merge-RowTicks $line $theirs[$nr] }
        }
        $line
    }
    $out = @($out) + @($theirs.Keys | Where-Object { -not $oursHas.ContainsKey($_) } | ForEach-Object { $theirs[$_] })
    Write-Utf8File $ChecklistFile (($out -join "`n") + "`n")
}

# The round record after a squash conflict: in every conflict hunk the integration branch's side, then the branch's
# side; the marker lines and the base section of the diff3 styles are dropped.
function Resolve-Record([string]$File) {
    $state = 'outside'
    $out = foreach ($line in [IO.File]::ReadAllLines((Join-Path (Get-Location).Path $File))) {
        if ($state -eq 'outside' -and $line.StartsWith('<<<<<<<')) { $state = 'ours'; continue }
        if ($state -eq 'ours' -and $line.StartsWith('|||||||')) { $state = 'base'; continue }
        if ($state -in 'ours', 'base' -and $line -eq '=======') { $state = 'theirs'; continue }
        if ($state -eq 'theirs' -and $line.StartsWith('>>>>>>>')) { $state = 'outside'; continue }
        if ($state -ne 'base') { $line }
    }
    Write-Utf8File $File ((@($out) -join "`n") + "`n")
}

# Number of lines that start with "Result:" (the manual test list).
function Get-ResultCount([string[]]$Lines) { return @($Lines | Where-Object { $_.StartsWith('Result:') }).Count }

# A set of lines; the leading comma keeps PowerShell from unrolling it.
function New-LineSet([string[]]$Lines) {
    $set = [Collections.Generic.HashSet[string]]::new()
    foreach ($line in $Lines) { [void]$set.Add($line) }
    return , $set
}

# Every row of both sides is in the resolved checklist, and none of their ticks is missing there.
function Test-ChecklistResolved([string[]]$Result, [string]$Branch) {
    $rows = @{}
    foreach ($line in $Result) { $nr = Get-RowNumber $line; if ($nr) { $rows[$nr] = $line } }
    $sides = @(Get-GitLines @('show', "HEAD:$ChecklistFile")) + @(Get-GitLines @('show', "${Branch}:$ChecklistFile"))
    foreach ($line in $sides) {
        $nr = Get-RowNumber $line
        if (-not $nr) { continue }
        if (-not $rows.ContainsKey($nr) -or (Merge-RowTicks $rows[$nr] $line) -ne $rows[$nr]) { return $false }
    }
    return $true
}

# Nothing was lost in the resolved file: no conflict marker is left; the checklist keeps every row and tick of both
# sides; the record keeps every line both sides kept or either side added, and its Result: lines add up
# (ours + theirs - merge base).
function Test-Resolved([string]$File, [string]$Branch) {
    $result = @([IO.File]::ReadAllLines((Join-Path (Get-Location).Path $File)))
    if ($result | Where-Object { $_ -match '^(<<<<<<<|=======|>>>>>>>|\|{7})' }) { return $false }
    if ($File -eq $ChecklistFile) { return Test-ChecklistResolved $result $Branch }
    $base = @(Get-GitLines @('merge-base', 'HEAD', $Branch))[0]
    $ours = Get-GitLines @('show', "HEAD:$File")
    $theirs = Get-GitLines @('show', "${Branch}:$File")
    $before = Get-GitLines @('show', "${base}:$File")
    $have = New-LineSet $result
    $theirsSet = New-LineSet $theirs
    $baseSet = New-LineSet $before
    $needed = @($ours | Where-Object { $theirsSet.Contains($_) -or -not $baseSet.Contains($_) }) +
        @($theirs | Where-Object { -not $baseSet.Contains($_) })
    if (@($needed | Where-Object { -not $have.Contains($_) }).Count -gt 0) { return $false }
    return (Get-ResultCount $result) -eq ((Get-ResultCount $ours) + (Get-ResultCount $theirs) - (Get-ResultCount $before))
}

# Squashes branch slice-NN onto the branch checked out here. Conflicts only in the checklist and the open round record
# are resolved by rule and checked; any other conflict, or a failed check, resets the merge and stops the loop.
function Merge-Slice([string]$Nr) {
    $branch = "slice-$Nr"
    if (Get-GitLines @('status', '--porcelain')) { Stop-Loop "slice ${Nr}: this checkout has uncommitted changes – commit or remove them, then run -Merge" }
    $record = Get-OpenRoundFile  # read before the merge: a conflict at its first line would hide "Status: open"
    # diff3 keeps every hunk whole: the default style moves lines both sides end with (such as "Result: ☐") out of
    # the hunk, and keeping both sides would then keep that line once.
    git -c merge.conflictStyle=diff3 merge --squash $branch *> $null
    if ($LASTEXITCODE -ne 0) {
        $conflicts = @(Get-GitLines @('diff', '--name-only', '--diff-filter=U'))
        $foreign = @($conflicts | Where-Object { $_ -ne $ChecklistFile -and $_ -ne $record })
        if (-not $conflicts -or $foreign) {
            git reset --merge *> $null
            $what = if ($foreign) { "merge conflict in $($foreign -join ' ')" } else { 'git merge --squash failed' }
            Stop-Loop "slice ${Nr}: $what – merge reset, $branch kept"
        }
        foreach ($file in $conflicts) {
            if ($file -eq $ChecklistFile) { Resolve-Checklist $branch } else { Resolve-Record $file }
            if (-not (Test-Resolved $file $branch)) {
                git reset --merge *> $null
                Stop-Loop "slice ${Nr}: the rule-based resolution of $file failed its check – merge reset, $branch kept"
            }
            git add $file
        }
    }
    Set-CommitTick $Nr
    git add $ChecklistFile
    git commit -q -F (Get-SquashMessageFile $Nr)
    if ($LASTEXITCODE -ne 0) { Stop-Loop "slice ${Nr}: the squash commit failed – see git status" }
    Write-Host "[slice $Nr] squashed onto $(git branch --show-current) ($(git rev-parse --short HEAD))"
    if (-not (Test-Done $Nr)) { Stop-Loop "slice $Nr was squashed but is not ticked in $ChecklistFile – check it before running again" }
    Remove-SliceBranch $Nr
}

# After a build turn: a slice the session squashed itself is done; one that waits on its branch goes through the queue.
function Complete-Slice([string]$Nr) {
    if (-not (Test-Done $Nr)) {
        if (-not (Test-BranchReady $Nr)) {
            Stop-Loop "slice $Nr reported done or ready but is not ticked in $ChecklistFile or on slice-$Nr – check it before running again"
        }
        Merge-Slice $Nr
    }
    Write-Host "[slice $Nr] done"
}

# The merge queue alone (-Merge): every slice-NN branch, lowest number first; one not ticked through Checks is left.
function Invoke-MergeQueue {
    $branches = Get-GitLines @('for-each-ref', '--format=%(refname:short)', 'refs/heads/slice-*') |
        Where-Object { $_ -match '^slice-\d{2,}$' } | Sort-Object { [int]($_ -replace '^slice-', '') }
    foreach ($branch in $branches) {
        $nr = $branch -replace '^slice-', ''
        if (Test-Done $nr) { continue }
        if (Test-BranchReady $nr) { Merge-Slice $nr }
        else { Write-Host "[slice $nr] not ready to merge: its row on $branch is not ticked through Checks – left as it is" }
    }
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

# Path of the first round record in $RoundsDir whose first line is "Status: open", as git names it; nothing if none is open.
function Get-OpenRoundFile {
    $file = Get-ChildItem -Path $RoundsDir -Filter '*.md' -File -ErrorAction SilentlyContinue | Sort-Object Name |
        Where-Object { (Get-Content $_.FullName -TotalCount 1 -Encoding utf8) -ceq 'Status: open' } |
        Select-Object -First 1
    if ($file) { return "$RoundsDir/$($file.Name)" }
}

# Id (R01, R02 …) of the open round record; nothing if none is open.
function Get-OpenRound {
    $file = Get-OpenRoundFile
    if ($file) { return [regex]::Match((Split-Path $file -Leaf), '^R\d+').Value }
}

# Runs one claude turn on $Model (empty: the CLI default); output goes to the log and is returned for marker parsing.
function Invoke-ClaudeTurn([string]$Log, [string[]]$Arguments, [string]$Model = '') {
    $onModel = if ($Model) { @('--model', $Model) } else { @() }
    $output = & $script:ClaudeExe -p --permission-mode $PermissionMode @onModel @Arguments 2>&1 | Out-String
    Add-Content -Path $Log -Value $output -Encoding utf8
    if ($LASTEXITCODE -ne 0) { Stop-Loop "claude exited with $LASTEXITCODE – see $Log" }
    return $output
}

# Always returns an array (the leading comma stops PowerShell from unrolling a single line).
function Get-MarkerLines([string]$Output, [string]$Marker) {
    return , [string[]]@($Output -split "`r?`n" | Where-Object { $_.StartsWith($Marker) })
}

# Plans one slice on its model and waits for approval. Returns the message for the build turn.
function Request-Plan([string]$Nr, [string]$Session, [string]$Log, [string]$Model) {
    Write-Host "[slice $Nr] planning (session $Session, model $(if ($Model) { $Model } else { 'default' }), log $Log)"
    $output = Invoke-ClaudeTurn $Log @('--session-id', $Session, "/slice $Nr plan auto") $Model
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
            "Change request: $answer. Revise the plan, save it and end again with the PLAN line (auto).") $Model
    }
}

function Get-BuildMessage([string]$Approval) {
    if (-not $Parallel) { return $Approval }
    return "$Approval Other slices are built in parallel: if git is locked or the integration branch moved, wait and retry; in conflicts keep every tick in work/checklist.md."
}

function Assert-SliceFinished([string]$Nr, [string]$Output, [string]$Log) {
    $finished = @(Get-MarkerLines $Output 'SLICE-DONE:') + @(Get-MarkerLines $Output 'SLICE-READY:')
    if (-not ($finished -cmatch "^SLICE-(DONE|READY): $Nr(\D|$)")) {
        $open = Get-MarkerLines $Output 'SLICE-OPEN:'
        Stop-Loop "slice $Nr not finished: $(if ($open) { $open[-1] } else { 'no SLICE-DONE or SLICE-READY line' }) – see $Log"
    }
}

function Invoke-Round {
    $ready = @(Get-ReadySlices)
    if (-not $ready) { Stop-Loop "no slice is ready – check $ChecklistFile (/slice status)" }
    if (-not $Parallel) { $ready = @($ready[0]) }
    if ($SliceCap -gt 0) { $ready = @($ready | Select-Object -First ($SliceCap - $Built)) }
    $runs = foreach ($nr in $ready) {
        $session = [guid]::NewGuid().ToString()
        $log = Join-Path $LogDir "slice-$nr-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
        $model = Get-SliceModel $nr
        [pscustomobject]@{ Nr = $nr; Session = $session; Log = $log; Model = $model; Message = Get-BuildMessage (Request-Plan $nr $session $log $model) }
    }
    if (-not $Parallel) {
        $run = $runs[0]
        Write-Host "[slice $($run.Nr)] building – this can take a while (log $($run.Log))"
        Assert-SliceFinished $run.Nr (Invoke-ClaudeTurn $run.Log @('--resume', $run.Session, $run.Message) $run.Model) $run.Log
        Complete-Slice $run.Nr
        $script:Built++
        return
    }
    # Thread jobs run in this process; Start-Job's child processes hung on Linux CI runners.
    $jobs = foreach ($run in $runs) {
        Write-Host "[slice $($run.Nr)] building in parallel (log $($run.Log))"
        Start-ThreadJob -ArgumentList $script:ClaudeExe, (Get-Location).Path, $run.Session, $run.Message, $PermissionMode, $run.Model -ScriptBlock {
            param($Exe, $Directory, $Session, $Message, $Mode, $Model)
            Set-Location $Directory
            $onModel = if ($Model) { @('--model', $Model) } else { @() }
            & $Exe -p --permission-mode $Mode @onModel --resume $Session $Message 2>&1 | Out-String
        }
    }
    # Parallel builds are squashed one after another in list order, each as soon as it and the ones before it are built.
    for ($i = 0; $i -lt $runs.Count; $i++) {
        $output = Receive-Job -Job $jobs[$i] -Wait -AutoRemoveJob
        Add-Content -Path $runs[$i].Log -Value $output -Encoding utf8
        Assert-SliceFinished $runs[$i].Nr $output $runs[$i].Log
        Complete-Slice $runs[$i].Nr
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
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$exclude = '.git/info/exclude'
if ((Test-Path $exclude) -and -not (Select-String -Path $exclude -Pattern "^$LogDir/$" -Quiet)) {
    Add-Content -Path $exclude -Value "$LogDir/"
}
if ($Merge) { Invoke-MergeQueue; exit 0 }
$OpenRound = Get-OpenRound
if (-not $OpenRound) {
    Write-Host "slice-loop: no open round in $RoundsDir – start a round with the vibe-coding skill first"
    exit 0
}
$ClaudeExe = (Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $ClaudeExe) { Stop-Loop 'claude CLI not found' }
while (-not (Test-AllDone)) {
    Invoke-Round
    if ($SliceCap -gt 0 -and $Built -ge $SliceCap -and -not (Test-AllDone)) {
        Write-Host "slice-loop: stopped after $Built slice(s) – $(Get-OpenCount) still open"
        exit 0
    }
}
Close-Round
