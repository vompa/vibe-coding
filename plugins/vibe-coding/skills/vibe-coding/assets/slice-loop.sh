#!/usr/bin/env bash
# Builds the open round slice by slice, each slice in a fresh headless Claude session, then closes the round.
# A slice that ends with SLICE-READY is squashed by the merge queue: one slice-NN branch after another, in this
# checkout, with the message from .slice-loop/slice-NN.msg. Conflicts in work/checklist.md and the open round record
# are resolved by rule and checked; a conflict in any other file stops the loop and names the files.
# Stops for plan approval unless --yes; stops on NEEDS-DECISION, red tests or a blocked slice.
#
# Usage: bash .claude/scripts/slice-loop.sh [--yes] [--parallel] [--dry-run] [--max-slices N] [--merge]
#   --yes           approve plans without asking (still stops on NEEDS-DECISION)
#   --parallel      build slices that are ready at the same time side by side (experimental)
#   --dry-run       only print the slices that are ready now, then exit
#   --max-slices N  stop after N built slices if slices are left (exit 0; run again to continue)
#   --merge         only run the merge queue: squash every slice-NN branch ticked through Checks, then exit
#                   (starts no session, needs no open round)
# Env: SLICE_PERMISSION_MODE (default: auto) – passed to claude --permission-mode.
set -euo pipefail
shopt -s inherit_errexit
# Git Bash on Windows would rewrite the argument "/slice …" into a Windows path.
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'

readonly SLICES_FILE="work/_slices.json"
readonly CHECKLIST_FILE="work/checklist.md"
readonly ROUNDS_DIR="work/rounds"
readonly LOG_DIR=".slice-loop"
readonly PERMISSION_MODE="${SLICE_PERMISSION_MODE:-auto}"
readonly USAGE="use --yes, --parallel, --dry-run, --max-slices N, --merge"

auto_approve=false
parallel=false
dry_run=false
merge_only=false
max_slices=0  # 0 = no cap
built=0
round=""

die() { echo "slice-loop: $*" >&2; exit 1; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes) auto_approve=true ;;
      --parallel) parallel=true ;;
      --dry-run) dry_run=true ;;
      --merge) merge_only=true ;;
      --max-slices)
        [[ $# -ge 2 && "$2" =~ ^[1-9][0-9]*$ ]] || die "--max-slices needs a positive integer ($USAGE)"
        max_slices=$2
        shift ;;
      *) die "unknown option '$1' ($USAGE)" ;;
    esac
    shift
  done
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
  sed -E "/^\|[[:space:]]*$1([^0-9]|\$)/ s/(.*)☐/\1☑/" "$CHECKLIST_FILE" >"$CHECKLIST_FILE.tmp"
  mv "$CHECKLIST_FILE.tmp" "$CHECKLIST_FILE"
}

# Path of the squash message for slice $1: the file /slice wrote, else one written from the slice's name and source.
squash_message_file() {
  local nr=$1 file="$LOG_DIR/slice-$1.msg" name source
  if [[ -f "$file" ]]; then echo "$file"; return; fi
  file="$LOG_DIR/slice-$nr.fallback.msg"
  name=$(slice_field "$nr" name)
  source=$(slice_field "$nr" source)
  if [[ -n "$source" ]]; then echo "Slice $nr: $name ($source)"; else echo "Slice $nr: $name"; fi >"$file"
  echo "$file"
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

remove_slice_branch() {
  local branch="slice-$1" path
  path=$(worktree_of "$branch")
  if [[ -n "$path" ]]; then unlink_links "$path"; fi
  if [[ -n "$path" ]] && ! git worktree remove "$path" >/dev/null 2>&1; then
    echo "[slice $1] worktree $path could not be removed – it and $branch are left" >&2
    return
  fi
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
  printf '%s\n' "${out[@]}" >"$CHECKLIST_FILE"
}

# The round record $1 after a squash conflict: in every conflict hunk the integration branch's side, then the branch's
# side; the marker lines and the base section of the diff3 styles are dropped.
resolve_record() {
  local file=$1 line state=outside
  local -a out=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line%$'\r'}
    case "$state:$line" in
      outside:'<<<<<<<'*) state=ours; continue ;;
      ours:'|||||||'*) state=base; continue ;;
      ours:'=======' | base:'=======') state=theirs; continue ;;
      theirs:'>>>>>>>'*) state=outside; continue ;;
    esac
    if [[ "$state" != base ]]; then out+=("$line"); fi
  done <"$file"
  printf '%s\n' "${out[@]}" >"$file"
}

# Number of lines in file $1 that start with "Result:" (the manual test list).
count_results() { grep -c '^Result:' "$1" || true; }

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

# Nothing was lost in resolved file $1: no conflict marker is left; the checklist keeps every row and tick of both
# sides; the record keeps every line both sides kept or either side added, and its Result: lines add up
# (ours + theirs - merge base).
check_resolved() {
  local file=$1 branch=$2 base ours="$LOG_DIR/ours.tmp" theirs="$LOG_DIR/theirs.tmp" before="$LOG_DIR/base.tmp"
  local result="$LOG_DIR/result.tmp" needed="$LOG_DIR/needed.tmp"
  if grep -qE '^(<<<<<<<|=======|>>>>>>>|[|]{7})' "$file"; then return 1; fi
  if [[ "$file" == "$CHECKLIST_FILE" ]]; then check_checklist "$branch"; return; fi
  base=$(git merge-base HEAD "$branch")
  git show "HEAD:$file" >"$ours"
  git show "$branch:$file" >"$theirs"
  git show "$base:$file" >"$before" 2>/dev/null || : >"$before"
  tr -d '\r' <"$file" >"$result"
  { grep -Fx -f "$theirs" "$ours"; grep -Fxv -f "$before" "$ours"; grep -Fxv -f "$before" "$theirs"; } >"$needed" || true
  if grep -Fxv -f "$result" "$needed" >/dev/null; then return 1; fi
  (( $(count_results "$result") == $(count_results "$ours") + $(count_results "$theirs") - $(count_results "$before") ))
}

# Squashes branch slice-$1 onto the branch checked out here. Conflicts only in the checklist and the open round record
# are resolved by rule and checked; any other conflict, or a failed check, resets the merge and stops the loop.
merge_slice() {
  local nr=$1 branch="slice-$1" record conflicts foreign files file reason
  local -a resolvable=(-e "$CHECKLIST_FILE")
  [[ -z "$(git status --porcelain)" ]] || die "slice $nr: this checkout has uncommitted changes – commit or remove them, then run --merge"
  record=$(open_round_file)  # read before the merge: a conflict at its first line would hide "Status: open"
  if [[ -n "$record" ]]; then resolvable+=(-e "$record"); fi
  # diff3 keeps every hunk whole: the default style moves lines both sides end with (such as "Result: ☐") out of
  # the hunk, and keeping both sides would then keep that line once.
  if ! git -c merge.conflictStyle=diff3 merge --squash "$branch" >/dev/null 2>&1; then
    conflicts=$(git diff --name-only --diff-filter=U)
    foreign=$(grep -vxF "${resolvable[@]}" <<<"$conflicts" || true)
    if [[ -z "$conflicts" || -n "$foreign" ]]; then
      git reset --merge
      if [[ -n "$foreign" ]]; then files=$(tr '\n' ' ' <<<"$foreign"); reason="merge conflict in ${files% }"; else reason="git merge --squash failed"; fi
      die "slice $nr: $reason – merge reset, $branch kept"
    fi
    while IFS= read -r file; do
      if [[ "$file" == "$CHECKLIST_FILE" ]]; then resolve_checklist "$branch"; else resolve_record "$file"; fi
      if ! check_resolved "$file" "$branch"; then
        git reset --merge
        die "slice $nr: the rule-based resolution of $file failed its check – merge reset, $branch kept"
      fi
      git add "$file"
    done <<<"$conflicts"
  fi
  tick_commit "$nr"
  git add "$CHECKLIST_FILE"
  git commit -q -F "$(squash_message_file "$nr")" || die "slice $nr: the squash commit failed – see git status"
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
    merge_slice "$nr"
  fi
  echo "[slice $nr] done" >&2
}

# The merge queue alone (--merge): every slice-NN branch, lowest number first; one not ticked through Checks is left.
merge_queue() {
  local branch nr
  for branch in $(git for-each-ref --format='%(refname:short)' 'refs/heads/slice-*' | sort -t- -k2,2n); do
    nr=${branch#slice-}
    [[ "$nr" =~ ^[0-9]{2,}$ ]] || continue
    if is_done "$nr"; then continue; fi
    if branch_ready "$nr"; then
      merge_slice "$nr"
    else
      echo "[slice $nr] not ready to merge: its row on $branch is not ticked through Checks – left as it is" >&2
    fi
  done
}

ready_slices() {
  local -a numbers deps
  local i nr dep blocked
  mapfile -t numbers < <(slice_numbers)
  mapfile -t deps < <(slice_deps)
  [[ ${#numbers[@]} -eq ${#deps[@]} ]] || die "every entry in $SLICES_FILE needs \"nr\" and \"deps\""
  for i in "${!numbers[@]}"; do
    nr=${numbers[$i]}
    if is_done "$nr"; then continue; fi
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
  local nr=$1 session=$2 log=$3 approval=$4 model=$5 note="" output
  if $parallel; then
    note=" Other slices are built in parallel: if git is locked or the integration branch moved, wait and retry; in conflicts keep every tick in work/checklist.md."
  fi
  echo "[slice $nr] building – this can take a while (log $log)" >&2
  output=$(claude_turn "$log" "$model" --resume "$session" "$approval$note")
  grep -qE "^(SLICE-DONE:|SLICE-READY:) $nr([^0-9]|$)" <<<"$output" \
    || die "slice $nr not finished: $(grep '^SLICE-OPEN:' <<<"$output" || echo 'no SLICE-DONE or SLICE-READY line') – see $log"
}

run_round() {
  local -a ready sessions logs models approvals pids
  local i
  mapfile -t ready < <(ready_slices)
  [[ ${#ready[@]} -gt 0 ]] || die "no slice is ready – check $CHECKLIST_FILE (/slice status)"
  $parallel || ready=("${ready[0]}")
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
  if $merge_only; then merge_queue; exit 0; fi
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
      exit 0
    fi
  done
  close_round
}

main "$@"
