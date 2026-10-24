#!/usr/bin/env bash
# Runs the rebuild slice by slice, each slice in a fresh headless Claude session.
# Stops for plan approval unless --yes; stops on NEEDS-DECISION, red tests or a blocked slice.
#
# Usage: bash .claude/scripts/rebuild-loop.sh [--yes] [--parallel] [--dry-run]
#   --yes       approve plans without asking (still stops on NEEDS-DECISION)
#   --parallel  build slices that are ready at the same time side by side (experimental)
#   --dry-run   only print the slices that are ready now, then exit
# Env: REBUILD_PERMISSION_MODE (default: auto) – passed to claude --permission-mode.
set -euo pipefail
shopt -s inherit_errexit
# Git Bash on Windows would rewrite the argument "/rebuild …" into a Windows path.
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'

readonly SLICES_FILE="rebuild/_slices.json"
readonly CHECKLIST_FILE="rebuild/checklist.md"
readonly LOG_DIR=".rebuild-loop"
readonly PERMISSION_MODE="${REBUILD_PERMISSION_MODE:-auto}"

auto_approve=false
parallel=false
dry_run=false

die() { echo "rebuild-loop: $*" >&2; exit 1; }

parse_args() {
  for arg in "$@"; do
    case "$arg" in
      --yes) auto_approve=true ;;
      --parallel) parallel=true ;;
      --dry-run) dry_run=true ;;
      *) die "unknown option '$arg' (use --yes, --parallel, --dry-run)" ;;
    esac
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
    | while IFS= read -r deps; do { grep -o '[0-9][0-9]' <<<"$deps" || true; } | tr '\n' ' '; echo; done
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

# Random UUID v4 for --session-id (uuidgen and /proc are missing in Git Bash on Windows).
new_session_id() {
  if command -v uuidgen >/dev/null 2>&1; then uuidgen | tr 'A-Z' 'a-z'; return; fi
  if [[ -r /proc/sys/kernel/random/uuid ]]; then cat /proc/sys/kernel/random/uuid; return; fi
  local hex variant
  hex=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
  variant=$(printf '%x' $(( (16#${hex:16:1} & 3) | 8 )))
  printf '%s-%s-4%s-%s%s-%s\n' "${hex:0:8}" "${hex:8:4}" "${hex:13:3}" "$variant" "${hex:17:3}" "${hex:20:12}"
}

# Runs one claude turn; output goes to the log and is echoed back for marker parsing.
claude_turn() {
  local log=$1; shift
  claude -p --permission-mode "$PERMISSION_MODE" "$@" | tee -a "$log" \
    || die "claude exited with an error – see $log"
}

# Plans slice $1 and waits for approval. Prints the message for the build turn.
plan_slice() {
  local nr=$1 session=$2 log=$3 output answer decisions
  echo "[slice $nr] planning (session $session, log $log)" >&2
  output=$(claude_turn "$log" --session-id "$session" "/rebuild $nr plan auto")
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
    output=$(claude_turn "$log" --resume "$session" \
      "Change request: $answer. Revise the plan, save it and end again with the PLAN line (auto).")
  done
}

build_slice() {
  local nr=$1 session=$2 log=$3 approval=$4 note="" output
  if $parallel; then
    note=" Other slices are built in parallel: if git is locked or main moved, wait and retry; in conflicts keep every tick in rebuild/checklist.md."
  fi
  echo "[slice $nr] building – this can take a while (log $log)" >&2
  output=$(claude_turn "$log" --resume "$session" "$approval$note")
  grep -q "^SLICE-DONE: $nr" <<<"$output" \
    || die "slice $nr not finished: $(grep '^SLICE-OPEN:' <<<"$output" || echo 'no SLICE-DONE line') – see $log"
  is_done "$nr" || die "slice $nr reported done but is not ticked in $CHECKLIST_FILE – check it before running again"
  echo "[slice $nr] done" >&2
}

run_round() {
  local -a ready sessions logs approvals pids
  local i
  mapfile -t ready < <(ready_slices)
  [[ ${#ready[@]} -gt 0 ]] || die "no slice is ready – check rebuild/checklist.md (/rebuild status)"
  $parallel || ready=("${ready[0]}")
  for i in "${!ready[@]}"; do
    sessions[i]=$(new_session_id)
    logs[i]="$LOG_DIR/slice-${ready[i]}-$(date +%Y%m%d-%H%M%S).log"
    approvals[i]=$(plan_slice "${ready[i]}" "${sessions[i]}" "${logs[i]}")
  done
  for i in "${!ready[@]}"; do
    if $parallel; then
      build_slice "${ready[i]}" "${sessions[i]}" "${logs[i]}" "${approvals[i]}" &
      pids[i]=$!
    else
      build_slice "${ready[i]}" "${sessions[i]}" "${logs[i]}" "${approvals[i]}"
    fi
  done
  for i in "${!pids[@]}"; do wait "${pids[i]}" || die "slice ${ready[i]} failed – see ${logs[i]}"; done
}

main() {
  parse_args "$@"
  [[ -f "$SLICES_FILE" && -f "$CHECKLIST_FILE" ]] || die "run from the repo root (needs $SLICES_FILE and $CHECKLIST_FILE)"
  if $dry_run; then ready_slices; exit 0; fi
  command -v claude >/dev/null 2>&1 || die "claude CLI not found"
  mkdir -p "$LOG_DIR"
  grep -qx "$LOG_DIR/" .git/info/exclude 2>/dev/null || echo "$LOG_DIR/" >> .git/info/exclude
  until all_done; do run_round; done
  echo "All slices done. Next: type /rebuild in Claude Code to turn the plan README into the product README."
}

main "$@"
