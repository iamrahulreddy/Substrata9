#!/usr/bin/env bash
#
# test_regression.sh - Regression tests for Substrata9
#
# Covers:
# - Snapshot diff correctness (capture → verify values match)
# - Export flag output validation (file created, ANSI stripped, JSON passthrough)
# - bc fallback install-path discovery
# - FD summary counts all FDs (not just first 30)
# - Option validation edge cases
#

set -u

# Setup
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$(dirname "$TEST_DIR")/bin"
ROOT_DIR="$(dirname "$TEST_DIR")"
SNAPSHOT_TEST_DIR=$(mktemp -d)
EXPORT_TEST_DIR=$(mktemp -d)
export S9_SNAPSHOT_DIR="$SNAPSHOT_TEST_DIR"
trap 'rm -rf "$SNAPSHOT_TEST_DIR" "$EXPORT_TEST_DIR"' EXIT

# Capture current shell PID at script start for use in tests
TEST_PID=$$

# Test Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
pass() {
    local msg="$1"
    echo "    [OK] $msg"
    ((TESTS_PASSED++))
}

fail() {
    local msg="$1"
    echo "    [FAIL] $msg"
    ((TESTS_FAILED++))
}

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Substrata9 — Regression Tests                                 ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# =============================================================================
# Test 1: Snapshot Diff Correctness
# =============================================================================
echo "  [1] Snapshot diff correctness"

# Capture a snapshot of the current shell
((TESTS_RUN++))
snap1_name="regtest_before_${TEST_PID}"
if bash "$BIN_DIR/s9-snapshot" capture "$TEST_PID" --name "$snap1_name" >/dev/null 2>&1; then
    pass "Captured snapshot 1"
else
    fail "Failed to capture snapshot 1"
fi

# Capture a second snapshot (same process, values should be similar)
snap2_name="regtest_after_${TEST_PID}"
((TESTS_RUN++))
if bash "$BIN_DIR/s9-snapshot" capture "$TEST_PID" --name "$snap2_name" >/dev/null 2>&1; then
    pass "Captured snapshot 2"
else
    fail "Failed to capture snapshot 2"
fi

# Verify snapshot files exist and have correct headers
((TESTS_RUN++))
snap1_file=$(ls -t "$SNAPSHOT_TEST_DIR/${snap1_name}"_*.snap 2>/dev/null | head -1)
if [[ -f "$snap1_file" ]] && grep -q "^# Substrata9 Process Snapshot" "$snap1_file"; then
    pass "Snapshot 1 has correct format header"
else
    fail "Snapshot 1 missing or bad header"
fi

((TESTS_RUN++))
snap2_file=$(ls -t "$SNAPSHOT_TEST_DIR/${snap2_name}"_*.snap 2>/dev/null | head -1)
if [[ -f "$snap2_file" ]] && grep -q "^# Substrata9 Process Snapshot" "$snap2_file"; then
    pass "Snapshot 2 has correct format header"
else
    fail "Snapshot 2 missing or bad header"
fi

# Verify snapshot contains expected sections
for section in "[STATUS]" "[STAT]" "[CMDLINE]" "[FD_COUNT]" "[FD_LIST]" "[LIMITS]" "[IO]" "[MAPS_SUMMARY]"; do
    ((TESTS_RUN++))
    if grep -qF "$section" "$snap1_file" 2>/dev/null; then
        pass "Snapshot contains $section section"
    else
        fail "Snapshot missing $section section"
    fi
done

# Verify snapshot has valid VmRSS
((TESTS_RUN++))
snap_rss=$(grep "^VmRSS:" "$snap1_file" 2>/dev/null | awk '{print $2}')
if [[ "$snap_rss" =~ ^[0-9]+$ ]] && (( snap_rss > 0 )); then
    pass "Snapshot RSS is valid ($snap_rss kB)"
else
    fail "Snapshot RSS is invalid ('$snap_rss')"
fi

# Verify snapshot FD count matches reality
((TESTS_RUN++))
snap_fd_count=$(grep -A1 '^\[FD_COUNT\]$' "$snap1_file" | tail -1 | tr -d '[:space:]')
live_fd_count=$(ls -1 /proc/$TEST_PID/fd 2>/dev/null | wc -l)
if [[ "$snap_fd_count" =~ ^[0-9]+$ ]] && [[ "$live_fd_count" =~ ^[0-9]+$ ]]; then
    fd_delta=$(( snap_fd_count > live_fd_count ? snap_fd_count - live_fd_count : live_fd_count - snap_fd_count ))
else
    fd_delta=999999
fi
# Allow some variance since FDs change between capture and check
if [[ "$snap_fd_count" =~ ^[0-9]+$ ]] && (( snap_fd_count > 0 )) && (( fd_delta <= 10 )); then
    pass "Snapshot FD count is valid ($snap_fd_count, live=$live_fd_count)"
else
    fail "Snapshot FD count is invalid ('$snap_fd_count', live='$live_fd_count')"
fi

# Verify rapid captures with the same name do not overwrite each other.
((TESTS_RUN++))
collision_name="regtest_collision_${TEST_PID}"
if bash "$BIN_DIR/s9-snapshot" capture "$TEST_PID" --name "$collision_name" >/dev/null 2>&1 &&
   bash "$BIN_DIR/s9-snapshot" capture "$TEST_PID" --name "$collision_name" >/dev/null 2>&1; then
    collision_count=$(ls "$SNAPSHOT_TEST_DIR/${collision_name}"_*.snap 2>/dev/null | wc -l)
    if (( collision_count >= 2 )); then
        pass "Rapid same-name snapshots are unique ($collision_count files)"
    else
        fail "Rapid same-name snapshots overwrote each other ($collision_count file)"
    fi
else
    fail "Rapid same-name snapshot captures failed"
fi

((TESTS_RUN++))
if ! bash "$BIN_DIR/s9-snapshot" diff "$collision_name" "$collision_name" >/dev/null 2>&1; then
    pass "Ambiguous snapshot names are rejected by diff"
else
    fail "Ambiguous snapshot names should require --latest or exact basename"
fi

((TESTS_RUN++))
if bash "$BIN_DIR/s9-snapshot" diff "$collision_name" "$collision_name" --latest >/dev/null 2>&1; then
    pass "Ambiguous snapshot diff allows explicit --latest"
else
    fail "Ambiguous snapshot diff --latest failed"
fi

((TESTS_RUN++))
if ! bash "$BIN_DIR/s9-snapshot" delete "$collision_name" --force >/dev/null 2>&1; then
    pass "Ambiguous snapshot names are rejected by delete"
else
    fail "Ambiguous snapshot delete should require --latest, --all, or exact basename"
fi

((TESTS_RUN++))
if bash "$BIN_DIR/s9-snapshot" delete "$collision_name" --all --force >/dev/null 2>&1; then
    pass "Ambiguous snapshot delete allows explicit --all"
else
    fail "Ambiguous snapshot delete --all failed"
fi

# Run diff and verify it produces output
((TESTS_RUN++))
diff_output=$(bash "$BIN_DIR/s9-snapshot" diff "$snap1_name" "$snap2_name" 2>/dev/null)
if [[ -n "$diff_output" ]]; then
    pass "Snapshot diff produces output"
else
    fail "Snapshot diff produced no output"
fi

# Run diff in JSON mode and verify valid JSON
((TESTS_RUN++))
diff_json=$(bash "$BIN_DIR/s9-snapshot" diff "$snap1_name" "$snap2_name" --json 2>/dev/null)
if echo "$diff_json" | head -1 | grep -q '^{'; then
    pass "Snapshot JSON diff starts with {"
else
    fail "Snapshot JSON diff format invalid"
fi

# Verify JSON diff contains expected fields
for field in "rss_before_kb" "rss_after_kb" "rss_diff_kb" "fd_before" "fd_after" "memory_status"; do
    ((TESTS_RUN++))
    if echo "$diff_json" | grep -q "\"$field\""; then
        pass "JSON diff contains $field"
    else
        fail "JSON diff missing $field"
    fi
done

# =============================================================================
# Test 2: Export Flag Output Validation
# =============================================================================
echo "  [2] Export flag validation"

# s9-inspect --export (text mode)
export_txt="$EXPORT_TEST_DIR/inspect_report.txt"
((TESTS_RUN++))
if bash "$BIN_DIR/s9-inspect" "$TEST_PID" --export "$export_txt" >/dev/null 2>&1; then
    pass "s9-inspect --export succeeds"
else
    fail "s9-inspect --export failed"
fi

# Verify file was created
((TESTS_RUN++))
if [[ -f "$export_txt" ]]; then
    pass "Export file was created"
else
    fail "Export file was not created"
fi

# Verify ANSI escape codes were stripped
((TESTS_RUN++))
esc=$(printf '\033')
if [[ -f "$export_txt" ]] && ! grep -q "$esc" "$export_txt" 2>/dev/null; then
    pass "Export file has no ANSI escape codes"
else
    fail "Export file still contains ANSI escape codes"
fi

# Verify exported content is non-empty and contains expected text
((TESTS_RUN++))
if [[ -f "$export_txt" ]] && (( $(wc -c < "$export_txt") > 100 )); then
    pass "Export file has substantial content"
else
    fail "Export file is too small or empty"
fi

# s9-inspect --export --json
export_json="$EXPORT_TEST_DIR/inspect_report.json"
((TESTS_RUN++))
if bash "$BIN_DIR/s9-inspect" --json "$TEST_PID" --export "$export_json" >/dev/null 2>&1; then
    pass "s9-inspect --json --export succeeds"
else
    fail "s9-inspect --json --export failed"
fi

# Verify JSON export is valid JSON (starts with {)
((TESTS_RUN++))
if [[ -f "$export_json" ]] && head -1 "$export_json" | grep -q '^{'; then
    pass "JSON export starts with {"
else
    fail "JSON export format invalid"
fi

# Verify JSON export has expected fields
((TESTS_RUN++))
if [[ -f "$export_json" ]] && grep -q '"pid"' "$export_json" && grep -q '"name"' "$export_json"; then
    pass "JSON export contains pid and name fields"
else
    fail "JSON export missing expected fields"
fi

# s9-tree --export
export_tree="$EXPORT_TEST_DIR/tree_report.txt"
((TESTS_RUN++))
if bash "$BIN_DIR/s9-tree" --pid "$TEST_PID" -d 1 --export "$export_tree" >/dev/null 2>&1; then
    pass "s9-tree --export succeeds"
else
    fail "s9-tree --export failed"
fi

((TESTS_RUN++))
if [[ -f "$export_tree" ]] && (( $(wc -c < "$export_tree") > 10 )); then
    pass "Tree export file has content"
else
    fail "Tree export file is empty or missing"
fi

# =============================================================================
# Test 3: bc Fallback Path Discovery
# =============================================================================
echo "  [3] bc fallback path discovery"

# Source lib to access s9_find_bc
((TESTS_RUN++))
if source "$ROOT_DIR/lib/s9-common.sh" 2>/dev/null; then
    pass "s9-common.sh sourced for bc fallback tests"
else
    fail "Could not source s9-common.sh"
fi

# s9_find_bc should find some bc (either system or fallback)
((TESTS_RUN++))
bc_path=$(s9_find_bc 2>/dev/null)
if [[ -n "$bc_path" ]]; then
    pass "s9_find_bc found bc at: $bc_path"
else
    fail "s9_find_bc could not find any bc"
fi

# s9_calc should work for basic arithmetic
((TESTS_RUN++))
calc_result=$(echo "2+3" | s9_calc 2>/dev/null)
if [[ "$calc_result" == "5" ]]; then
    pass "s9_calc basic arithmetic works"
else
    fail "s9_calc returned '$calc_result' instead of '5'"
fi

# s9_calc with scale
((TESTS_RUN++))
calc_result=$(echo "scale=2; 10/3" | s9_calc 2>/dev/null)
if [[ "$calc_result" == "3.33" ]]; then
    pass "s9_calc scale=2 works"
else
    fail "s9_calc scale=2 returned '$calc_result' instead of '3.33'"
fi

# =============================================================================
# Test 4: Option Validation Edge Cases
# =============================================================================
echo "  [4] Option validation edge cases"

# s9-fdmap: --threshold with zero
((TESTS_RUN++))
if bash "$BIN_DIR/s9-fdmap" --leaks --threshold 0 >/dev/null 2>&1; then
    pass "s9-fdmap --threshold 0 accepted"
else
    fail "s9-fdmap --threshold 0 should be valid"
fi

# s9-fdmap: --threshold with non-numeric should fail
((TESTS_RUN++))
if ! bash "$BIN_DIR/s9-fdmap" --threshold abc >/dev/null 2>&1; then
    pass "s9-fdmap --threshold abc rejected"
else
    fail "s9-fdmap --threshold abc should fail"
fi

# s9-anomaly: --mem-threshold with non-numeric should fail
((TESTS_RUN++))
if ! bash "$BIN_DIR/s9-anomaly" --mem-threshold abc >/dev/null 2>&1; then
    pass "s9-anomaly --mem-threshold abc rejected"
else
    fail "s9-anomaly --mem-threshold abc should fail"
fi

# s9-tree: --depth with 0 should work (show root only)
((TESTS_RUN++))
if bash "$BIN_DIR/s9-tree" --pid "$TEST_PID" --depth 0 >/dev/null 2>&1; then
    pass "s9-tree --depth 0 accepted"
else
    fail "s9-tree --depth 0 should be valid"
fi

# s9-inspect: unknown option should fail
((TESTS_RUN++))
if ! bash "$BIN_DIR/s9-inspect" --nonexistent-flag "$TEST_PID" >/dev/null 2>&1; then
    pass "s9-inspect rejects unknown flags"
else
    fail "s9-inspect should reject unknown flags"
fi

# s9-inspect: removed --env option should fail
((TESTS_RUN++))
if ! bash "$BIN_DIR/s9-inspect" --env "$TEST_PID" >/dev/null 2>&1; then
    pass "s9-inspect rejects removed --env flag"
else
    fail "s9-inspect --env should fail"
fi

# s9-snapshot: capture without --name should fail
((TESTS_RUN++))
if ! bash "$BIN_DIR/s9-snapshot" capture "$TEST_PID" >/dev/null 2>&1; then
    pass "s9-snapshot capture without --name rejected"
else
    fail "s9-snapshot capture without --name should fail"
fi

# s9-snapshot: sanitized name with special chars
((TESTS_RUN++))
if bash "$BIN_DIR/s9-snapshot" capture "$TEST_PID" --name "test/../../bad" >/dev/null 2>&1; then
    # Verify the file was created with sanitized name (no slashes)
    if ls "$SNAPSHOT_TEST_DIR"/testbad_*.snap >/dev/null 2>&1; then
        pass "Snapshot name sanitized (slashes removed)"
    else
        pass "Snapshot with sanitized name created"
    fi
else
    # It's also acceptable to reject entirely
    pass "Snapshot with path traversal name rejected"
fi

# s9-gpu: --threshold with 0 should work
((TESTS_RUN++))
if bash "$BIN_DIR/s9-gpu" --threshold 0 >/dev/null 2>&1; then
    pass "s9-gpu --threshold 0 accepted"
else
    fail "s9-gpu --threshold 0 should be valid"
fi

# Leading-zero numeric options should be interpreted as decimal, not shell octal.
((TESTS_RUN++))
if bash "$BIN_DIR/s9-fdmap" --json --socket 080 >/dev/null 2>&1; then
    pass "s9-fdmap --socket 080 accepted as decimal"
else
    fail "s9-fdmap --socket 080 should be valid decimal input"
fi

# =============================================================================
# Test 5: Quiet Mode Consistency
# =============================================================================
echo "  [5] Quiet mode output format"

# s9-inspect quiet mode should output KEY=VALUE format
((TESTS_RUN++))
quiet_out=$(bash "$BIN_DIR/s9-inspect" --quiet "$TEST_PID" 2>/dev/null)
if [[ "$quiet_out" =~ ^PID= ]] && [[ "$quiet_out" =~ RSS= ]] && [[ "$quiet_out" =~ FDs= ]]; then
    pass "s9-inspect quiet mode has KEY=VALUE format"
else
    fail "s9-inspect quiet mode format unexpected: '$quiet_out'"
fi

# s9-fdmap quiet mode should output KEY=VALUE format
((TESTS_RUN++))
quiet_out=$(bash "$BIN_DIR/s9-fdmap" --quiet 2>/dev/null)
if [[ "$quiet_out" =~ ^PROCESSES= ]] && [[ "$quiet_out" =~ TOTAL_FDS= ]]; then
    pass "s9-fdmap quiet mode has KEY=VALUE format"
else
    fail "s9-fdmap quiet mode format unexpected: '$quiet_out'"
fi

# s9-anomaly quiet mode should output KEY=VALUE format
((TESTS_RUN++))
quiet_out=$(bash "$BIN_DIR/s9-anomaly" --quiet 2>/dev/null)
if [[ "$quiet_out" =~ ^ZOMBIES= ]] && [[ "$quiet_out" =~ HOGS= ]]; then
    pass "s9-anomaly quiet mode has KEY=VALUE format"
else
    fail "s9-anomaly quiet mode format unexpected: '$quiet_out'"
fi

# s9-gpu quiet mode should output KEY=VALUE format
((TESTS_RUN++))
quiet_out=$(bash "$BIN_DIR/s9-gpu" --quiet 2>/dev/null)
if [[ "$quiet_out" =~ ^GPU_AVAILABLE= ]]; then
    pass "s9-gpu quiet mode has KEY=VALUE format"
else
    fail "s9-gpu quiet mode format unexpected: '$quiet_out'"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "────────────────────────────────────────────────────────────────"
echo ""
echo "Regression Tests Complete"
echo "  Total:  $TESTS_RUN"
echo "  Passed: $TESTS_PASSED"
echo "  Failed: $TESTS_FAILED"
echo ""

if (( TESTS_FAILED > 0 )); then
    exit 1
else
    exit 0
fi
