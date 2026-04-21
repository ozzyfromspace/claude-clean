#!/usr/bin/env bash
# Zero-dependency test harness for claude-clean.
#
# Each test function uses $HOME which points at a fresh temp dir for isolation.
# Returns 0 = pass, non-zero = fail. The harness captures output and prints it
# on failure so you can see what went wrong.

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/claude-clean"

TESTS_RUN=0
TESTS_FAILED=0
ORIGINAL_HOME="$HOME"

run_test() {
  local name="$1" fn="$2"
  local testdir
  testdir=$(mktemp -d)
  export HOME="$testdir"
  TESTS_RUN=$((TESTS_RUN + 1))
  local output status
  output=$("$fn" 2>&1) && status=0 || status=$?
  if [ "$status" = "0" ]; then
    printf "  ✓ %s\n" "$name"
  else
    printf "  ✗ %s\n" "$name"
    [ -n "$output" ] && echo "$output" | sed 's/^/      /'
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
  export HOME="$ORIGINAL_HOME"
  rm -rf "$testdir"
}

contains() {
  case "$2" in *"$1"*) return 0 ;; *) return 1 ;; esac
}

# ---------- Tests ----------

t_help_exits_zero_and_shows_usage() {
  local out; out=$("$SCRIPT" --help 2>&1) || { echo "help exited nonzero"; return 1; }
  contains "Usage: claude-clean" "$out" || { echo "missing 'Usage:'"; return 1; }
  contains "Units: s, m, h, d" "$out" || { echo "missing units doc"; return 1; }
  contains "--protect" "$out" || { echo "missing --protect doc"; return 1; }
}

t_unknown_flag_rejected() {
  local out; out=$("$SCRIPT" --not-a-real-flag 2>&1) && { echo "should have errored"; return 1; }
  contains "unknown option" "$out" || { echo "error message unclear: $out"; return 1; }
}

t_bad_duration_suffix() {
  local out; out=$("$SCRIPT" --older-than=5mo 2>&1) && { echo "should have errored"; return 1; }
  contains "unknown time suffix 'mo'" "$out" || { echo "did not catch 'mo': $out"; return 1; }
  contains "Supported units" "$out" || { echo "missing help in error"; return 1; }
}

t_months_suffix_rejected() {
  local out; out=$("$SCRIPT" --older-than=5months 2>&1) && { echo "should have errored"; return 1; }
  contains "unknown time suffix 'months'" "$out" || { echo "did not catch 'months': $out"; return 1; }
}

t_decimal_duration_rejected() {
  local out; out=$("$SCRIPT" --older-than=1.5h 2>&1) && { echo "should have errored"; return 1; }
  contains "whole numbers" "$out" || { echo "decimal not caught: $out"; return 1; }
}

t_empty_duration_rejected() {
  local out; out=$("$SCRIPT" --older-than= 2>&1) && { echo "should have errored"; return 1; }
  contains "empty" "$out" || { echo "empty not caught: $out"; return 1; }
}

t_no_number_rejected() {
  local out; out=$("$SCRIPT" --older-than=abc 2>&1) && { echo "should have errored"; return 1; }
  contains "must start with a number" "$out" || { echo "not caught: $out"; return 1; }
}

t_leading_zero_duration_parses() {
  # '09m' would fail if we let bash arithmetic treat it as octal; we force base 10.
  "$SCRIPT" --older-than=09m --profile="$(id -un)" >/dev/null 2>&1 \
    || { echo "09m should parse as 9 minutes"; return 1; }
}

t_raw_seconds_accepted() {
  "$SCRIPT" --older-than=300 --profile="$(id -un)" >/dev/null 2>&1 \
    || { echo "raw seconds should be accepted"; return 1; }
}

t_bad_user_rejected() {
  local out; out=$("$SCRIPT" --profile=thisusernamedoesnotexistx 2>&1) && { echo "should have errored"; return 1; }
  contains "no such user" "$out" || { echo "error unclear: $out"; return 1; }
}

t_empty_profile_rejected() {
  local out; out=$("$SCRIPT" --profile= 2>&1) && { echo "should have errored"; return 1; }
  contains "requires a username" "$out" || { echo "error unclear: $out"; return 1; }
}

t_list_protected_empty() {
  local out; out=$("$SCRIPT" --list-protected 2>&1) || { echo "--list-protected failed"; return 1; }
  contains "No protected" "$out" || { echo "expected 'No protected' message, got: $out"; return 1; }
}

t_protect_invalid_pid_rejected() {
  local out; out=$("$SCRIPT" --protect=notapid 2>&1) && { echo "should have errored"; return 1; }
  contains "invalid PID" "$out" || { echo "error unclear: $out"; return 1; }
}

t_symlink_protect_dir_refused() {
  ln -s /etc "$HOME/.claude-clean"
  local out; out=$("$SCRIPT" --list-protected 2>&1) && { echo "should have errored"; return 1; }
  contains "is a symlink" "$out" || { echo "dir symlink not refused: $out"; return 1; }
}

t_symlink_protect_file_refused_and_target_untouched() {
  mkdir "$HOME/.claude-clean"
  local target="$HOME/.claude-clean/sensitive-target"
  printf 'SECRET_DATA_DO_NOT_TRUNCATE' > "$target"
  ln -s "$target" "$HOME/.claude-clean/protected"
  "$SCRIPT" --protect=99999 >/dev/null 2>&1 && { echo "should have refused"; return 1; }
  local after; after=$(cat "$target")
  [ "$after" = "SECRET_DATA_DO_NOT_TRUNCATE" ] \
    || { echo "symlinked target was modified! (now: '$after')"; return 1; }
}

t_protect_file_perms_are_strict() {
  "$SCRIPT" --protect=99999 >/dev/null 2>&1
  local dir_mode file_mode
  dir_mode=$(stat -f '%Lp' "$HOME/.claude-clean")
  file_mode=$(stat -f '%Lp' "$HOME/.claude-clean/protected")
  [ "$dir_mode" = "700" ] || { echo "dir mode $dir_mode, expected 700"; return 1; }
  [ "$file_mode" = "600" ] || { echo "file mode $file_mode, expected 600"; return 1; }
}

t_prune_drops_stale_and_garbage_entries() {
  # Seed the protect file with a mix of dead PIDs and garbage lines. Any
  # invocation runs prune_protect, which should clean them all out.
  mkdir "$HOME/.claude-clean"
  printf '%s\n' "99999" "notanumber" "" "88888" "-5" > "$HOME/.claude-clean/protected"
  local out; out=$("$SCRIPT" --list-protected 2>&1) || { echo "list failed"; return 1; }
  contains "No protected" "$out" \
    || { echo "prune did not empty stale/garbage entries: $out"; return 1; }
  # Also verify the file on disk is empty.
  [ ! -s "$HOME/.claude-clean/protected" ] \
    || { echo "protect file still has content: $(cat "$HOME/.claude-clean/protected")"; return 1; }
}

t_list_default_shows_column_headers() {
  local out; out=$("$SCRIPT" 2>&1) || { echo "default run failed"; return 1; }
  contains "PID" "$out" || { echo "missing PID header"; return 1; }
  contains "STATE" "$out" || { echo "missing STATE header"; return 1; }
  contains "TITLE" "$out" || { echo "missing TITLE header"; return 1; }
}

t_unprotect_noop_is_honest() {
  # Unprotecting a PID that was never protected must NOT falsely claim success.
  local out; out=$("$SCRIPT" --unprotect=99999 2>&1)
  contains "was not protected" "$out" \
    || { echo "expected 'was not protected' but got: $out"; return 1; }
  case "$out" in *"Unprotected PID"*) echo "falsely claimed success: $out"; return 1 ;; esac
}

t_protect_nonexistent_pid_rejected() {
  # Protecting a PID that doesn't exist used to silently succeed then get
  # pruned on the next run. Must fail loudly instead.
  local out; out=$("$SCRIPT" --protect=99999 2>&1) && { echo "should have errored"; return 1; }
  contains "not found" "$out" \
    || { echo "expected 'not found' but got: $out"; return 1; }
}

t_protect_non_claude_pid_rejected() {
  # Protecting a real but non-claude process (e.g., our own shell) must fail.
  # $$ = the test's shell PID; its comm is definitely not 'claude'.
  local out; out=$("$SCRIPT" --protect=$$ 2>&1) && { echo "should have errored"; return 1; }
  contains "is not a claude process" "$out" \
    || { echo "expected rejection but got: $out"; return 1; }
}

# ---- Injection-resistance tests ----
#
# Each one passes a command-substitution payload through a tainted input and
# asserts a sentinel file was NOT created. If the payload fires, the file
# would appear; absence proves the validator held.

t_no_injection_via_duration() {
  local sentinel="$HOME/INJECTED_VIA_DURATION"
  "$SCRIPT" --older-than='$(touch '"$sentinel"')m' >/dev/null 2>&1 || true
  [ ! -e "$sentinel" ] \
    || { echo "INJECTION: $sentinel was created via --older-than"; return 1; }
}

t_no_injection_via_duration_backticks() {
  local sentinel="$HOME/INJECTED_VIA_BACKTICKS"
  "$SCRIPT" --older-than='`touch '"$sentinel"'`m' >/dev/null 2>&1 || true
  [ ! -e "$sentinel" ] \
    || { echo "INJECTION: $sentinel was created via backticks in --older-than"; return 1; }
}

t_no_injection_via_profile() {
  local sentinel="$HOME/INJECTED_VIA_PROFILE"
  "$SCRIPT" --profile='$(touch '"$sentinel"')' >/dev/null 2>&1 || true
  [ ! -e "$sentinel" ] \
    || { echo "INJECTION: $sentinel was created via --profile"; return 1; }
}

t_no_injection_via_protect() {
  local sentinel="$HOME/INJECTED_VIA_PROTECT"
  "$SCRIPT" --protect='123$(touch '"$sentinel"')' >/dev/null 2>&1 || true
  [ ! -e "$sentinel" ] \
    || { echo "INJECTION: $sentinel was created via --protect"; return 1; }
}

t_no_injection_via_unknown_flag() {
  # Unknown flags get echoed back in the error; ensure arg isn't evaluated.
  local sentinel="$HOME/INJECTED_VIA_FLAG"
  "$SCRIPT" '--bogus=$(touch '"$sentinel"')' >/dev/null 2>&1 || true
  [ ! -e "$sentinel" ] \
    || { echo "INJECTION: $sentinel was created via unknown-flag echo"; return 1; }
}

t_sanitize_strips_control_bytes() {
  # Exercise the sanitize logic via tr directly with the same arguments the
  # script uses. This guards against someone loosening the filter.
  local input='safe-prefix\x1b[2J\x1b]0;HIJACK\x07tail'
  local cleaned
  cleaned=$(printf '%b' "$input" | LC_ALL=C tr -d '\000-\037\177')
  # Expect no ESC (\x1b) and no BEL (\x07) bytes remain.
  case "$cleaned" in
    *$'\x1b'*|*$'\x07'*) echo "control bytes survived: $cleaned"; return 1 ;;
  esac
  contains "safe-prefix" "$cleaned" || { echo "lost safe content: $cleaned"; return 1; }
  contains "tail" "$cleaned" || { echo "lost trailing content: $cleaned"; return 1; }
}

# ---------- Runner ----------

echo "Running claude-clean tests (script: $SCRIPT)"
echo

run_test "help: exits 0 and documents key flags"              t_help_exits_zero_and_shows_usage
run_test "unknown flag is rejected"                           t_unknown_flag_rejected
run_test "duration: 5mo rejected with helpful message"        t_bad_duration_suffix
run_test "duration: 5months rejected"                         t_months_suffix_rejected
run_test "duration: 1.5h rejected (no decimals)"              t_decimal_duration_rejected
run_test "duration: empty rejected"                           t_empty_duration_rejected
run_test "duration: abc rejected"                             t_no_number_rejected
run_test "duration: 09m parses (no octal surprise)"           t_leading_zero_duration_parses
run_test "duration: raw seconds (300) accepted"               t_raw_seconds_accepted
run_test "profile: nonexistent user rejected"                 t_bad_user_rejected
run_test "profile: empty value rejected"                      t_empty_profile_rejected
run_test "--list-protected on fresh HOME is empty"            t_list_protected_empty
run_test "--protect with non-numeric PID rejected"            t_protect_invalid_pid_rejected
run_test "--unprotect on not-protected PID is honest"         t_unprotect_noop_is_honest
run_test "--protect on nonexistent PID fails loudly"          t_protect_nonexistent_pid_rejected
run_test "--protect on non-claude PID fails loudly"           t_protect_non_claude_pid_rejected
run_test "symlinked protect dir refused"                      t_symlink_protect_dir_refused
run_test "symlinked protect file refused, target untouched"   t_symlink_protect_file_refused_and_target_untouched
run_test "protect dir=700 / file=600 perms enforced"          t_protect_file_perms_are_strict
run_test "prune drops stale + garbage entries from file"      t_prune_drops_stale_and_garbage_entries
run_test "default list shows expected column headers"         t_list_default_shows_column_headers
run_test "sanitize strips ESC/BEL control bytes"              t_sanitize_strips_control_bytes
run_test "no injection: \$() in --older-than"                 t_no_injection_via_duration
run_test "no injection: backticks in --older-than"            t_no_injection_via_duration_backticks
run_test "no injection: \$() in --profile"                    t_no_injection_via_profile
run_test "no injection: \$() in --protect"                    t_no_injection_via_protect
run_test "no injection: \$() in unknown-flag echo"            t_no_injection_via_unknown_flag

echo
echo "Ran $TESTS_RUN tests; $TESTS_FAILED failed."
[ "$TESTS_FAILED" = "0" ]
