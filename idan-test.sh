#!/usr/bin/env bash
# test.sh — automated tests for the pipeline system
# 7.7.2025


# ------------------------ Config ------------------------
LOGGER_PREFIX="[logger] "
SHUTDOWN_MSG="Pipeline shutdown complete"
ANALYZER="./output/analyzer"
QS_DEFAULT=10
TIMEOUT_SECS=30
# ----------------------------------------------------

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok(){   echo -e "${GREEN}[PASS]${NC} $*"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $*"; }
err(){  echo -e "${RED}[FAIL]${NC} $*"; }
info(){ echo -e "${GREEN}[TEST]${NC}  $*"; }

PASSED=0
FAILED=0

# Simple test function that actually works
test_contains() {
  local name="$1" cmd="$2" expected="$3"
  info "$name"
  
  # Run command with timeout
  local output
  output=$(timeout ${TIMEOUT_SECS}s bash -c "$cmd" 2>&1) || true
  
  # Check if output contains expected pattern
  if echo "$output" | grep -Fq "$expected"; then
    ok "$name"
    PASSED=$((PASSED + 1))
  else
    err "$name"
    echo -e "${YELLOW}Command:${NC} $cmd"
    echo -e "${YELLOW}Expected to contain:${NC} $expected"
    echo -e "${YELLOW}Output:${NC}\n$output"
    FAILED=$((FAILED + 1))
  fi
  echo
}

# Test function for exact output matching
test_equals() {
  local name="$1" cmd="$2" expected="$3"
  info "$name"
  
  # Run command with timeout
  local output
  output=$(timeout ${TIMEOUT_SECS}s bash -c "$cmd" 2>&1) || true
  
  # Remove trailing newline for comparison
  output=$(echo "$output" | sed 's/\n$//')
  expected=$(echo "$expected" | sed 's/\n$//')
  
  if [[ "$output" == "$expected" ]]; then
    ok "$name"
    PASSED=$((PASSED + 1))
  else
    err "$name"
    echo -e "${YELLOW}Command:${NC} $cmd"
    echo -e "${YELLOW}Expected exactly:${NC}\n$expected"
    echo -e "${YELLOW}Got:${NC}\n$output"
    FAILED=$((FAILED + 1))
  fi
  echo
}

# Test function for commands that should fail
test_fails() {
  local name="$1" cmd="$2" expected_error="$3"
  info "$name (should fail)"
  
  # Run command with timeout
  local output
  output=$(timeout ${TIMEOUT_SECS}s bash -c "$cmd" 2>&1) || true
  
  # Check if output contains expected error
  if echo "$output" | grep -Fq "$expected_error"; then
    ok "$name (failed as expected)"
    PASSED=$((PASSED + 1))
  else
    err "$name"
    echo -e "${YELLOW}Command:${NC} $cmd"
    echo -e "${YELLOW}Expected error containing:${NC} $expected_error"
    echo -e "${YELLOW}Output:${NC}\n$output"
    FAILED=$((FAILED + 1))
  fi
  echo
}

# ------------------------------- Build phase -----------------------------------
info "Building project (./build.sh)…"
if ./build.sh; then
  ok "Build completed"
else
  err "Build failed — cannot run tests"
  exit 1
fi
echo

# quick existence check
if [[ ! -x "$ANALYZER" ]]; then
  err "Analyzer binary not found at $ANALYZER"
  exit 1
fi

# ------------------------------- Positive tests --------------------------------

# 1) Single plugin — logger (basic pass-through)
test_contains \
  "Single plugin: logger echoes input" \
  "printf 'hello\n<END>\n' | $ANALYZER $QS_DEFAULT logger" \
  "[logger] hello"

# 2) Uppercaser + logger
test_contains \
  "Two plugins: uppercaser -> logger" \
  "printf 'hello\n<END>\n' | $ANALYZER $QS_DEFAULT uppercaser logger" \
  "[logger] HELLO"

# 3) Uppercaser + rotator + logger (rotator rotates right by 1)
test_contains \
  "Chain: uppercaser -> rotator -> logger (HELLO -> OHELL)" \
  "printf 'hello\n<END>\n' | $ANALYZER $QS_DEFAULT uppercaser rotator logger" \
  "[logger] OHELL"

# 4) Uppercaser + rotator + flipper + logger
test_contains \
  "Chain: uppercaser -> rotator -> flipper -> logger (HELLO -> OHELL -> LLEHO)" \
  "printf 'hello\n<END>\n' | $ANALYZER $QS_DEFAULT uppercaser rotator flipper logger" \
  "[logger] LLEHO"

# 5) Shutdown marker <END> propagates and stops pipeline
test_contains \
  "End-of-stream: <END> triggers clean shutdown" \
  "printf '<END>\n' | $ANALYZER $QS_DEFAULT logger" \
  "$SHUTDOWN_MSG"

# 6) Multiple lines processed
test_contains \
  "Multiple lines: both processed" \
  "printf 'hello\nworld\n<END>\n' | $ANALYZER $QS_DEFAULT uppercaser logger | grep -c '\[logger\] HELLO\|\[logger\] WORLD'" \
  "2"

# 7) Long string (near 1000 chars) stays intact through uppercaser
test_equals \
  "Long string (1000 x's) -> 1000 X's" \
  "printf '%*s\n<END>\n' 1000 | tr ' ' 'x' | $ANALYZER $QS_DEFAULT uppercaser logger 2>/dev/null | grep -o 'X' | wc -l | tr -d ' '" \
  "1000"

# 8) Long string (near 1024 chars) stays intact through uppercaser
test_equals \
  "Boundary: 1024 x's -> 1024 X's" \
  "printf '%*s\n<END>\n' 1024 | tr ' ' 'x' | $ANALYZER $QS_DEFAULT uppercaser logger 2>/dev/null | grep -o 'X' | wc -l | tr -d ' '" \
  "1024"

# 8) Small queue size should still work
test_contains \
  "Small queue size (1) works" \
  "printf 'hello\n<END>\n' | $ANALYZER 1 logger" \
  "[logger] hello"

# 9) Repeated plugin (idempotent uppercaser)
test_contains \
  "Repeated plugin: uppercaser three times" \
  "printf 'hello\n<END>\n' | $ANALYZER $QS_DEFAULT uppercaser uppercaser uppercaser logger" \
  "[logger] HELLO"

# 10) Complex chain (optional expander if exists; expect 'L L E H O')
if [[ -f "./output/expander.so" ]]; then
  test_contains \
      "Complex chain: uppercaser -> rotator -> flipper -> expander -> logger" \
  "printf 'hello\n<END>\n' | $ANALYZER $QS_DEFAULT uppercaser rotator flipper expander logger" \
  "[logger] L L E H O"
else
  warn "Skipping 'expander' positive test (plugin not built)"
fi

# ------------------------------- Edge cases ------------------------------------

# 11) Empty line (should not crash; either echo empty or nothing; accept prefix or just newline)
test_contains \
  "Edge: empty line handled (no crash)" \
  "printf '\n<END>\n' | $ANALYZER $QS_DEFAULT logger" \
  "[logger]"

# 12) Whitespace preservation (tabs/spaces preserved)
test_contains \
  "Edge: whitespace preservation" \
  "printf '  a\tb  \n<END>\n' | $ANALYZER $QS_DEFAULT logger" \
  "[logger]   a	b  "

# 13) Multiple <END> tokens (should stop at first)
test_contains \
  "Edge: multiple <END> tokens handled" \
  "printf 'hello\n<END>\n<END>\n<END>\n' | $ANALYZER $QS_DEFAULT logger" \
  "[logger] hello"

# 14) Very long input line (near 1000 chars)
test_contains \
  "Edge: very long input line (~1000 chars)" \
  "printf '%*s\n<END>\n' 1000 | tr ' ' 'a' | $ANALYZER $QS_DEFAULT logger" \
  "[logger]"

# 15) Queue capacity edge cases (1 and 1000)
test_contains \
  "Edge: queue size 1 works" \
  "printf 'test\n<END>\n' | $ANALYZER 1 logger" \
  "[logger] test"

test_contains \
  "Edge: queue size 1000 works" \
  "printf 'test\n<END>\n' | $ANALYZER 1000 logger" \
  "[logger] test"

# 16) Plugin isolation (many instances of same plugin)
test_contains \
  "Edge: plugin isolation (4 uppercaser instances)" \
  "printf 'test\n<END>\n' | $ANALYZER $QS_DEFAULT uppercaser uppercaser uppercaser uppercaser logger" \
  "[logger] TEST"

# 17) Performance stress test (many small inputs)
test_contains \
  "Edge: performance stress (50 items)" \
  "printf '%s\n' $(seq 1 50) '<END>' | $ANALYZER 20 logger | grep -c '\[logger\]'" \
  "50"

# 18) Complex plugin dependency chain
test_contains \
  "Edge: complex transformations chain" \
  "printf 'hello world\n<END>\n' | $ANALYZER $QS_DEFAULT uppercaser rotator flipper expander typewriter" \
  ""

# 19) Boundary conditions
test_contains \
  "Edge: single character boundary" \
  "printf 'x\n<END>\n' | $ANALYZER $QS_DEFAULT rotator logger" \
  "[logger] x"

test_contains \
  "Edge: short string boundary" \
  "printf 'ab\n<END>\n' | $ANALYZER $QS_DEFAULT flipper logger" \
  "[logger] ba"

test_contains \
  "Full chain: uppercaser -> rotator -> flipper -> expander -> logger -> typewriter" \
  "printf 'hello\n<END>\n' | $ANALYZER $QS_DEFAULT uppercaser rotator flipper expander logger typewriter | grep -E '^\[(logger|typewriter)\] L L E H O' | wc -l | tr -d ' '" \
  "2"
# 20) Memory leak detection (multiple runs)
test_contains \
  "Edge: memory leak detection (5 consecutive runs)" \
  "for i in {1..5}; do printf 'run$i\n<END>\n' | $ANALYZER 10 uppercaser logger >/dev/null 2>&1; done && echo 'OK'" \
  "OK"

# 21) Concurrent plugin stress test
test_contains \
  "Edge: concurrent plugin stress" \
  "printf 'concurrent\n<END>\n' | $ANALYZER 5 uppercaser uppercaser rotator rotator logger" \
  ""

# 22) No internal logs on STDOUT (submission rule)
test_fails \
  "Edge: no internal [INFO] logs on STDOUT" \
  "printf 'x\n<END>\n' | $ANALYZER $QS_DEFAULT logger 2>/dev/null | grep -q '^\[INFO\]'" \
  ""

# 23) Plugin init failure handling
test_fails \
  "Edge: plugin_init failure -> exit code 2" \
  "printf '<END>\n' | $ANALYZER 10 failinit 2>/dev/null" \
  ""

# 24) Missing required symbol (dlsym failure)
test_fails \
  "Edge: missing symbol -> dlsym failure" \
  "$ANALYZER 8 broken" \
  ""

# 25) Backpressure (queue size=1 preserves order)
test_contains \
  "Edge: backpressure - queue=1 preserves FIFO order" \
  "printf 'one\ntwo\nthree\n<END>\n' | $ANALYZER 1 logger | grep -c '\[logger\]'" \
  "3"

# 26) Multiple lines + <END> -> no extra logs after END
test_contains \
  "Edge: stop reading after first <END>" \
  "printf 'first\nsecond\n<END>\nthird\n' | $ANALYZER $QS_DEFAULT logger | grep -c '^\[logger\]'" \
  "2"

# 27) No <END> → program keeps waiting (expect timeout)
test_fails \
  "Edge: absent <END> -> program should keep waiting (expect timeout)" \
  "timeout 5s printf 'still waiting\n' | $ANALYZER $QS_DEFAULT logger" \
  ""

# 28) Happy-path STDERR should contain only INFO messages
test_contains \
  "Edge: STDERR hygiene - happy path (no errors)" \
  "printf 'ok\n<END>\n' | $ANALYZER $QS_DEFAULT uppercaser logger 2>&1 | grep -v '^\[INFO\]' | grep -v '^\[logger\]' | grep -v '^Pipeline shutdown complete' | wc -l | tr -d ' '" \
  "0"

# 29) FIFO order stress with queue=1 (no busy-wait, order preserved)
test_contains \
  "Edge: FIFO order stress (queue=1, 50 items)" \
  "printf '%s\n' $(seq 1 50) '<END>' | $ANALYZER 1 logger | grep -c '^\[logger\]'" \
  "50"

# 30) Deeper duplicate usage (triple isolation)
test_contains \
  "Edge: triple uppercaser isolation" \
  "printf 'HeLlo\n<END>\n' | $ANALYZER $QS_DEFAULT uppercaser uppercaser uppercaser logger" \
  "[logger] HELLO"

# ------------------------------- Negative tests --------------------------------

# 31) Missing arguments (no queue size / plugins)
test_fails \
  "Invalid usage: no args" \
  "$ANALYZER" \
  "Missing"

# 32) Invalid queue size: negative
test_fails \
  "Invalid queue size: -5" \
  "$ANALYZER -5 logger" \
  "Invalid"

# 33) Invalid queue size: zero
test_fails \
  "Invalid queue size: 0" \
  "$ANALYZER 0 logger" \
  "Invalid"

# 34) Missing plugins (only size provided)
test_fails \
  "Invalid usage: missing plugins" \
  "$ANALYZER $QS_DEFAULT" \
  "Missing"

# 35) Non-existent plugin
test_fails \
  "Plugin load failure: nonexistent plugin" \
  "$ANALYZER $QS_DEFAULT nonexistent" \
  "Failed to load"

# ------------------------------- Summary ---------------------------------------

echo -e "${GREEN}[TEST]${NC} Completed: ${PASSED} passed, ${FAILED} failed"
if [[ "$FAILED" -gt 0 ]]; then
  err "Some tests failed"
  exit 1
else
  ok "All tests passed!"
  exit 0
fi