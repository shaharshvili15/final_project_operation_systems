#!/usr/bin/env bash
set -euo pipefail

# Pretty prints
print_status() { echo -e "\033[32m[PASS]\033[0m $1"; }
print_error()  { echo -e "\033[31m[FAIL]\033[0m $1"; }

# Always build first
./build.sh >/dev/null

########################################
# Tests
########################################

# 1A) Basic pipeline: uppercaser -> logger
EXPECTED="[logger] HELLO"
ACTUAL=$(echo -e "hello\n<END>" | ./output/analyzer 10 uppercaser logger | grep "^\[logger\]" | tail -n1)
if [ "$ACTUAL" == "$EXPECTED" ]; then
  print_status "uppercaser + logger transforms 'hello' -> 'HELLO'"
else
  print_error "uppercaser + logger (Expected '$EXPECTED', got '$ACTUAL')"
  exit 1
fi

# 1B) expander -> logger
EXPECTED="[logger] h e l l o"
ACTUAL=$(echo -e "hello\n<END>" | ./output/analyzer 10 expander logger | grep "^\[logger\]" | tail -n1)
if [ "$ACTUAL" == "$EXPECTED" ]; then
  print_status "expander + logger transforms 'hello' -> 'h e l l o'"
else
  print_error "expander + logger (Expected '$EXPECTED', got '$ACTUAL')"
  exit 1
fi

# 1C) flipper -> logger
EXPECTED="[logger] olleh"
ACTUAL=$(echo -e "hello\n<END>" | ./output/analyzer 10 flipper logger | grep "^\[logger\]" | tail -n1)
if [ "$ACTUAL" == "$EXPECTED" ]; then
  print_status "flipper + logger transforms 'hello' -> 'olleh'"
else
  print_error "flipper + logger (Expected '$EXPECTED', got '$ACTUAL')"
  exit 1
fi

# 1D) rotator -> logger
EXPECTED="[logger] ohell"
ACTUAL=$(echo -e "hello\n<END>" | ./output/analyzer 10 rotator logger | grep "^\[logger\]" | tail -n1)
if [ "$ACTUAL" == "$EXPECTED" ]; then
  print_status "rotator + logger transforms 'hello' -> 'ohell'"
else
  print_error "rotator + logger (Expected '$EXPECTED', got '$ACTUAL')"
  exit 1
fi

# 1E) uppercaser -> typewriter
EXPECTED="[typewriter] HELLO"
ACTUAL=$(echo -e "hello\n<END>" | ./output/analyzer 10 uppercaser typewriter | grep "^\[typewriter\]" | tail -n1)
if [ "$ACTUAL" == "$EXPECTED" ]; then
  print_status "uppercaser + typewriter transforms 'hello' -> 'HELLO'"
else
  print_error "uppercaser + typewriter (Expected '$EXPECTED', got '$ACTUAL')"
  exit 1
fi

# 1F) expander -> typewriter
EXPECTED="[typewriter] h e l l o"
ACTUAL=$(echo -e "hello\n<END>" | ./output/analyzer 10 expander typewriter | grep "^\[typewriter\]" | tail -n1)
if [ "$ACTUAL" == "$EXPECTED" ]; then
  print_status "expander + typewriter transforms 'hello' -> 'h e l l o'"
else
  print_error "expander + typewriter (Expected '$EXPECTED', got '$ACTUAL')"
  exit 1
fi

# 1G) flipper -> typewriter
EXPECTED="[typewriter] olleh"
ACTUAL=$(echo -e "hello\n<END>" | ./output/analyzer 10 flipper typewriter | grep "^\[typewriter\]" | tail -n1)
if [ "$ACTUAL" == "$EXPECTED" ]; then
  print_status "flipper + typewriter transforms 'hello' -> 'olleh'"
else
  print_error "flipper + typewriter (Expected '$EXPECTED', got '$ACTUAL')"
  exit 1
fi

# 1H) rotator -> typewriter
EXPECTED="[typewriter] ohell"
ACTUAL=$(echo -e "hello\n<END>" | ./output/analyzer 10 rotator typewriter | grep "^\[typewriter\]" | tail -n1)
if [ "$ACTUAL" == "$EXPECTED" ]; then
  print_status "rotator + typewriter transforms 'hello' -> 'ohell'"
else
  print_error "rotator + typewriter (Expected '$EXPECTED', got '$ACTUAL')"
  exit 1
fi

# 2) Multiple lines
EXPECTED="[logger] THERE"
ACTUAL=$(echo -e "hello\nthere\n<END>" | ./output/analyzer 10 uppercaser logger | grep "^\[logger\]" | tail -n1)
if [ "$ACTUAL" == "$EXPECTED" ]; then
  print_status "multiple lines; last is 'THERE'"
else
  print_error "multiple lines (Expected '$EXPECTED', got '$ACTUAL')"
  exit 1
fi

# 3) Invalid plugin
set +e
echo -e "hello\n<END>" | ./output/analyzer 10 does_not_exist logger >/dev/null 2>&1
RC=$?
set -e
if [[ $RC -ne 0 ]]; then
  print_status "invalid plugin name returns non-zero exit code"
else
  print_error "invalid plugin name should fail but returned 0"
  exit 1
fi

# 4) Empty string
EXPECTED="[logger] "
ACTUAL=$(echo -e "\n<END>" | ./output/analyzer 10 uppercaser logger | grep "^\[logger\]" | tail -n1)
if [ "$ACTUAL" == "$EXPECTED" ]; then
  print_status "empty line passes through"
else
  print_error "empty line (Expected '$EXPECTED', got '$ACTUAL')"
  exit 1
fi

# 5) uppercaser -> rotator -> logger
EXPECTED="[logger] OHELL"
ACTUAL=$(echo -e "hello\n<END>" | ./output/analyzer 10 uppercaser rotator logger | grep "^\[logger\]" | tail -n1)
if [ "$ACTUAL" == "$EXPECTED" ]; then
  print_status "uppercaser -> rotator -> logger works"
else
  print_error "uppercaser -> rotator -> logger (Expected '$EXPECTED', got '$ACTUAL')"
  exit 1
fi

# 6) flipper -> expander -> logger
EXPECTED="[logger] o l l e h"
ACTUAL=$(echo -e "hello\n<END>" | ./output/analyzer 10 flipper expander logger | grep "^\[logger\]" | tail -n1)
if [ "$ACTUAL" == "$EXPECTED" ]; then
  print_status "flipper -> expander -> logger works"
else
  print_error "flipper -> expander -> logger (Expected '$EXPECTED', got '$ACTUAL')"
  exit 1
fi

# 7) more than one END
EXPECTED="[logger] o l l e h"
ACTUAL=$(echo -e "hello\n<END>\nthere\n<END>" | ./output/analyzer 10 flipper expander logger | grep "^\[logger\]" | head -n1)
if [ "$ACTUAL" == "$EXPECTED" ]; then
  print_status "multiple <END>; only first chunk processed"
else
  print_error "multiple <END> (Expected '$EXPECTED', got '$ACTUAL')"
  exit 1
fi

# 8) 1..100 in order
EXPECTED=$(for i in $(seq 1 100); do echo "[logger] $i"; done)
ACTUAL=$( { seq 1 100; echo "<END>"; } | ./output/analyzer 10 logger | grep "^\[logger\]")
if [ "$ACTUAL" == "$EXPECTED" ]; then
  print_status "1..100 lines in order"
else
  print_error "1..100 lines order mismatch"
  exit 1
fi

# 9) expander one space
EXPECTED="[logger]  "
ACTUAL=$(echo -e " \n<END>" | ./output/analyzer 10 expander logger | grep "^\[logger\]" | tail -n1)
if [ "$ACTUAL" == "$EXPECTED" ]; then
  print_status "expander handles single space"
else
  print_error "expander single space (Expected '$EXPECTED', got '$ACTUAL')"
  exit 1
fi

# 10) expander two spaces
EXPECTED="[logger]    "
ACTUAL=$(echo -e "  \n<END>" | ./output/analyzer 10 expander logger | grep "^\[logger\]" | tail -n1)
if [ "$ACTUAL" == "$EXPECTED" ]; then
  print_status "expander handles two spaces"
else
  print_error "expander two spaces (Expected '$EXPECTED', got '$ACTUAL')"
  exit 1
fi

# 11) queue size = 1 with multiple plugins
EXPECTED="[logger]  L L E HO"
ACTUAL=$(echo -e "hello\n<END>" | ./output/analyzer 1 uppercaser expander rotator flipper logger | grep "^\[logger\]" | tail -n1)
if [ "$ACTUAL" == "$EXPECTED" ]; then
  print_status "queue size = 1 with multiple plugins"
else
  print_error "queue size=1 (Expected '$EXPECTED', got '$ACTUAL')"
  exit 1
fi

# 12) plugin appears twice
EXPECTED=$'[logger] HELLO\n[logger] OHELL'
ACTUAL=$(echo -e "hello\n<END>" | ./output/analyzer 10 uppercaser logger rotator logger | grep "^\[logger\]")
if [ "$ACTUAL" == "$EXPECTED" ]; then
  print_status "plugin used twice works"
else
  print_error "plugin twice (Expected '$EXPECTED', got '$ACTUAL')"
  exit 1
fi

# 13) no <END>
set +e
timeout 2s bash -c 'echo "hello" | ./output/analyzer 10 uppercaser logger >/dev/null 2>&1'
RC=$?
set -e
if [ $RC -eq 124 ]; then
  print_status "no <END> token → blocks until timeout"
else
  print_error "no <END> token (expected timeout rc=124, got $RC)"
fi

# 14) invalid args (no args) → usage printed, exit 1
set +e
OUTPUT=$(./output/analyzer 2>&1)
RC=$?
set -e

if [ $RC -ne 0 ] && echo "$OUTPUT" | grep -q "Usage"; then
  print_status "no args → usage printed, exit non-zero"
else
  print_error "no args should fail but returned $RC with output: $OUTPUT"
fi


# 15) check <end> and not <END> 
EXPECTED="[logger] < e n d >"
ACTUAL=$(echo -e "<end>\n<END>" | ./output/analyzer 1 expander logger | grep "^\[logger\]" | tail -n1)
if [ "$ACTUAL" == "$EXPECTED" ]; then
  print_status "entering <end> and not <END> works as expected"
else
  print_error "entering <end> and not <END> (Expected '$EXPECTED', got '$ACTUAL')"
fi

# 16) check <END> as a substring 
EXPECTED="[logger] HELLO<END>THERE"
ACTUAL=$(echo -e "hello<END>there\n<END>" | ./output/analyzer 1 uppercaser logger | grep "^\[logger\]" | tail -n1)
if [ "$ACTUAL" == "$EXPECTED" ]; then
  print_status "<END> as a substring did not end the running"
else
  print_error "<END> as a substring did not work as expected (Expected '$EXPECTED', got '$ACTUAL')"
fi

# 17) invalid queue size (not_a_number)
set +e
./output/analyzer not_a_number logger >/dev/null 2>&1
RC=$?
set -e
if [ $RC -ne 0 ] && echo "$OUTPUT" | grep -q "Usage"; then
  print_status "non-integer queue size → usage printed, exit non-zero"
else
  print_error "non-integer queue size should fail but returned 0"
fi

# 18) invalid queue size (negative)
set +e
./output/analyzer -1 logger >/dev/null 2>&1
RC=$?
set -e
if [ $RC -ne 0 ] && echo "$OUTPUT" | grep -q "Usage"; then
  print_status "negative queue size → usage printed, exit non-zero"
else
  print_error "negative queue size should fail but returned 0"
fi

# 19) invalid queue size (zero)
set +e
./output/analyzer 0 logger >/dev/null 2>&1
RC=$?
set -e
if [ $RC -ne 0 ] && echo "$OUTPUT" | grep -q "Usage"; then
  print_status "zero queue size → usage printed, exit non-zero"
else
  print_error "zero queue size should fail but returned 0"
fi

# 20) Same plugin used 3 times (ordering)
EXPECTED=$'[logger] hello\n[logger] hello\n[logger] hello'
ACTUAL=$(printf "hello\n<END>\n" | ./output/analyzer 10 logger logger logger | grep "^\[logger\]")
if [ "$ACTUAL" == "$EXPECTED" ]; then
  print_status "same plugin used thrice maintains order"
else
  print_error "triple plugin order (Expected 3 identical logger lines, got: '$ACTUAL')"
  exit 1
fi

# 21) Huge queue size accepted (within reasonable limits)
printf "<END>\n" | ./output/analyzer 10000 logger >/dev/null 2>&1
RC=$?
if [ $RC -eq 0 ]; then
  print_status "large queue size accepted"
else
  print_error "large queue size should be accepted (rc=$RC)"
fi

# 22) case sensitive Uppercaser
set +e
echo -e "ok\n<END>" | ./output/analyzer 10 Uppercaser logger >/dev/null 2>&1
RC=$?
set -e
if [ $RC -ne 0 ]; then
  print_status "plugin name is case-sensitive: 'Uppercaser' fails as expected"
else
  print_error "case-insensitive load detected (or bug): 'Uppercaser' unexpectedly succeeded"
  exit 1
fi


require_valgrind() {
  if ! command -v valgrind >/dev/null 2>&1; then
    echo "⚠ valgrind not found; skipping valgrind tests"
    return 1
  fi
  return 0
}

build_failinit_so() {
  mkdir -p output
  gcc -shared -fPIC -O2 -x c -o output/failinit.so - <<'EOF'
#include <stddef.h>
const char* plugin_init(const char* name, int queue_size) {
    (void)name; (void)queue_size;
    return "failed to initialize plugin: failinit";
}
const char* plugin_name(void) { return "failinit"; }
void plugin_place_work(char* s) { (void)s; }
void plugin_shutdown(void) {}
EOF
}

build_failinit_so
set +e
printf "<END>\n" | ./output/analyzer 10 failinit logger >/dev/null 2>&1
RC=$?
set -e
if [ $RC -ne 0 ]; then
  print_status "plugin init error propagates → non-zero exit"
else
  print_error "plugin with failing init should not run but exited 0"
  exit 1
fi

echo "All tests passed ✔"
