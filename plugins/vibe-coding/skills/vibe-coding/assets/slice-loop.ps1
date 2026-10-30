#Requires -Version 7
<#
.SYNOPSIS
Builds the open round slice by slice, each slice in a fresh headless Claude session, then closes the round.
A slice that ends with SLICE-READY is squashed by the merge queue: one slice-NN branch after another, in this
checkout, with the message from .slice-loop/slice-NN.msg, once .slice-loop/slice-NN.ready names the branch tip (the
session wrote it last, at SLICE-READY) and .slice-loop/slice-NN.checks proves green checks on that tip. Only proof lines of the branch tip count (lines of other commits are stale runs and ignored); of each
command the last line on the tip counts. Conflicts are resolved by rule and checked: work/checklist.md by the union of
ticks, and in any text file a hunk where both sides only added lines (both kept) or changed rows of one table (merged
per row key, e.g. the status row of a round). A slice cut from an older integration branch is squashed as it is,
unless the integration branch changed since then a file the slice changes too (documents *.md and work/ aside). That
overlap, a real conflict, a missing proof, a duplicate finding id, a line glued to the next one in the round record, a
decision line in neither format ("Ruling: …", "Build decision (slice NN): …") or a malformed manual test block leaves
that slice behind with its branch; the queue goes on, lists every slice left behind and exits non-zero. A slice whose
session has not reported ready on its tip yet is listed as not ready yet and does not fail -Merge. Removing the worktree of a squashed slice is retried, and
the entries of every folder a link in the worktree points to are counted before and after: fewer afterwards is
reported and makes the run exit non-zero (the squash stays done). A stale .slice-loop/full-suite.lock (its slice
branch is gone, or it is older than 60 minutes) is reported at the start, never removed; so is a work/conventions.md
without a "- Baseline check" line (its keys stay English in any language).
Stops for plan approval unless -Yes; stops on NEEDS-DECISION, red tests or a blocked slice. A slice that ends its
turn with SLICE-WAIT is still running: the loop checks back on it in the same session.

.EXAMPLE
pwsh .claude/scripts/slice-loop.ps1                  # ask for every plan
pwsh .claude/scripts/slice-loop.ps1 -Yes             # approve plans without asking
pwsh .claude/scripts/slice-loop.ps1 -Parallel        # build ready slices side by side (headless; for long autonomous runs): at most SLICE_PARALLEL_MAX per batch, and a slice whose "files" in work/_slices.json overlap a slice already in the batch waits for the next one
pwsh .claude/scripts/slice-loop.ps1 -DryRun          # only print the slices that are ready now
pwsh .claude/scripts/slice-loop.ps1 -MaxSlices 3     # stop after 3 built slices if slices are left (exit 0; run again to continue)
pwsh .claude/scripts/slice-loop.ps1 -Merge           # only run the merge queue: squash every slice-NN branch ticked through Checks, retry removing worktrees an earlier squash left, then exit (starts no session, needs no open round)
pwsh .claude/scripts/slice-loop.ps1 -Merge -Verify   # after the queue, when it squashed a slice: run every command of the "- Full check chain" line in work/conventions.md on the integration branch, under .slice-loop/full-suite.lock (red: exit 1; -Verify needs -Merge)
pwsh .claude/scripts/slice-loop.ps1 -Merge -Watch    # wait until a slice reports ready on a new tip, run the queue once, then exit (a background command, so it wakes the chat that started it; -Watch needs -Merge). A slice left behind brings it back only with a new tip; a second watch next to a running one exits at once
Optional field "files" of an entry in work/_slices.json: the repo-relative paths (or prefixes ending in "/") the slice is expected to change.
Env: SLICE_PERMISSION_MODE (default: auto) – passed to claude --permission-mode.
     SLICE_PARALLEL_MAX (default: 2) – most slices in one -Parallel batch (three sessions on one machine made unrelated tests red under load).
     SLICE_WAIT_SECONDS (default: 60), SLICE_WAIT_MAX (default: 30) – pause and number of check-backs on SLICE-WAIT.
     SLICE_WATCH_SECONDS (default: 60), SLICE_WATCH_MAX (default: 480) – pause and number of checks of -Watch.
     SLICE_WRITE_RETRIES (default: 5), SLICE_WRITE_BACKOFF_SECONDS (default: 2) – retries and pause when the queue
     cannot write a file or reset a merge because another process (scanner, indexer, editor) holds it, and when git
     cannot remove the worktree of a squashed slice (a shell of the finished session may still stand in it).
#>
param(
    [switch]$Yes,
    [switch]$Parallel,
    [switch]$DryRun,
    [switch]$Merge,
    [switch]$Verify,
    [switch]$Watch,
    [string]$MaxSlices
)
$ErrorActionPreference = 'Stop'

$SlicesFile = 'work/_slices.json'
$ChecklistFile = 'work/checklist.md'
$ConventionsFile = 'work/conventions.md'
$RoundsDir = 'work/rounds'
$LogDir = '.slice-loop'
$PermissionMode = if ($env:SLICE_PERMISSION_MODE) { $env:SLICE_PERMISSION_MODE } else { 'auto' }
$WaitSeconds = if ($env:SLICE_WAIT_SECONDS) { [int]$env:SLICE_WAIT_SECONDS } else { 60 }
$WaitMax = if ($env:SLICE_WAIT_MAX) { [int]$env:SLICE_WAIT_MAX } else { 30 }
$WriteRetries = if ($env:SLICE_WRITE_RETRIES) { [int]$env:SLICE_WRITE_RETRIES } else { 5 }
$WriteBackoff = if ($env:SLICE_WRITE_BACKOFF_SECONDS) { [double]$env:SLICE_WRITE_BACKOFF_SECONDS } else { 2 }
$ParallelMax = if ($env:SLICE_PARALLEL_MAX) { [int]$env:SLICE_PARALLEL_MAX } else { 2 }
$WatchSeconds = if ($env:SLICE_WATCH_SECONDS) { [double]$env:SLICE_WATCH_SECONDS } else { 60 }
$WatchMax = if ($env:SLICE_WATCH_MAX) { [int]$env:SLICE_WATCH_MAX } else { 480 }
$WatchAlive = "$LogDir/watch.alive"   # sign of life of a running -Watch, written at every check
$MergeLock = "$LogDir/merge.lock"   # taken (mkdir) by a running -Merge queue; older than 60 minutes: its owner died
$LockDir = "$LogDir/full-suite.lock"   # taken (mkdir) by whoever runs the full suite; holds a file "owner"
$WriteFailed = ''   # the file Write-Utf8File gave up on
$Merging = $false   # a squash merge is in progress in this checkout; Merge-Slice resets it on any way out
$Squashed = 0       # slices this run squashed
$LinkLost = $false  # a folder a link of a removed worktree pointed to lost entries
$Usage = 'use -Yes, -Parallel, -DryRun, -MaxSlices N, -Merge, -Verify and -Watch (with -Merge)'
$SliceCap = 0   # 0 = no cap
$Built = 0
$LeftBehind = [ordered]@{}  # slices the merge queue left behind in this run: number -> reason
$NotReady = [ordered]@{}    # slices -Merge found not ready yet (their session still checks): number -> reason
$CleanUp = [ordered]@{}     # squashed slices whose worktree or folder could not be removed: number -> what is left

function Stop-Loop([string]$Message) {
    [Console]::Error.WriteLine("slice-loop: $Message")
    exit 1
}

# Leaves a slice behind: its branch stays, the run goes on without it.
function Add-LeftSlice([string]$Nr, [string]$Reason) {
    Write-Host "[slice $Nr] left behind: $Reason – slice-$Nr kept"
    $script:LeftBehind[$Nr] = $Reason
    # -Watch comes back to this slice only with a new tip.
    if ($Watch) { Set-Content -LiteralPath (Join-Path $LogDir "slice-$Nr.left") -Value @(Get-GitLines @('rev-parse', "slice-$Nr"))[0] -Encoding utf8 }
}

# A slice -Merge leaves for a later run: its session has not reported ready on its tip yet. Not a problem of the slice.
function Add-NotReady([string]$Nr, [string]$Reason) {
    Write-Host "[slice $Nr] not ready yet: $Reason – left for a later -Merge"
    $script:NotReady[$Nr] = $Reason
}

# Lists every slice not ready yet and every slice left behind; $false when one was left behind, or when a removed
# worktree's link target lost entries (that was reported where it happened). Not ready yet alone is no failure.
function Write-LeftReport {
    if ($script:NotReady.Count -gt 0) {
        Write-Host "slice-loop: $($script:NotReady.Count) slice(s) not ready yet – their sessions still check; run -Merge again after SLICE-READY:"
        foreach ($nr in $script:NotReady.Keys) { Write-Host "  slice ${nr}: $($script:NotReady[$nr])" }
    }
    if ($script:LeftBehind.Count -gt 0) {
        [Console]::Error.WriteLine("slice-loop: $($script:LeftBehind.Count) slice(s) left behind – fix them on their branch, then run -Merge again:")
        foreach ($nr in $script:LeftBehind.Keys) { [Console]::Error.WriteLine("  slice ${nr}: $($script:LeftBehind[$nr])") }
    }
    if ($script:CleanUp.Count -gt 0) {
        Write-Host "slice-loop: $($script:CleanUp.Count) squashed slice(s) left something to clean up:"
        foreach ($nr in $script:CleanUp.Keys) { Write-Host "  slice ${nr}: $($script:CleanUp[$nr])" }
    }
    return $script:LeftBehind.Count -eq 0 -and -not $script:LinkLost
}

function Get-Slices {
    Get-Content $SlicesFile -Raw -Encoding utf8 | ConvertFrom-Json | ForEach-Object {
        [pscustomobject]@{
            Nr = $_.nr; Deps = @([regex]::Matches([string]$_.deps, '\d{2,}') | ForEach-Object Value)
            Model = [string]$_.model; Name = [string]$_.name; Source = [string]$_.source
            Files = @($_.files | Where-Object { $_ } | ForEach-Object { [string]$_ })
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
# Retries while another process holds the file (a scanner or indexer with it mapped); after the last retry it names the
# file in $WriteFailed and throws.
function Write-Utf8File([string]$Path, [string]$Text) {
    $full = Join-Path (Get-Location).Path $Path
    for ($attempt = 0; ; $attempt++) {
        try { [IO.File]::WriteAllText($full, $Text, [Text.UTF8Encoding]::new($false)); return }
        catch [IO.IOException], [UnauthorizedAccessException] {
            if ($attempt -ge $WriteRetries) { $script:WriteFailed = $Path; throw }
            Write-Host "slice-loop: could not write $Path (locked by another process?) – retrying in $WriteBackoff s (attempt $($attempt + 1) of $WriteRetries)"
            Start-Sleep -Seconds $WriteBackoff
        }
    }
}

# Ticks the last open box of the slice's row – its Commit column – keeping the file's line endings.
function Set-CommitTick([string]$Nr) {
    $text = [IO.File]::ReadAllText((Join-Path (Get-Location).Path $ChecklistFile))
    Write-Utf8File $ChecklistFile ([regex]::Replace($text, "(?m)^(\|\s*$Nr(?!\d)[^\r\n]*)☐", '$1☑'))
}

# Path of the worktree that has the branch checked out; nothing when none has.
function Get-WorktreeOf([string]$Branch) {
    $path = ''
    foreach ($line in Get-GitLines @('worktree', 'list', '--porcelain')) {
        if ($line.StartsWith('worktree ')) { $path = $line.Substring(9) }
        elseif ($line -eq "branch refs/heads/$Branch") { return $path }
    }
}

# Entries directly in a folder.
function Get-EntryCount([string]$Folder) { return @(Get-ChildItem -LiteralPath $Folder -Force -ErrorAction SilentlyContinue).Count }

# Reports every folder in $Held (path -> entries before the removal of the worktree of slice $Nr) that has fewer entries now.
function Test-LinkTargets([string]$Nr, $Held) {
    foreach ($target in $Held.Keys) {
        $now = Get-EntryCount $target
        if ($now -ge $Held[$target]) { continue }
        [Console]::Error.WriteLine("slice-loop: link target $target lost entries during the removal of the worktree of slice-$Nr (before $($Held[$target]), now $now) – restore it (for example npm ci)")
        $script:LinkLost = $true
    }
}

# Removes the squashed branch slice-NN and its worktree; a worktree git will not remove (after retries) is reported and
# kept with its branch.
function Remove-SliceBranch([string]$Nr) {
    $branch = "slice-$Nr"
    $path = Get-WorktreeOf $branch
    if ($path) {
        # Links first (for example node_modules as a junction onto the main checkout): git follows a junction when it
        # removes the worktree and empties its target. Deleting the reparse point removes the link, never the target.
        # The entries of each target are counted before and after, so a loss is noticed.
        $held = [ordered]@{}
        foreach ($link in @(Get-ChildItem -LiteralPath $path -Recurse -Force -Attributes ReparsePoint -ErrorAction SilentlyContinue)) {
            $target = $link.ResolveLinkTarget($true)
            if ($target -is [IO.DirectoryInfo] -and -not $held.Contains($target.FullName)) { $held[$target.FullName] = Get-EntryCount $target.FullName }
            if ($link.PSIsContainer) { [System.IO.Directory]::Delete($link.FullName) } else { [System.IO.File]::Delete($link.FullName) }
        }
        # A shell of the finished session may still stand in the worktree: it often lets go within seconds.
        for ($attempt = 0; ; $attempt++) {
            git worktree remove $path *> $null
            if ($LASTEXITCODE -eq 0) { break }
            # Git drops its entry even when files inside are held: there is nothing left to retry, only a folder.
            if (-not (Get-WorktreeOf $branch)) { break }
            if ($attempt -ge $WriteRetries) {
                Write-Host ("[slice $Nr] worktree $path could not be removed – most likely a shell, editor or process still runs inside it " +
                    "(or it is locked); close it and run -Merge again to retry. $path and $branch are kept")
                $script:CleanUp[$Nr] = "$path and $branch kept – close what runs inside it, then run -Merge again"
                return
            }
            Write-Host "slice-loop: could not remove the worktree of slice-$Nr (a shell or process still runs inside it?) – retrying in $WriteBackoff s (attempt $($attempt + 1) of $WriteRetries)"
            Start-Sleep -Seconds $WriteBackoff
        }
        Test-LinkTargets $Nr $held
        if (Test-Path -LiteralPath $path) { $script:CleanUp[$Nr] = "folder $path remains – close what holds it and delete it" }
    }
    Remove-Item -LiteralPath (Join-Path $LogDir "slice-$Nr.squashed") -ErrorAction SilentlyContinue
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

# Lines of a file in this checkout (without line ends), as one array: assign it before a foreach, which would see one item.
function Read-Lines([string]$File) { return , [string[]]@([IO.File]::ReadAllLines((Join-Path (Get-Location).Path $File))) }

# Table rows: a row starts with "|", its key is its first cell, and a cell holds items separated by "; ".
function Test-Row([string]$Line) { return $Line.StartsWith('|') }
function Get-RowKey([string]$Line) { $raw = $Line.Split('|'); if ($raw.Count -lt 2) { return '' }; return $raw[1].Trim() }
function Get-Cells([string]$Line) {
    $raw = $Line.Split('|')
    $last = if ($raw[-1].Trim() -eq '') { $raw.Count - 2 } else { $raw.Count - 1 }
    return , [string[]]@(for ($i = 1; $i -le $last; $i++) { $raw[$i].Trim() })
}
function Test-Item([string]$Text, [string]$Item) { return @($Text -split '; ' | ForEach-Object { $_.Trim() }) -ccontains $Item }

# A cell both sides changed keeps the integration branch's text and adds every item only the branch's text has.
function Merge-Cell([string]$O, [string]$B, [string]$T) {
    if ($O -ceq $T -or $T -ceq $B) { return $O }
    if ($O -ceq $B) { return $T }
    $out = $O
    foreach ($x in @($T -split '; ' | ForEach-Object { $_.Trim() })) {
        if ($x -and -not (Test-Item $O $x) -and -not (Test-Item $B $x)) { $out = if ($out) { "$out; $x" } else { $x } }
    }
    return $out
}

# The row both sides changed, merged cell by cell ($B is the base row, empty when both added it); $null when the cells differ in number.
function Merge-Row([string]$O, [string]$B, [string]$T) {
    if ($O -ceq $T -or $T -ceq $B) { return $O }
    if ($O -ceq $B) { return $T }
    $co = Get-Cells $O; $ct = Get-Cells $T
    $cb = if ($B) { Get-Cells $B } else { [string[]]@($co | ForEach-Object { '' }) }
    if ($ct.Count -ne $co.Count -or $cb.Count -ne $co.Count) { return $null }
    $row = '|'
    for ($i = 0; $i -lt $co.Count; $i++) { $row += " $(Merge-Cell $co[$i] $cb[$i] $ct[$i]) |" }
    return $row
}

# Every item row $Line added to a cell (against base row $B) is in result row $R.
function Test-RowCovered([string]$Line, [string]$B, [string]$R) {
    $cl = Get-Cells $Line; $cr = Get-Cells $R
    $cb = if ($B) { Get-Cells $B } else { [string[]]@($cl | ForEach-Object { '' }) }
    if ($cr.Count -ne $cl.Count -or $cb.Count -ne $cl.Count) { return $false }
    for ($i = 0; $i -lt $cl.Count; $i++) {
        foreach ($x in @($cl[$i] -split '; ' | ForEach-Object { $_.Trim() })) {
            if ($x -and -not (Test-Item $cb[$i] $x) -and -not (Test-Item $cr[$i] $x)) { return $false }
        }
    }
    return $true
}

# Key -> index of table rows with unique keys; $null when a line is no row, has no key or repeats one.
function Get-KeyIndex($Lines) {
    $keys = [Collections.Generic.Dictionary[string, int]]::new([StringComparer]::Ordinal)
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if (-not (Test-Row $Lines[$i])) { return $null }
        $k = Get-RowKey $Lines[$i]
        if (-not $k -or $k -match '^[-: ]+$' -or $keys.ContainsKey($k)) { return $null }
        $keys[$k] = $i
    }
    return , $keys
}

# A hunk of table rows where no side removed a key: one row per key; $null when the hunk is not such a table.
function Merge-TableHunk($O, $B, $T) {
    $ko = Get-KeyIndex $O; $kb = Get-KeyIndex $B; $kt = Get-KeyIndex $T
    if ($null -eq $ko -or $null -eq $kb -or $null -eq $kt) { return $null }
    foreach ($k in $kb.Keys) { if (-not $ko.ContainsKey($k) -or -not $kt.ContainsKey($k)) { return $null } }
    $merged = [Collections.Generic.List[string]]::new()
    foreach ($line in $O) {
        $k = Get-RowKey $line
        if (-not $kt.ContainsKey($k)) { $merged.Add($line); continue }
        $row = Merge-Row $line $(if ($kb.ContainsKey($k)) { $B[$kb[$k]] } else { '' }) $T[$kt[$k]]
        if ($null -eq $row) { return $null }
        $merged.Add($row)
    }
    foreach ($line in $T) { if (-not $ko.ContainsKey((Get-RowKey $line))) { $merged.Add($line) } }
    return , [string[]]$merged
}

# One conflict hunk resolved by rule; $null for a real conflict. Both sides only added lines (empty base): the
# integration branch's lines, then the branch's. Table rows: Merge-TableHunk. Mode 'record' (the open round record)
# keeps both sides of any other hunk, too – the rule of 1.2.
function Resolve-Hunk($O, $B, $T, [string]$Mode) {
    if ($B.Count -eq 0) { return , [string[]](@($O) + @($T)) }
    $table = Merge-TableHunk $O $B $T
    if ($null -ne $table) { return , $table }
    if ($Mode -eq 'record') { return , [string[]](@($O) + @($T)) }
    return $null
}

# Resolves every conflict hunk (diff3 style) of the file by rule and rewrites it; $false, leaving it as it is, on a real conflict.
function Resolve-Hunks([string]$File, [string]$Mode) {
    $state = ''
    $out = [Collections.Generic.List[string]]::new()
    $lines = Read-Lines $File
    foreach ($line in $lines) {
        if ($state -eq '' -and $line.StartsWith('<<<<<<<')) {
            $state = 'o'; $o = [Collections.Generic.List[string]]::new(); $b = [Collections.Generic.List[string]]::new(); $t = [Collections.Generic.List[string]]::new()
            continue
        }
        if ($state -eq 'o' -and $line.StartsWith('|||||||')) { $state = 'b'; continue }
        if ($state -in 'o', 'b' -and $line -ceq '=======') { $state = 't'; continue }
        if ($state -eq 't' -and $line.StartsWith('>>>>>>>')) {
            $state = ''
            $resolved = Resolve-Hunk $o $b $t $Mode
            if ($null -eq $resolved) { return $false }
            $out.AddRange($resolved)
            continue
        }
        if ($state -eq 'o') { $o.Add($line) } elseif ($state -eq 'b') { $b.Add($line) } elseif ($state -eq 't') { $t.Add($line) } else { $out.Add($line) }
    }
    if ($state) { return $false }
    Write-Utf8File $File (($out -join "`n") + "`n")
    return $true
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

# Why the resolved file lost something; empty when it is fine. No conflict marker is left; the checklist keeps every row
# and tick of both sides. Any other file keeps every line both sides kept or either side added – a table row as it is
# or covered by the result row of its key (every item the side added to a cell is there) –, no key has more rows than
# either side had, and its Result: lines add up (ours + theirs - merge base).
function Get-ResolutionProblem([string]$File, [string]$Branch) {
    $result = Read-Lines $File
    if ($result | Where-Object { $_ -match '^(<<<<<<<|=======|>>>>>>>|\|{7})' }) { return 'a conflict marker is left' }
    if ($File -eq $ChecklistFile) { return $(if (Test-ChecklistResolved $result $Branch) { '' } else { 'a row or tick is missing' }) }
    $base = @(Get-GitLines @('merge-base', 'HEAD', $Branch))[0]
    $ours = @(Get-GitLines @('show', "HEAD:$File"))
    $theirs = @(Get-GitLines @('show', "${Branch}:$File"))
    $before = @(Get-GitLines @('show', "${base}:$File"))
    $have = New-LineSet $result
    $theirsSet = New-LineSet $theirs
    $baseSet = New-LineSet $before
    $baseRow = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    foreach ($line in $before) { if ((Test-Row $line) -and -not $baseRow.ContainsKey((Get-RowKey $line))) { $baseRow[(Get-RowKey $line)] = $line } }
    $resultRows = @($result | Where-Object { Test-Row $_ })
    $neededKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $needed = @($ours | Where-Object { $theirsSet.Contains($_) -or -not $baseSet.Contains($_) }) +
        @($theirs | Where-Object { -not $baseSet.Contains($_) })
    foreach ($line in $needed) {
        if ($have.Contains($line)) { continue }
        if (-not (Test-Row $line)) { return "lost: $line" }
        $k = Get-RowKey $line
        [void]$neededKeys.Add($k)
        $b = if ($baseRow.ContainsKey($k)) { $baseRow[$k] } else { '' }
        if (-not @($resultRows | Where-Object { (Get-RowKey $_) -ceq $k -and (Test-RowCovered $line $b $_) })) { return "lost: $line" }
    }
    foreach ($k in $neededKeys) {
        $count = { param($Lines) @($Lines | Where-Object { (Test-Row $_) -and (Get-RowKey $_) -ceq $k }).Count }
        $inResult = & $count $result
        if ($inResult -gt (& $count $ours) -and $inResult -gt (& $count $theirs)) { return "duplicate rows for $k" }
    }
    if ((Get-ResultCount $result) -ne ((Get-ResultCount $ours) + (Get-ResultCount $theirs) - (Get-ResultCount $before))) { return 'Result: lines do not add up' }
    return ''
}

# Puts the blocks under "## Manual test list" of the record in slice-number order (stable); the file is rewritten only
# when a block moved, and nothing else moves.
function Sort-ManualTests([string]$File) {
    $lines = Read-Lines $File
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].StartsWith('## Manual test list')) { $start = $i; break } }
    if ($start -lt 0) { return }
    $stop = $start + 1
    while ($stop -lt $lines.Count -and -not $lines[$stop].StartsWith('## ')) { $stop++ }
    $firsts = @(for ($i = $start + 1; $i -lt $stop; $i++) { if ($lines[$i] -match '^### Slice \d') { $i } })
    if (-not $firsts) { return }
    $blocks = @(for ($j = 0; $j -lt $firsts.Count; $j++) {
        $end = $(if ($j -lt $firsts.Count - 1) { $firsts[$j + 1] } else { $stop }) - 1
        while ($end -gt $firsts[$j] -and $lines[$end] -eq '') { $end-- }
        [pscustomobject]@{ Index = $j; End = $end; Nr = [int][regex]::Match($lines[$firsts[$j]], '\d+').Value; Lines = $lines[$firsts[$j]..$end] }
    })
    $sorted = @($blocks | Sort-Object -Stable Nr)
    if (-not @(for ($j = 0; $j -lt $sorted.Count; $j++) { if ($sorted[$j].Index -ne $j) { $j } })) { return }
    $out = [Collections.Generic.List[string]]::new()
    if ($firsts[0] -gt 0) { $out.AddRange([string[]]$lines[0..($firsts[0] - 1)]) }
    for ($j = 0; $j -lt $sorted.Count; $j++) { if ($j -gt 0) { $out.Add('') }; $out.AddRange([string[]]$sorted[$j].Lines) }
    for ($i = $blocks[-1].End + 1; $i -lt $stop; $i++) { $out.Add('') }
    if ($stop -lt $lines.Count) { $out.AddRange([string[]]$lines[$stop..($lines.Count - 1)]) }
    Write-Utf8File $File (($out -join "`n") + "`n")
}

# Problems of the slice's block in the record's manual test list: steps numbered 1..n, exactly one Expected: per step,
# exactly one Closes: and one Result: per block, one block per slice. Empty when the slice has no block or it is fine.
function Get-ManualTestProblem([string]$File, [string]$Nr) {
    $bad = [Collections.Generic.List[string]]::new()
    $section = $false; $inBlock = $false; $blocks = 0; $steps = 0; $checked = 0; $expected = 0; $closes = 0; $results = 0
    # Dot-sourced, so it updates this function's counters: the step before a new step, Closes:, Result: or a heading.
    $endStep = {
        if ($steps -gt $checked) {
            if ($expected -ne 1) { $bad.Add("step $steps has $expected Expected: lines") }
            $checked = $steps; $expected = 0
        }
    }
    $lines = Read-Lines $File
    foreach ($line in $lines) {
        if ($line.StartsWith('## ')) { . $endStep; $section = $line.StartsWith('## Manual test list'); $inBlock = $false; continue }
        if ($section -and $line.StartsWith('### ')) { . $endStep; $inBlock = $line -cmatch "^### Slice $Nr(\D|$)"; if ($inBlock) { $blocks++ }; continue }
        if (-not $inBlock) { continue }
        if ($line -match '^(\d+)\. ') { . $endStep; $steps++; if ([int]$Matches[1] -ne $steps) { $bad.Add("step $steps is numbered $($Matches[1])") }; continue }
        if ($line.StartsWith('Expected:')) { if ($steps -eq 0 -or $closes -or $results) { $bad.Add('Expected: outside a step') } else { $expected++ }; continue }
        if ($line.StartsWith('Closes:')) { . $endStep; $closes++; continue }
        if ($line.StartsWith('Result:')) { . $endStep; $results++; continue }
    }
    . $endStep
    if ($blocks -eq 0) { return '' }
    if ($blocks -gt 1) { $bad.Add("$blocks blocks") }
    if ($steps -eq 0) { $bad.Add('no numbered step') }
    if ($closes -ne 1) { $bad.Add("$closes Closes: lines") }
    if ($results -ne 1) { $bad.Add("$results Result: lines") }
    return $bad -join '; '
}

# Finding ids defined more than once in the lines: as the first cell of two table rows, or as the first word of two headings.
function Get-DuplicateIds([string[]]$Lines) {
    $seen = @{ row = [Collections.Generic.Dictionary[string, int]]::new([StringComparer]::Ordinal); head = [Collections.Generic.Dictionary[string, int]]::new([StringComparer]::Ordinal) }
    foreach ($line in $Lines) {
        if ($line.StartsWith('|')) { $kind = 'row'; $id = Get-RowKey $line }
        elseif ($line -match '^#+ (\S+)') { $kind = 'head'; $id = $Matches[1] -replace '[:.,]$', '' }
        else { continue }
        if ($id -cnotmatch '^\p{Lu}+-?[0-9]+$') { continue }  # uppercase letters in any script: B71, F-01, Ä77
        $seen[$kind][$id] = 1 + $(if ($seen[$kind].ContainsKey($id)) { $seen[$kind][$id] } else { 0 })
        if ($seen[$kind][$id] -eq 2) { $id }
    }
}

# Tracked files that the record names in backticks under "## Source" (the findings file).
function Get-FindingsFiles([string]$Record) {
    $inSource = $false
    $lines = Read-Lines $Record
    foreach ($line in $lines) {
        if ($line.StartsWith('## ')) { $inSource = $line.StartsWith('## Source'); continue }
        if (-not $inSource) { continue }
        foreach ($m in [regex]::Matches($line, '`([^`]+)`')) {
            $path = $m.Groups[1].Value
            if ($path -ne $Record -and (Test-Path -LiteralPath $path -PathType Leaf)) { $path }
        }
    }
}

# A line of the record on the integration branch that the squash lost and that is the start of a longer line of the
# result: two lines glued into one (a hand-made conflict resolution without the line break). Nothing when there is none.
function Get-GluedLine([string]$Record) {
    $result = Read-Lines $Record
    $have = New-LineSet $result
    foreach ($line in Get-GitLines @('show', "HEAD:$Record")) {
        $line = $line.TrimEnd([char]13)
        if (-not $line.Trim() -or (Test-Row $line) -or $have.Contains($line)) { continue }
        # Glued only when the rest starts like a line of its own (a bullet, a step, a heading, "Word:"); text a slice
        # adds to the end of a line is no glue.
        $glued = @($result | Where-Object { $_.Length -gt $line.Length -and $_.StartsWith($line, [StringComparison]::Ordinal) -and
            $_.Substring($line.Length) -match '^\s*([-*+] |\d+\. |#+ |\p{L}[\p{L}\d-]*: )' })
        if ($glued) { return $line }
    }
}

# Finding ids the squash would define twice in the record or its findings file, as "<id> in <file>"; ids already
# duplicated on the integration branch do not count.
function Get-NewDuplicateIds([string]$Record) {
    foreach ($file in @($Record) + @(Get-FindingsFiles $Record)) {
        $before = @(Get-DuplicateIds @(Get-GitLines @('show', "HEAD:$file")))
        foreach ($id in @(Get-DuplicateIds (Read-Lines $file) | Sort-Object -Unique)) { if ($before -cnotcontains $id) { "$id in $file" } }
    }
}

# The commands of the line of work/conventions.md that starts with $Prefix ("- Baseline check", "- Full check chain"):
# its backtick spans before the source arrow.
function Get-CheckCommands([string]$Prefix) {
    if (-not (Test-Path $ConventionsFile)) { return }
    $line = Get-Content $ConventionsFile -Encoding utf8 | Where-Object { $_.StartsWith($Prefix) } | Select-Object -First 1
    if (-not $line) { return }
    $line = $line.Split('←')[0]
    foreach ($m in [regex]::Matches($line, '`([^`]*)`')) { if ($m.Groups[1].Value) { $m.Groups[1].Value } }
}

# Why the checks proof .slice-loop/slice-NN.checks does not allow the squash; empty when it does. One line per check:
# "<exit code> <commit SHA> <command>". Only lines of the branch tip count (the SHA is a prefix of it, 7 to 40 hex
# digits): lines of other commits are stale runs, for example of an old session, and ignored. Of each command the last
# line on the tip counts – red then green is fine, green then red is red. Every such line is green and every command
# of the baseline check in work/conventions.md has one.
function Get-ChecksProblem([string]$Nr) {
    $file = Join-Path $LogDir "slice-$Nr.checks"
    if (-not (Test-Path -LiteralPath $file)) { return "no checks proof $LogDir/slice-$Nr.checks" }
    $tip = @(Get-GitLines @('rev-parse', "slice-$Nr"))[0]
    $last = [Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)   # command -> exit code of its last line on the tip
    $stale = 0
    foreach ($line in [IO.File]::ReadAllLines((Join-Path (Get-Location).Path $file))) {
        if (-not $line -or $line.StartsWith('#')) { continue }
        if ($line -cnotmatch '^(-?\d+)\s+([0-9a-f]{7,40})\s+(.+)$') { return "unreadable line in $LogDir/slice-$Nr.checks: $line" }
        $code, $sha, $command = $Matches[1], $Matches[2], $Matches[3]
        if ($tip.StartsWith($sha)) { $last[$command] = $code } else { $stale++ }
    }
    if ($last.Count -eq 0) {
        if ($stale -eq 0) { return "no check listed in $LogDir/slice-$Nr.checks" }
        return "no check ran on the tip $($tip.Substring(0, 12)) of slice-$Nr ($stale stale line(s) ignored)"
    }
    foreach ($command in $last.Keys) { if ($last[$command] -ne '0') { return "check red (exit $($last[$command])): $command" } }
    foreach ($command in Get-CheckCommands '- Baseline check') {
        if (-not $last.Contains($command)) { return "baseline check missing from $LogDir/slice-$Nr.checks: $command" }
    }
    return ''
}

# The files the integration branch (checked out here) changed since slice-NN last took it in that the slice changes too:
# the slice's checks never ran on them together. Documents (*.md) and work/ are left out – the queue merges those by its
# rules. Nothing when the slice's tip already holds the integration branch.
function Get-Overlap([string]$Nr) {
    $base = @(Get-GitLines @('merge-base', 'HEAD', "slice-$Nr"))[0]
    $integration = @(Get-GitLines @('diff', '--name-only', $base, 'HEAD'))
    if (-not $integration) { return }
    $slice = @(Get-GitLines @('diff', '--name-only', $base, "slice-$Nr"))
    $integration | Where-Object { $slice -ccontains $_ -and -not $_.StartsWith('work/') -and -not $_.EndsWith('.md') }
}

# Lines the slice added under "## Decisions" of the round record that are neither a ruling ("Ruling: …") nor a build
# decision ("Build decision (slice NN): …"), each ending in "– <who>, <date>"; a leading "- " is allowed. Empty when every
# added line has one of the formats.
function Get-DecisionProblem([string]$Record, [string]$Branch) {
    $base = @(Get-GitLines @('merge-base', 'HEAD', $Branch))[0]
    $before = @(Get-DecisionLines @(Get-GitLines @('show', "${base}:$Record")))
    $added = @(Get-DecisionLines @(Get-GitLines @('show', "${Branch}:$Record")) | Where-Object { $before -cnotcontains $_ })
    return @($added | Where-Object { $_ -cnotmatch '^(- )?(Ruling: |Build decision \(slice \d{2,}\): ).* – .+, \d\S*$' }) | Select-Object -First 1
}

# The non-empty lines of the section "## Decisions".
function Get-DecisionLines([string[]]$Lines) {
    $inside = $false
    foreach ($line in $Lines) {
        if ($line.StartsWith('## ')) { $inside = $line -match '^## Decisions\b'; continue }
        if ($inside -and $line.Trim()) { $line.TrimEnd() }
    }
}

# Why the slice has not reported ready on its branch tip; empty when it has. As its last step before SLICE-READY,
# /slice writes the tip's SHA to .slice-loop/slice-NN.ready: a session still running its last checks has no such file,
# or one of an older tip, and its worktree is not taken away under it.
function Get-ReadyProblem([string]$Nr) {
    $file = Join-Path $LogDir "slice-$Nr.ready"
    if (-not (Test-Path -LiteralPath $file)) { return "not reported ready: no $LogDir/slice-$Nr.ready (the session has not ended with SLICE-READY)" }
    $tip = @(Get-GitLines @('rev-parse', "slice-$Nr"))[0]
    $sha = [IO.File]::ReadAllText((Join-Path (Get-Location).Path $file)).Trim()
    if ($sha -cmatch '^[0-9a-f]{7,40}$' -and $tip.StartsWith($sha)) { return '' }
    return "slice-$Nr moved after SLICE-READY: $LogDir/slice-$Nr.ready names '$sha', the tip is $($tip.Substring(0, 12))"
}

# Resets the merge in progress, retrying while another process holds a file it has to restore; stops the loop when it
# cannot, so the checkout never stays mid-squash unnoticed. Hard: Merge-Slice starts only on a clean checkout, and a
# reset --merge that failed half-way leaves files every later reset --merge refuses.
function Reset-Merge {
    $script:Merging = $false
    for ($attempt = 0; ; $attempt++) {
        git reset -q --hard *> $null
        if ($LASTEXITCODE -eq 0) { return }
        if ($attempt -ge $WriteRetries) {
            Stop-Loop 'could not reset the merge in progress (a file is still locked by another process?) – run git reset --merge once it is free, then -Merge again'
        }
        Write-Host "slice-loop: could not reset the merge (a file is locked by another process?) – retrying in $WriteBackoff s (attempt $($attempt + 1) of $WriteRetries)"
        Start-Sleep -Seconds $WriteBackoff
    }
}

# Leaves the slice behind after resetting the merge in progress.
function Reset-AndLeave([string]$Nr, [string]$Reason) {
    Reset-Merge
    Add-LeftSlice $Nr "$Reason – merge reset"
}

# Squashes branch slice-NN onto the branch checked out here; $false when it leaves the slice behind (branch kept).
# A file it cannot write leaves the slice behind, too; any other way out of the merge (an exception, a stop) resets it.
function Merge-Slice([string]$Nr) {
    if (Get-GitLines @('status', '--porcelain')) { Stop-Loop "slice ${Nr}: this checkout has uncommitted changes – commit or remove them, then run -Merge" }
    $problem = Get-ReadyProblem $Nr
    if ($problem -and $Merge) { Add-NotReady $Nr $problem; return $false }
    if (-not $problem -and -not (Test-Path -LiteralPath (Join-Path $LogDir "slice-$Nr.msg"))) { $problem = "no squash message: $LogDir/slice-$Nr.msg is missing" }
    if (-not $problem) { $problem = Get-ChecksProblem $Nr }
    if (-not $problem) {
        $overlap = @(Get-Overlap $Nr)
        if ($overlap) { $problem = "integration branch moved and touches $($overlap -join ' ') – merge it on the slice branch" }
    }
    if ($problem) { Add-LeftSlice $Nr $problem; return $false }
    $script:WriteFailed = ''
    $script:Merging = $true
    try { return Invoke-Squash $Nr }
    catch {
        if (-not $script:WriteFailed) { throw }
        Reset-AndLeave $Nr "could not write $($script:WriteFailed) (locked by another process)"
        return $false
    }
    finally { if ($script:Merging) { Reset-Merge } }
}

# The squash of Merge-Slice: every conflict is resolved by rule and checked (a real conflict leaves the slice); then the
# record's manual test list is put in slice order and the slice's block checked, and no finding id may be defined twice.
function Invoke-Squash([string]$Nr) {
    $branch = "slice-$Nr"
    $record = Get-OpenRoundFile  # read before the merge: a conflict at its first line would hide "Status: open"
    # diff3 keeps every hunk whole and shows its base: the default style moves lines both sides end with (such as
    # "Result: ☐") out of the hunk, and keeping both sides would then keep that line once.
    git -c merge.conflictStyle=diff3 merge --squash $branch *> $null
    if ($LASTEXITCODE -ne 0) {
        $conflicts = @(Get-GitLines @('diff', '--name-only', '--diff-filter=U'))
        if (-not $conflicts) { Reset-AndLeave $Nr 'git merge --squash failed'; return $false }
        $real = @()
        foreach ($file in $conflicts) {
            if ($file -eq $ChecklistFile) { Resolve-Checklist $branch }
            elseif (-not (Resolve-Hunks $file $(if ($file -eq $record) { 'record' } else { 'strict' }))) { $real += $file; continue }
            $problem = Get-ResolutionProblem $file $branch
            if ($problem) { Reset-AndLeave $Nr "the rule-based resolution of $file failed its check ($problem)"; return $false }
            git add $file
        }
        if ($real) { Reset-AndLeave $Nr "merge conflict in $($real -join ' ') – merge the integration branch on the slice branch"; return $false }
    }
    if ($record) {
        Sort-ManualTests $record
        git add $record
        $glued = Get-GluedLine $record
        if ($glued) { Reset-AndLeave $Nr "line glued to the next one in ${record}: $glued"; return $false }
        $problem = Get-ManualTestProblem $record $Nr
        if ($problem) { Reset-AndLeave $Nr "manual test block of slice $Nr in ${record}: $problem"; return $false }
        $duplicates = @(Get-NewDuplicateIds $record)
        if ($duplicates) { Reset-AndLeave $Nr "finding id defined twice: $($duplicates -join ', ')"; return $false }
        $decision = Get-DecisionProblem $record $branch
        if ($decision) { Reset-AndLeave $Nr "decision line in neither format ('Ruling: …' or 'Build decision (slice $Nr): …') in ${record}: $decision"; return $false }
    }
    Set-CommitTick $Nr
    git add $ChecklistFile
    Write-Utf8File "$LogDir/slice-$Nr.squashed" "$(@(Get-GitLines @('rev-parse', $branch))[0])`n"
    git commit -q -F (Join-Path $LogDir "slice-$Nr.msg")
    if ($LASTEXITCODE -ne 0) { Stop-Loop "slice ${Nr}: the squash commit failed – merge reset" }
    $script:Merging = $false
    $script:Squashed++
    Write-Host "[slice $Nr] squashed onto $(git branch --show-current) ($(git rev-parse --short HEAD))"
    if (-not (Test-Done $Nr)) { Stop-Loop "slice $Nr was squashed but is not ticked in $ChecklistFile – check it before running again" }
    Remove-SliceBranch $Nr
    return $true
}

# After a build turn: a slice the session squashed itself is done; one that waits on its branch goes through the queue.
function Complete-Slice([string]$Nr) {
    if (-not (Test-Done $Nr)) {
        if (-not (Test-BranchReady $Nr)) {
            Stop-Loop "slice $Nr reported done or ready but is not ticked in $ChecklistFile or on slice-$Nr – check it before running again"
        }
        if (-not (Merge-Slice $Nr)) { return }
    }
    Write-Host "[slice $Nr] done"
}

# A slice squashed in an earlier run whose worktree could not be removed: its branch still points where it did at the
# squash (.slice-loop/slice-NN.squashed), so the removal is tried again; a branch that moved since is left as it is.
function Invoke-RetryRemoval([string]$Nr) {
    $squashed = Join-Path $LogDir "slice-$Nr.squashed"
    if (-not (Test-Path -LiteralPath $squashed)) { return }
    if (@(Get-GitLines @('rev-parse', "slice-$Nr"))[0] -ceq (Get-Content -LiteralPath $squashed -Raw).Trim()) {
        Write-Host "[slice $Nr] already squashed – removing its leftover worktree and branch again"
        Remove-SliceBranch $Nr
    } else {
        Write-Host "[slice $Nr] already squashed; slice-$Nr has commits after the squash – nothing to do for the queue (squash them by hand or delete the branch)"
    }
}

# The number of every slice-NN branch, lowest first.
function Get-SliceNumbers {
    Get-GitLines @('for-each-ref', '--format=%(refname:short)', 'refs/heads/slice-*') |
        Where-Object { $_ -match '^slice-\d{2,}$' } | ForEach-Object { $_ -replace '^slice-', '' } | Sort-Object { [int]$_ }
}

# Whether a slice has reported ready on a tip the queue has not left behind yet.
function Test-SliceReported {
    foreach ($nr in Get-SliceNumbers) {
        if ((Test-Done $nr) -or (Get-ReadyProblem $nr)) { continue }
        $left = Join-Path $LogDir "slice-$nr.left"
        if ((Test-Path -LiteralPath $left) -and (Get-Content -LiteralPath $left -Raw).Trim() -ceq @(Get-GitLines @('rev-parse', "slice-$nr"))[0]) { continue }
        return $true
    }
    return $false
}

# Whether another -Watch shows a sign of life. An older one has died: its file stays, and this run goes on.
# Takes the queue lock; $false while another queue holds it.
function Enter-MergeLock {
    try { New-Item -ItemType Directory -Path $MergeLock -ErrorAction Stop | Out-Null }
    catch {
        if (-not (Test-Path -LiteralPath $MergeLock)) {
            [Console]::Error.WriteLine("slice-loop: could not create $MergeLock – going on without it")
            return $true
        }
        if (((Get-Date) - (Get-Item -LiteralPath $MergeLock).LastWriteTime).TotalMinutes -lt 60) {
            [Console]::Error.WriteLine("slice-loop: another merge queue runs ($MergeLock; delete it if none runs) – this one does nothing")
            return $false
        }
        [Console]::Error.WriteLine("slice-loop: taking over $MergeLock, older than 60 minutes")
    }
    Write-Utf8File "$MergeLock/owner" "merge queue $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))`n"
    return $true
}

function Test-WatchRunning {
    if (-not (Test-Path -LiteralPath $WatchAlive)) { return $false }
    return ((Get-Date) - (Get-Item -LiteralPath $WatchAlive).LastWriteTime).TotalMinutes -lt 60
}

# -Watch: waits until a slice has reported ready; $false after the last check. The queue then runs once and the script
# ends, so the chat that started it in the background is woken even when a session's own report never reached it.
function Wait-ForReadySlice {
    Write-Host "slice-loop: watching for SLICE-READY every $WatchSeconds s, at most $WatchMax check(s)"
    for ($check = 1; $check -le $WatchMax; $check++) {
        Set-Content -LiteralPath $WatchAlive -Value '' -NoNewline
        if (Test-SliceReported) { return $true }
        if ($check -lt $WatchMax) { Start-Sleep -Seconds $WatchSeconds }
    }
    Write-Host "slice-loop: no slice reported ready after $WatchMax check(s) – start the watch again while sessions run"
    return $false
}

# The merge queue alone (-Merge): every slice-NN branch, lowest number first; one not ticked through Checks is left,
# one that conflicts or lacks its proof is left behind and the queue goes on.
function Invoke-MergeQueue {
    foreach ($nr in Get-SliceNumbers) {
        $branch = "slice-$nr"
        if (Test-Done $nr) { Invoke-RetryRemoval $nr; continue }
        if (Test-BranchReady $nr) { [void](Merge-Slice $nr) }
        else { Write-Host "[slice $nr] not ready to merge: its row on $branch is not ticked through Checks – left as it is" }
    }
}

# Who holds the full-suite lock, from its owner file, e.g. "slice 100 2026-10-27T09:00:00Z" or "merge queue …".
function Get-LockOwner {
    $file = Join-Path $LockDir 'owner'
    if (-not (Test-Path -LiteralPath $file)) { return 'unknown' }
    return (Get-Content -LiteralPath $file -Raw -Encoding utf8).Trim()
}

# Reports a full-suite lock nobody can hold any more: its owner is a slice whose branch is gone, or it is older than an
# hour. Only reports – removing it is the caller's call; the run goes on.
function Write-StaleLockNotice {
    if (-not (Test-Path -LiteralPath $LockDir -PathType Container)) { return }
    $owner = Get-LockOwner
    $why = ''
    $ownerFile = Join-Path $LockDir 'owner'
    $touched = (Get-Item -LiteralPath $(if (Test-Path -LiteralPath $ownerFile) { $ownerFile } else { $LockDir })).LastWriteTime
    if ($owner -match '^slice (\d{2,})(\s|$)' -and -not (Get-GitLines @('rev-parse', '--verify', '--quiet', "refs/heads/slice-$($Matches[1])"))) {
        $why = 'its slice branch is gone'
    } elseif (((Get-Date) - $touched).TotalMinutes -gt 60) {
        $why = 'it is older than 60 minutes'
    }
    if ($why) { [Console]::Error.WriteLine("slice-loop: stale lock $LockDir (owner: $owner) – $why; remove it with: Remove-Item -Recurse $LockDir") }
}

# Reports a work/conventions.md without a "- Baseline check" line: the queue then cannot require the baseline commands
# in the checks proof. A key translated into the repository's language is the usual cause. Only reports; the run goes on.
function Write-BaselineNotice {
    if (-not (Test-Path -LiteralPath $ConventionsFile)) { return }
    if (Select-String -LiteralPath $ConventionsFile -Pattern '^- Baseline check' -CaseSensitive -Quiet) { return }
    [Console]::Error.WriteLine("slice-loop: no '- Baseline check' line in $ConventionsFile – checks proofs are not checked for the baseline commands; the key stays English in any language, e.g. '- Baseline check (<own words>): ``<command>``'")
}

# After the merge queue (-Verify): when the queue squashed a slice, every command of the "- Full check chain" line in
# work/conventions.md runs on the integration branch, under the full-suite lock. $false when one is red or the lock is held.
function Invoke-Verify {
    if ($Squashed -eq 0) { return $true }
    $commands = @(Get-CheckCommands '- Full check chain')
    if (-not $commands) {
        Write-Host "slice-loop: no '- Full check chain' line in $ConventionsFile – nothing verified (the key stays English in any language)"
        return $true
    }
    try { New-Item -ItemType Directory -Path $LockDir -ErrorAction Stop | Out-Null }
    catch {
        [Console]::Error.WriteLine("slice-loop: $LockDir is held (owner: $(Get-LockOwner)) – the full check chain was not run")
        return $false
    }
    $red = $false
    try {
        Write-Utf8File "$LockDir/owner" "merge queue $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))`n"
        foreach ($command in $commands) {
            # A process of its own: an "exit" in the command ends that process, not this script with the lock held.
            # It hands on the command's own exit code (-Command alone turns every failure into 1).
            $program = "`$global:LASTEXITCODE = 0`n$command`nif (-not `$?) { exit [Math]::Max(1, [int]`$LASTEXITCODE) }`nexit `$LASTEXITCODE"
            & (Get-Process -Id $PID).Path -NoProfile -Command $program | Out-Host
            $code = $LASTEXITCODE
            Write-Host "[verify] $command – $(if ($code -eq 0) { 'green' } else { "red (exit $code)" })"
            if ($code -ne 0) { $red = $true }
        }
    } finally { Remove-Item -LiteralPath $LockDir -Recurse -Force -ErrorAction SilentlyContinue }
    if ($red) { [Console]::Error.WriteLine("slice-loop: full check chain red on $(git branch --show-current) after the merge queue") }
    return -not $red
}

# Two paths of the "files" of slices overlap when they are equal or one is a prefix ending in "/" of the other.
# Returns the more specific of the two, nothing when they do not overlap.
function Get-SharedPath([string]$A, [string]$B) {
    if ($A -ceq $B) { return $A }
    if ($A.EndsWith('/') -and $B.StartsWith($A, [StringComparison]::Ordinal)) { return $B }
    if ($B.EndsWith('/') -and $A.StartsWith($B, [StringComparison]::Ordinal)) { return $A }
}

# The ready slices (in order) that go into the next -Parallel batch: at most $ParallelMax, and none whose "files" overlap
# a slice already picked; that one waits for a later batch.
function Select-ParallelBatch([string[]]$Ready) {
    $files = @{}
    foreach ($slice in Get-Slices) { $files[$slice.Nr] = $slice.Files }
    $batch = [Collections.Generic.List[string]]::new()
    foreach ($nr in $Ready) {
        if ($batch.Count -ge $ParallelMax) { break }
        $clash = $null
        foreach ($other in $batch) {
            foreach ($mine in $files[$nr]) {
                foreach ($theirs in $files[$other]) {
                    if (-not $clash -and (Get-SharedPath $mine $theirs)) { $clash = "shares $(Get-SharedPath $mine $theirs) with slice $other" }
                }
            }
        }
        if ($clash) { Write-Host "[slice $nr] waits: $clash" } else { $batch.Add($nr) }
    }
    return , [string[]]$batch
}

function Get-ReadySlices {
    foreach ($slice in Get-Slices) {
        if ((Test-Done $slice.Nr) -or $script:LeftBehind.Contains($slice.Nr)) { continue }
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

# SLICE-WAIT: the session ended its turn while its checks still run – it is not done, so check back in the same session.
# Returns the output of the last turn.
function Wait-WhileRunning([string]$Nr, [string]$Session, [string]$Log, [string]$Model, [string]$Output) {
    $waits = 0
    while ($true) {
        $finished = @(Get-MarkerLines $Output 'SLICE-DONE:') + @(Get-MarkerLines $Output 'SLICE-READY:')
        $waiting = @(Get-MarkerLines $Output "SLICE-WAIT: $Nr" | Where-Object { $_ -cmatch "^SLICE-WAIT: $Nr(\D|$)" })
        if (($finished -cmatch "^SLICE-(DONE|READY): $Nr(\D|$)") -or -not $waiting) { return $Output }
        $what = $waiting[-1].Substring("SLICE-WAIT: $Nr".Length).Trim()
        if ($waits -ge $WaitMax) { Stop-Loop "slice $Nr still waiting after $waits check-backs ($($waiting[-1])) – see $Log" }
        $waits++
        Write-Host "[slice $Nr] still running: $what – checking back in ${WaitSeconds}s"
        Start-Sleep -Seconds $WaitSeconds
        $Output = Invoke-ClaudeTurn $Log @('--resume', $Session,
            "Still waiting for: $what. Check it; when it is done, finish slice $Nr and close it (auto).") $Model
    }
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
    if (-not $ready) {
        if (-not (Write-LeftReport)) { exit 1 }
        Stop-Loop "no slice is ready – check $ChecklistFile (/slice status)"
    }
    $ready = if ($Parallel) { @(Select-ParallelBatch $ready) } else { @($ready[0]) }
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
        $output = Invoke-ClaudeTurn $run.Log @('--resume', $run.Session, $run.Message) $run.Model
        Assert-SliceFinished $run.Nr (Wait-WhileRunning $run.Nr $run.Session $run.Log $run.Model $output) $run.Log
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
        $output = Wait-WhileRunning $runs[$i].Nr $runs[$i].Session $runs[$i].Log $runs[$i].Model $output
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
if ($Verify -and -not $Merge) { Stop-Loop "-Verify needs -Merge ($Usage)" }
if ($Watch -and -not $Merge) { Stop-Loop "-Watch needs -Merge ($Usage)" }
if (-not ((Test-Path $SlicesFile) -and (Test-Path $ChecklistFile))) {
    Stop-Loop "run from the repo root (needs $SlicesFile and $ChecklistFile)"
}
if ($DryRun) { Get-ReadySlices; exit 0 }
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$exclude = '.git/info/exclude'
if ((Test-Path $exclude) -and -not (Select-String -Path $exclude -Pattern "^$LogDir/$" -Quiet)) {
    Add-Content -Path $exclude -Value "$LogDir/"
}
Write-StaleLockNotice
Write-BaselineNotice
if ($Merge) {
    if ($Watch -and (Test-WatchRunning)) {
        Write-Host "slice-loop: already watching ($WatchAlive is under 60 minutes old; delete it if no watch runs)"
        exit 0
    }
    try {
        if ($Watch -and -not (Wait-ForReadySlice)) { exit 0 }
        if (-not (Enter-MergeLock)) { exit 0 }
        try { Invoke-MergeQueue }
        finally { Remove-Item -LiteralPath $MergeLock -Recurse -Force -ErrorAction SilentlyContinue }
        $clean = Write-LeftReport
        $verified = if ($Verify) { Invoke-Verify } else { $true }
        if (-not ($clean -and $verified)) { exit 1 }
        exit 0
    }
    finally { if ($Watch) { Remove-Item -LiteralPath $WatchAlive -ErrorAction SilentlyContinue } }
}
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
        if (-not (Write-LeftReport)) { exit 1 }
        exit 0
    }
}
Close-Round
if ($LinkLost) { exit 1 }
