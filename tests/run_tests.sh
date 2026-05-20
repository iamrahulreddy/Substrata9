#!/usr/bin/env bash
#
# run_tests.sh - Test runner for Substrata9
#
# Usage: ./tests/run_tests.sh [test_file]
#

# Note: Using set -uo pipefail (without -e) to allow test runner to continue
# even when individual tests fail or arithmetic operations return 0
set -uo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$TEST_DIR")"
FAILED=0
TOTAL=0
PASSED=0

# Header
echo ""
printf "%b╔════════════════════════════════════════════════════════════════════╗%b\n" "${BOLD}" "${NC}"
printf "%b║  Substrata9 — Test Suite                                           ║%b\n" "${BOLD}" "${NC}"
printf "%b╚════════════════════════════════════════════════════════════════════╝%b\n" "${BOLD}" "${NC}"
echo ""

# Dependency checks
LIB_FILE="$ROOT_DIR/lib/s9-common.sh"
if [[ ! -f "$LIB_FILE" ]]; then
    printf "%bError: Core library not found: %s%b\n" "${RED}" "$LIB_FILE" "${NC}"
    printf "%bPlease run tests from the project root directory.%b\n" "${YELLOW}" "${NC}"
    exit 1
fi

# Check if we're on a proper Linux/WSL system
if [[ ! -d "/proc" ]]; then
    printf "%bWarning: /proc not found. Tests require Linux or WSL.%b\n" "${YELLOW}" "${NC}"
fi

# Function to run a single test file
run_test_file() {
    local test_file=$1
    local test_name
    test_name=$(basename "$test_file")
    
    printf "%bRunning %s...%b\n" "${BOLD}" "$test_name" "${NC}"
    
    if bash "$test_file"; then
        printf "%b✓ PASS: %s%b\n" "${GREEN}" "$test_name" "${NC}"
        ((PASSED++))
    else
        printf "%b✗ FAIL: %s%b\n" "${RED}" "$test_name" "${NC}"
        ((FAILED++))
    fi
    ((TOTAL++))
    echo ""
}

# Main execution
if [[ $# -gt 0 ]]; then
    # Run specific test
    for arg in "$@"; do
        if [[ -f "$arg" ]]; then
            run_test_file "$arg"
        elif [[ -f "$TEST_DIR/$arg" ]]; then
            run_test_file "$TEST_DIR/$arg"
        else
            printf "%bError: Test file '%s' not found%b\n" "${RED}" "$arg" "${NC}"
            exit 1
        fi
    done
else
    # Run all tests
    while IFS= read -r test_file; do
        [[ -e "$test_file" ]] || continue
        run_test_file "$test_file"
    done < <(find "$TEST_DIR" -maxdepth 1 -name 'test_*.sh' -type f | sort)
fi

# Summary
echo ""
printf "%b────────────────────────────────────────────────────────────────────%b\n" "${BOLD}" "${NC}"
echo ""
printf "%bSummary%b\n" "${BOLD}" "${NC}"
echo ""
printf "  Total:   %b%d%b\n" "${BOLD}" "$TOTAL" "${NC}"
printf "  Passed:  %b%d%b\n" "${GREEN}" "$PASSED" "${NC}"
printf "  Failed:  %b%d%b\n" "${RED}" "$FAILED" "${NC}"
echo ""

if (( FAILED > 0 )); then
    exit 1
else
    exit 0
fi
