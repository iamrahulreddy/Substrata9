#!/usr/bin/env bash
#
# test_json.sh - JSON output validation tests
#

set -u

# Setup
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$(dirname "$TEST_DIR")/bin"

# Capture current shell PID at script start for use in tests
TEST_PID=$$

# Test Counters
TESTS_RUN=0
TESTS_FAILED=0
SKIPPED=0

# Check for JSON validator
VALIDATOR=""
if command -v jq >/dev/null 2>&1; then
    VALIDATOR="jq ."
elif command -v python3 >/dev/null 2>&1; then
    VALIDATOR="python3 -m json.tool"
elif command -v python >/dev/null 2>&1; then
    VALIDATOR="python -m json.tool"
fi

echo "Testing JSON Output..."

if [[ -z "$VALIDATOR" ]]; then
    echo "Warning: No JSON validator found (jq or python). Skipping validation checks."
    echo "Only checking if commands run successfully."
fi

validate_json() {
    local tool="$1"
    local args="$2"
    local desc="$3"
    
    echo -n "  Testing $tool $args ($desc)... "
    ((TESTS_RUN++))
    
    local output
    if ! output=$("$BIN_DIR/$tool" $args 2>&1); then
        echo "FAIL (Command failed)"
        ((TESTS_FAILED++))
        return 1
    fi
    
    if [[ -n "$VALIDATOR" ]]; then
        if echo "$output" | $VALIDATOR >/dev/null 2>&1; then
            echo "OK (Valid JSON)"
            return 0
        else
            echo "FAIL (Invalid JSON)"
            # Show first few lines of invalid output for debugging
            echo "$output" | head -n 5 | sed 's/^/    /'
            ((TESTS_FAILED++))
            return 1
        fi
    else
        echo "OK (Run only)"
        return 0
    fi
}

# Test 1: s9-inspect JSON
validate_json "s9-inspect" "--json $TEST_PID" "Inspect current shell"

# Test 2: s9-tree JSON
validate_json "s9-tree" "--json -d 1" "Tree depth 1"

# Test 3: s9-fdmap JSON
validate_json "s9-fdmap" "--json --top 5" "FD summary"

# Test 4: s9-snapshot JSON
# Capture first using TEST_PID for unique naming
snap_name="json_test_${TEST_PID}"
"$BIN_DIR/s9-snapshot" capture "$TEST_PID" --name "$snap_name" --json >/dev/null
# List
validate_json "s9-snapshot" "list --json" "List snapshots"
# Delete (cleanup) - use --force to avoid interactive prompt
"$BIN_DIR/s9-snapshot" delete "$snap_name" --force --json >/dev/null 2>&1 || true

# Test 5: s9-anomaly JSON
validate_json "s9-anomaly" "--json" "Anomaly scan"

# Summary
echo ""
echo "JSON Tests Complete"
echo "Run: $TESTS_RUN"
echo "Failed: $TESTS_FAILED"

if (( TESTS_FAILED > 0 )); then
    exit 1
else
    exit 0
fi
