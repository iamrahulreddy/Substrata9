#!/usr/bin/env bash
#
# test_common.sh - Unit tests for s9-common.sh
#
# Tests core library functions including formatting, validation, JSON output,
# process helpers, and edge case handling.
#

set -u

# Setup
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$TEST_DIR")/lib"
source "$LIB_DIR/s9-common.sh" || { echo "Failed to source library"; exit 1; }

# Test Counters
TESTS_RUN=0
TESTS_FAILED=0

# Helper functions
assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-}"
    
    ((TESTS_RUN++))
    if [[ "$expected" == "$actual" ]]; then
        echo "    [OK] $msg"
        return 0
    else
        echo "    [FAIL] $msg"
        echo "      Expected: '$expected'"
        echo "      Actual:   '$actual'"
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_match() {
    local regex="$1"
    local actual="$2"
    local msg="${3:-}"
    
    ((TESTS_RUN++))
    if [[ "$actual" =~ $regex ]]; then
        echo "    [OK] $msg"
        return 0
    else
        echo "    [FAIL] $msg"
        echo "      Expected match: '$regex'"
        echo "      Actual:         '$actual'"
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_not_empty() {
    local actual="$1"
    local msg="${2:-}"
    
    ((TESTS_RUN++))
    if [[ -n "$actual" ]]; then
        echo "    [OK] $msg"
        return 0
    else
        echo "    [FAIL] $msg (was empty)"
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_exit_code() {
    local expected="$1"
    local msg="${2:-}"
    shift 2
    
    ((TESTS_RUN++))
    "$@" >/dev/null 2>&1
    local actual=$?
    if [[ "$expected" == "$actual" ]]; then
        echo "    [OK] $msg"
        return 0
    else
        echo "    [FAIL] $msg"
        echo "      Expected exit: $expected, Got: $actual"
        ((TESTS_FAILED++))
        return 1
    fi
}

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Testing s9-common.sh                                          ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# =============================================================================
# Test 1: Human Readable Bytes
# =============================================================================
echo "  [1] Testing s9_human_bytes..."
assert_eq "0 B" "$(s9_human_bytes 0)" "0 bytes"
assert_eq "0 B" "$(s9_human_bytes "")" "Empty string defaults to 0"
assert_eq "0 B" "$(s9_human_bytes "abc")" "Invalid input defaults to 0"
assert_eq "100 B" "$(s9_human_bytes 100)" "100 bytes"
assert_eq "1023 B" "$(s9_human_bytes 1023)" "1023 bytes (just under 1KB)"
assert_eq "1.00 KB" "$(s9_human_bytes 1024)" "1 KB"
assert_eq "1.50 KB" "$(s9_human_bytes 1536)" "1.5 KB"
assert_eq "1.00 MB" "$(s9_human_bytes 1048576)" "1 MB"
assert_eq "1.00 GB" "$(s9_human_bytes 1073741824)" "1 GB"

# =============================================================================
# Test 2: Human Readable KB
# =============================================================================
echo "  [2] Testing s9_human_kb..."
assert_eq "0 B" "$(s9_human_kb 0)" "0 KB = 0 B"
assert_eq "1.00 KB" "$(s9_human_kb 1)" "1 KB"
assert_eq "1.00 MB" "$(s9_human_kb 1024)" "1024 KB = 1 MB"
assert_eq "1.00 GB" "$(s9_human_kb 1048576)" "1048576 KB = 1 GB"

# =============================================================================
# Test 3: Human Readable Duration
# =============================================================================
echo "  [3] Testing s9_human_duration..."
assert_eq "0s" "$(s9_human_duration 0)" "0 seconds"
assert_eq "0s" "$(s9_human_duration -5)" "Negative duration clamps to 0"
assert_eq "59s" "$(s9_human_duration 59)" "59 seconds"
assert_eq "1m 0s" "$(s9_human_duration 60)" "1 minute"
assert_eq "1m 30s" "$(s9_human_duration 90)" "1 minute 30 seconds"
assert_eq "1h 0m 0s" "$(s9_human_duration 3600)" "1 hour"
assert_eq "1h 30m 0s" "$(s9_human_duration 5400)" "1 hour 30 minutes"
assert_eq "1d 0h 0m" "$(s9_human_duration 86400)" "1 day"
assert_eq "2d 3h 4m" "$(s9_human_duration 183840)" "2 days 3 hours 4 minutes"

# =============================================================================
# Test 4: JSON Sanitization
# =============================================================================
echo "  [4] Testing s9_sanitize_json..."
assert_eq "hello" "$(s9_sanitize_json "hello")" "Simple string"
assert_eq "hello world" "$(s9_sanitize_json "hello world")" "String with space"
assert_eq "hello\\\"world" "$(s9_sanitize_json 'hello"world')" "Double quotes escaped"
assert_eq "hello\\\\world" "$(s9_sanitize_json 'hello\world')" "Backslash escaped"
assert_eq "" "$(s9_sanitize_json "")" "Empty string"
assert_eq "line1\\nline2" "$(s9_sanitize_json $'line1\nline2')" "Newline escaped"
assert_eq "tab\\there" "$(s9_sanitize_json $'tab\there')" "Tab escaped"

# =============================================================================
# Test 5: JSON Key-Value Output
# =============================================================================
echo "  [5] Testing s9_json_kv..."
out=$(s9_json_kv "key" "value")
assert_match '  "key": "value",' "$out" "Simple string KV"

out=$(s9_json_kv "num" "123")
assert_match '  "num": 123,' "$out" "Number KV (no quotes)"

out=$(s9_json_kv "float" "3.14")
assert_match '  "float": 3.14,' "$out" "Float KV (no quotes)"

out=$(s9_json_kv "bool" "true")
assert_match '  "bool": true,' "$out" "Boolean true KV"

out=$(s9_json_kv "bool" "false")
assert_match '  "bool": false,' "$out" "Boolean false KV"

out=$(s9_json_kv "null" "null")
assert_match '  "null": null,' "$out" "Null KV"

out=$(s9_json_kv "last" "val" "last")
assert_match '  "last": "val"$' "$out" "Last KV (no trailing comma)"

# =============================================================================
# Test 6: Sanitize Filename
# =============================================================================
echo "  [6] Testing s9_sanitize_filename..."
assert_eq "test-file_1" "$(s9_sanitize_filename "test-file_1")" "Safe filename unchanged"
assert_eq "testfile" "$(s9_sanitize_filename "test/file")" "Slashes removed"
assert_eq "testfile" "$(s9_sanitize_filename "test..file")" "Dots removed"
assert_eq "testfile" "$(s9_sanitize_filename 'test"file')" "Quotes removed"
assert_eq "testfile" "$(s9_sanitize_filename 'test$file')" "Dollar sign removed"
assert_eq "" "$(s9_sanitize_filename '///...')" "All special chars = empty"
assert_eq "abc123" "$(s9_sanitize_filename "abc123")" "Alphanumeric unchanged"

# =============================================================================
# Test 7: Validate Number
# =============================================================================
echo "  [7] Testing s9_validate_number..."
# Valid numbers should not cause exit (we test by checking the function doesn't fail)
(s9_validate_number "123" "test" 2>/dev/null) && echo "    [OK] Valid number 123"
(s9_validate_number "0" "test" 2>/dev/null) && echo "    [OK] Valid number 0"
((TESTS_RUN+=2))

# Invalid should fail (we can't easily test s9_die, so we check it would fail)
if ! (s9_validate_number "abc" "test" 2>/dev/null); then
    echo "    [OK] Invalid number 'abc' rejected"
    ((TESTS_RUN++))
else
    echo "    [FAIL] Invalid number 'abc' was accepted"
    ((TESTS_RUN++))
    ((TESTS_FAILED++))
fi

# =============================================================================
# Test 8: Process Functions (on current shell)
# =============================================================================
echo "  [8] Testing process functions on PID $$..."
assert_not_empty "$(s9_get_comm $$)" "s9_get_comm returns process name"
assert_not_empty "$(s9_get_state $$)" "s9_get_state returns state"
assert_not_empty "$(s9_get_ppid $$)" "s9_get_ppid returns parent PID"
assert_match "^[0-9]+$" "$(s9_get_rss $$)" "s9_get_rss returns numeric value"
assert_match "^[0-9]+$" "$(s9_get_threads $$)" "s9_get_threads returns numeric value"
assert_match "^[0-9]+$" "$(s9_get_fd_count $$)" "s9_get_fd_count returns numeric value"

# =============================================================================
# Test 9: Process Existence Check
# =============================================================================
echo "  [9] Testing s9_process_exists..."
((TESTS_RUN++))
if s9_process_exists $$; then
    echo "    [OK] Current process exists"
else
    echo "    [FAIL] Current process should exist"
    ((TESTS_FAILED++))
fi

((TESTS_RUN++))
if ! s9_process_exists 999999999; then
    echo "    [OK] Non-existent PID correctly detected"
else
    echo "    [FAIL] Non-existent PID should not exist"
    ((TESTS_FAILED++))
fi

# =============================================================================
# Test 10: Signal Decoding
# =============================================================================
echo "  [10] Testing s9_decode_signals..."
assert_eq "none" "$(s9_decode_signals 0)" "Zero mask = none"
assert_eq "none" "$(s9_decode_signals "")" "Empty mask = none"
assert_match "SIGHUP" "$(s9_decode_signals 1)" "Mask 1 contains SIGHUP"
assert_match "SIGINT" "$(s9_decode_signals 2)" "Mask 2 contains SIGINT"
assert_match "SIGTERM" "$(s9_decode_signals 4000)" "Mask 4000 (hex) contains SIGTERM"

# =============================================================================
# Test 11: State Description
# =============================================================================
echo "  [11] Testing s9_get_state_desc..."
# We need to create mock, so we test the description format
result=$(s9_get_state_desc $$)
assert_not_empty "$result" "s9_get_state_desc returns description"

# =============================================================================
# Test 12: System Info Functions
# =============================================================================
echo "  [12] Testing system info functions..."
assert_match "^[0-9]+$" "$(s9_get_total_mem)" "s9_get_total_mem returns number"
assert_match "^[0-9]+$" "$(s9_get_avail_mem)" "s9_get_avail_mem returns number"
assert_match "^[0-9]+$" "$(s9_get_uptime)" "s9_get_uptime returns number"
assert_not_empty "$(s9_get_kernel)" "s9_get_kernel returns kernel version"

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "────────────────────────────────────────────────────────────────"
echo ""
echo "Unit Tests Complete"
echo "  Total:  $TESTS_RUN"
echo "  Passed: $((TESTS_RUN - TESTS_FAILED))"
echo "  Failed: $TESTS_FAILED"
echo ""

if (( TESTS_FAILED > 0 )); then
    exit 1
else
    exit 0
fi
