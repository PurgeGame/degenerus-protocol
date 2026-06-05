#!/usr/bin/env bash
# coordinator.sh — unattended, API-error-resilient supervisor for the audit-v52 run.
#
# Lives OUTSIDE the Claude process, so a rate-limited / poisoned / crashed `claude -p`
# cannot take it down. Drives the three phases in order (hunt -> verify -> synthesize),
# each as a bounded headless `claude -p`. Idempotent: a phase whose sentinel exists is
# skipped. Each attempt is a FRESH `claude -p` (NEVER --continue/--resume) — this is the
# load-bearing reason a "thinking blocks cannot be modified" 400 self-heals (a poisoned
# transcript simply does not exist in the next attempt). DO NOT add --continue/--resume.
#
# It CLASSIFIES each failure and recovers per-class instead of one flat backoff:
#   transient/network -> short attempt-indexed backoff (+jitter)   [CLI already burned its 10x internal retries]
#   rate_limit (429)  -> medium wait
#   usage_limit (5h)  -> sleep until the parsed reset clock
#   thinking_block    -> fresh relaunch, bounded counter + floor sleep (no hot-loop)
#   invalid/context/unknown/clean_no_sentinel -> HARD: cap consecutive failures, then STOP (status=blocked)
# The hunt phase is RESUMABLE: 01-hunt.js writes candidates.partial.json per round, so a
# cold re-run resumes from the last completed round, and partial-file GROWTH is the
# progress signal that resets the hard cap (a long job making progress is never killed).
#
# Usage:
#   bin/coordinator.sh --sha <FROZEN_SHA> [--run-id id] [--audit-dir DIR] [--max-hours 23]
#       [--cap-hard 4] [--cap-thinking 3] [--rate-sleep 600] [--limit-sleep 3600]
#       [--retry-sleep 300] [--net-window 3600] [--claude claude] [--detach]
#
#   nohup bin/coordinator.sh --sha <FROZEN_SHA> --detach &   # fire-and-forget overnight
#
# FROZEN_SHA MUST be the v51-closure HEAD (the audit subject), NOT a moving HEAD.
set -uo pipefail

AUDIT_DIR=".planning/audit-v52"
SHA=""
RUN_ID=""
MAX_HOURS=23
CAP_HARD=4            # consecutive HARD (deterministic) failures before a phase is BLOCKED + stopped
CAP_THINKING=3       # consecutive thinking-block relaunches before treating poison as deterministic + stopping
ABS_ATTEMPT_CEIL=60  # absolute per-phase attempt ceiling (independent of progress) — bounds a never-finalizing phase
RATE_SLEEP=600       # 429 backoff
LIMIT_SLEEP=3600     # subscription 5h-window fallback when the reset clock can't be parsed
RETRY_SLEEP=300      # HARD-class floor backoff (kept short; the cap stops real hammering)
NET_WINDOW=3600      # tolerate up to this many seconds of continuous network loss before escalating to HARD
CLAUDE_BIN="claude"
DETACH=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sha)          SHA="$2"; shift 2 ;;
    --run-id)       RUN_ID="$2"; shift 2 ;;
    --audit-dir)    AUDIT_DIR="$2"; shift 2 ;;
    --max-hours)    MAX_HOURS="$2"; shift 2 ;;
    --cap-hard)     CAP_HARD="$2"; shift 2 ;;
    --cap-thinking) CAP_THINKING="$2"; shift 2 ;;
    --abs-ceil)     ABS_ATTEMPT_CEIL="$2"; shift 2 ;;
    --rate-sleep)   RATE_SLEEP="$2"; shift 2 ;;
    --limit-sleep)  LIMIT_SLEEP="$2"; shift 2 ;;
    --retry-sleep)  RETRY_SLEEP="$2"; shift 2 ;;
    --net-window)   NET_WINDOW="$2"; shift 2 ;;
    --claude)       CLAUDE_BIN="$2"; shift 2 ;;
    --detach)       DETACH=1; shift ;;
    -h|--help)      grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "coordinator: unknown arg $1" >&2; exit 2 ;;
  esac
done
[[ -z "$SHA" ]] && { echo "coordinator: --sha <FROZEN_SHA> is required (the v51-closure HEAD)" >&2; exit 2; }

# Pin the repo root and cd into it so ALL relative paths are cwd-invariant. Doing this BEFORE
# the setsid re-exec means the detached child inherits this cwd; we also re-assert it after
# re-exec for belt-and-suspenders.
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT" || { echo "coordinator: cannot cd to repo root $REPO_ROOT" >&2; exit 2; }

# Absolute paths (cwd-invariant).
case "$AUDIT_DIR" in /*) AUDIT_DIR_ABS="$AUDIT_DIR" ;; *) AUDIT_DIR_ABS="$REPO_ROOT/$AUDIT_DIR" ;; esac
[[ -z "$RUN_ID" ]] && RUN_ID="run-${SHA:0:10}"
RUN_DIR="$AUDIT_DIR_ABS/runs/$RUN_ID"
mkdir -p "$RUN_DIR/council"
LOG="$RUN_DIR/coordinator.log"
STATE="$RUN_DIR/run-state.json"
HUNT_SENTINEL="$RUN_DIR/candidates.json"
VERIFY_SENTINEL="$RUN_DIR/verified.json"
SYNTH_SENTINEL="$REPO_ROOT/audit/FINDINGS-v60.0.md"
HUNT_PROGRESS="$RUN_DIR/candidates.partial.json"

# Re-exec detached so it survives the terminal closing; capture boot stderr to a file (NOT /dev/null)
# so a bash-level crash before logging is diagnosable.
if [[ "$DETACH" == "1" && -z "${COORD_DETACHED:-}" ]]; then
  export COORD_DETACHED=1
  setsid "$0" --sha "$SHA" --run-id "$RUN_ID" --audit-dir "$AUDIT_DIR" --max-hours "$MAX_HOURS" \
    --cap-hard "$CAP_HARD" --cap-thinking "$CAP_THINKING" --abs-ceil "$ABS_ATTEMPT_CEIL" --rate-sleep "$RATE_SLEEP" \
    --limit-sleep "$LIMIT_SLEEP" --retry-sleep "$RETRY_SLEEP" --net-window "$NET_WINDOW" \
    --claude "$CLAUDE_BIN" >/dev/null 2>"$RUN_DIR/coordinator.boot.stderr" < /dev/null &
  echo "coordinator: detached (pid $!). Logs: $LOG"
  exit 0
fi
cd "$REPO_ROOT" 2>/dev/null || true   # re-assert in the detached child

now_s()  { date +%s 2>/dev/null || echo 0; }
now_hms(){ date -u +%H:%M:%SZ 2>/dev/null || echo ''; }
log() { printf '[coordinator %s] %s\n' "$(now_hms)" "$*" | tee -a "$LOG"; }

write_state() { # $1=phase $2=status  (+heartbeat so an external watcher can tell sleeping from wedged)
  printf '{\n  "run_id": "%s",\n  "frozen_sha": "%s",\n  "phase": "%s",\n  "status": "%s",\n  "heartbeat": "%s",\n  "run_dir": "%s"\n}\n' \
    "$RUN_ID" "$SHA" "$1" "$2" "$(now_s)" "$RUN_DIR" > "$STATE"
}

START_TS="$(now_s)"
elapsed_hours() { echo $(( ( $(now_s) - START_TS ) / 3600 )); }

safe_sleep() { # never let a garbage/empty duration skip the sleep (-> hot loop)
  local s="${1:-}"; case "$s" in ''|*[!0-9]*) s=60 ;; esac; (( s < 1 )) && s=60; sleep "$s"; }

progress_size() { [[ -n "${1:-}" && -f "$1" ]] && { wc -c < "$1" 2>/dev/null || echo 0; } || echo 0; }

partial_round() { # the hunt partial's lastRound — genuine progress is a ROUND advance, not mere byte growth
  local f="${1:-}"; [[ -n "$f" && -f "$f" ]] || { echo 0; return; }
  if command -v jq >/dev/null 2>&1; then jq -r '.lastRound // 0' "$f" 2>/dev/null || echo 0
  else { grep -oE '"lastRound"[[:space:]]*:[[:space:]]*[0-9]+' "$f" 2>/dev/null | grep -oE '[0-9]+' | head -1; } || echo 0; fi; }

# A phase is COMPLETE only if its sentinel exists, is non-empty, AND (for .json) parses — so a nonempty-but-corrupt
# sentinel is NOT mistaken for success (it falls through to clean_no_sentinel → retry → HARD-cap).
sentinel_complete() {
  local s="$1"; [[ -s "$s" ]] || return 1
  case "$s" in
    *.json)
      if command -v jq >/dev/null 2>&1; then jq -e . "$s" >/dev/null 2>&1 || return 1
      elif command -v python3 >/dev/null 2>&1; then python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$s" >/dev/null 2>&1 || return 1; fi ;;
  esac
  return 0; }

tail_sha() { # stable hash of the failure tail to detect a byte-identical (deterministic) crash
  if command -v sha1sum >/dev/null 2>&1; then tail -n 20 "$1" 2>/dev/null | sha1sum | cut -d' ' -f1
  else tail -n 5 "$1" 2>/dev/null | tr -d '[:space:]' | cut -c1-80; fi; }

backoff_for_attempt() { # attempt-indexed base + shell-side jitter ($RANDOM allowed OUTSIDE the model; the
  local a="${1:-1}" b j s    # no-randomness rule binds ONLY the Workflow JS runtime, not this shell)
  case "$a" in 1) b=30 ;; 2) b=60 ;; 3) b=120 ;; *) b=300 ;; esac
  j=$(( RANDOM % 30 )); s=$(( b + j )); (( s > 600 )) && s=600; echo "$s"; }

# Classify a failed attempt. Reads only the TAIL (the API-Error wrapper lands near the end) so a finding/vote
# that merely QUOTES an attack-class term ("429", "overloaded", "quota") can't poison the classifier. Order:
# most-specific / poisoning first; the 'usage credits' override is checked BEFORE the 5h-limit grep.
classify_error() { # $1=out $2=rc  -> echoes one class token
  local out="$1" rc="$2" t
  t="$(tail -n 60 "$out" 2>/dev/null)"
  grep -qiF 'continuing with usage credits' <<<"$t" && { echo transient; return; }                               # work proceeds on credits
  grep -qiE 'cannot be modified|These blocks must remain|redacted_thinking' <<<"$t" && { echo thinking_block; return; }
  # usage/session limit — broadened to the REAL Claude CLI wording, which classify v1 missed:
  #   "You've hit your session limit · resets 11:10pm (America/Chicago)"  (note: "session" not "usage",
  #   and "resets 11:10pm" with NO "at"). Anchor on the API-specific limit phrasings + any "reset(s) <clock>".
  #   Checked BEFORE rate_limit so a hard window-reset waits for the clock instead of a 600s rate nap.
  grep -qiE 'session limit|usage limit|hit your[^.]*limit|[0-9]+-hour limit|limit reached|limit will reset|reset[s]?( at)? +[0-9]{1,2}(:[0-9]{2})? *[ap]?m?' <<<"$t" && { echo usage_limit; return; }
  grep -qiE 'request_too_large|prompt is too long|exceed the length limit|maximum context' <<<"$t" && { echo context_length; return; }
  grep -qiE 'invalid_request_error|Prefilling assistant messages|is not supported for this model' <<<"$t" && { echo invalid_request; return; }
  grep -qiE 'rate_limit_error|Server is temporarily limiting|too many requests|API Error \(429' <<<"$t" && { echo rate_limit; return; }
  grep -qiE 'ECONNRESET|ETIMEDOUT|EPIPE|ECONNREFUSED|ENOTFOUND|fetch failed|Connection error|socket hang up' <<<"$t" && { echo network; return; }
  grep -qiE 'overloaded_error|"message":"Overloaded"|timeout_error|API Error \(5[0-9][0-9]' <<<"$t" && { echo transient; return; }
  if [[ "$rc" == "0" ]]; then echo clean_no_sentinel; else echo unknown; fi
}

parse_reset_seconds() { # grep the WHOLE output for the reset clock (it can appear ABOVE the tail wrapper)
  local out="$1" clock tz now target delta
  command -v date >/dev/null 2>&1 || { echo ""; return; }
  # Match BOTH "reset(s) at 11:10 pm" and the real CLI "resets 11:10pm" (no "at"); :MM optional.
  clock="$(grep -oiE 'reset[s]?( at)? +[0-9]{1,2}(:[0-9]{2})? ?[ap]m' "$out" 2>/dev/null | head -1 \
            | sed -E 's/.*reset[s]?( at)? +//I')"
  [[ -z "$clock" ]] && { echo ""; return; }
  # The CLI prints the window's timezone in parens, e.g. "(America/Chicago)" — honor it so the clock
  # is interpreted in the RIGHT zone (a 5h-window reset misread by hours = waking early/late repeatedly).
  tz="$(grep -oiE '\([A-Za-z]+/[A-Za-z_]+\)' "$out" 2>/dev/null | head -1 | tr -d '()')"
  now="$(date -u +%s 2>/dev/null)" || { echo ""; return; }
  if [[ -n "$tz" ]]; then target="$(TZ="$tz" date -d "$clock" +%s 2>/dev/null)" || target=""
  else                    target="$(date -d "$clock" +%s 2>/dev/null)" || target=""; fi
  [[ -z "$target" ]] && { echo ""; return; }
  delta=$(( target - now )); (( delta < 0 )) && delta=$(( delta + 86400 ))   # roll a past clock to tomorrow
  delta=$(( delta + 60 )); (( delta < 60 )) && delta=60                       # +60s pad
  # Cap generously (6h) so a parse glitch can't sleep absurdly long; a genuine longer window just
  # re-trips usage_limit on the next wake and waits again (usage_limit never counts toward the HARD cap).
  (( delta > 21600 )) && delta=21600
  echo "$delta"
}

# Run one phase to completion (sentinel-gated), classifying + recovering per failure class.
# $1=name $2=sentinel $3=prompt $4=progress-file(optional, for the resumable hunt)
# returns 0=complete, 4=blocked(needs human); exits 3 on wall-clock cap.
run_phase() {
  local name="$1" sentinel="$2" prompt="$3" progress="${4:-}"
  if sentinel_complete "$sentinel"; then log "phase $name already complete ($sentinel, valid) — skipping"; return 0; fi
  local attempt=0 consec_hard=0 consec_transient=0 consec_thinking=0 net_started=0
  local last_sha='' last_progress last_round
  last_progress="$(progress_size "$progress")"; last_round="$(partial_round "$progress")"
  while :; do
    if [[ "$(elapsed_hours)" -ge "$MAX_HOURS" ]]; then log "WALL-CLOCK CAP (${MAX_HOURS}h) during $name — stopping"; write_state "$name" capped; exit 3; fi
    # Absolute attempt ceiling, independent of progress — a never-finalizing phase still trips a cap
    # (a partial that keeps growing by bytes but never produces a valid sentinel cannot loop until MAX_HOURS).
    if (( attempt >= ABS_ATTEMPT_CEIL )); then log "phase $name BLOCKED: ${attempt} attempts without a valid sentinel (absolute ceiling) — stopping"; write_state "$name" blocked; return 4; fi
    attempt=$(( attempt + 1 ))
    write_state "$name" "running(attempt $attempt)"
    log "phase $name attempt $attempt (hard=$consec_hard transient=$consec_transient thinking=$consec_thinking)"
    local out="$RUN_DIR/$name.attempt${attempt}.out"
    "$CLAUDE_BIN" -p "$prompt" --permission-mode bypassPermissions --output-format text >"$out" 2>&1
    local rc=$?
    if sentinel_complete "$sentinel"; then log "phase $name COMPLETE (sentinel present + valid, rc=$rc)"; write_state "$name" complete; return 0; fi

    local class; class="$(classify_error "$out" "$rc")"
    # GENUINE progress = the resumable hunt advanced a ROUND (lastRound grew) OR — with per-cell resume —
    # banked more cells mid-round so the partial grew in bytes. Either resets the HARD cap; the ABS_ATTEMPT_CEIL
    # still backstops a pathological partial that grows-but-never-finalizes, so this cannot reset the cap forever.
    local cur_progress cur_round made_progress=0
    cur_progress="$(progress_size "$progress")"; cur_round="$(partial_round "$progress")"
    [[ -n "$progress" && ( "$cur_round" -gt "$last_round" || "$cur_progress" -gt "$last_progress" ) ]] && made_progress=1
    last_progress="$cur_progress"; last_round="$cur_round"
    log "phase $name attempt $attempt: class=$class rc=$rc made_progress=$made_progress (round $last_round)"

    case "$class" in
      transient)
        consec_transient=$(( consec_transient + 1 )); [[ "$made_progress" == 1 ]] && consec_hard=0; net_started=0
        write_state "$name" "retrying(transient)"; safe_sleep "$(backoff_for_attempt "$consec_transient")" ;;
      network)
        [[ "$net_started" == 0 ]] && net_started="$(now_s)"
        local net_elapsed=$(( $(now_s) - net_started ))
        consec_transient=$(( consec_transient + 1 ))
        if (( net_elapsed > NET_WINDOW )); then
          consec_hard=$(( consec_hard + 1 )); log "network down ${net_elapsed}s > ${NET_WINDOW}s — escalating toward HARD ($consec_hard/$CAP_HARD)"
          if (( consec_hard >= CAP_HARD )); then log "phase $name BLOCKED: network down too long — check connectivity/proxy"; write_state "$name" blocked; return 4; fi
        fi
        write_state "$name" "retrying(network)"; safe_sleep "$(backoff_for_attempt "$consec_transient")" ;;
      rate_limit)
        consec_transient=0; consec_thinking=0; net_started=0; [[ "$made_progress" == 1 ]] && consec_hard=0
        write_state "$name" rate-limited; log "429 rate limit — sleeping ${RATE_SLEEP}s"; safe_sleep "$RATE_SLEEP" ;;
      usage_limit)
        consec_transient=0; consec_thinking=0; net_started=0; [[ "$made_progress" == 1 ]] && consec_hard=0
        local rs; rs="$(parse_reset_seconds "$out")"; [[ -z "$rs" ]] && rs="$LIMIT_SLEEP"
        write_state "$name" usage-wait; log "5h usage window — sleeping ${rs}s (until reset)"; safe_sleep "$rs" ;;
      thinking_block)
        consec_thinking=$(( consec_thinking + 1 )); net_started=0
        write_state "$name" thinking-relaunch
        log "thinking-block poison — FRESH relaunch ($consec_thinking/$CAP_THINKING); next attempt is a clean conversation"
        if (( consec_thinking >= CAP_THINKING )); then log "phase $name BLOCKED: thinking-block recurs ${consec_thinking}× — deterministic poison, NOT self-healing (verify no --resume / no engine transcript reload)"; write_state "$name" blocked; return 4; fi
        safe_sleep 30 ;;   # floor so a recurring poison is not a tight CPU spin
      clean_no_sentinel)
        if [[ "$made_progress" == 1 ]]; then
          log "clean_no_sentinel but progress file GREW — making progress, NOT counting toward cap"; consec_hard=0
          write_state "$name" "retrying(progressing)"; safe_sleep "$(backoff_for_attempt 1)"
        else
          local th; th="$(tail_sha "$out")"; if [[ "$th" == "$last_sha" ]]; then consec_hard=$(( consec_hard + 2 )); else consec_hard=$(( consec_hard + 1 )); fi; last_sha="$th"
          write_state "$name" "retrying(no-sentinel)"
          if (( consec_hard >= CAP_HARD )); then log "phase $name BLOCKED: clean_no_sentinel with NO progress ×$consec_hard — stopping (read $out)"; write_state "$name" blocked; return 4; fi
          safe_sleep "$(backoff_for_attempt "$consec_hard")"
        fi ;;
      invalid_request|context_length|unknown)
        local th2; th2="$(tail_sha "$out")"; if [[ "$th2" == "$last_sha" ]]; then consec_hard=$(( consec_hard + 2 )); else consec_hard=$(( consec_hard + 1 )); fi; last_sha="$th2"
        write_state "$name" "retrying($class)"
        if (( consec_hard >= CAP_HARD )); then log "phase $name BLOCKED after $consec_hard HARD failures (class=$class) — deterministic, needs a human (read $out tail)"; write_state "$name" blocked; return 4; fi
        safe_sleep "$RETRY_SLEEP" ;;
    esac
  done
}

WF="$AUDIT_DIR_ABS/workflows"
ARGS_COMMON="auditDir: \"$AUDIT_DIR_ABS\", frozenSHA: \"$SHA\", runDir: \"$RUN_DIR\""

log "=== audit-v52 coordinator start === run=$RUN_ID sha=$SHA dir=$RUN_DIR cap=${MAX_HOURS}h cap_hard=$CAP_HARD"
write_state init starting

run_phase hunt "$HUNT_SENTINEL" \
  "Run the audit-v52 HUNT phase. Call the Workflow tool with scriptPath \"$WF/01-hunt.js\" and args { $ARGS_COMMON, spine: false, batchSize: 4, concurrency: 2, maxRounds: 6, dryRounds: 2 }. Let it run to completion, then report the returned JSON. Do nothing else." \
  "$HUNT_PROGRESS" \
  || { log "ABORT: hunt BLOCKED — see run-state.json (status=blocked) and the latest hunt.attempt*.out"; exit 4; }

run_phase verify "$VERIFY_SENTINEL" \
  "Run the audit-v52 COUNCIL-VERIFY phase. Call the Workflow tool with scriptPath \"$WF/02-council-verify.js\" and args { $ARGS_COMMON }. Let it run to completion, then report the returned JSON. Do nothing else." \
  || { log "ABORT: verify BLOCKED — see run-state.json and verify.attempt*.out"; exit 4; }

run_phase synth "$SYNTH_SENTINEL" \
  "Run the audit-v52 SYNTHESIZE phase. Call the Workflow tool with scriptPath \"$WF/03-synthesize.js\" and args { $ARGS_COMMON, reportPath: \"$SYNTH_SENTINEL\" }. Let it run to completion, then report the returned JSON including the completeness-critic gaps. Do nothing else." \
  || { log "ABORT: synth BLOCKED — see run-state.json and synth.attempt*.out"; exit 4; }

write_state done complete
log "=== audit-v52 coordinator DONE === report: $SYNTH_SENTINEL  candidates: $HUNT_SENTINEL  verified: $VERIFY_SENTINEL"
# Surface coverage caveats loudly so a green run is never mistaken for full coverage.
if command -v grep >/dev/null 2>&1; then
  grep -q '"truncated": *true' "$HUNT_SENTINEL" 2>/dev/null && log "⚠ HUNT WAS TRUNCATED (budget) — coverage INCOMPLETE; see candidates.json .truncated/.lostCells and re-run with more budget/rounds."
  grep -q '"lostCells": *\[[^]]' "$HUNT_SENTINEL" 2>/dev/null && log "⚠ Some cells were lost to API/terminal errors — see candidates.json .lostCells; the completeness critic names them as gaps to re-hunt."
fi
log "Review the completeness-critic gaps in the synth output; to go deeper, raise --max-hours or re-run hunt (it resumes from candidates.partial.json)."
