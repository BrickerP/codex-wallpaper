#!/bin/zsh
set -eu
setopt NO_UNSET

readonly repo_root="${0:A:h:h}"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/codex-wallpaper-protocol.XXXXXX")"
trap '/bin/rm -rf "$test_root"' EXIT INT TERM

fail() { print -u2 "FAIL [$1]"; exit 1; }
assert_true() { local name="$1"; shift; "$@" || fail "$name"; }
assert_equal() {
  local name="$1" actual="$2" expected="$3"
  [[ "$actual" == "$expected" ]] || fail "$name: expected '$expected', got '$actual'"
}
assert_fails() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then fail "$name: command unexpectedly succeeded"; fi
}

export HOME="$test_root/home"
export CODEX_WALLPAPER_SOURCE_ONLY=1
export CODEX_WALLPAPER_PROTOCOL_TEST=1
mkdir -p "$HOME"
source "$repo_root/skill/codex-wallpaper/scripts/codex-wallpaper.zsh"

export CODEX_WALLPAPER_FAILPOINT=lock-after-mkdir
assert_fails 'lock init failure is reported' acquire_restart_lock theme-init
assert_true 'lock init failure removes new lock' test ! -e "$RESTART_LOCK"
export CODEX_WALLPAPER_FAILPOINT=owner-publication
assert_fails 'owner publication failure is reported' acquire_restart_lock theme-owner
assert_true 'owner publication failure removes new lock' test ! -e "$RESTART_LOCK"
unset CODEX_WALLPAPER_FAILPOINT

acquire_restart_lock theme-nonce
scheduled_tuple="$RESTART_OWNER_TUPLE"
nonce="$NONCE_ROOT/restart.nonce-binding"
print -rn -- 'wrong tuple' > "$nonce"
chmod 600 "$nonce"
assert_fails 'nonce must bind full scheduled tuple' claim_restart_lock "$scheduled_tuple" "$nonce"
assert_equal 'bad nonce preserves scheduled owner' "$(read_owner_tuple)" "$scheduled_tuple"
release_restart_lock "$scheduled_tuple"

claimer='
  export CODEX_WALLPAPER_SOURCE_ONLY=1 CODEX_WALLPAPER_PROTOCOL_TEST=1
  source "$1"
  scheduled="$2"; nonce="$3"; result="$4"; delay="$5"; ready="$6"; start_gate="$7"
  export CODEX_WALLPAPER_CLAIM_ACK_DELAY="$delay"
  trap '\''release_restart_lock "${RESTART_OWNER_TUPLE:-}" >/dev/null 2>&1 || true'\'' EXIT
  print -r -- "$$" > "$ready"
  while [[ ! -f "$start_gate" ]]; do /bin/sleep 0.01; done
  claim_restart_lock "$scheduled" "$nonce" || exit 1
  print -r -- "$$" > "$result"
  worker_wait_for_go "$RESTART_OWNER_TUPLE" 100 || exit 1
  /bin/sleep 0.2
'

acquire_restart_lock theme-concurrent
scheduled_tuple="$RESTART_OWNER_TUPLE"
nonce="$NONCE_ROOT/restart.concurrent"
print -rn -- "$scheduled_tuple" > "$nonce"
chmod 600 "$nonce"
result_one="$test_root/claimer-one"
result_two="$test_root/claimer-two"
ready_one="$test_root/ready-one"
ready_two="$test_root/ready-two"
start_gate="$test_root/start-concurrent"
env HOME="$HOME" zsh -c "$claimer" _ "$SCRIPT_PATH" "$scheduled_tuple" "$nonce" "$result_one" 0 \
  "$ready_one" "$start_gate" \
  >/dev/null 2>&1 &
pid_one=$!
env HOME="$HOME" zsh -c "$claimer" _ "$SCRIPT_PATH" "$scheduled_tuple" "$nonce" "$result_two" 0 \
  "$ready_two" "$start_gate" \
  >/dev/null 2>&1 &
pid_two=$!
for _ in {1..100}; do
  [[ -f "$ready_one" && -f "$ready_two" ]] && break
  /bin/sleep 0.01
done
assert_true 'first claimer reaches ready barrier' test -f "$ready_one"
assert_true 'second claimer reaches ready barrier' test -f "$ready_two"
ready_pid_one="$(/bin/cat "$ready_one")"
ready_pid_two="$(/bin/cat "$ready_two")"
assert_equal 'first ready PID matches first subprocess' "$ready_pid_one" "$pid_one"
assert_equal 'second ready PID matches second subprocess' "$ready_pid_two" "$pid_two"
assert_true 'ready barrier contains two distinct PIDs' test "$ready_pid_one" -ne "$ready_pid_two"
/usr/bin/touch "$start_gate"
assert_true 'one real worker ACKs within bound' scheduler_wait_for_ack "$scheduled_tuple" 50
claimed_tuple="$REPLY"
assert_equal 'winning claimer preserves exact acknowledged owner tuple' \
  "$(read_owner_tuple)" "$claimed_tuple"
set +e
wait "$pid_one"; status_one=$?
wait "$pid_two"; status_two=$?
set -e
successes=0
(( status_one == 0 )) && successes=$(( successes + 1 ))
(( status_two == 0 )) && successes=$(( successes + 1 ))
assert_equal 'exactly one concurrent claimer succeeds' "$successes" 1
result_count=0
[[ -f "$result_one" ]] && result_count=$(( result_count + 1 ))
[[ -f "$result_two" ]] && result_count=$(( result_count + 1 ))
assert_equal 'exactly one concurrent claimer publishes result' "$result_count" 1
assert_true 'winning worker releases after GO' test ! -e "$RESTART_LOCK"

acquire_restart_lock theme-mismatch
scheduled_tuple="$RESTART_OWNER_TUPLE"
scheduled_fields=("${(@f)scheduled_tuple}")
mismatch_tuple="$(make_owner_tuple "$scheduled_fields[1]" wrong-theme "$scheduled_fields[3]" \
  worker "$$" "$(process_birth "$$")")"
publish_owner_tuple "$mismatch_tuple"
print -rn -- "$mismatch_tuple" > "$RESTART_LOCK/ack"
chmod 600 "$RESTART_LOCK/ack"
assert_fails 'valid but mismatched ACK is rejected' scheduler_wait_for_ack "$scheduled_tuple" 1
assert_true 'mismatched ACK never grants GO' test ! -e "$RESTART_LOCK/decision/go"
assert_true 'mismatched ACK produces CANCEL' test -f "$RESTART_LOCK/decision/cancel"
release_restart_lock "$mismatch_tuple"

acquire_restart_lock theme-timeout-after-claim
scheduled_tuple="$RESTART_OWNER_TUPLE"
nonce="$NONCE_ROOT/restart.timeout-claim"
print -rn -- "$scheduled_tuple" > "$nonce"
chmod 600 "$nonce"
delayed_result="$test_root/delayed-claimer"
delayed_ready="$test_root/delayed-ready"
delayed_start="$test_root/delayed-start"
env HOME="$HOME" zsh -c "$claimer" _ "$SCRIPT_PATH" "$scheduled_tuple" "$nonce" "$delayed_result" 0.5 \
  "$delayed_ready" "$delayed_start" \
  >/dev/null 2>&1 &
delayed_pid=$!
for _ in {1..100}; do
  [[ -f "$delayed_ready" ]] && break
  /bin/sleep 0.01
done
assert_true 'delayed claimer reaches ready barrier' test -f "$delayed_ready"
/usr/bin/touch "$delayed_start"
claimed=0
for _ in {1..50}; do
  current="$(read_owner_tuple 2>/dev/null || true)"
  current_fields=("${(@f)current}")
  if (( ${#current_fields} == 6 )) && [[ "$current_fields[4]" == worker ]]; then claimed=1; break; fi
  /bin/sleep 0.02
done
assert_equal 'delayed worker claims before scheduler timeout' "$claimed" 1
assert_fails 'timeout after claim chooses CANCEL' scheduler_wait_for_ack "$scheduled_tuple" 1
assert_true 'timeout after claim cannot grant GO' test ! -e "$RESTART_LOCK/decision/go"
assert_true 'timeout after claim publishes CANCEL' test -f "$RESTART_LOCK/decision/cancel"
set +e
wait "$delayed_pid"; delayed_status=$?
set -e
assert_true 'cancelled delayed worker fails' test "$delayed_status" -ne 0
assert_true 'cancelled worker releases its lock' test ! -e "$RESTART_LOCK"

acquire_restart_lock theme-nonowner
owner_tuple="$RESTART_OWNER_TUPLE"
child='export CODEX_WALLPAPER_SOURCE_ONLY=1; source "$1"; "$2" "$EXPECTED_TUPLE"'
assert_fails 'non-owner release is rejected' env HOME="$HOME" EXPECTED_TUPLE="$owner_tuple" \
  zsh -c "$child" _ "$SCRIPT_PATH" release_restart_lock
child='export CODEX_WALLPAPER_SOURCE_ONLY=1; source "$1"; write_restart_state "$EXPECTED_TUPLE" test theme message'
assert_fails 'non-owner status write is rejected' env HOME="$HOME" EXPECTED_TUPLE="$owner_tuple" \
  zsh -c "$child" _ "$SCRIPT_PATH"
release_restart_lock "$owner_tuple"

acquire_restart_lock theme-stale
stale_tuple="$RESTART_OWNER_TUPLE"
stale_fields=("${(@f)stale_tuple}")
dead_tuple="$(make_owner_tuple "$stale_fields[1]" "$stale_fields[2]" "$stale_fields[3]" \
  scheduler 999999 dead-owner-birth)"
publish_owner_tuple "$dead_tuple"
/usr/bin/touch -t 202001010000 "$RESTART_LOCK"
RESTART_OWNER_TUPLE=''; RESTART_LOCK_TOKEN=''; RESTART_OPERATION_ID=''
acquire_restart_lock theme-recovered
recovered_fields=("${(@f)RESTART_OWNER_TUPLE}")
assert_equal 'dead-owner stale recovery acquires requested theme' "$recovered_fields[2]" theme-recovered
release_restart_lock "$RESTART_OWNER_TUPLE"

print 'restart protocol: ok'
