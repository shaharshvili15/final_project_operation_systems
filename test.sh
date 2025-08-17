#!/usr/bin/env bash
set -euo pipefail

# Pretty prints
print_status() { echo -e "\033[32m[PASS]\033[0m $1"; }
print_error()  { echo -e "\033[31m[FAIL]\033[0m $1"; }

# Build first (so tests always run on fresh binaries)
./build.sh >/dev/null

# Helper: run analyzer with given plugins and capture the last [logger] line
#   usage: actual_logger_line "input_lines" plugin1 plugin2 ...
capture_logger_line() {
  local input="$1"; shift
  # Send input, silence plugin init logs on stderr, keep only logger lines on stdout
  printf "%b" "$input" \
    | output/analyzer 10 "$@" 2>/dev/null \
    | grep -E '^\[logger\] ' | tail -n1
}

capture_typewriter_line() {
  local input="$1"; shift
  # Send input, silence plugin init logs on stderr, keep only logger lines on stdout
  printf "%b" "$input" \
    | output/analyzer 10 "$@" 2>/dev/null \
    | grep -E '^\[typewriter\] ' | tail -n1
}

# Helper: assert equality
assert_eq() {
  local expected="$1"; local actual="$2"; local name="$3"
  if [[ "$actual" == "$expected" ]]; then
    print_status "$name"
  else
    print_error "$name (expected: '$expected', got: '$actual')"
    exit 1
  fi
}



#EXPECTED="[logger] HELLO"
#ACTUAL=$(echo "hello
#<END>" | ./output/analyzer 10 uppercaser logger | grep "\[logger\]")
#if [ "$ACTUAL" == "$EXPECTED" ]; then
# print_status "Test uppercaser + logger: PASS"
#else
# print_error "Test uppercaser + logger: FAIL (Expected '$EXPECTED', got
#'$ACTUAL')"
# exit 1
#fi

########################################
# Tests
########################################

# 1A) Basic pipeline: uppercaser -> logger
test_uppercaser_logger_basic() {
  local expected="[logger] HELLO"
  local actual
  actual=$(capture_logger_line "hello\n<END>\n" uppercaser logger)
  assert_eq "$expected" "$actual" "uppercaser + logger transforms 'hello' -> 'HELLO'"
}
# 1B) Basic pipeline: expander -> logger
test_expander_logger_basic() {
  local expected="[logger] h e l l o"
  local actual
  actual=$(capture_logger_line "hello\n<END>\n" expander logger)
  assert_eq "$expected" "$actual" "expander + logger transforms 'hello' -> 'h e l l o'"
}
# 1C) Basic pipeline: flipper -> logger
test_flipper_logger_basic() {
  local expected="[logger] olleh"
  local actual
  actual=$(capture_logger_line "hello\n<END>\n" flipper logger)
  assert_eq "$expected" "$actual" "flipper + logger transforms 'hello' -> 'olleh'"
}
# 1D) Basic pipeline: rotator -> logger
test_rotator_logger_basic() {
  local expected="[logger] ohell"
  local actual
  actual=$(capture_logger_line "hello\n<END>\n" rotator logger)
  assert_eq "$expected" "$actual" "expander + logger transforms 'hello' -> 'ohell'"
}


# 1E) Basic pipeline: uppercaser -> typewriter
test_uppercaser_typewriter_basic() {
  local expected="[typewriter] HELLO"
  local actual
  actual=$(capture_typewriter_line "hello\n<END>\n" uppercaser typewriter)
  assert_eq "$expected" "$actual" "uppercaser + typewriter transforms 'hello' -> 'HELLO'"
}
# 1F) Basic pipeline: expander -> typewriter
test_expander_typewriter_basic() {
  local expected="[typewriter] h e l l o"
  local actual
  actual=$(capture_typewriter_line "hello\n<END>\n" expander typewriter)
  assert_eq "$expected" "$actual" "expander + typewriter transforms 'hello' -> 'h e l l o'"
}
# 1G) Basic pipeline: flipper -> typewriter
test_flipper_typewriter_basic() {
  local expected="[typewriter] olleh"
  local actual
  actual=$(capture_typewriter_line "hello\n<END>\n" flipper typewriter)
  assert_eq "$expected" "$actual" "flipper + typewriter transforms 'hello' -> 'olleh'"
}
# 1H) Basic pipeline: rotator -> typewriter
test_rotator_typewriter_basic() {
  local expected="[typewriter] ohell"
  local actual
  actual=$(capture_typewriter_line "hello\n<END>\n" rotator typewriter)
  assert_eq "$expected" "$actual" "expander + typewriter transforms 'hello' -> 'ohell'"
}

#expander
#flipper
#rotator
#

# 2) Multiple lines: ensure we process all and take the last line
test_multiple_lines() {
  local expected="[logger] THERE"
  local actual
  actual=$(capture_logger_line "hello\nthere\n<END>\n" uppercaser logger)
  assert_eq "$expected" "$actual" "process multiple lines; last is 'THERE'"
}

# 3) Invalid plugin name should fail (non‑zero exit)
test_invalid_plugin() {
  set +e
  printf "hello\n<END>\n" | output/analyzer 10 output/does_not_exist logger >/dev/null 2>&1
  local rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    print_status "invalid plugin name returns non-zero exit code"
  else
    print_error "invalid plugin name should fail but returned 0"
    exit 1
  fi
}

# 4) Empty string edge case
test_empty_string() {
  local expected="[logger] "
  local actual
  actual=$(capture_logger_line "\n<END>\n" uppercaser logger)
  assert_eq "$expected" "$actual" "empty line passes through"
}

# 5) Uppercaser -> Rotator -> Logger 
test_chain_uppercaser_rotator_logger(){
  local expected="[logger] OHELL"
  local actual
  actual=$(capture_logger_line "hello\n<END>\n" uppercaser rotator logger)
  assert_eq "$expected" "$actual" "test hello input with uppercaser rotator logger"
}
# 6) flipper -> expander -> logger
test_chain_flipper_expander_logger(){
    local expected="[logger] o l l e h"
    local actual
    actual=$(capture_logger_line "hello\n<END>\n" flipper expander logger)
    assert_eq "$expected" "$actual" "test hello input with flipper expander logger"
}
# 7) more then 1 end 
test_more_then_one_end(){
    local expected="[logger] o l l e h"
    local actual
    actual=$(capture_logger_line "hello\n<END>\nthere\n<END>" flipper expander logger)
    assert_eq "$expected" "$actual" "test hello <END> there <END> input with flipper expander logger check only o l l e h is written "
}


capture_all_logger_lines() {
  local input="$1"; shift
  printf "%b" "$input" \
    | output/analyzer 10 "$@" 2>/dev/null \
    | grep -E '^\[logger\] '
}

# 8) check 1-100 and see all lines are in the same order 
test_100_lines_same_order(){
    local expected
    # Build expected with [logger] prefix
    expected=$(for i in $(seq 1 100); do
        printf "[logger] %s\n" "$i"
    done)

    local actual
    actual=$(
      { seq 1 100; echo "<END>"; } \
      | ./output/analyzer 10 logger \
      | grep "^\[logger\] "
    )

    assert_eq  "$expected" "$actual" "write lines 1 to 100 work"
}

# 9) check expander with one space
test_expander_one_space(){
    local expected="[logger]  "
    local actual
    actual=$(capture_logger_line " \n<END>\n" expander logger)
    assert_eq "$expected" "$actual" "test one space with expader"
}

# 10) check expander with two space
test_expander_two_spaces(){
    local expected="[logger]    "
    local actual
    actual=$(capture_logger_line "  \n<END>\n" expander logger)
    assert_eq "$expected" "$actual" "test two spaces with expader"
}

# 11) check queue size 1 with multiple plugins 
test_multiple_plugins_queue_size_one(){
    local expected="[logger]  L L E HO"
    local actual
    actual=$( { printf "hello\n<END>\n"; } \
            | ./output/analyzer 1 uppercaser expander rotator flipper logger \
            | grep "^\[logger\] " | tail -n1 )
    assert_eq "$expected" "$actual" "queue size = 1 with multiple plugins preserves order and correctness"
}

test_large_input() {
  local lines=10000
  local expected="[logger] $lines"
  local actual
  actual=$( { seq 1 $lines; echo "<END>"; } \
            | ./output/analyzer 50 logger \
            | grep "^\[logger\] " | tail -n1 )
  assert_eq "$expected" "$actual" "large input of $lines lines works"
}



test_use_of_plugin_more_than_once() {
  local expected=$'[logger] HELLO\n[logger] OHELL'
  local actual
  actual=$(capture_all_logger_lines "hello\n<END>\n" uppercaser logger rotator logger)
  assert_eq "$expected" "$actual" "plugin appears twice in pipeline and both executions work"
}


# Run all tests
test_uppercaser_logger_basic
test_expander_logger_basic
test_flipper_logger_basic
test_rotator_logger_basic
test_uppercaser_typewriter_basic
test_expander_typewriter_basic
test_flipper_typewriter_basic
test_rotator_typewriter_basic
test_multiple_lines
test_invalid_plugin
test_empty_string
test_chain_uppercaser_rotator_logger
test_chain_flipper_expander_logger
test_more_then_one_end
test_100_lines_same_order
test_expander_one_space
test_expander_two_spaces
test_multiple_plugins_queue_size_one
test_use_of_plugin_more_than_once

#TODO 
#*** for runs with exit code do set +e 
#test_not_arguments echo -e "1\n<END>" | ./output/analyzer
#test_queue_size_not_valid echo -e "1\n<END>" | ./output/analyzer 0

echo "All tests passed ✔"
