#!/usr/bin/env bash
#
# test_tools.sh - Integration tests for Substrata9 tools
#
# Tests all tools with various options, edge cases, and validates
# both success and error handling scenarios.
#

set -u

# Setup
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$(dirname "$TEST_DIR")/bin"

# Capture current shell PID at script start for use in tests
TEST_PID=$$

# Test Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
run_tool() {
    local tool="$1"
    local args="$2"
    local desc="$3"
    
    echo -n "    $tool $args ($desc)... "
    ((TESTS_RUN++))
    
    if "$BIN_DIR/$tool" $args >/dev/null 2>&1; then
        echo "OK"
        ((TESTS_PASSED++))
        return 0
    else
        echo "FAIL"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Test that a command fails (for error handling validation)
expect_fail() {
    local tool="$1"
    local args="$2"
    local desc="$3"
    
    echo -n "    $tool $args ($desc)... "
    ((TESTS_RUN++))
    
    if ! "$BIN_DIR/$tool" $args >/dev/null 2>&1; then
        echo "OK (expected failure)"
        ((TESTS_PASSED++))
        return 0
    else
        echo "FAIL (should have failed)"
        ((TESTS_FAILED++))
        return 1
    fi
}

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Substrata9 — Integration Tests                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# =============================================================================
# Test 1: Help and Version flags (Smoke tests)
# =============================================================================
echo "  [1] Smoke Tests (Help & Version)"
for tool in s9-inspect s9-tree s9-fdmap s9-snapshot s9-anomaly s9-compare; do
    run_tool "$tool" "--help" "Help flag"
    run_tool "$tool" "--version" "Version flag"
done

# =============================================================================
# Test 2: s9-inspect
# =============================================================================
echo "  [2] s9-inspect"
run_tool "s9-inspect" "$TEST_PID" "Inspect current shell"
run_tool "s9-inspect" "--quiet $TEST_PID" "Quiet mode"
run_tool "s9-inspect" "--full $TEST_PID" "Full inspection"
run_tool "s9-inspect" "--json $TEST_PID" "JSON output"
run_tool "s9-inspect" "-e $TEST_PID" "With environment"

# Error handling
expect_fail "s9-inspect" "999999999" "Non-existent PID"
expect_fail "s9-inspect" "not-a-pid" "Invalid PID format"

# =============================================================================
# Test 3: s9-tree
# =============================================================================
echo "  [3] s9-tree"
run_tool "s9-tree" "-d 1" "Depth limit"
run_tool "s9-tree" "--no-memory" "No memory flag"
run_tool "s9-tree" "--no-state" "No state flag"
run_tool "s9-tree" "--pid $TEST_PID" "From specific PID"
run_tool "s9-tree" "--threads" "Show threads"
run_tool "s9-tree" "--json -d 1" "JSON output"

# Error handling
expect_fail "s9-tree" "--pid 999999999" "Non-existent root PID"

# =============================================================================
# Test 4: s9-fdmap
# =============================================================================
echo "  [4] s9-fdmap"
run_tool "s9-fdmap" "--top 5" "Top 5 summary"
run_tool "s9-fdmap" "--quiet" "Quiet mode"
run_tool "s9-fdmap" "--leaks" "Leak detection"
run_tool "s9-fdmap" "--leaks --threshold 1000" "Custom threshold"
run_tool "s9-fdmap" "--json" "JSON output"

# Test file finding
tmp_file=$(mktemp)
(sleep 2 > "$tmp_file") &
bg_pid=$!
sleep 0.5
run_tool "s9-fdmap" "--file $tmp_file" "Find file user"
kill $bg_pid 2>/dev/null || true
rm -f "$tmp_file"

# =============================================================================
# Test 5: s9-snapshot
# =============================================================================
echo "  [5] s9-snapshot"
run_tool "s9-snapshot" "list" "List snapshots"

# Capture snapshot
snap_name="test_snap_${TEST_PID}"
run_tool "s9-snapshot" "capture $TEST_PID --name $snap_name" "Capture snapshot"

# Verify snapshot was created
echo -n "    Snapshot verification... "
((TESTS_RUN++))
if "$BIN_DIR/s9-snapshot" list 2>/dev/null | grep -q "$snap_name"; then
    echo "OK"
    ((TESTS_PASSED++))
else
    echo "FAIL"
    ((TESTS_FAILED++))
fi

# JSON list
run_tool "s9-snapshot" "list --json" "List JSON"

# Delete snapshot
run_tool "s9-snapshot" "delete $snap_name --force" "Delete snapshot"

# Error handling
expect_fail "s9-snapshot" "capture 999999999 --name test" "Capture non-existent PID"
expect_fail "s9-snapshot" "diff nonexistent1 nonexistent2" "Diff non-existent snapshots"

# =============================================================================
# Test 6: s9-anomaly
# =============================================================================
echo "  [6] s9-anomaly"
run_tool "s9-anomaly" "" "Full scan"
run_tool "s9-anomaly" "--quiet" "Quiet mode"
run_tool "s9-anomaly" "--zombies" "Check zombies only"
run_tool "s9-anomaly" "--hogs" "Check hogs only"
run_tool "s9-anomaly" "--states" "Check states only"
run_tool "s9-anomaly" "--orphans" "Check orphans only"
run_tool "s9-anomaly" "--mem-threshold 99" "Custom memory threshold"
run_tool "s9-anomaly" "--fd-threshold 10000" "Custom FD threshold"
run_tool "s9-anomaly" "--json" "JSON output"

# =============================================================================
# Test 7: s9-compare
# =============================================================================
echo "  [7] s9-compare"
# Compare current shell with itself (valid test case)
run_tool "s9-compare" "$TEST_PID $TEST_PID" "Compare process with itself"

# Error handling
expect_fail "s9-compare" "999999999 888888888" "Compare non-existent PIDs"

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "────────────────────────────────────────────────────────────────"
echo ""
echo "Integration Tests Complete"
echo "  Total:  $TESTS_RUN"
echo "  Passed: $TESTS_PASSED"
echo "  Failed: $TESTS_FAILED"
echo ""

if (( TESTS_FAILED > 0 )); then
    exit 1
else
    exit 0
fi
