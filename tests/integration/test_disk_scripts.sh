#!/usr/bin/env bash

# Integration tests for disk analysis and cleanup scripts
# Version: 1.0.0

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"

# Source test utilities if available
if [[ -f "${TEST_DIR}/test_utils.sh" ]]; then
    source "${TEST_DIR}/test_utils.sh"
fi

# Test configuration
TEST_LOG="${TEST_DIR}/test_disk_scripts.log"
PASSED=0
FAILED=0

# Color codes
if command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; then
    COLOR_GREEN=$(tput setaf 2 2>/dev/null || echo '')
    COLOR_RED=$(tput setaf 1 2>/dev/null || echo '')
    COLOR_RESET=$(tput sgr0 2>/dev/null || echo '')
else
    COLOR_GREEN='\033[0;32m'
    COLOR_RED='\033[0;31m'
    COLOR_RESET='\033[0m'
fi

# Test result tracking
test_pass() {
    local test_name="$1"
    echo -e "${COLOR_GREEN}✓ PASS${COLOR_RESET}: $test_name"
    PASSED=$((PASSED + 1))
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] PASS: $test_name" >> "$TEST_LOG"
}

test_fail() {
    local test_name="$1"
    local reason="$2"
    echo -e "${COLOR_RED}✗ FAIL${COLOR_RESET}: $test_name - $reason"
    FAILED=$((FAILED + 1))
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] FAIL: $test_name - $reason" >> "$TEST_LOG"
}

# Test disk analysis library functions
test_disk_analysis_library() {
    echo "Testing disk analysis library..."

    # Test format_bytes
    if [[ -f "${PROJECT_ROOT}/lib/disk_analysis.sh" ]]; then
        source "${PROJECT_ROOT}/lib/disk_analysis.sh"

        local result=$(format_bytes 1024)
        if [[ -n "$result" ]]; then
            test_pass "format_bytes function exists and returns output"
        else
            test_fail "format_bytes function" "does not return output"
        fi
    else
        test_fail "lib/disk_analysis.sh" "file not found"
    fi
}

# Test cleanup preview library functions
test_cleanup_preview_library() {
    echo "Testing cleanup preview library..."

    if [[ -f "${PROJECT_ROOT}/lib/cleanup_preview.sh" ]]; then
        source "${PROJECT_ROOT}/lib/cleanup_preview.sh"

        local categories=$(get_cleanup_categories)
        if [[ -n "$categories" ]]; then
            test_pass "get_cleanup_categories returns categories"
        else
            test_fail "get_cleanup_categories" "returns empty result"
        fi
    else
        test_fail "lib/cleanup_preview.sh" "file not found"
    fi
}

# Test analyze-disk.sh script
test_analyze_disk_script() {
    echo "Testing analyze-disk.sh script..."

    local os_type=$(uname -s)
    local script_path=""

    if [[ "$os_type" == "Darwin" ]]; then
        script_path="${PROJECT_ROOT}/mac/analyze-disk.sh"
    elif [[ "$os_type" == "Linux" ]]; then
        script_path="${PROJECT_ROOT}/linux/analyze-disk.sh"
    else
        test_fail "analyze-disk.sh" "unsupported OS: $os_type"
        return
    fi

    if [[ ! -f "$script_path" ]]; then
        test_fail "analyze-disk.sh" "script not found: $script_path"
        return
    fi

    if [[ ! -x "$script_path" ]]; then
        test_fail "analyze-disk.sh" "script not executable"
        return
    fi

    # Test --help flag
    if bash "$script_path" --help 2>&1 | grep -q "Usage:"; then
        test_pass "analyze-disk.sh --help works"
    else
        test_fail "analyze-disk.sh --help" "does not show help"
    fi

    # Test --dry-run flag
    if bash "$script_path" --dry-run --quiet 2>&1 | grep -q "DRY-RUN\|dry-run\|Disk Analysis"; then
        test_pass "analyze-disk.sh --dry-run works"
    else
        test_fail "analyze-disk.sh --dry-run" "does not work correctly"
    fi
}

# Test cleanup-disk.sh script
test_cleanup_disk_script() {
    echo "Testing cleanup-disk.sh script..."

    local os_type=$(uname -s)
    local script_path=""

    if [[ "$os_type" == "Darwin" ]]; then
        script_path="${PROJECT_ROOT}/mac/cleanup-disk.sh"
    elif [[ "$os_type" == "Linux" ]]; then
        script_path="${PROJECT_ROOT}/linux/cleanup-disk.sh"
    else
        test_fail "cleanup-disk.sh" "unsupported OS: $os_type"
        return
    fi

    if [[ ! -f "$script_path" ]]; then
        test_fail "cleanup-disk.sh" "script not found: $script_path"
        return
    fi

    if [[ ! -x "$script_path" ]]; then
        test_fail "cleanup-disk.sh" "script not executable"
        return
    fi

    # Test --help flag
    if bash "$script_path" --help 2>&1 | grep -q "Usage:"; then
        test_pass "cleanup-disk.sh --help works"
    else
        test_fail "cleanup-disk.sh --help" "does not show help"
    fi

    # Test --dry-run flag (with force to skip confirmation)
    if bash "$script_path" --dry-run --force --quiet 2>&1 | grep -q "DRY-RUN\|dry-run\|Disk Cleanup"; then
        test_pass "cleanup-disk.sh --dry-run works"
    else
        test_fail "cleanup-disk.sh --dry-run" "does not work correctly"
    fi
}

# Test platform detection compatibility
test_platform_detection() {
    echo "Testing platform detection..."

    if [[ -f "${PROJECT_ROOT}/lib/common.sh" ]]; then
        source "${PROJECT_ROOT}/lib/common.sh"

        if command -v is_macos >/dev/null 2>&1 || type is_macos >/dev/null 2>&1; then
            test_pass "is_macos() function exists"
        else
            test_fail "is_macos() function" "not found"
        fi

        if command -v is_linux >/dev/null 2>&1 || type is_linux >/dev/null 2>&1; then
            test_pass "is_linux() function exists"
        else
            test_fail "is_linux() function" "not found"
        fi

        if [[ -n "${PLATFORM:-}" ]]; then
            test_pass "PLATFORM variable is set"
        else
            test_fail "PLATFORM variable" "not set"
        fi
    else
        test_fail "lib/common.sh" "file not found"
    fi
}

# Test script integration with libraries
test_library_integration() {
    echo "Testing library integration..."

    local os_type=$(uname -s)
    local analyze_script=""
    local cleanup_script=""

    if [[ "$os_type" == "Darwin" ]]; then
        analyze_script="${PROJECT_ROOT}/mac/analyze-disk.sh"
        cleanup_script="${PROJECT_ROOT}/mac/cleanup-disk.sh"
    elif [[ "$os_type" == "Linux" ]]; then
        analyze_script="${PROJECT_ROOT}/linux/analyze-disk.sh"
        cleanup_script="${PROJECT_ROOT}/linux/cleanup-disk.sh"
    else
        test_fail "library integration" "unsupported OS: $os_type"
        return
    fi

    # Test that scripts can source libraries without errors
    if bash -n "$analyze_script" 2>/dev/null; then
        test_pass "analyze-disk.sh syntax is valid"
    else
        test_fail "analyze-disk.sh syntax" "contains errors"
    fi

    if bash -n "$cleanup_script" 2>/dev/null; then
        test_pass "cleanup-disk.sh syntax is valid"
    else
        test_fail "cleanup-disk.sh syntax" "contains errors"
    fi
}

# Run all tests
main() {
    echo "=========================================="
    echo "Disk Scripts Integration Tests"
    echo "=========================================="
    echo ""

    # Initialize test log
    echo "Test started: $(date)" > "$TEST_LOG"
    echo "" >> "$TEST_LOG"

    # Run tests
    test_platform_detection
    test_disk_analysis_library
    test_cleanup_preview_library
    test_analyze_disk_script
    test_cleanup_disk_script
    test_library_integration

    # Summary
    echo ""
    echo "=========================================="
    echo "Test Summary"
    echo "=========================================="
    echo -e "${COLOR_GREEN}Passed: $PASSED${COLOR_RESET}"
    echo -e "${COLOR_RED}Failed: $FAILED${COLOR_RESET}"
    echo "Total: $((PASSED + FAILED))"
    echo ""

    # Write summary to log
    echo "" >> "$TEST_LOG"
    echo "Test completed: $(date)" >> "$TEST_LOG"
    echo "Passed: $PASSED" >> "$TEST_LOG"
    echo "Failed: $FAILED" >> "$TEST_LOG"

    if [[ $FAILED -eq 0 ]]; then
        echo "All tests passed!"
        exit 0
    else
        echo "Some tests failed. See $TEST_LOG for details."
        exit 1
    fi
}

# Run main function
main "$@"
