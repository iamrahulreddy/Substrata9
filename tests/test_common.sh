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
ROOT_DIR="$(dirname "$TEST_DIR")"
LIB_DIR="$ROOT_DIR/lib"
COMMON_WORK_DIR=$(mktemp -d)
trap 'rm -rf "$COMMON_WORK_DIR"' EXIT
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

out=$(s9_json_kv "leading" "080")
assert_match '  "leading": "080",' "$out" "Leading-zero value stays quoted"

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
# Test 6: Auto Export Filename
# =============================================================================
echo "  [6] Testing s9_auto_export_path..."
out=$(cd "$COMMON_WORK_DIR" && s9_auto_export_path "Inspect Report!")
assert_match '^s9-inspect-report_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}_[A-Za-z0-9_-]+\.json$' "$out" "Purpose sanitized with timezone timestamp"

out=$(cd "$COMMON_WORK_DIR" && s9_auto_export_path "")
assert_match '^s9-report_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}_[A-Za-z0-9_-]+\.json$' "$out" "Empty purpose falls back to report"

# =============================================================================
# Test 7: Sanitize Filename
# =============================================================================
echo "  [7] Testing s9_sanitize_filename..."
assert_eq "test-file_1" "$(s9_sanitize_filename "test-file_1")" "Safe filename unchanged"
assert_eq "testfile" "$(s9_sanitize_filename "test/file")" "Slashes removed"
assert_eq "testfile" "$(s9_sanitize_filename "test..file")" "Dots removed"
assert_eq "testfile" "$(s9_sanitize_filename 'test"file')" "Quotes removed"
assert_eq "testfile" "$(s9_sanitize_filename 'test$file')" "Dollar sign removed"
assert_eq "" "$(s9_sanitize_filename '///...')" "All special chars = empty"
assert_eq "abc123" "$(s9_sanitize_filename "abc123")" "Alphanumeric unchanged"

# =============================================================================
# Test 8: Validate Number
# =============================================================================
echo "  [8] Testing s9_validate_number..."
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
# Test 9: Process Functions (on current shell)
# =============================================================================
echo "  [9] Testing process functions on PID $$..."
assert_not_empty "$(s9_get_comm $$)" "s9_get_comm returns process name"
assert_not_empty "$(s9_get_state $$)" "s9_get_state returns state"
assert_not_empty "$(s9_get_ppid $$)" "s9_get_ppid returns parent PID"
assert_match "^[0-9]+$" "$(s9_get_rss $$)" "s9_get_rss returns numeric value"
assert_match "^[0-9]+$" "$(s9_get_threads $$)" "s9_get_threads returns numeric value"
assert_match "^[0-9]+$" "$(s9_get_fd_count $$)" "s9_get_fd_count returns numeric value"

# =============================================================================
# Test 10: Process Existence Check
# =============================================================================
echo "  [10] Testing s9_process_exists..."
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
# Test 11: Signal Decoding
# =============================================================================
echo "  [11] Testing s9_decode_signals..."
assert_eq "none" "$(s9_decode_signals 0)" "Zero mask = none"
assert_eq "none" "$(s9_decode_signals "")" "Empty mask = none"
assert_match "SIGHUP" "$(s9_decode_signals 1)" "Mask 1 contains SIGHUP"
assert_match "SIGINT" "$(s9_decode_signals 2)" "Mask 2 contains SIGINT"
assert_match "SIGTERM" "$(s9_decode_signals 4000)" "Mask 4000 (hex) contains SIGTERM"

# =============================================================================
# Test 12: State Description
# =============================================================================
echo "  [12] Testing s9_get_state_desc..."
# We need to create mock, so we test the description format
result=$(s9_get_state_desc $$)
assert_not_empty "$result" "s9_get_state_desc returns description"

# =============================================================================
# Test 13: System Info Functions
# =============================================================================
echo "  [13] Testing system info functions..."
assert_match "^[0-9]+$" "$(s9_get_total_mem)" "s9_get_total_mem returns number"
assert_match "^[0-9]+$" "$(s9_get_avail_mem)" "s9_get_avail_mem returns number"
assert_match "^[0-9]+$" "$(s9_get_uptime)" "s9_get_uptime returns number"
assert_not_empty "$(s9_get_kernel)" "s9_get_kernel returns kernel version"

# =============================================================================
# Test 14: FD Type Classification
# =============================================================================
echo "  [14] Testing s9_fd_type..."
assert_eq "socket" "$(s9_fd_type "socket:[123]")" "Socket target"
assert_eq "pipe" "$(s9_fd_type "pipe:[123]")" "Pipe target"
assert_eq "device" "$(s9_fd_type "/dev/null")" "Device target"
assert_eq "anon" "$(s9_fd_type "anon_inode:[eventfd]")" "Anonymous inode target"
assert_eq "file" "$(s9_fd_type "/tmp/file")" "File target"

# =============================================================================
# Test 15: Calculator Fallback
# =============================================================================
echo "  [15] Testing bundled bc fallback..."
assert_eq "2" "$(echo "1+1" | bash "$ROOT_DIR/bin/bc")" "Basic arithmetic"
assert_eq "1.50" "$(echo "scale=2; 3/2" | bash "$ROOT_DIR/bin/bc")" "Scale handling"

((TESTS_RUN++))
if ! echo 'system("id")' | bash "$ROOT_DIR/bin/bc" >/dev/null 2>&1; then
    echo "    [OK] Unsupported expression rejected"
else
    echo "    [FAIL] Unsupported expression was accepted"
    ((TESTS_FAILED++))
fi

# =============================================================================
# Test 16: GPU Helpers
# =============================================================================
echo "  [16] Testing GPU helpers..."
assert_match "^[0-9]+$" "$(s9_gpu_process_count)" "GPU process count is numeric"

fake_smi="$COMMON_WORK_DIR/nvidia-smi"
cat > "$fake_smi" <<'FAKE_NVIDIA_SMI'
#!/usr/bin/env bash
set -u
case "${1:-}" in
    --query-gpu=index)
        [[ "${S9_FAKE_GPU_BROKEN:-0}" == "1" ]] && exit 1
        if [[ "${S9_FAKE_GPU_MULTIPLE:-0}" == "1" ]]; then
            printf "0\n1\n"
        else
            echo "0"
        fi
        ;;
    --query-gpu=index,uuid,name)
        [[ "${S9_FAKE_GPU_BROKEN:-0}" == "1" ]] && exit 1
        if [[ "${S9_FAKE_GPU_MULTIPLE:-0}" == "1" ]]; then
            printf "0, GPU-fake-0, Substrata Test GPU\n1, GPU-fake-1, Substrata Backup GPU\n"
        elif [[ "${S9_FAKE_GPU_COMMAS:-0}" == "1" ]]; then
            echo "0, GPU-fake-0, Substrata, Test GPU | Pipe"
        else
            echo "0, GPU-fake-0, Substrata Test GPU"
        fi
        ;;
    --query-compute-apps=pid,process_name,gpu_uuid,used_memory)
        [[ "${S9_FAKE_GPU_BROKEN:-0}" == "1" ]] && exit 1
        [[ "${S9_FAKE_GPU_EMPTY:-0}" == "1" ]] && exit 0
        if [[ "${S9_FAKE_GPU_MALFORMED:-0}" == "1" ]]; then
            printf "not-a-pid, broken, GPU-fake-0, 999\n12345, missing-memory, GPU-fake-0\n"
        elif [[ "${S9_FAKE_GPU_MULTIPLE:-0}" == "1" ]]; then
            printf "%s, fake_gpu_process, GPU-fake-0, %s\n67890, second_gpu_process, GPU-fake-1, 512\n" "${S9_FAKE_GPU_PID:-12345}" "${S9_FAKE_GPU_MEM:-1536}"
        elif [[ "${S9_FAKE_GPU_COMMAS:-0}" == "1" ]]; then
            echo "${S9_FAKE_GPU_PID:-12345}, fake,worker|gpu, GPU-fake-0, ${S9_FAKE_GPU_MEM:-1536}"
        else
            echo "${S9_FAKE_GPU_PID:-12345}, fake_gpu_process, GPU-fake-0, ${S9_FAKE_GPU_MEM:-1536}"
        fi
        ;;
    *)
        exit 1
        ;;
esac
FAKE_NVIDIA_SMI
chmod +x "$fake_smi"

export S9_NVIDIA_SMI="$COMMON_WORK_DIR/missing-nvidia-smi"
((TESTS_RUN++))
if ! s9_gpu_available; then
    echo "    [OK] Missing nvidia-smi reports unavailable"
else
    echo "    [FAIL] Missing nvidia-smi should be unavailable"
    ((TESTS_FAILED++))
fi

export S9_NVIDIA_SMI="$fake_smi"
export S9_FAKE_GPU_PID="12345"
export S9_FAKE_GPU_MEM="1536"
((TESTS_RUN++))
if s9_gpu_available; then
    echo "    [OK] Fake nvidia-smi reports available"
else
    echo "    [FAIL] Fake nvidia-smi should be available"
    ((TESTS_FAILED++))
fi
assert_eq "1" "$(s9_gpu_process_count)" "Fake GPU process count"
assert_match "^12345\\|fake_gpu_process\\|0\\|Substrata Test GPU\\|1536\\|compute$" "$(s9_gpu_process_for_pid 12345)" "Fake GPU process row"

export S9_FAKE_GPU_MULTIPLE=1
assert_eq "2" "$(s9_gpu_process_count)" "Multiple fake GPU process count"
assert_match "^67890\\|second_gpu_process\\|1\\|Substrata Backup GPU\\|512\\|compute$" "$(s9_gpu_process_for_pid 67890)" "Second fake GPU process row"
unset S9_FAKE_GPU_MULTIPLE

export S9_FAKE_GPU_COMMAS=1
comma_row=$(s9_gpu_process_for_pid 12345)
assert_match "fake,worker gpu" "$comma_row" "GPU process name preserves comma and strips pipe delimiter"
assert_match "Substrata, Test GPU" "$comma_row" "GPU name preserves comma"
unset S9_FAKE_GPU_COMMAS

export S9_FAKE_GPU_MALFORMED=1
assert_eq "0" "$(s9_gpu_process_count)" "Malformed GPU rows are ignored"
unset S9_FAKE_GPU_MALFORMED

export S9_FAKE_GPU_BROKEN=1
((TESTS_RUN++))
if ! s9_gpu_available; then
    echo "    [OK] Broken nvidia-smi reports unavailable"
else
    echo "    [FAIL] Broken nvidia-smi should be unavailable"
    ((TESTS_FAILED++))
fi
unset S9_NVIDIA_SMI S9_FAKE_GPU_PID S9_FAKE_GPU_MEM S9_FAKE_GPU_BROKEN S9_FAKE_GPU_EMPTY S9_FAKE_GPU_MULTIPLE S9_FAKE_GPU_COMMAS S9_FAKE_GPU_MALFORMED

# =============================================================================
# Test 17: Calculator Fallback - Edge Cases
# =============================================================================
echo "  [17] Testing bundled bc fallback edge cases..."

# Empty input should produce no output and succeed
out=$(echo "" | bash "$ROOT_DIR/bin/bc")
assert_eq "" "$out" "Empty input produces no output"

# Negative numbers
assert_eq "-3" "$(echo "2-5" | bash "$ROOT_DIR/bin/bc")" "Negative result"

# Parenthesized expressions
assert_eq "10" "$(echo "(2+3)*2" | bash "$ROOT_DIR/bin/bc")" "Parenthesized expression"

# Scale at maximum (capped to 12)
out=$(echo "scale=15; 1/3" | bash "$ROOT_DIR/bin/bc")
assert_match "^0\\.3333" "$out" "Scale capped at 12 digits"

# Multi-line whitespace (tabs, newlines collapsed)
out=$(printf "1\n+\n1\n" | bash "$ROOT_DIR/bin/bc")
assert_eq "2" "$out" "Multi-line expression collapsed"

# Comparison operators
assert_eq "1" "$(echo "5>3" | bash "$ROOT_DIR/bin/bc")" "Greater-than comparison"
assert_eq "0" "$(echo "3>5" | bash "$ROOT_DIR/bin/bc")" "Failed greater-than comparison"

# -l option ignored gracefully
assert_eq "2" "$(echo "1+1" | bash "$ROOT_DIR/bin/bc" -l)" "Accepts -l flag"

# Rejection of letters/commands
((TESTS_RUN++))
if ! echo 'print 1' | bash "$ROOT_DIR/bin/bc" >/dev/null 2>&1; then
    echo "    [OK] 'print' command rejected"
else
    echo "    [FAIL] 'print' command was accepted"
    ((TESTS_FAILED++))
fi

((TESTS_RUN++))
if ! echo 'sqrt(4)' | bash "$ROOT_DIR/bin/bc" >/dev/null 2>&1; then
    echo "    [OK] 'sqrt()' function rejected"
else
    echo "    [FAIL] 'sqrt()' function was accepted"
    ((TESTS_FAILED++))
fi

# Division by zero — awk may return inf or error, but script should not crash
((TESTS_RUN++))
out=$(echo "1/0" | bash "$ROOT_DIR/bin/bc" 2>&1) && rc=0 || rc=$?
if (( rc <= 1 )); then
    echo "    [OK] Division by zero handled gracefully (exit=$rc, got: $out)"
else
    echo "    [FAIL] Division by zero caused a crash (exit=$rc)"
    ((TESTS_FAILED++))
fi

# =============================================================================
# Test 18: Validate Safe Directory
# =============================================================================
echo "  [18] Testing s9_validate_safe_dir..."

# Under HOME should be safe
((TESTS_RUN++))
if s9_validate_safe_dir "$HOME" 2>/dev/null; then
    echo "    [OK] HOME is a safe directory"
else
    echo "    [FAIL] HOME should be safe"
    ((TESTS_FAILED++))
fi

# Under /tmp should be safe
((TESTS_RUN++))
if s9_validate_safe_dir "/tmp" 2>/dev/null; then
    echo "    [OK] /tmp is a safe directory"
else
    echo "    [FAIL] /tmp should be safe"
    ((TESTS_FAILED++))
fi

# Outside HOME and /tmp should fail
((TESTS_RUN++))
if ! s9_validate_safe_dir "/etc" 2>/dev/null; then
    echo "    [OK] /etc correctly rejected"
else
    echo "    [FAIL] /etc should not be safe"
    ((TESTS_FAILED++))
fi

((TESTS_RUN++))
if ! s9_validate_safe_dir "/usr/local" 2>/dev/null; then
    echo "    [OK] /usr/local correctly rejected"
else
    echo "    [FAIL] /usr/local should not be safe"
    ((TESTS_FAILED++))
fi

# Root directory should fail
((TESTS_RUN++))
if ! s9_validate_safe_dir "/" 2>/dev/null; then
    echo "    [OK] / correctly rejected"
else
    echo "    [FAIL] / should not be safe"
    ((TESTS_FAILED++))
fi

# Subdirectory under HOME should be safe
((TESTS_RUN++))
if s9_validate_safe_dir "$HOME/.substrata9" 2>/dev/null; then
    echo "    [OK] HOME subdirectory is safe"
else
    echo "    [FAIL] HOME subdirectory should be safe"
    ((TESTS_FAILED++))
fi

# =============================================================================
# Test 19: Resolve PID
# =============================================================================
echo "  [19] Testing s9_resolve_pid..."

# Current PID should resolve
out=$(s9_resolve_pid "$$" true)
assert_eq "$$" "$out" "Numeric PID resolves to itself"

# Non-existent PID should fail
((TESTS_RUN++))
if ! s9_resolve_pid "999999999" true >/dev/null 2>&1; then
    echo "    [OK] Non-existent PID correctly rejected"
else
    echo "    [FAIL] Non-existent PID should not resolve"
    ((TESTS_FAILED++))
fi

# Input with special characters should be rejected
((TESTS_RUN++))
if ! s9_resolve_pid "12;rm" true >/dev/null 2>&1; then
    echo "    [OK] PID with semicolon rejected"
else
    echo "    [FAIL] PID with semicolon should be rejected"
    ((TESTS_FAILED++))
fi

((TESTS_RUN++))
if ! s9_resolve_pid '../etc/passwd' true >/dev/null 2>&1; then
    echo "    [OK] Path traversal in PID rejected"
else
    echo "    [FAIL] Path traversal should be rejected"
    ((TESTS_FAILED++))
fi

# Name resolution for 'init' (PID 1 should exist on Linux)
if [[ -d /proc/1 ]]; then
    ((TESTS_RUN++))
    result=$(s9_resolve_pid "1" true 2>/dev/null)
    if [[ "$result" == "1" ]]; then
        echo "    [OK] PID 1 resolves correctly"
    else
        echo "    [FAIL] PID 1 should resolve (got: '$result')"
        ((TESTS_FAILED++))
    fi
fi

# =============================================================================
# Test 20: JSON Sanitization - Control Characters
# =============================================================================
echo "  [20] Testing s9_sanitize_json control characters..."

# Form feed
assert_eq "hello\\fworld" "$(s9_sanitize_json $'hello\fworld')" "Form feed escaped"

# Backspace
assert_eq "hello\\bworld" "$(s9_sanitize_json $'hello\bworld')" "Backspace escaped"

# Carriage return
assert_eq "hello\\rworld" "$(s9_sanitize_json $'hello\rworld')" "Carriage return escaped"

# Null bytes — bash echo truncates at \x00, so only 'hello' survives
out=$(s9_sanitize_json $'hello\x00world')
assert_eq "hello" "$out" "Null bytes truncated by echo"

# Bell character (should be stripped by tr)
out=$(s9_sanitize_json $'hello\x07world')
assert_eq "helloworld" "$out" "Bell character stripped"

# Combined: backslash + quote in one string
# Input:  hello\world"test
# Expect: hello\\world\"test  (backslash doubled, quote escaped)
out=$(s9_sanitize_json 'hello\world"test')
assert_eq 'hello\\world\"test' "$out" "Backslash + quote combined"

# =============================================================================
# Test 21: Comparison Display Functions
# =============================================================================
echo "  [21] Testing s9_compare_row and s9_diff_indicator..."

# diff_indicator: positive diff
out=$(s9_diff_indicator 5)
assert_match "↑" "$out" "Positive diff shows up arrow"
assert_match "\\+5" "$out" "Positive diff shows +5"

# diff_indicator: negative diff
out=$(s9_diff_indicator -3)
assert_match "↓" "$out" "Negative diff shows down arrow"

# diff_indicator: zero diff
out=$(s9_diff_indicator 0)
assert_match "→" "$out" "Zero diff shows right arrow"

# diff_indicator: reverse mode (positive = bad)
out=$(s9_diff_indicator 5 reverse)
assert_match "↑" "$out" "Reverse positive still shows up arrow"

# compare_row basic operation (just verify it produces output without crashing)
((TESTS_RUN++))
out=$(s9_compare_row "TestMetric" "100" "200" "kB" "" 2>/dev/null)
if [[ -n "$out" ]]; then
    echo "    [OK] s9_compare_row produces output"
else
    echo "    [FAIL] s9_compare_row produced no output"
    ((TESTS_FAILED++))
fi

# compare_row with zero values
((TESTS_RUN++))
out=$(s9_compare_row "ZeroTest" "0" "0" "" "" 2>/dev/null)
if [[ -n "$out" ]]; then
    echo "    [OK] s9_compare_row handles zero values"
else
    echo "    [FAIL] s9_compare_row failed on zero values"
    ((TESTS_FAILED++))
fi

# compare_row with human_func=kb
((TESTS_RUN++))
out=$(s9_compare_row "Memory" "1024" "2048" "kB" "kb" 2>/dev/null)
if [[ -n "$out" ]]; then
    echo "    [OK] s9_compare_row with kb formatting"
else
    echo "    [FAIL] s9_compare_row failed with kb formatting"
    ((TESTS_FAILED++))
fi

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
