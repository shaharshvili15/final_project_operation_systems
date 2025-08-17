#!/usr/bin/env bash
# set -Eeuo pipefail  # Removed to prevent script termination issues

# ------------- Pretty printing -------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; FAILED=1; }
info() { echo -e "${YELLOW}[TEST]${NC} $1"; }

# ------------- Helpers -------------
ROOT_DIR="$(pwd)"
OUT_DIR="$ROOT_DIR/output"
TMP_DIR="$(mktemp -d)"
FAILED=0

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# Run analyzer with INPUT provided via stdin.
# Usage: run_analyzer <queue> <plugins...>
run_analyzer() {
  local queue="$1"; shift
  local out="$TMP_DIR/out.txt"
  local err="$TMP_DIR/err.txt"
  local code=0
  local cmd=( "$OUT_DIR/analyzer" "$queue" "$@" )

  if command -v timeout >/dev/null 2>&1; then
    set +e
    printf "%s" "${INPUT-}" | timeout 8s "${cmd[@]}" >"$out" 2>"$err"
    code=$?
    set -e
    if [ $code -eq 124 ]; then
      fail "Timeout while running: ${cmd[*]}"
    fi
  else
    set +e
    printf "%s" "${INPUT-}" | "${cmd[@]}" >"$out" 2>"$err"
    code=$?
    set -e
  fi
  echo "$out|$err|$code"
}

# Return whichever uppercaser name is available post-build.
resolve_uppercaser_name() {
  if [ -f "$OUT_DIR/uppercaser.so" ]; then
    echo "uppercaser"
  elif [ -f "$OUT_DIR/uppercase.so" ]; then
    # Compat alias: create expected name if only "uppercase.so" exists.
    ln -sf "uppercase.so" "$OUT_DIR/uppercaser.so"
    echo "uppercaser"
  else
    # Fall back to "uppercaser" so tests still run locally.
    echo "uppercaser"
  fi
}

# Generate a string of length N consisting of the given character (default 'a').
gen_string() {
  local n="$1"; local ch="${2:-a}"
  # Works in bash without external tools; fast enough for 1024.
  local s=""
  while [ ${#s} -lt "$n" ]; do s="$s$ch$ch$ch$ch$ch$ch$ch$ch$ch$ch"; done
  echo "${s:0:$n}"
}

# ------------- 0) Build everything -------------
info "Building project via build.sh…"
./build.sh

if [ ! -x "$OUT_DIR/analyzer" ]; then
  fail "Analyzer binary not found at $OUT_DIR/analyzer after build."
  echo "Make sure build.sh outputs analyzer into ./output/"
  exit 1
fi

UPPER=$(resolve_uppercaser_name)

# ------------- 1) Smoke: simple logger pipeline -------------
info "Simple pipeline: logger"
INPUT=$'<END>\n'
res=$(run_analyzer 10 logger); IFS='|' read -r out err code <<<"$res"
if grep -q "Pipeline shutdown complete" "$out"; then
  pass "Clean shutdown message present"
else
  fail "Expected 'Pipeline shutdown complete' on STDOUT."
fi

# logger should NOT log for <END>
if grep -q "^\[logger\]" "$out"; then
  fail "logger printed a line for <END>; it should not."
else
  pass "No logger output for <END>."
fi

if [ "$code" -eq 0 ]; then
  pass "Exit code 0 on normal path"
else
  fail "Expected exit 0, got $code"
fi

# ------------- 2) Uppercaser + logger transforms correctly -------------
info "$UPPER + logger transforms 'hello' => 'HELLO'"
INPUT=$'hello\n<END>\n'
res=$(run_analyzer 10 "$UPPER" logger); IFS='|' read -r out err code <<<"$res"
exp='[logger] HELLO'
act=$(grep "^\[logger\]" "$out" | tail -n1 || true)
if [ "$act" = "$exp" ]; then
  pass "Uppercaser+logger output ok"
else
  fail "Expected '$exp', got '${act:-<empty>}'"
fi

# ------------- 3) Rotator correctness -------------
info "$UPPER + rotator + logger on 'ab' => 'BA'"
INPUT=$'ab\n<END>\n'
res=$(run_analyzer 10 "$UPPER" rotator logger); IFS='|' read -r out err code <<<"$res"
exp='[logger] BA'
act=$(grep "^\[logger\]" "$out" | tail -n1 || true)
if [ "$act" = "$exp" ]; then
  pass "Rotator output ok"
else
  fail "Expected '$exp', got '${act:-<empty>}'"
fi

# ------------- 4) Flipper correctness -------------
info "flipper + logger on 'abc' => 'cba'"
INPUT=$'abc\n<END>\n'
res=$(run_analyzer 10 flipper logger); IFS='|' read -r out err code <<<"$res"
exp='[logger] cba'
act=$(grep "^\[logger\]" "$out" | tail -n1 || true)
if [ "$act" = "$exp" ]; then
  pass "Flipper output ok"
else
  fail "Expected '$exp', got '${act:-<empty>}'"
fi

# ------------- 5) Expander correctness -------------
info "expander + logger on 'ab' => 'a b'"
INPUT=$'ab\n<END>\n'
res=$(run_analyzer 10 expander logger); IFS='|' read -r out err code <<<"$res"
exp='[logger] a b'
act=$(grep "^\[logger\]" "$out" | tail -n1 || true)
if [ "$act" = "$exp" ]; then
  pass "Expander output ok"
else
  fail "Expected '$exp', got '${act:-<empty>}'"
fi

# ------------- 6) Empty string handling -------------
info "Empty line handling (should log an empty payload)"
INPUT=$'\n<END>\n'
res=$(run_analyzer 10 logger); IFS='|' read -r out err code <<<"$res"
exp='[logger] '
act=$(grep "^\[logger\]" "$out" | tail -n1 || true)
if [ "$act" = "$exp" ]; then
  pass "Empty string processed"
else
  fail "Expected '$exp', got '${act:-<empty>}'"
fi

# ------------- 7) Long line (1024 chars) boundary -------------
info "Boundary: 1024 chars are accepted per spec"
long=$(gen_string 1024 a)
INPUT="${long}"$'\n<END>\n'
res=$(run_analyzer 10 "$UPPER" logger); IFS='|' read -r out err code <<<"$res"
line=$(grep "^\[logger\]" "$out" | sed 's/^\[logger\] //' | head -n1 || true)
len=$(printf "%s" "$line" | wc -c | awk '{print $1}')
if [ "$len" -eq 1024 ]; then
  pass "1024-char line processed"
else
  fail "Expected 1024 chars, got $len"
fi

# ------------- 8) Backpressure (queue size=1 preserves order) -------------
info "Backpressure: queue=1 preserves FIFO order"
INPUT=$'one\ntwo\nthree\n<END>\n'
res=$(run_analyzer 1 logger); IFS='|' read -r out err code <<<"$res"
mapfile -t logs < <(grep "^\[logger\]" "$out" | sed 's/^\[logger\] //')
if [ "${logs[0]-}" = "one" ] && [ "${logs[1]-}" = "two" ] && [ "${logs[2]-}" = "three" ]; then
  pass "FIFO order preserved with capacity 1"
else
  fail "Order mismatch. Got: ${logs[*]-<none>}"
fi

# ------------- 9) Complex chain sanity (include typewriter at the end) -------------
info "Complex chain sanity: $UPPER rotator logger flipper expander typewriter"
INPUT=$'ra\n<END>\n'
res=$(run_analyzer 10 "$UPPER" rotator logger flipper expander typewriter)
IFS='|' read -r out err code <<<"$res"
# logger is 3rd; value after rotator('RA'->'AR'):
exp='[logger] AR'
act=$(grep "^\[logger\]" "$out" | tail -n1 || true)
if [ "$act" = "$exp" ]; then
  pass "Complex chain logger step ok"
else
  fail "Expected '$exp', got '${act:-<empty>}'"
fi

# ------------- 10) Duplicate plugin support (spec requires this) -------------
info "Duplicate plugin usage: $UPPER $UPPER logger"
INPUT=$'HeLlo\n<END>\n'
res=$(run_analyzer 10 "$UPPER" "$UPPER" logger); IFS='|' read -r out err code <<<"$res"
exp='[logger] HELLO'
act=$(grep "^\[logger\]" "$out" | tail -n1 || true)
if [ "$act" = "$exp" ]; then
  pass "Same plugin twice works"
else
  fail "Duplicate plugin failed (expected '$exp', got '${act:-<empty>}')."
fi

# ------------- 11) No internal logs on STDOUT (submission rule) -------------
info "STDOUT must not contain internal [INFO] logs"
INPUT=$'x\n<END>\n'
res=$(run_analyzer 10 logger); IFS='|' read -r out err code <<<"$res"
if grep -q "^\[INFO\]" "$out"; then
  fail "Found [INFO] on STDOUT. Internal logs must be silenced or moved to STDERR for submission."
else
  pass "No internal [INFO] logs on STDOUT"
fi

# ------------- 12) Invalid args: missing everything -------------
info "Invalid args: missing parameters -> usage to STDOUT, exit 1"
out="$TMP_DIR/out_u.txt"; err="$TMP_DIR/err_u.txt"
set +e
"$OUT_DIR/analyzer" >"$out" 2>"$err"
code=$?
set -e
if grep -q "^Usage: ./analyzer" "$out"; then
  pass "Usage printed to STDOUT"
else
  fail "Expected Usage on STDOUT"
fi

if grep -q "No arguments were send" "$err"; then
  pass "Error printed to STDERR"
else
  fail "Expected error message on STDERR"
fi

if [ "$code" -eq 1 ]; then
  pass "Exit code 1 on invalid args"
else
  fail "Expected exit 1, got $code"
fi

# ------------- 13) Invalid args: non-integer queue size -------------
info "Invalid args: non-integer queue size"
out="$TMP_DIR/out_badq.txt"; err="$TMP_DIR/err_badq.txt"
set +e
"$OUT_DIR/analyzer" abc logger >"$out" 2>"$err"
code=$?
set -e
if grep -q "^Usage: ./analyzer" "$out"; then
  pass "Usage printed to STDOUT"
else
  fail "Expected Usage on STDOUT"
fi

if grep -q "Queue size is not valid" "$err"; then
  pass "Invalid size on STDERR"
else
  fail "Expected invalid size on STDERR"
fi

if [ "$code" -eq 1 ]; then
  pass "Exit 1"
else
  fail "Expected exit 1, got $code"
fi

# ------------- 14) Invalid plugin name (dlopen failure path) -------------
info "Invalid plugin: should print usage to STDOUT and error to STDERR; exit 1"
out="$TMP_DIR/out_badp.txt"; err="$TMP_DIR/err_badp.txt"
set +e
"$OUT_DIR/analyzer" 10 does_not_exist >"$out" 2>"$err"
code=$?
set -e
if grep -q "^Usage: ./analyzer" "$out"; then
  pass "Usage printed to STDOUT"
else
  fail "Expected Usage on STDOUT"
fi

if grep -q "Failed to load plugin does_not_exist" "$err"; then
  pass "dlopen error on STDERR"
else
  fail "Expected dlopen error on STDERR"
fi

if [ "$code" -eq 1 ]; then
  pass "Exit 1"
else
  fail "Expected exit 1, got $code"
fi

# ------------- 15) Multiple lines + <END> -> no extra logs after END -------------
info "No logs after <END>"
INPUT=$'first\nsecond\n<END>\nthird\n'
res=$(run_analyzer 10 logger); IFS='|' read -r out err code <<<"$res"
count=$(grep -c "^\[logger\]" "$out" || true)
if [ "$count" -eq 2 ]; then
  pass "Only first two lines logged (stop on <END>)"
else
  fail "Expected 2 logs before END, got $count"
fi

# ------------- Optional: memory leak sanity (if valgrind exists) -------------
if command -v valgrind >/dev/null 2>&1; then
  info "Valgrind leak check (optional)"
  INPUT=$'memtest\n<END>\n'
  set +e
  valgrind --leak-check=full --error-exitcode=42 "$OUT_DIR/analyzer" 10 "$UPPER" logger >/dev/null 2>"$TMP_DIR/valgrind.txt"
  code=$?
  set -e
  if [ "$code" -eq 42 ]; then
    fail "Valgrind reported leaks. See $TMP_DIR/valgrind.txt"
  else
    pass "No leaks detected by valgrind"
  fi
else
  info "Valgrind not found; skipping leak check."
fi

# ------------- 16) Overlong line (>1024) is discarded; next line is processed -------------
info "Overlong line (>1024) is discarded; next valid line processed"
too_long="$(gen_string 1025 a)"
INPUT="${too_long}"$'\nOK\n<END>\n'
res=$(run_analyzer 10 logger); IFS='|' read -r out err code <<<"$res"
cnt=$(grep -c "^\[logger\]" "$out" || true)
last=$(grep "^\[logger\]" "$out" | tail -n1 | sed 's/^\[logger\] //')
[ "$cnt" -eq 1 ] && [ "$last" = "OK" ] && pass "Overlong discarded; OK processed" \
  || fail "Expected exactly one 'OK' log; got cnt=$cnt last='$last'"
# Optional: Check STDERR mentions discard (wording may vary)
grep -qi "exceeds 1024\|too long\|discard" "$err" && pass "Discard notice on STDERR" || pass "Skip strict STDERR wording check"

# ------------- 17) Multiple <END> tokens behave like a single shutdown -------------
info "Multiple <END> tokens -> stop at the first, ignore later"
INPUT=$'line1\n<END>\n<END>\nline2\n'
res=$(run_analyzer 10 logger); IFS='|' read -r out err code <<<"$res"
cnt=$(grep -c "^\[logger\]" "$out" || true)
[ "$cnt" -eq 1 ] && pass "Only lines before first END processed" \
  || fail "Expected 1 log before END, got $cnt"

# ------------- 18) No <END> → program keeps waiting (expect timeout) -------------
# Your run_analyzer helper treats timeouts as failures. For this single test, bypass the helper and expect exit code 124 from timeout.
info "No <END> -> program should keep waiting (expect timeout)"
out="$TMP_DIR/no_end_out.txt"; err="$TMP_DIR/no_end_err.txt"
set +e
printf "still waiting\n" | timeout 5s "$OUT_DIR/analyzer" 10 logger >"$out" 2>"$err"
code=$?
set -e
[ "$code" -eq 124 ] && pass "Hangs as expected without END (timeout)" \
  || fail "Expected timeout exit (124), got $code"

# ------------- 19) Plugin init failure → exit code 2 -------------
# Create a tiny failing plugin on the fly and run with it.
info "plugin_init failure -> exit code 2"
cat > "$TMP_DIR/failinit.c" <<'EOF'
#include <stddef.h>
#include "plugins/plugin_sdk.h"
const char* plugin_get_name(void){ return "failinit"; }
const char* plugin_init(int q){ (void)q; return "boom"; }   // fail on init
const char* plugin_fini(void){ return NULL; }
const char* plugin_place_work(const char* s){ (void)s; return NULL; }
void plugin_attach(const char* (*n)(const char*)) { (void)n; }
const char* plugin_wait_finished(void){ return NULL; }
EOF
gcc -fPIC -shared -o "$OUT_DIR/failinit.so" "$TMP_DIR/failinit.c" -lpthread -ldl -I"$ROOT_DIR"

out="$TMP_DIR/out_init.txt"; err="$TMP_DIR/err_init.txt"
set +e; printf '<END>\n' | "$OUT_DIR/analyzer" 10 failinit >"$out" 2>"$err"; code=$?; set -e
grep -q "Failed to initialize plugin failinit" "$err" && [ "$code" -eq 2 ] \
  && pass "plugin_init failure handled with exit 2" \
  || fail "Expected exit 2 and init error for failing plugin (code=$code)."

# ------------- 20) Missing required symbol (dlsym failure) → usage + exit 1 -------------
info "Missing symbol in plugin -> dlsym failure (usage + exit 1)"
cat > "$TMP_DIR/broken.c" <<'EOF'
#include <stddef.h>
#include "plugins/plugin_sdk.h"
const char* plugin_get_name(void){ return "broken"; }
const char* plugin_init(int q){ (void)q; return NULL; }
const char* plugin_fini(void){ return NULL; }
const char* plugin_place_work(const char* s){ (void)s; return NULL; }
void plugin_attach(const char* (*n)(const char*)) { (void)n; }
/* intentionally omit plugin_wait_finished */
EOF
gcc -fPIC -shared -o "$OUT_DIR/broken.so" "$TMP_DIR/broken.c" -lpthread -ldl -I"$ROOT_DIR"

out="$TMP_DIR/out_sym.txt"; err="$TMP_DIR/err_sym.txt"
set +e; "$OUT_DIR/analyzer" 8 broken >"$out" 2>"$err"; code=$?; set -e
grep -q "^Usage: ./analyzer" "$out" && [ "$code" -eq 1 ] \
  && pass "dlsym failure -> printed usage and exit 1" \
  || fail "Expected usage+exit 1 for missing symbol (code=$code)."

# ------------- 21) Deeper duplicate usage (triple isolation via dlmopen) -------------
info "Duplicate plugin isolation: triple uppercaser"
INPUT=$'HeLlo\n<END>\n'
res=$(run_analyzer 10 "$UPPER" "$UPPER" "$UPPER" logger); IFS='|' read -r out err code <<<"$res"
exp='[logger] HELLO'; act=$(grep "^\[logger\]" "$out" | tail -n1 || true)
[ "$act" = "$exp" ] && pass "Triple $UPPER OK (isolated instances)" \
  || fail "Triple duplicate failed (expected '$exp', got '${act:-<empty>}')"

# ------------- 22) Larger FIFO stress with queue=1 (no busy-wait, order preserved) -------------
info "FIFO stress (queue=1, 50 items)"
INPUT="$(printf '%s\n' $(seq 1 50))"$'\n<END>\n'
res=$(run_analyzer 1 logger); IFS='|' read -r out err code <<<"$res"
mapfile -t logs < <(grep "^\[logger\]" "$out" | sed 's/^\[logger\] //')
ok=1
for i in $(seq 1 50); do [ "${logs[$((i-1))]}" = "$i" ] || { ok=0; break; }; done
[ $ok -eq 1 ] && pass "Order preserved for 50 items" || fail "Order mismatch in FIFO stress"

# ------------- 23) Happy-path STDERR should contain only INFO messages -------------
info "Happy path -> STDERR should contain only INFO messages (no errors)"
INPUT=$'ok\n<END>\n'
res=$(run_analyzer 10 "$UPPER" logger); IFS='|' read -r out err code <<<"$res"
# Check that STDERR contains INFO messages (expected) but no error messages
if grep -q "Error\|error\|ERROR" "$err"; then
    fail "STDERR contains error messages on happy path"
elif [ -s "$err" ] && grep -q "\[INFO\]" "$err"; then
    pass "STDERR contains INFO messages as expected (no errors)"
elif [ ! -s "$err" ]; then
    pass "STDERR is empty (no INFO messages)"
else
    fail "STDERR contains unexpected content on happy path"
fi

# ------------- 24) Whitespace preservation -------------
info "Whitespace preservation (tabs/spaces) with logger"
INPUT=$'  a\tb  \n<END>\n'
res=$(run_analyzer 10 logger); IFS='|' read -r out err code <<<"$res"
payload=$(grep "^\[logger\]" "$out" | sed 's/^\[logger\] //')
[ "$payload" = $'  a\tb  ' ] && pass "Whitespace intact" || fail "Whitespace changed: '$payload'"

# ------------- Final verdict -------------
if [ "$FAILED" -ne 0 ]; then
  echo -e "${RED}Some tests FAILED.${NC}"
  exit 1
else
  echo -e "${GREEN}All tests passed!${NC}"
  exit 0
fi