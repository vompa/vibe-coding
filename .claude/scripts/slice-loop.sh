#!/usr/bin/env bash
# Builds the open round slice by slice, each slice in a fresh headless Claude session, then closes the round.
# Stops for plan approval unless --yes; stops on NEEDS-DECISION, red tests or a blocked slice.
#
# Usage: bash .claude/scripts/slice-loop.sh [--yes] [--parallel] [--dry-run] [--max-slices N]
#   --yes           approve plans without asking (still stops on NEEDS-DECISION)
#   --parallel      build slices that are ready at the same time side by side (experimental)
#   --dry-run       only print the slices that are ready now, then exit
#   --max-slices N  stop after N built slices if slices are left (exit 0; run again to continue)
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
readonly USAGE="use --yes, --parallel, --dry-run, --max-slices N"

auto_approve=false
parallel=false
dry_run=false
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

# Model of slice $1 – its "model" field, empty when the entry has none. Every turn of the slice runs on it,
# never on the default of the caller. The entries hold no nested objects, so "}" ends an entry.
slice_model() {
  tr '\n}' ' \n' <"$SLICES_FILE" \
    | grep "\"nr\"[[:space:]]*:[[:space:]]*\"$1\"" \
    | grep -o '"model"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*:[[:space:]]*"//; s/"$//' || true
}

# A slice is done when its checklist row has at least one ☑ and no ☐.
is_done() {
  local row
  row=$(grep -E "^\|[[:space:]]*$1([^0-9]|$)" "$CHECKLIST_FILE" || true)
  [[ -n "$row" && "$row" == *"☑"* && "$row" != *"☐"* ]]
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

# Id (R01, R02 …) of the first round record in $ROUNDS_DIR whose first line is "Status: open"; nothing if none is open.
open_round() {
  local file first
  for file in "$ROUNDS_DIR"/*.md; do
    [[ -f "$file" ]] || continue
    IFS= read -r first <"$file" || true
    if [[ "${first%$'\r'}" == "Status: open" ]]; then
      basename "$file" | grep -o '^R[0-9][0-9]*' || true
      return
    fi
  done
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
  grep -qE "^SLICE-DONE: $nr([^0-9]|$)" <<<"$output" \
    || die "slice $nr not finished: $(grep '^SLICE-OPEN:' <<<"$output" || echo 'no SLICE-DONE line') – see $log"
  is_done "$nr" || die "slice $nr reported done but is not ticked in $CHECKLIST_FILE – check it before running again"
  echo "[slice $nr] done" >&2
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
    fi
  done
  for i in "${!pids[@]}"; do wait "${pids[i]}" || die "slice ${ready[i]} failed – see ${logs[i]}"; done
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
  round=$(open_round)
  if [[ -z "$round" ]]; then
    echo "slice-loop: no open round in $ROUNDS_DIR – start a round with the vibe-coding skill first" >&2
    exit 0
  fi
  command -v claude >/dev/null 2>&1 || die "claude CLI not found"
  mkdir -p "$LOG_DIR"
  grep -qx "$LOG_DIR/" .git/info/exclude 2>/dev/null || echo "$LOG_DIR/" >> .git/info/exclude
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
