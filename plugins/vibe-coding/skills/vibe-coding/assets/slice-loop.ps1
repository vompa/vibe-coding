#Requires -Version 7
<#
.SYNOPSIS
Builds the open round slice by slice, each slice in a fresh headless Claude session, then closes the round.
A slice that ends with SLICE-READY is squashed by the merge queue: one slice-NN branch after another, in this
checkout, with the message from .slice-loop/slice-NN.msg, once .slice-loop/slice-NN.checks proves green checks on
the branch tip. Conflicts are resolved by rule and checked: work/checklist.md by the union of ticks, and in any text
file a hunk where both sides only added lines (both kept) or changed rows of one table (merged per row key, e.g. the
status row of a round). A real conflict, a missing proof, a duplicate finding id or a malformed manual test block
leaves that slice behind with its branch; the queue goes on, lists every slice left behind and exits non-zero.
Stops for plan approval unless -Yes; stops on NEEDS-DECISION, red tests or a blocked slice. A slice that ends its
turn with SLICE-WAIT is still running: the loop checks back on it in the same session.

.EXAMPLE
pwsh .claude/scripts/slice-loop.ps1                  # ask for every plan
pwsh .claude/scripts/slice-loop.ps1 -Yes             # approve plans without asking
pwsh .claude/scripts/slice-loop.ps1 -Parallel        # build ready slices side by side (headless; for long autonomous runs)
pwsh .claude/scripts/slice-loop.ps1 -DryRun          # only print the slices that are ready now
pwsh .claude/scripts/slice-loop.ps1 -MaxSlices 3     # stop after 3 built slices if slices are left (exit 0; run again to continue)
pwsh .claude/scripts/slice-loop.ps1 -Merge           # only run the merge queue: squash every slice-NN branch ticked through Checks, retry removing worktrees an earlier squash left, then exit (starts no session, needs no open round)
Env: SLICE_PERMISSION_MODE (default: auto) – passed to claude --permission-mode.
     SLICE_WAIT_SECONDS (default: 60), SLICE_WAIT_MAX (default: 30) – pause and number of check-backs on SLICE-WAIT.
     SLICE_WRITE_RETRIES (default: 5), SLICE_WRITE_BACKOFF_SECONDS (default: 2) – retries and pause when the queue
     cannot write a file or reset a merge because another process (scanner, indexer, editor) holds it.
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
$ConventionsFile = 'work/conventions.md'
$RoundsDir = 'work/rounds'
$LogDir = '.slice-loop'
$PermissionMode = if ($env:SLICE_PERMISSION_MODE) { $env:SLICE_PERMISSION_MODE } else { 'auto' }
$WaitSeconds = if ($env:SLICE_WAIT_SECONDS) { [int]$env:SLICE_WAIT_SECONDS } else { 60 }
$WaitMax = if ($env:SLICE_WAIT_MAX) { [int]$env:SLICE_WAIT_MAX } else { 30 }
$WriteRetries = if ($env:SLICE_WRITE_RETRIES) { [int]$env:SLICE_WRITE_RETRIES } else { 5 }
$WriteBackoff = if ($env:SLICE_WRITE_BACKOFF_SECONDS) { [double]$env:SLICE_WRITE_BACKOFF_SECONDS } else { 2 }
$WriteFailed = ''   # the file Write-Utf8File gave up on
$Merging = $false   # a squash merge is in progress in this checkout; Merge-Slice resets it on any way out
$Usage = 'use -Yes, -Parallel, -DryRun, -MaxSlices N, -Merge'
$SliceCap = 0   # 0 = no cap
$Built = 0
$LeftBehind = [ordered]@{}  # slices the merge queue left behind in this run: number -> reason

function Stop-Loop([string]$Message) {
    [Console]::Error.WriteLine("slice-loop: $Message")
    exit 1
}

# Leaves a slice behind: its branch stays, the run goes on without it.
function Add-LeftSlice([string]$Nr, [string]$Reason) {
    Write-Host "[slice $Nr] left behind: $Reason – slice-$Nr kept"
    $script:LeftBehind[$Nr] = $Reason
}

# Lists every slice left behind; $false when there is one.
function Write-LeftReport {
    if ($script:LeftBehind.Count -eq 0) { return $true }
    [Console]::Error.WriteLine("slice-loop: $($script:LeftBehind.Count) slice(s) left behind – fix them on their branch, then run -Merge again:")
    foreach ($nr in $script:LeftBehind.Keys) { [Console]::Error.WriteLine("  slice ${nr}: $($script:LeftBehind[$nr])") }
    return $false
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
        # Links first (for example node_modules as a junction onto the main checkout): git follows a junction when it
        # removes the worktree and empties its target. Deleting the reparse point removes the link, never the target.
        foreach ($link in @(Get-ChildItem -LiteralPath $path -Recurse -Force -Attributes ReparsePoint -ErrorAction SilentlyContinue)) {
            if ($link.PSIsContainer) { [System.IO.Directory]::Delete($link.FullName) } else { [System.IO.File]::Delete($link.FullName) }
        }
        git worktree remove $path *> $null
        if ($LASTEXITCODE -ne 0) {
            Write-Host ("[slice $Nr] worktree $path could not be removed – most likely a shell, editor or process still runs inside it " +
                "(or it is locked); close it and run -Merge again to retry. $path and $branch are kept")
            return
        }
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

# Finding ids the squash would define twice in the record or its findings file, as "<id> in <file>"; ids already
# duplicated on the integration branch do not count.
function Get-NewDuplicateIds([string]$Record) {
    foreach ($file in @($Record) + @(Get-FindingsFiles $Record)) {
        $before = @(Get-DuplicateIds @(Get-GitLines @('show', "HEAD:$file")))
        foreach ($id in @(Get-DuplicateIds (Read-Lines $file) | Sort-Object -Unique)) { if ($before -cnotcontains $id) { "$id in $file" } }
    }
}

# The commands of the "Baseline check" line in work/conventions.md: its backtick spans before the source arrow.
function Get-BaselineCommands {
    if (-not (Test-Path $ConventionsFile)) { return }
    $line = Get-Content $ConventionsFile -Encoding utf8 | Where-Object { $_.StartsWith('- Baseline check') } | Select-Object -First 1
    if (-not $line) { return }
    $line = $line.Split('←')[0]
    foreach ($m in [regex]::Matches($line, '`([^`]*)`')) { if ($m.Groups[1].Value) { $m.Groups[1].Value } }
}

# Why the checks proof .slice-loop/slice-NN.checks does not allow the squash; empty when it does. One line per check:
# "<exit code> <commit SHA> <command>". Every exit code is 0, every SHA is the branch tip (7 to 40 hex digits), and
# every command of the baseline check in work/conventions.md is listed.
function Get-ChecksProblem([string]$Nr) {
    $file = Join-Path $LogDir "slice-$Nr.checks"
    if (-not (Test-Path -LiteralPath $file)) { return "no checks proof $LogDir/slice-$Nr.checks" }
    $tip = @(Get-GitLines @('rev-parse', "slice-$Nr"))[0]
    $ran = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($line in [IO.File]::ReadAllLines((Join-Path (Get-Location).Path $file))) {
        if (-not $line -or $line.StartsWith('#')) { continue }
        if ($line -cnotmatch '^(-?\d+)\s+([0-9a-f]{7,40})\s+(.+)$') { return "unreadable line in $LogDir/slice-$Nr.checks: $line" }
        $code, $sha, $command = $Matches[1], $Matches[2], $Matches[3]
        if ($code -ne '0') { return "check red (exit $code): $command" }
        if (-not $tip.StartsWith($sha)) { return "check ran on $sha, not on the tip $($tip.Substring(0, 12)) of slice-${Nr}: $command" }
        [void]$ran.Add($command)
    }
    if ($ran.Count -eq 0) { return "no check listed in $LogDir/slice-$Nr.checks" }
    foreach ($command in Get-BaselineCommands) {
        if (-not $ran.Contains($command)) { return "baseline check missing from $LogDir/slice-$Nr.checks: $command" }
    }
    return ''
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
    $problem = Get-ChecksProblem $Nr
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
        if ($real) { Reset-AndLeave $Nr "merge conflict in $($real -join ' ')"; return $false }
    }
    if ($record) {
        Sort-ManualTests $record
        git add $record
        $problem = Get-ManualTestProblem $record $Nr
        if ($problem) { Reset-AndLeave $Nr "manual test block of slice $Nr in ${record}: $problem"; return $false }
        $duplicates = @(Get-NewDuplicateIds $record)
        if ($duplicates) { Reset-AndLeave $Nr "finding id defined twice: $($duplicates -join ', ')"; return $false }
    }
    Set-CommitTick $Nr
    git add $ChecklistFile
    Write-Utf8File "$LogDir/slice-$Nr.squashed" "$(@(Get-GitLines @('rev-parse', $branch))[0])`n"
    git commit -q -F (Get-SquashMessageFile $Nr)
    if ($LASTEXITCODE -ne 0) { Stop-Loop "slice ${Nr}: the squash commit failed – merge reset" }
    $script:Merging = $false
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
        Write-Host "[slice $Nr] already squashed, but slice-$Nr moved since – left as it is"
    }
}

# The merge queue alone (-Merge): every slice-NN branch, lowest number first; one not ticked through Checks is left,
# one that conflicts or lacks its proof is left behind and the queue goes on.
function Invoke-MergeQueue {
    $branches = Get-GitLines @('for-each-ref', '--format=%(refname:short)', 'refs/heads/slice-*') |
        Where-Object { $_ -match '^slice-\d{2,}$' } | Sort-Object { [int]($_ -replace '^slice-', '') }
    foreach ($branch in $branches) {
        $nr = $branch -replace '^slice-', ''
        if (Test-Done $nr) { Invoke-RetryRemoval $nr; continue }
        if (Test-BranchReady $nr) { [void](Merge-Slice $nr) }
        else { Write-Host "[slice $nr] not ready to merge: its row on $branch is not ticked through Checks – left as it is" }
    }
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
if (-not ((Test-Path $SlicesFile) -and (Test-Path $ChecklistFile))) {
    Stop-Loop "run from the repo root (needs $SlicesFile and $ChecklistFile)"
}
if ($DryRun) { Get-ReadySlices; exit 0 }
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$exclude = '.git/info/exclude'
if ((Test-Path $exclude) -and -not (Select-String -Path $exclude -Pattern "^$LogDir/$" -Quiet)) {
    Add-Content -Path $exclude -Value "$LogDir/"
}
if ($Merge) { Invoke-MergeQueue; if (-not (Write-LeftReport)) { exit 1 }; exit 0 }
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
