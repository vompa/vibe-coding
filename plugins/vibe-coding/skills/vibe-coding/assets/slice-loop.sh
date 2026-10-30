#!/usr/bin/env bash
# Builds the open round slice by slice, each slice in a fresh headless Claude session, then closes the round.
# A slice that ends with SLICE-READY is squashed by the merge queue: one slice-NN branch after another, in this
# checkout, with the message from .slice-loop/slice-NN.msg, once .slice-loop/slice-NN.ready names the branch tip (the
# session wrote it last, at SLICE-READY) and .slice-loop/slice-NN.checks proves green checks on
# the branch tip. Only proof lines of the branch tip count (lines of other commits are stale runs and ignored); of each
# command the last line on the tip counts. Conflicts are resolved by rule and checked: work/checklist.md by the union of
# ticks, and in any text file a hunk where both sides only added lines (both kept) or changed rows of one table (merged
# per row key, e.g. the status row of a round). A slice cut from an older integration branch is squashed as it is,
# unless the integration branch changed since then a file the slice changes too (documents *.md and work/ aside). That
# overlap, a real conflict, a missing proof, a duplicate finding id, a line glued to the next one in the round record, a
# decision line in neither format ("Ruling: …", "Build decision (slice NN): …") or a malformed manual test block leaves
# that slice behind with its branch; the queue goes on, lists every slice left behind and exits non-zero. A slice whose
# session has not reported ready on its tip yet is listed as not ready yet and does not fail --merge. Removing the worktree of a squashed slice is retried, and
# the entries of every folder a link in the worktree points to are counted before and after: fewer afterwards is
# reported and makes the run exit non-zero (the squash stays done). A stale .slice-loop/full-suite.lock (its slice
# branch is gone, or it is older than 60 minutes) is reported at the start, never removed; so is a work/conventions.md
# without a "- Baseline check" line (its keys stay English in any language).
# Stops for plan approval unless --yes; stops on NEEDS-DECISION, red tests or a blocked slice. A slice that ends its
# turn with SLICE-WAIT is still running: the loop checks back on it in the same session.
#
# Usage: bash .claude/scripts/slice-loop.sh [--yes] [--parallel] [--dry-run] [--max-slices N] [--merge [--verify] [--watch]]
#   --yes           approve plans without asking (still stops on NEEDS-DECISION)
#   --parallel      build slices that are ready at the same time side by side (headless; for long autonomous runs):
#                   at most SLICE_PARALLEL_MAX per batch, and a slice whose "files" in work/_slices.json overlap a
#                   slice already in the batch waits for the next one
#   --dry-run       only print the slices that are ready now, then exit
#   --max-slices N  stop after N built slices if slices are left (exit 0; run again to continue)
#   --merge         only run the merge queue: squash every slice-NN branch ticked through Checks, retry removing
#                   worktrees an earlier squash left, then exit (starts no session, needs no open round)
#   --verify        with --merge: after the queue, when it squashed a slice, run every command of the "- Full check
#                   chain" line in work/conventions.md on the integration branch, under .slice-loop/full-suite.lock
#                   (red: exit 1)
#   --watch         with --merge: wait until a slice reports ready on a new tip, run the queue once, then exit (a
#                   background command, so it wakes the chat that started it). A slice left behind brings it back only
#                   with a new tip; a second watch next to a running one exits at once
# Optional field "files" of an entry in work/_slices.json: the repo-relative paths (or prefixes ending in "/") the slice
# is expected to change.
# Env: SLICE_PERMISSION_MODE (default: auto) – passed to claude --permission-mode.
#      SLICE_PARALLEL_MAX (default: 2) – most slices in one --parallel batch (three sessions on one machine made unrelated tests red under load).
#      SLICE_WAIT_SECONDS (default: 60), SLICE_WAIT_MAX (default: 30) – pause and number of check-backs on SLICE-WAIT.
#      SLICE_WATCH_SECONDS (default: 60), SLICE_WATCH_MAX (default: 480) – pause and number of checks of --watch.
#      SLICE_WRITE_RETRIES (default: 5), SLICE_WRITE_BACKOFF_SECONDS (default: 2) – retries and pause when the queue
#      cannot write a file or reset a merge because another process (scanner, indexer, editor) holds it, and when git
#      cannot remove the worktree of a squashed slice (a shell of the finished session may still stand in it).
set -euo pipefail
shopt -s inherit_errexit
# Git Bash on Windows would rewrite the argument "/slice …" into a Windows path.
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'

readonly SLICES_FILE="work/_slices.json"
readonly CHECKLIST_FILE="work/checklist.md"
readonly CONVENTIONS_FILE="work/conventions.md"
readonly ROUNDS_DIR="work/rounds"
readonly LOG_DIR=".slice-loop"
readonly PERMISSION_MODE="${SLICE_PERMISSION_MODE:-auto}"
readonly WAIT_SECONDS="${SLICE_WAIT_SECONDS:-60}"
readonly WAIT_MAX="${SLICE_WAIT_MAX:-30}"
readonly WRITE_RETRIES="${SLICE_WRITE_RETRIES:-5}"
readonly WRITE_BACKOFF="${SLICE_WRITE_BACKOFF_SECONDS:-2}"
readonly PARALLEL_MAX="${SLICE_PARALLEL_MAX:-2}"
readonly WATCH_SECONDS="${SLICE_WATCH_SECONDS:-60}"
readonly WATCH_MAX="${SLICE_WATCH_MAX:-480}"
readonly WATCH_ALIVE="$LOG_DIR/watch.alive"  # sign of life of a running --watch, written at every check
readonly MERGE_LOCK="$LOG_DIR/merge.lock"  # taken (mkdir) by a running --merge queue; older than 60 minutes: its owner died
readonly LOCK_DIR="$LOG_DIR/full-suite.lock"  # taken (mkdir) by whoever runs the full suite; holds a file "owner"
readonly USAGE="use --yes, --parallel, --dry-run, --max-slices N, --merge, --verify and --watch (with --merge)"

auto_approve=false
parallel=false
dry_run=false
merge_only=false
verify=false
watch=false
merge_locked=false      # this run holds the queue lock; the exit trap removes it
watching=false          # this run wrote the sign of life; the exit trap removes it
squashed_count=0        # slices this run squashed
link_lost=false         # a folder a link of a removed worktree pointed to lost entries
max_slices=0  # 0 = no cap
built=0
round=""
declare -A left_nrs=()  # slices the merge queue left behind in this run
left_lines=()           # "slice NN: <reason>", in the order they were left
not_ready_lines=()      # "slice NN: <reason>" for slices --merge found not ready yet (their session still checks)
clean_up_lines=()       # "slice NN: <what is left>" for squashed slices whose worktree or folder could not be removed
write_failed=""         # the file replace_file gave up on
merging=""              # a squash merge is in progress in this checkout; the exit trap resets it

die() { echo "slice-loop: $*" >&2; exit 1; }

# Moves temp file $1 onto $2, retrying while another process holds $2 (a scanner or indexer with it mapped); after the
# last retry it names $2 in write_failed and fails.
replace_file() {
  local tmp=$1 target=$2 attempt
  for (( attempt = 0; ; attempt++ )); do
    mv -f "$tmp" "$target" 2>/dev/null && return 0
    if (( attempt >= WRITE_RETRIES )); then write_failed=$target; return 1; fi
    echo "slice-loop: could not write $target (locked by another process?) – retrying in $WRITE_BACKOFF s (attempt $((attempt + 1)) of $WRITE_RETRIES)" >&2
    sleep "$WRITE_BACKOFF"
  done
}

# Resets the merge in progress, retrying while another process holds a file it has to restore; stops the loop when it
# cannot, so the checkout never stays mid-squash unnoticed. Hard: merge_slice starts only on a clean checkout, and a
# reset --merge that failed half-way leaves files every later reset --merge refuses.
reset_merge() {
  local attempt
  merging=""
  for (( attempt = 0; ; attempt++ )); do
    git reset -q --hard 2>/dev/null && return 0
    (( attempt < WRITE_RETRIES )) \
      || die "could not reset the merge in progress (a file is still locked by another process?) – run git reset --merge once it is free, then --merge again"
    echo "slice-loop: could not reset the merge (a file is locked by another process?) – retrying in $WRITE_BACKOFF s (attempt $((attempt + 1)) of $WRITE_RETRIES)" >&2
    sleep "$WRITE_BACKOFF"
  done
}
trap 'if $watching; then rm -f "$WATCH_ALIVE"; fi; if $merge_locked; then rm -r "$MERGE_LOCK" || true; fi; if [[ -n "$merging" ]]; then reset_merge; fi' EXIT
trap 'exit 130' INT TERM

# Leaves slice $1 behind for reason $2: its branch stays, the run goes on without it.
leave_slice() {
  echo "[slice $1] left behind: $2 – slice-$1 kept" >&2
  left_nrs[$1]=1
  left_lines+=("slice $1: $2")
  # --watch comes back to this slice only with a new tip.
  if $watch; then git rev-parse "slice-$1" >"$LOG_DIR/slice-$1.left"; fi
}

# Slice $1 is left for a later --merge (reason $2): its session has not reported ready on its tip yet. Not a problem
# of the slice.
not_ready() {
  echo "[slice $1] not ready yet: $2 – left for a later --merge" >&2
  not_ready_lines+=("slice $1: $2")
}

# Lists every slice not ready yet and every slice left behind; fails when one was left behind, or when a removed
# worktree's link target lost entries (that was reported where it happened). Not ready yet alone is no failure.
report_left() {
  if (( ${#not_ready_lines[@]} > 0 )); then
    echo "slice-loop: ${#not_ready_lines[@]} slice(s) not ready yet – their sessions still check; run --merge again after SLICE-READY:" >&2
    printf '  %s\n' "${not_ready_lines[@]}" >&2
  fi
  if (( ${#left_lines[@]} > 0 )); then
    echo "slice-loop: ${#left_lines[@]} slice(s) left behind – fix them on their branch, then run --merge again:" >&2
    printf '  %s\n' "${left_lines[@]}" >&2
  fi
  if (( ${#clean_up_lines[@]} > 0 )); then
    echo "slice-loop: ${#clean_up_lines[@]} squashed slice(s) left something to clean up:" >&2
    printf '  %s\n' "${clean_up_lines[@]}" >&2
  fi
  (( ${#left_lines[@]} == 0 )) && ! $link_lost
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes) auto_approve=true ;;
      --parallel) parallel=true ;;
      --dry-run) dry_run=true ;;
      --merge) merge_only=true ;;
      --verify) verify=true ;;
      --watch) watch=true ;;
      --max-slices)
        [[ $# -ge 2 && "$2" =~ ^[1-9][0-9]*$ ]] || die "--max-slices needs a positive integer ($USAGE)"
        max_slices=$2
        shift ;;
      *) die "unknown option '$1' ($USAGE)" ;;
    esac
    shift
  done
  if $verify && ! $merge_only; then die "--verify needs --merge ($USAGE)"; fi
  if $watch && ! $merge_only; then die "--watch needs --merge ($USAGE)"; fi
}

# Slice numbers in plan order, one per line.
slice_numbers() {
  grep -o '"nr"[[:space:]]*:[[:space:]]*"[0-9][0-9]*"' "$SLICES_FILE" | grep -o '"[0-9][0-9]*"$' | tr -d '"'
}

# Dependencies of every slice, one line per slice in the same order (may be empty).
slice_deps() {
  grep -o '"deps"[[:space:]]*:[[:space:]]*"[^"]*"' "$SLICES_FILE" \
    | sed 's/^"deps"[[:space:]]*:[[:space:]]*//' \
    | while IFS= read -r deps; do { grep -oE '[0-9]{2,}' <<<"$deps" || true; } | tr '\n' ' '; echo; done
}

# Text field $2 of slice $1, empty when the entry has none. The entries hold no nested objects, so "}" ends an
# entry; a value with an escaped quote is cut at that quote.
slice_field() {
  tr '\n}' ' \n' <"$SLICES_FILE" \
    | grep "\"nr\"[[:space:]]*:[[:space:]]*\"$1\"" \
    | grep -o "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed 's/^[^:]*:[[:space:]]*"//; s/"$//' || true
}

# The "files" of slice $1 (paths the slice is expected to change), one per line; nothing when the entry has none.
slice_files() {
  tr '\n}' ' \n' <"$SLICES_FILE" \
    | grep "\"nr\"[[:space:]]*:[[:space:]]*\"$1\"" \
    | { grep -o '"files"[[:space:]]*:[[:space:]]*\[[^]]*\]' || true; } \
    | sed 's/^"files"[[:space:]]*:[[:space:]]*\[//; s/\]$//' \
    | { grep -o '"[^"]*"' || true; } | tr -d '"'
}

# Model of slice $1 – its "model" field. Every turn of the slice runs on it, never on the default of the caller.
slice_model() { slice_field "$1" model; }

# A slice is done when its checklist row has at least one ☑ and no ☐.
is_done() {
  local row
  row=$(grep -E "^\|[[:space:]]*$1([^0-9]|$)" "$CHECKLIST_FILE" || true)
  [[ -n "$row" && "$row" == *"☑"* && "$row" != *"☐"* ]]
}

# Ready for the merge queue: the slice's row on branch slice-$1 has a ☑ and no ☐ outside its last cell (Commit).
branch_ready() {
  local row body
  row=$(git show "slice-$1:$CHECKLIST_FILE" 2>/dev/null | grep -E "^\|[[:space:]]*$1([^0-9]|$)" | head -1) || return 1
  body=${row%|*}   # without the closing pipe
  body=${body%|*}  # without the last cell
  [[ "$body" == *"☑"* && "$body" != *"☐"* ]]
}

# Ticks the last open box of slice $1's row – its Commit column – keeping the file's line endings.
tick_commit() {
  sed -E "/^\|[[:space:]]*$1([^0-9]|\$)/ s/(.*)☐/\1☑/" "$CHECKLIST_FILE" >"$LOG_DIR/checklist.tmp"
  replace_file "$LOG_DIR/checklist.tmp" "$CHECKLIST_FILE"
}

# Path of the worktree that has branch $1 checked out; nothing when none has.
worktree_of() {
  local line path=""
  while IFS= read -r line; do
    case "$line" in
      "worktree "*) path=${line#worktree } ;;
      "branch refs/heads/$1") echo "$path"; return ;;
    esac
  done < <(git worktree list --porcelain)
}

# Removes the squashed branch slice-$1 and its worktree; a worktree git will not remove is reported and kept with its branch.
# Removes every symlink and junction inside worktree $1, never what it points to: on Windows git follows a
# junction (for example node_modules linked onto the main checkout) when it removes the worktree and empties its target.
unlink_links() {
  local link
  while IFS= read -r link; do
    if [[ -d "$link" ]] && command -v cygpath >/dev/null 2>&1; then
      # Plain /c: this script turns off Git Bash path conversion, so //c would reach cmd as it is.
      cmd /c rmdir "$(cygpath -w "$link")" >/dev/null
    else
      rm -f "$link"
    fi
  done < <(find "$1" -type l 2>/dev/null)
}

# Entries directly in folder $1.
entry_count() { find "$1" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' '; }

# Removes the worktree $2 of slice $1 and its links like unlink_links, counting the entries of every folder a link
# points to before and after, so that a loss is reported (and makes the run fail). Fails when git will not remove the
# worktree, even after retries.
remove_worktree() {
  local nr=$1 path=$2 link target now attempt
  local -A held=()
  while IFS= read -r link; do
    target=$(readlink -f "$link" 2>/dev/null || true)
    if [[ -n "$target" && -d "$target" && -z "${held[$target]+set}" ]]; then held[$target]=$(entry_count "$target"); fi
  done < <(find "$path" -type l 2>/dev/null)
  unlink_links "$path"
  # A shell of the finished session may still stand in the worktree: it often lets go within seconds.
  for (( attempt = 0; ; attempt++ )); do
    git worktree remove "$path" >/dev/null 2>&1 && break
    # Git drops its entry even when files inside are held: there is nothing left to retry, only a folder.
    [[ -n "$(worktree_of "slice-$nr")" ]] || break
    (( attempt < WRITE_RETRIES )) || return 1
    echo "slice-loop: could not remove the worktree of slice-$nr (a shell or process still runs inside it?) – retrying in $WRITE_BACKOFF s (attempt $((attempt + 1)) of $WRITE_RETRIES)" >&2
    sleep "$WRITE_BACKOFF"
  done
  for target in "${!held[@]}"; do
    now=$(entry_count "$target")
    (( now >= held[$target] )) && continue
    echo "slice-loop: link target $target lost entries during the removal of the worktree of slice-$nr (before ${held[$target]}, now $now) – restore it (for example npm ci)" >&2
    link_lost=true
  done
  return 0
}

remove_slice_branch() {
  local branch="slice-$1" path
  path=$(worktree_of "$branch")
  if [[ -n "$path" ]] && ! remove_worktree "$1" "$path"; then
    echo "[slice $1] worktree $path could not be removed – most likely a shell, editor or process still runs inside it" \
      "(or it is locked); close it and run --merge again to retry. $path and $branch are kept" >&2
    clean_up_lines+=("slice $1: $path and $branch kept – close what runs inside it, then run --merge again")
    return
  fi
  if [[ -n "$path" && -e "$path" ]]; then clean_up_lines+=("slice $1: folder $path remains – close what holds it and delete it"); fi
  rm -f "$LOG_DIR/slice-$1.squashed"
  # -D: a squash merge leaves the branch unmerged in git's eyes; the squash commit made just now is the proof.
  git branch -D "$branch" >/dev/null || echo "[slice $1] branch $branch could not be removed" >&2
}

# Slice number of a checklist row; fails for any other line.
row_number() {
  local row='^[|][[:space:]]*([0-9]{2,})([^0-9]|$)'
  [[ "$1" =~ $row ]] && echo "${BASH_REMATCH[1]}"
}

# Row $1 with every cell ticked that row $2 – the same slice's row on the other side – has ticked: the union of ticks.
union_row() {
  local -a ours theirs
  local i
  IFS='|' read -ra ours <<<"${1%$'\r'}"
  IFS='|' read -ra theirs <<<"${2%$'\r'}"
  for i in "${!ours[@]}"; do
    if [[ "${theirs[i]-}" == *"☑"* ]]; then ours[i]=${ours[i]//☐/☑}; fi
  done
  local IFS='|'
  echo "${ours[*]}|"
}

# The checklist after a squash conflict, built from both committed versions: the integration branch's lines in their
# order, a row the branch also has with the union of both rows' ticks, rows only the branch has appended in its order.
resolve_checklist() {
  local branch=$1 line nr
  local -A theirs=() ours_has=()
  local -a order=() out=()
  while IFS= read -r line; do
    if nr=$(row_number "$line"); then theirs[$nr]=$line; order+=("$nr"); fi
  done < <(git show "$branch:$CHECKLIST_FILE")
  while IFS= read -r line; do
    if nr=$(row_number "$line"); then
      ours_has[$nr]=1
      if [[ -n "${theirs[$nr]+set}" ]]; then line=$(union_row "$line" "${theirs[$nr]}"); fi
    fi
    out+=("$line")
  done < <(git show "HEAD:$CHECKLIST_FILE")
  for nr in "${order[@]}"; do
    if [[ -z "${ours_has[$nr]+set}" ]]; then out+=("${theirs[$nr]}"); fi
  done
  printf '%s\n' "${out[@]}" >"$LOG_DIR/checklist.tmp"
  replace_file "$LOG_DIR/checklist.tmp" "$CHECKLIST_FILE"
}

# Table rows for the awk programs below: a row starts with "|", its key is its first cell, and a cell holds items
# separated by "; ". Merging a row both sides changed takes, per cell, the change of the one side that changed it; a
# cell both changed keeps the integration branch's text and adds every item only the branch's text has.
readonly AWK_TABLE='
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function is_row(line) { return line ~ /^[|]/ }
function row_key(line,   raw) { split(line, raw, "|"); return trim(raw[2]) }
function cells(line, arr,   raw, n, last, i) {
  n = split(line, raw, "|"); last = (trim(raw[n]) == "") ? n - 1 : n
  for (i = 2; i <= last; i++) arr[i - 1] = trim(raw[i])
  return last - 1
}
function has_item(text, x,   parts, n, i) {
  n = split(text, parts, /; /)
  for (i = 1; i <= n; i++) if (trim(parts[i]) == x) return 1
  return 0
}
function merge_cell(o, b, t,   parts, n, i, out, x) {
  if (o == t || t == b) return o
  if (o == b) return t
  out = o; n = split(t, parts, /; /)
  for (i = 1; i <= n; i++) {
    x = trim(parts[i])
    if (x != "" && !has_item(o, x) && !has_item(b, x)) out = (out == "") ? x : (out "; " x)
  }
  return out
}
function merge_row(o, b, t,   co, cb, ct, n, i, row) {
  if (o == t || t == b) return o
  if (o == b) return t
  n = cells(o, co); if (cells(t, ct) != n) return ""
  if (b != "") { if (cells(b, cb) != n) return "" } else for (i = 1; i <= n; i++) cb[i] = ""
  row = "|"; for (i = 1; i <= n; i++) row = row " " merge_cell(co[i], cb[i], ct[i]) " |"
  return row
}
function covers(line, b, r,   cl, cb, cr, n, i, parts, m, j, x) {
  n = cells(line, cl); if (cells(r, cr) != n) return 0
  if (b != "") { if (cells(b, cb) != n) return 0 } else for (i = 1; i <= n; i++) cb[i] = ""
  for (i = 1; i <= n; i++) {
    m = split(cl[i], parts, /; /)
    for (j = 1; j <= m; j++) { x = trim(parts[j]); if (x != "" && !has_item(cb[i], x) && !has_item(cr[i], x)) return 0 }
  }
  return 1
}
'

# Resolves every conflict hunk (diff3 style) of the file on stdin, writes the result to stdout; fails on a real conflict.
# A hunk whose base part is empty (both sides only added lines) keeps the integration branch's lines, then the branch's.
# A hunk of table rows with unique keys where no side removed a key keeps one row per key: rows only one side has, rows
# only one side changed in that change, rows both changed merged cell by cell. Any other hunk is a real conflict;
# mode "record" (the open round record) keeps both sides there, too – the rule of 1.2.
readonly AWK_RESOLVE='
function keyed(arr, n, keys,   i, k) {
  for (i = 1; i <= n; i++) {
    if (!is_row(arr[i])) return 0
    k = row_key(arr[i]); if (k == "" || k ~ /^[-: ]+$/ || (k in keys)) return 0
    keys[k] = i
  }
  return 1
}
function table_merge(   ko, kb, kt, i, k, m) {
  nm = 0
  if (!keyed(O, no, ko) || !keyed(B, nb, kb) || !keyed(T, nt, kt)) return 0
  for (k in kb) if (!(k in ko) || !(k in kt)) return 0
  for (i = 1; i <= no; i++) {
    k = row_key(O[i])
    if (k in kt) { m = merge_row(O[i], (k in kb) ? B[kb[k]] : "", T[kt[k]]); if (m == "") return 0; M[++nm] = m }
    else M[++nm] = O[i]
  }
  for (i = 1; i <= nt; i++) if (!(row_key(T[i]) in ko)) M[++nm] = T[i]
  return 1
}
function both_sides(   i) { for (i = 1; i <= no; i++) print O[i]; for (i = 1; i <= nt; i++) print T[i] }
function resolve(   i) {
  if (nb == 0) both_sides()
  else if (table_merge()) for (i = 1; i <= nm; i++) print M[i]
  else if (mode == "record") both_sides()
  else { failed = 1; exit 1 }
}
{ sub(/\r$/, "") }
state == "" && /^<<<<<<</ { state = "o"; no = nb = nt = 0; next }
state == "o" && /^[|][|][|][|][|][|][|]/ { state = "b"; next }
(state == "o" || state == "b") && $0 == "=======" { state = "t"; next }
state == "t" && /^>>>>>>>/ { state = ""; resolve(); next }
state == "o" { O[++no] = $0; next }
state == "b" { B[++nb] = $0; next }
state == "t" { T[++nt] = $0; next }
{ print }
END { if (failed || state != "") exit 1 }
'

# Nothing was lost in a resolved text file (variables ours, theirs, base, result name the files): every line both sides
# kept or either side added is in the result, a table row as it is or covered by the result row of its key (every item
# the side added to a cell is there); no key has more rows than either side had; the Result: lines add up
# (ours + theirs - merge base). Prints the first problem; prints nothing when the file is fine.
readonly AWK_CHECK='
function load(file, lines, set,   n, line) {
  n = 0
  while ((getline line < file) > 0) { sub(/\r$/, "", line); lines[++n] = line; set[line] = 1 }
  close(file); return n
}
function results(lines, n,   i, c) { c = 0; for (i = 1; i <= n; i++) if (lines[i] ~ /^Result:/) c++; return c }
function keys(lines, n, count,   i) { for (i = 1; i <= n; i++) if (is_row(lines[i])) count[row_key(lines[i])]++ }
function need(line,   k, j) {
  if (line in hs) return 1
  if (!is_row(line)) return 0
  k = row_key(line); needed_key[k] = 1
  for (j = 1; j <= nh; j++) if (is_row(H[j]) && row_key(H[j]) == k && covers(line, (k in brow) ? brow[k] : "", H[j])) return 1
  return 0
}
BEGIN {
  no = load(ours, O, os); nt = load(theirs, T, ts); nb = load(base, B, bs); nh = load(result, H, hs)
  for (i = nb; i >= 1; i--) if (is_row(B[i])) brow[row_key(B[i])] = B[i]
  for (i = 1; i <= no; i++) if (((O[i] in ts) || !(O[i] in bs)) && !need(O[i])) { print "lost: " O[i]; exit }
  for (i = 1; i <= nt; i++) if (!(T[i] in bs) && !need(T[i])) { print "lost: " T[i]; exit }
  keys(O, no, ko); keys(T, nt, kt); keys(H, nh, kh)
  for (k in needed_key) if (kh[k] > ko[k] && kh[k] > kt[k]) { print "duplicate rows for " k; exit }
  if (results(H, nh) != results(O, no) + results(T, nt) - results(B, nb)) print "Result: lines do not add up"
}
'

# Resolves the conflict hunks of file $1 by rule (mode $2: strict, or record for the open round record); fails and leaves
# the file as it is on a real conflict.
resolve_hunks() {
  local file=$1 mode=$2 out="$LOG_DIR/resolved.tmp"
  awk -v mode="$mode" "$AWK_TABLE$AWK_RESOLVE" "$file" >"$out" || return 1
  replace_file "$out" "$file"
}

# Puts the blocks under "## Manual test list" of record $1 in slice-number order (stable); nothing else moves.
readonly AWK_ORDER='
{ sub(/\r$/, ""); L[++n] = $0 }
END {
  for (i = 1; i <= n; i++) if (L[i] ~ /^## Manual test list/) { start = i; break }
  if (!start) { for (i = 1; i <= n; i++) print L[i]; exit }
  for (stop = start + 1; stop <= n && L[stop] !~ /^## /; stop++) ;
  for (i = start + 1; i < stop; i++) if (L[i] ~ /^### Slice [0-9]/) { first[++nb] = i; match(L[i], /[0-9]+/); num[nb] = substr(L[i], RSTART, RLENGTH) + 0 }
  if (!nb) { for (i = 1; i <= n; i++) print L[i]; exit }
  for (b = 1; b <= nb; b++) { last[b] = (b < nb ? first[b + 1] : stop) - 1; while (last[b] > first[b] && L[last[b]] == "") last[b]-- }
  blank = 0; for (i = stop - 1; i > last[nb] && L[i] == ""; i--) blank++
  for (b = 1; b <= nb; b++) order[b] = b
  for (b = 2; b <= nb; b++) for (c = b; c > 1 && num[order[c - 1]] > num[order[c]]; c--) { t = order[c]; order[c] = order[c - 1]; order[c - 1] = t }
  for (i = 1; i < first[1]; i++) print L[i]
  for (b = 1; b <= nb; b++) { if (b > 1) print ""; for (i = first[order[b]]; i <= last[order[b]]; i++) print L[i] }
  for (i = 1; i <= blank; i++) print ""
  for (i = stop; i <= n; i++) print L[i]
}
'
order_manual_tests() {
  local file=$1 out="$LOG_DIR/ordered.tmp"
  awk "$AWK_ORDER" "$file" >"$out"
  # Rewritten only when a block moved, so a file with CRLF line endings keeps them otherwise.
  if ! tr -d '\r' <"$file" | cmp -s - "$out"; then replace_file "$out" "$file"; fi
}

# Problems of the manual test block of slice nr in the record: steps numbered 1..n, exactly one Expected: per step,
# exactly one Closes: and one Result: per block, one block per slice. Prints nothing when the slice has no block or it is fine.
readonly AWK_BLOCK='
function end_step() { if (steps > checked) { if (expected != 1) bad = bad "step " steps " has " expected " Expected: lines; "; checked = steps; expected = 0 } }
{ sub(/\r$/, "") }
/^## / { end_step(); section = ($0 ~ /^## Manual test list/); inblock = 0; next }
section && /^### / { end_step(); inblock = ($0 ~ ("^### Slice " nr "([^0-9]|$)")); if (inblock) blocks++; next }
!inblock { next }
/^[0-9]+\. / { end_step(); steps++; if ($0 + 0 != steps) bad = bad "step " steps " is numbered " ($0 + 0) "; "; next }
/^Expected:/ { if (steps == 0 || closes || results) bad = bad "Expected: outside a step; "; else expected++; next }
/^Closes:/ { end_step(); closes++; next }
/^Result:/ { end_step(); results++; next }
END {
  end_step()
  if (!blocks) exit
  if (blocks > 1) bad = bad blocks " blocks; "
  if (!steps) bad = bad "no numbered step; "
  if (closes != 1) bad = bad closes " Closes: lines; "
  if (results != 1) bad = bad results " Result: lines; "
  if (bad != "") print bad
}
'

# Finding ids defined more than once in file $1: as the first cell of two table rows, or as the first word of two headings.
# An id is uppercase letters, an optional "-" and digits (B71, F-01, Ä77). awk runs on bytes (LC_ALL=C), so an uppercase
# letter is A-Z or a two-byte UTF-8 Latin-1 capital (\303\200-\303\236: À-Þ, with Ä Ö Ü); other scripts are not matched.
readonly AWK_IDS='
function is_id(w) { return w ~ /^([A-Z]|\303[\200-\236])+-?[0-9]+$/ }
{ sub(/\r$/, "") }
/^[|]/ { split($0, c, "|"); k = c[2]; gsub(/^[ \t]+|[ \t]+$/, "", k); if (is_id(k) && ++rows[k] == 2) print k; next }
/^#+ / { w = $2; sub(/[:.,]$/, "", w); if (is_id(w) && ++heads[w] == 2) print w }
'
duplicate_ids_in() { LC_ALL=C awk "$AWK_IDS" "$@" | LC_ALL=C sort -u; }

# Tracked files that record $1 names in backticks under "## Source" (the findings file), one per line.
findings_files() {
  local record=$1 path
  while IFS= read -r path; do
    if [[ -f "$path" && "$path" != "$record" ]]; then echo "$path"; fi
  done < <(awk '/^## /{ s = ($0 ~ /^## Source/); next } s' "$record" | { grep -o '`[^`]*`' || true; } | tr -d '`')
}

# A line of record $1 on the integration branch that the squash lost and that is the start of a longer line of the
# result: two lines glued into one (a hand-made conflict resolution without the line break). Prints the first one;
# nothing when there is none.
readonly AWK_GLUED='
BEGIN { while ((getline line < result) > 0) { sub(/\r$/, "", line); R[++n] = line; has[line] = 1 } }
{ sub(/\r$/, "") }
found || $0 ~ /^[ \t]*$/ || $0 ~ /^\|/ || ($0 in has) { next }
# Glued only when the rest starts like a line of its own (a bullet, a step, a heading, "Word:"); text a slice adds to
# the end of a line is no glue.
{ for (i = 1; i <= n; i++) if (length(R[i]) > length($0) && substr(R[i], 1, length($0)) == $0 &&
    substr(R[i], length($0) + 1) ~ /^[ \t]*([-*+] |[0-9]+\. |#+ |[A-Za-z][A-Za-z0-9-]*: )/) { print; found = 1; break } }
'
glued_line() { git show "HEAD:$1" 2>/dev/null | awk -v result="$1" "$AWK_GLUED" || true; }

# Finding ids the squash would define twice in record $1 or its findings file, as "<id> in <file>"; ids already
# duplicated on the integration branch do not count.
new_duplicate_ids() {
  local record=$1 file id
  while IFS= read -r file; do
    while IFS= read -r id; do
      echo "$id in $file"
    done < <(LC_ALL=C comm -23 <(duplicate_ids_in "$file") <(git show "HEAD:$file" 2>/dev/null | duplicate_ids_in))
  done < <(echo "$record"; findings_files "$record")
}

# The commands of the line of work/conventions.md that starts with $1 ("- Baseline check", "- Full check chain"): its
# backtick spans before the source arrow.
check_commands() {
  local line
  [[ -f "$CONVENTIONS_FILE" ]] || return 0
  line=$(grep -m1 "^$1" "$CONVENTIONS_FILE" | tr -d '\r' || true)
  line=${line%%←*}
  { grep -o '`[^`]*`' <<<"$line" || true; } | tr -d '`'
}

# Why the checks proof .slice-loop/slice-$1.checks does not allow the squash; nothing when it does. One line per check:
# "<exit code> <commit SHA> <command>". Only lines of the branch tip count (the SHA is a prefix of it, 7 to 40 hex
# digits): lines of other commits are stale runs, for example of an old session, and ignored. Of each command the last
# line on the tip counts – red then green is fine, green then red is red. Every such line is green and every command of
# the baseline check in work/conventions.md has one.
checks_problem() {
  local nr=$1 file="$LOG_DIR/slice-$1.checks" tip line stale=0 command
  local -A last=()   # command -> exit code of its last line on the tip
  local -a order=()  # the commands in the order of their first line on the tip
  [[ -f "$file" ]] || { echo "no checks proof $file"; return; }
  tip=$(git rev-parse "slice-$nr")
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line%$'\r'}
    [[ -z "$line" || "$line" == '#'* ]] && continue
    [[ "$line" =~ ^(-?[0-9]+)[[:space:]]+([0-9a-f]{7,40})[[:space:]]+(.+)$ ]] || { echo "unreadable line in $file: $line"; return; }
    if [[ "$tip" == "${BASH_REMATCH[2]}"* ]]; then
      command=${BASH_REMATCH[3]}
      [[ -n "${last[$command]+set}" ]] || order+=("$command")
      last["$command"]=${BASH_REMATCH[1]}
    else
      stale=$((stale + 1))
    fi
  done <"$file"
  if (( ${#order[@]} == 0 )); then
    if (( stale == 0 )); then echo "no check listed in $file"; else echo "no check ran on the tip ${tip:0:12} of slice-$nr ($stale stale line(s) ignored)"; fi
    return
  fi
  for command in "${order[@]}"; do
    [[ "${last[$command]}" == 0 ]] || { echo "check red (exit ${last[$command]}): $command"; return; }
  done
  while IFS= read -r command; do
    [[ -z "$command" || -n "${last[$command]+set}" ]] || { echo "baseline check missing from $file: $command"; return; }
  done < <(check_commands '- Baseline check')
}

# The files the integration branch (checked out here) changed since slice-$1 last took it in that the slice changes too,
# one per line: the slice's checks never ran on them together. Documents (*.md) and work/ are left out – the queue
# merges those by its rules. Nothing when the slice's tip already holds the integration branch.
overlap_files() {
  local base
  base=$(git merge-base HEAD "slice-$1")
  LC_ALL=C comm -12 <(git diff --name-only "$base" HEAD | LC_ALL=C sort) <(git diff --name-only "$base" "slice-$1" | LC_ALL=C sort) \
    | grep -vE '^work/|\.md$' || true
}

# The non-empty lines of the section "## Decisions" on stdin, sorted.
decision_lines() { tr -d '\r' | awk '/^## /{inside = ($0 ~ /^## Decisions([^[:alnum:]]|$)/); next} inside && NF' | LC_ALL=C sort -u; }

# The first line the slice added under "## Decisions" of round record $1 that is neither a ruling ("Ruling: …") nor a
# build decision ("Build decision (slice NN): …"), each ending in "– <who>, <date>"; a leading "- " is allowed. Nothing
# when every added line fits.
decision_problem() {
  local record=$1 branch=$2 base
  base=$(git merge-base HEAD "$branch")
  LC_ALL=C comm -23 <(git show "$branch:$record" 2>/dev/null | decision_lines) <(git show "$base:$record" 2>/dev/null | decision_lines) \
    | grep -vE '^(- )?(Ruling: |Build decision \(slice [0-9]{2,}\): ).* – .+, [0-9][^ ]*$' | head -n 1 || true
}

# Why slice $1 has not reported ready on its branch tip; nothing when it has. As its last step before SLICE-READY,
# /slice writes the tip's SHA to .slice-loop/slice-NN.ready: a session still running its last checks has no such file,
# or one of an older tip, and its worktree is not taken away under it.
ready_problem() {
  local nr=$1 file="$LOG_DIR/slice-$1.ready" tip sha
  [[ -f "$file" ]] || { echo "not reported ready: no $file (the session has not ended with SLICE-READY)"; return; }
  tip=$(git rev-parse "slice-$nr")
  sha=$(tr -d '[:space:]' <"$file")
  [[ "$sha" =~ ^[0-9a-f]{7,40}$ && "$tip" == "$sha"* ]] && return
  echo "slice-$nr moved after SLICE-READY: $file names '$sha', the tip is ${tip:0:12}"
}

# Every row of both sides is in the resolved checklist, and none of their ticks is missing there.
check_checklist() {
  local branch=$1 line nr
  local -A rows=()
  while IFS= read -r line; do
    if nr=$(row_number "$line"); then rows[$nr]=${line%$'\r'}; fi
  done <"$CHECKLIST_FILE"
  while IFS= read -r line; do
    nr=$(row_number "$line") || continue
    [[ -n "${rows[$nr]+set}" ]] || return 1
    [[ "$(union_row "${rows[$nr]}" "$line")" == "${rows[$nr]}" ]] || return 1
  done < <(git show "HEAD:$CHECKLIST_FILE"; git show "$branch:$CHECKLIST_FILE")
}

# Why resolved file $1 lost something; nothing when it is fine. No conflict marker is left; the checklist keeps every
# row and tick of both sides; any other file passes AWK_CHECK.
resolution_problem() {
  local file=$1 branch=$2 base ours="$LOG_DIR/ours.tmp" theirs="$LOG_DIR/theirs.tmp" before="$LOG_DIR/base.tmp"
  if grep -qE '^(<<<<<<<|=======|>>>>>>>|[|]{7})' "$file"; then echo "a conflict marker is left"; return; fi
  if [[ "$file" == "$CHECKLIST_FILE" ]]; then check_checklist "$branch" || echo "a row or tick is missing"; return; fi
  base=$(git merge-base HEAD "$branch")
  git show "HEAD:$file" >"$ours"
  git show "$branch:$file" >"$theirs"
  git show "$base:$file" >"$before" 2>/dev/null || : >"$before"
  awk -v ours="$ours" -v theirs="$theirs" -v base="$before" -v result="$file" "$AWK_TABLE$AWK_CHECK" </dev/null
}

# Leaves slice $1 behind for reason $2 after resetting the merge in progress.
reset_and_leave() {
  reset_merge
  leave_slice "$1" "$2 – merge reset"
}

# Leaves slice $1 behind (merge reset) when replace_file gave up on a file; fails when it did not.
left_on_write() {
  [[ -n "$write_failed" ]] || return 1
  reset_and_leave "$1" "could not write $write_failed (locked by another process)"
}

# Squashes branch slice-$1 onto the branch checked out here; fails when it leaves the slice behind (branch kept).
# First the checks proof; then every conflict is resolved by rule and checked (a real conflict leaves the slice); then
# the record's manual test list is put in slice order and the slice's block checked, and no finding id may be defined twice.
# A file it cannot write leaves the slice behind, too; any other way out of the merge (a stop, a signal) resets it.
merge_slice() {
  local nr=$1 branch="slice-$1" record conflicts file problem overlap
  local -a real=()
  [[ -z "$(git status --porcelain)" ]] || die "slice $nr: this checkout has uncommitted changes – commit or remove them, then run --merge"
  problem=$(ready_problem "$nr")
  if [[ -n "$problem" ]] && $merge_only; then not_ready "$nr" "$problem"; return 1; fi
  if [[ -z "$problem" && ! -f "$LOG_DIR/slice-$nr.msg" ]]; then problem="no squash message: $LOG_DIR/slice-$nr.msg is missing"; fi
  [[ -n "$problem" ]] || problem=$(checks_problem "$nr")
  if [[ -z "$problem" ]]; then
    overlap=$(overlap_files "$nr" | tr '\n' ' ' | sed 's/ $//')
    [[ -z "$overlap" ]] || problem="integration branch moved and touches $overlap – merge it on the slice branch"
  fi
  if [[ -n "$problem" ]]; then leave_slice "$nr" "$problem"; return 1; fi
  record=$(open_round_file)  # read before the merge: a conflict at its first line would hide "Status: open"
  write_failed=""
  merging=$nr
  # diff3 keeps every hunk whole and shows its base: the default style moves lines both sides end with (such as
  # "Result: ☐") out of the hunk, and keeping both sides would then keep that line once.
  if ! git -c merge.conflictStyle=diff3 merge --squash "$branch" >/dev/null 2>&1; then
    conflicts=$(git diff --name-only --diff-filter=U)
    [[ -n "$conflicts" ]] || { reset_and_leave "$nr" "git merge --squash failed"; return 1; }
    while IFS= read -r file; do
      if [[ "$file" == "$CHECKLIST_FILE" ]]; then
        if ! resolve_checklist "$branch" && left_on_write "$nr"; then return 1; fi
      elif ! resolve_hunks "$file" "$([[ "$file" == "$record" ]] && echo record || echo strict)"; then
        if left_on_write "$nr"; then return 1; fi
        real+=("$file")
        continue
      fi
      problem=$(resolution_problem "$file" "$branch")
      if [[ -n "$problem" ]]; then reset_and_leave "$nr" "the rule-based resolution of $file failed its check ($problem)"; return 1; fi
      git add "$file"
    done <<<"$conflicts"
    if (( ${#real[@]} )); then reset_and_leave "$nr" "merge conflict in ${real[*]} – merge the integration branch on the slice branch"; return 1; fi
  fi
  if [[ -n "$record" ]]; then
    if ! order_manual_tests "$record" && left_on_write "$nr"; then return 1; fi
    git add "$record"
    problem=$(glued_line "$record")
    if [[ -n "$problem" ]]; then reset_and_leave "$nr" "line glued to the next one in $record: $problem"; return 1; fi
    problem=$(awk -v nr="$nr" "$AWK_BLOCK" "$record")
    if [[ -n "$problem" ]]; then reset_and_leave "$nr" "manual test block of slice $nr in $record: ${problem%; }"; return 1; fi
    problem=$(new_duplicate_ids "$record" | tr '\n' ',' | sed 's/,$//; s/,/, /g')
    if [[ -n "$problem" ]]; then reset_and_leave "$nr" "finding id defined twice: $problem"; return 1; fi
    problem=$(decision_problem "$record" "$branch")
    if [[ -n "$problem" ]]; then
      reset_and_leave "$nr" "decision line in neither format ('Ruling: …' or 'Build decision (slice $nr): …') in $record: $problem"; return 1
    fi
  fi
  if ! tick_commit "$nr" && left_on_write "$nr"; then return 1; fi
  git add "$CHECKLIST_FILE"
  git rev-parse "$branch" >"$LOG_DIR/squashed.tmp"
  if ! replace_file "$LOG_DIR/squashed.tmp" "$LOG_DIR/slice-$nr.squashed" && left_on_write "$nr"; then return 1; fi
  git commit -q -F "$LOG_DIR/slice-$nr.msg" || die "slice $nr: the squash commit failed – merge reset"
  merging=""
  squashed_count=$((squashed_count + 1))
  echo "[slice $nr] squashed onto $(git branch --show-current) ($(git rev-parse --short HEAD))" >&2
  is_done "$nr" || die "slice $nr was squashed but is not ticked in $CHECKLIST_FILE – check it before running again"
  remove_slice_branch "$nr"
}

# After a build turn: a slice the session squashed itself is done; one that waits on its branch goes through the queue.
finish_slice() {
  local nr=$1
  if ! is_done "$nr"; then
    branch_ready "$nr" \
      || die "slice $nr reported done or ready but is not ticked in $CHECKLIST_FILE or on slice-$nr – check it before running again"
    merge_slice "$nr" || return 0
  fi
  echo "[slice $nr] done" >&2
}

# A slice squashed in an earlier run whose worktree could not be removed: its branch still points where it did at the
# squash (.slice-loop/slice-NN.squashed), so the removal is tried again; a branch that moved since is left as it is.
retry_removal() {
  local nr=$1 squashed="$LOG_DIR/slice-$1.squashed"
  [[ -f "$squashed" ]] || return 0
  if [[ "$(git rev-parse "slice-$nr")" == "$(tr -d '\r\n' <"$squashed")" ]]; then
    echo "[slice $nr] already squashed – removing its leftover worktree and branch again" >&2
    remove_slice_branch "$nr"
  else
    echo "[slice $nr] already squashed; slice-$nr has commits after the squash – nothing to do for the queue (squash them by hand or delete the branch)" >&2
  fi
}

# The number of every slice-NN branch, lowest first, one per line.
branch_numbers() {
  git for-each-ref --format='%(refname:short)' 'refs/heads/slice-*' | sort -t- -k2,2n | sed -n 's/^slice-\([0-9][0-9][0-9]*\)$/\1/p'
}

# Whether a slice has reported ready on a tip the queue has not left behind yet.
slice_reported() {
  local nr left
  while IFS= read -r nr; do
    if is_done "$nr" || [[ -n "$(ready_problem "$nr")" ]]; then continue; fi
    left="$LOG_DIR/slice-$nr.left"
    if [[ -f "$left" && "$(tr -d '[:space:]' <"$left")" == "$(git rev-parse "slice-$nr")" ]]; then continue; fi
    return 0
  done < <(branch_numbers)
  return 1
}

# Takes the queue lock; fails while another queue holds it.
take_merge_lock() {
  if ! mkdir "$MERGE_LOCK" 2>/dev/null; then
    if [[ ! -d "$MERGE_LOCK" ]]; then
      echo "slice-loop: could not create $MERGE_LOCK – going on without it" >&2
      return 0
    fi
    if [[ -n "$(find "$MERGE_LOCK" -maxdepth 0 -mmin -60 2>/dev/null)" ]]; then
      echo "slice-loop: another merge queue runs ($MERGE_LOCK; delete it if none runs) – this one does nothing" >&2
      return 1
    fi
    echo "slice-loop: taking over $MERGE_LOCK, older than 60 minutes" >&2
  fi
  merge_locked=true
  date -u +"merge queue %Y-%m-%dT%H:%M:%SZ" >"$MERGE_LOCK/owner"
  touch "$MERGE_LOCK"
}

# Whether another --watch shows a sign of life. An older one has died: its file stays, and this run goes on.
watch_running() {
  [[ -f "$WATCH_ALIVE" && -n "$(find "$WATCH_ALIVE" -mmin -60 2>/dev/null)" ]]
}

# --watch: waits until a slice has reported ready; fails after the last check. The queue then runs once and the script
# ends, so the chat that started it in the background is woken even when a session's own report never reached it.
wait_for_ready_slice() {
  local check
  echo "slice-loop: watching for SLICE-READY every $WATCH_SECONDS s, at most $WATCH_MAX check(s)" >&2
  for (( check = 1; check <= WATCH_MAX; check++ )); do
    : >"$WATCH_ALIVE"
    if slice_reported; then return 0; fi
    if (( check < WATCH_MAX )); then sleep "$WATCH_SECONDS"; fi
  done
  echo "slice-loop: no slice reported ready after $WATCH_MAX check(s) – start the watch again while sessions run" >&2
  return 1
}

# The merge queue alone (--merge): every slice-NN branch, lowest number first; one not ticked through Checks is left,
# one that conflicts or lacks its proof is left behind and the queue goes on.
merge_queue() {
  local branch nr
  for nr in $(branch_numbers); do
    branch="slice-$nr"
    if is_done "$nr"; then retry_removal "$nr"; continue; fi
    if branch_ready "$nr"; then
      merge_slice "$nr" || true
    else
      echo "[slice $nr] not ready to merge: its row on $branch is not ticked through Checks – left as it is" >&2
    fi
  done
}

# Who holds the full-suite lock, from its owner file, e.g. "slice 100 2026-10-27T09:00:00Z" or "merge queue …".
lock_owner() {
  if [[ -f "$LOCK_DIR/owner" ]]; then tr -d '\r' <"$LOCK_DIR/owner" | head -1; else echo unknown; fi
}

# Reports a full-suite lock nobody can hold any more: its owner is a slice whose branch is gone, or it is older than an
# hour. Only reports – removing it is the caller's call; the run goes on.
stale_lock_notice() {
  local owner why="" touched=$LOCK_DIR
  [[ -d "$LOCK_DIR" ]] || return 0
  owner=$(lock_owner)
  if [[ -f "$LOCK_DIR/owner" ]]; then touched=$LOCK_DIR/owner; fi
  if [[ "$owner" =~ ^slice\ ([0-9]{2,})([[:space:]]|$) ]] && ! git rev-parse --verify --quiet "refs/heads/slice-${BASH_REMATCH[1]}" >/dev/null; then
    why="its slice branch is gone"
  elif [[ -n "$(find "$touched" -maxdepth 0 -mmin +60)" ]]; then
    why="it is older than 60 minutes"
  fi
  if [[ -n "$why" ]]; then echo "slice-loop: stale lock $LOCK_DIR (owner: $owner) – $why; remove it with: rm -r $LOCK_DIR" >&2; fi
}

# Reports a work/conventions.md without a "- Baseline check" line: the queue then cannot require the baseline commands
# in the checks proof. A key translated into the repository's language is the usual cause. Only reports; the run goes on.
baseline_notice() {
  [[ -f "$CONVENTIONS_FILE" ]] || return 0
  grep -q '^- Baseline check' "$CONVENTIONS_FILE" && return 0
  echo "slice-loop: no '- Baseline check' line in $CONVENTIONS_FILE – checks proofs are not checked for the baseline commands; the key stays English in any language, e.g. '- Baseline check (<own words>): \`<command>\`'" >&2
}

# After the merge queue (--verify): when the queue squashed a slice, every command of the "- Full check chain" line in
# work/conventions.md runs on the integration branch, under the full-suite lock. Fails when one is red or the lock is held.
verify_chain() {
  local command code red=false
  local -a commands
  (( squashed_count > 0 )) || return 0
  mapfile -t commands < <(check_commands '- Full check chain')
  if (( ${#commands[@]} == 0 )); then
    echo "slice-loop: no '- Full check chain' line in $CONVENTIONS_FILE – nothing verified (the key stays English in any language)" >&2
    return 0
  fi
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "slice-loop: $LOCK_DIR is held (owner: $(lock_owner)) – the full check chain was not run" >&2
    return 1
  fi
  echo "merge queue $(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$LOCK_DIR/owner"
  for command in "${commands[@]}"; do
    code=0
    bash -c "$command" || code=$?
    if (( code == 0 )); then echo "[verify] $command – green" >&2; else echo "[verify] $command – red (exit $code)" >&2; red=true; fi
  done
  rm -r "$LOCK_DIR"
  if $red; then echo "slice-loop: full check chain red on $(git branch --show-current) after the merge queue" >&2; return 1; fi
}

# Two paths of the "files" of slices overlap when they are equal or one is a prefix ending in "/" of the other.
# Prints the more specific of the two; fails when they do not overlap.
shared_path() {
  if [[ "$1" == "$2" ]]; then echo "$1"
  elif [[ "$1" == */ && "$2" == "$1"* ]]; then echo "$2"
  elif [[ "$2" == */ && "$1" == "$2"* ]]; then echo "$1"
  else return 1
  fi
}

# The ready slices $@ (in order) that go into the next --parallel batch, one per line: at most PARALLEL_MAX, and none
# whose "files" overlap a slice already picked; that one waits for a later batch.
parallel_batch() {
  local nr other mine theirs shared clash
  local -a batch=()
  local -A files=()
  for nr in "$@"; do files[$nr]=$(slice_files "$nr"); done
  for nr in "$@"; do
    (( ${#batch[@]} < PARALLEL_MAX )) || break
    clash=""
    for other in ${batch[@]+"${batch[@]}"}; do
      while IFS= read -r mine; do
        [[ -n "$mine" && -z "$clash" ]] || continue
        while IFS= read -r theirs; do
          if [[ -n "$theirs" && -z "$clash" ]] && shared=$(shared_path "$mine" "$theirs"); then clash="shares $shared with slice $other"; fi
        done <<<"${files[$other]}"
      done <<<"${files[$nr]}"
    done
    if [[ -n "$clash" ]]; then echo "[slice $nr] waits: $clash" >&2; else batch+=("$nr"); fi
  done
  printf '%s\n' ${batch[@]+"${batch[@]}"}
}

ready_slices() {
  local -a numbers deps
  local i nr dep blocked
  mapfile -t numbers < <(slice_numbers)
  mapfile -t deps < <(slice_deps)
  [[ ${#numbers[@]} -eq ${#deps[@]} ]] || die "every entry in $SLICES_FILE needs \"nr\" and \"deps\""
  for i in "${!numbers[@]}"; do
    nr=${numbers[$i]}
    if is_done "$nr" || [[ -n "${left_nrs[$nr]+set}" ]]; then continue; fi
    blocked=false
    for dep in ${deps[$i]}; do is_done "$dep" || blocked=true; done
    $blocked || echo "$nr"
  done
}

all_done() {
  local nr
  for nr in $(slice_numbers); do is_done "$nr" || return 1; done
}

open_count() {
  local nr count=0
  for nr in $(slice_numbers); do is_done "$nr" || count=$((count + 1)); done
  echo "$count"
}

# Path of the first round record in $ROUNDS_DIR whose first line is "Status: open"; nothing if none is open.
open_round_file() {
  local file first
  for file in "$ROUNDS_DIR"/*.md; do
    [[ -f "$file" ]] || continue
    IFS= read -r first <"$file" || true
    if [[ "${first%$'\r'}" == "Status: open" ]]; then
      echo "$file"
      return
    fi
  done
}

# Id (R01, R02 …) of the open round record; nothing if none is open.
open_round() {
  local file
  file=$(open_round_file)
  if [[ -n "$file" ]]; then basename "$file" | grep -o '^R[0-9][0-9]*' || true; fi
}

# Random UUID v4 for --session-id (uuidgen and /proc are missing in Git Bash on Windows).
new_session_id() {
  if command -v uuidgen >/dev/null 2>&1; then uuidgen | tr 'A-Z' 'a-z'; return; fi
  if [[ -r /proc/sys/kernel/random/uuid ]]; then cat /proc/sys/kernel/random/uuid; return; fi
  local hex variant
  hex=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
  variant=$(printf '%x' $(( (16#${hex:16:1} & 3) | 8 )))
  printf '%s-%s-4%s-%s%s-%s\n' "${hex:0:8}" "${hex:8:4}" "${hex:13:3}" "$variant" "${hex:17:3}" "${hex:20:12}"
}

# Runs one claude turn on model $2 (empty: the CLI default); output goes to the log and is echoed back for marker parsing.
claude_turn() {
  local log=$1 model=$2; shift 2
  local -a on_model=()
  if [[ -n "$model" ]]; then on_model=(--model "$model"); fi
  claude -p --permission-mode "$PERMISSION_MODE" ${on_model[@]+"${on_model[@]}"} "$@" | tee -a "$log" \
    || die "claude exited with an error – see $log"
}

# Plans slice $1 on model $4 and waits for approval. Prints the message for the build turn.
plan_slice() {
  local nr=$1 session=$2 log=$3 model=$4 output answer decisions
  echo "[slice $nr] planning (session $session, model ${model:-default}, log $log)" >&2
  output=$(claude_turn "$log" "$model" --session-id "$session" "/slice $nr plan auto")
  while true; do
    grep -q '^PLAN:' <<<"$output" || die "slice $nr: no PLAN line – see $log"
    decisions=$(grep '^NEEDS-DECISION:' <<<"$output" || true)
    echo "[slice $nr] $(grep '^PLAN:' <<<"$output" | tail -1)" >&2
    if $auto_approve && [[ -z "$decisions" ]]; then
      echo "Approved. Build slice $nr and close it (auto)."
      return
    fi
    if [[ -n "$decisions" ]]; then echo "$decisions" >&2; fi
    read -r -p "[slice $nr] Enter = approve, text = change request / answers, q = stop: " answer </dev/tty
    case "$answer" in
      q) die "stopped by user before building slice $nr" ;;
      "") echo "Approved. Build slice $nr and close it (auto)."; return ;;
    esac
    if [[ -n "$decisions" ]]; then
      echo "Approved with these answers: $answer. Build slice $nr and close it (auto)."
      return
    fi
    output=$(claude_turn "$log" "$model" --resume "$session" \
      "Change request: $answer. Revise the plan, save it and end again with the PLAN line (auto).")
  done
}

build_slice() {
  local nr=$1 session=$2 log=$3 approval=$4 model=$5 note="" output waiting waits=0
  if $parallel; then
    note=" Other slices are built in parallel: if git is locked or the integration branch moved, wait and retry; in conflicts keep every tick in work/checklist.md."
  fi
  echo "[slice $nr] building – this can take a while (log $log)" >&2
  output=$(claude_turn "$log" "$model" --resume "$session" "$approval$note")
  # SLICE-WAIT: the session ended its turn while its checks still run – it is not done, so check back in it.
  while ! slice_finished "$nr" "$output" && waiting=$(wait_line "$nr" "$output") && [[ -n "$waiting" ]]; do
    (( waits < WAIT_MAX )) || die "slice $nr still waiting after $waits check-backs (${waiting}) – see $log"
    waits=$((waits + 1))
    echo "[slice $nr] still running: ${waiting#SLICE-WAIT: $nr } – checking back in ${WAIT_SECONDS}s" >&2
    sleep "$WAIT_SECONDS"
    output=$(claude_turn "$log" "$model" --resume "$session" \
      "Still waiting for: ${waiting#SLICE-WAIT: $nr }. Check it; when it is done, finish slice $nr and close it (auto).")
  done
  slice_finished "$nr" "$output" \
    || die "slice $nr not finished: $(grep '^SLICE-OPEN:' <<<"$output" || echo 'no SLICE-DONE or SLICE-READY line') – see $log"
}

# Slice $1 ended with SLICE-DONE or SLICE-READY in output $2.
slice_finished() { grep -qE "^(SLICE-DONE:|SLICE-READY:) $1([^0-9]|$)" <<<"$2"; }

# The last SLICE-WAIT line of slice $1 in output $2; nothing when the turn did not end waiting.
wait_line() { { grep -E "^SLICE-WAIT: $1([^0-9]|$)" <<<"$2" || true; } | tail -1; }

run_round() {
  local -a ready sessions logs models approvals pids
  local i
  mapfile -t ready < <(ready_slices)
  if [[ ${#ready[@]} -eq 0 ]]; then
    report_left || exit 1
    die "no slice is ready – check $CHECKLIST_FILE (/slice status)"
  fi
  if $parallel; then mapfile -t ready < <(parallel_batch "${ready[@]}"); else ready=("${ready[0]}"); fi
  if (( max_slices > 0 )); then ready=("${ready[@]:0:max_slices - built}"); fi
  for i in "${!ready[@]}"; do
    sessions[i]=$(new_session_id)
    logs[i]="$LOG_DIR/slice-${ready[i]}-$(date +%Y%m%d-%H%M%S).log"
    models[i]=$(slice_model "${ready[i]}")
    approvals[i]=$(plan_slice "${ready[i]}" "${sessions[i]}" "${logs[i]}" "${models[i]}")
  done
  for i in "${!ready[@]}"; do
    if $parallel; then
      build_slice "${ready[i]}" "${sessions[i]}" "${logs[i]}" "${approvals[i]}" "${models[i]}" &
      pids[i]=$!
    else
      build_slice "${ready[i]}" "${sessions[i]}" "${logs[i]}" "${approvals[i]}" "${models[i]}"
      finish_slice "${ready[i]}"
    fi
  done
  # Parallel builds are squashed one after another in list order, each as soon as it and the ones before it are built.
  for i in "${!pids[@]}"; do
    wait "${pids[i]}" || die "slice ${ready[i]} failed – see ${logs[i]}"
    finish_slice "${ready[i]}"
  done
  built=$((built + ${#ready[@]}))
}

# Closes the round in one more fresh session and prints its ROUND-DONE line.
close_round() {
  local log output
  log="$LOG_DIR/close-$(date +%Y%m%d-%H%M%S).log"
  echo "[round $round] all slices done – closing the round (log $log)" >&2
  output=$(claude_turn "$log" "" --session-id "$(new_session_id)" "/slice close auto")
  grep -q '^ROUND-DONE:' <<<"$output" \
    || die "round $round not closed: $(grep '^ROUND-OPEN:' <<<"$output" || echo 'no ROUND-DONE line') – see $log"
  grep '^ROUND-DONE:' <<<"$output" | tail -1
  echo "Round closed. Next: test with the manual test list in $ROUNDS_DIR/, then start the next round with the vibe-coding skill."
}

main() {
  parse_args "$@"
  [[ -f "$SLICES_FILE" && -f "$CHECKLIST_FILE" ]] || die "run from the repo root (needs $SLICES_FILE and $CHECKLIST_FILE)"
  if $dry_run; then ready_slices; exit 0; fi
  mkdir -p "$LOG_DIR"
  grep -qx "$LOG_DIR/" .git/info/exclude 2>/dev/null || echo "$LOG_DIR/" >> .git/info/exclude
  stale_lock_notice
  baseline_notice
  if $merge_only; then
    if $watch; then
      if watch_running; then
        echo "slice-loop: already watching ($WATCH_ALIVE is under 60 minutes old; delete it if no watch runs)" >&2
        exit 0
      fi
      watching=true
      wait_for_ready_slice || exit 0
    fi
    take_merge_lock || exit 0
    merge_queue
    if $merge_locked; then rm -r "$MERGE_LOCK" || true; fi
    merge_locked=false
    local clean=true
    report_left || clean=false
    if $verify; then verify_chain || clean=false; fi
    $clean || exit 1
    exit 0
  fi
  round=$(open_round)
  if [[ -z "$round" ]]; then
    echo "slice-loop: no open round in $ROUNDS_DIR – start a round with the vibe-coding skill first" >&2
    exit 0
  fi
  command -v claude >/dev/null 2>&1 || die "claude CLI not found"
  until all_done; do
    run_round
    if (( max_slices > 0 && built >= max_slices )) && ! all_done; then
      echo "slice-loop: stopped after $built slice(s) – $(open_count) still open" >&2
      report_left || exit 1
      exit 0
    fi
  done
  close_round
  if $link_lost; then exit 1; fi
}

main "$@"
