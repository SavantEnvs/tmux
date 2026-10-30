#!/usr/bin/env bash
#
# mayhem/test.sh — RUN tmux's own regress/*.sh behavioral scripts against the normal-flags tmux that
# mayhem/build.sh built (mayhem/build-tests/tmux). Each script drives a real tmux server and asserts exact output.
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

TESTS="cmd-parse-assignment cmd-parse-condition cmd-parse-unicode-escape command-alias command-order
conf-syntax environ format-fuzzy format-list-default format-list-empty format-strings format-variables
json layout-custom layout-nesting-limit options-array options-scope options-values show-options-output
session-ops window-ops pane-ops targets targets-current targets-panes if-shell-error if-shell-nested
input-sgr input-unicode input-cursor input-edit input-modes utf8-test codepoint-widths combine-test
cursor-test1 cursor-test2 cursor-test3 cursor-test4 style-trim buffers list-keys-sort-name
new-session-command new-window-command check-names session-group-name window-index-limit
renumber-window-limit"

TEST_TMUX="$SRC/mayhem/build-tests/tmux"
[ -x "$TEST_TMUX" ] || { echo "missing $TEST_TMUX — mayhem/build.sh should have built it" >&2; emit_ctrf tmux-regress 0 1 0; exit 1; }
export TEST_TMUX
LOGS="$(mktemp -d)"
cd "$SRC/regress"

passed=0; failed=0
for t in $TESTS; do
  # the scripts expect a scrubbed environment (as in regress/Makefile); keep LD_PRELOAD for the sabotage check
  if timeout 120 env -i LC_CTYPE=C.UTF-8 SHELL=/bin/sh TEST_TMUX="$TEST_TMUX" ${LD_PRELOAD:+LD_PRELOAD="$LD_PRELOAD"} \
       sh -x "$t.sh" >"$LOGS/$t.log" 2>&1; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1)); echo "FAIL $t" >&2; tail -n 5 "$LOGS/$t.log" >&2
  fi
done
rm -rf "$LOGS"
emit_ctrf tmux-regress "$passed" "$failed" 0
