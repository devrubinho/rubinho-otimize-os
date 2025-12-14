#!/usr/bin/env bash

# Platform Parity Testing Script
# Version: 1.0.0
# Description: Verify functional equivalence between macOS and Linux scripts

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"

# Expected scripts
REQUIRED_SCRIPTS=(
    "clean-memory.sh"
    "optimize-cpu.sh"
    "optimize-all.sh"
    "analyze-disk.sh"
    "cleanup-disk.sh"
)

# Test results
PASSED=0
FAILED=0
WARNINGS=0

# Color codes
if command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; then
    COLOR_GREEN=$(tput setaf 2 2>/dev/null || echo '')
    COLOR_RED=$(tput setaf 1 2>/dev/null || echo '')
    COLOR_YELLOW=$(tput setaf 3 2>/dev/null || echo '')
    COLOR_RESET=$(tput sgr0 2>/dev/null || echo '')
else
    COLOR_GREEN='\033[0;32m'
    COLOR_RED='\033[0;31m'
    COLOR_YELLOW='\033[1;33m'
    COLOR_RESET='\033[0m'
fi

test_pass() {
    local test_name="$1"
    echo -e "${COLOR_GREEN}✓ PASS${COLOR_RESET}: $test_name"
    PASSED=$((PASSED + 1))
}

test_fail() {
    local test_name="$1"
    local reason="$2"
    echo -e "${COLOR_RED}✗ FAIL${COLOR_RESET}: $test_name - $reason"
    FAILED=$((FAILED + 1))
}

test_warn() {
    local test_name="$1"
    local reason="$2"
    echo -e "${COLOR_YELLOW}⚠ WARN${COLOR_RESET}: $test_name - $reason"
    WARNINGS=$((WARNINGS + 1))
}

# Test that all required scripts exist
test_script_existence() {
    echo "Testing script existence..."

    for script in "${REQUIRED_SCRIPTS[@]}"; do
        local mac_script="${PROJECT_ROOT}/mac/${script}"
        local linux_script="${PROJECT_ROOT}/linux/${script}"

        if [[ -f "$mac_script" ]]; then
            test_pass "macOS script exists: $script"
        else
            test_fail "macOS script exists: $script" "File not found"
        fi

        if [[ -f "$linux_script" ]]; then
            test_pass "Linux script exists: $script"
        else
            test_fail "Linux script exists: $script" "File not found"
        fi
    done
    echo ""
}

# Test that scripts are executable
test_script_executability() {
    echo "Testing script executability..."

    for script in "${REQUIRED_SCRIPTS[@]}"; do
        local mac_script="${PROJECT_ROOT}/mac/${script}"
        local linux_script="${PROJECT_ROOT}/linux/${script}"

        if [[ -x "$mac_script" ]]; then
            test_pass "macOS script executable: $script"
        else
            test_fail "macOS script executable: $script" "Not executable"
        fi

        if [[ -x "$linux_script" ]]; then
            test_pass "Linux script executable: $script"
        else
            test_fail "Linux script executable: $script" "Not executable"
        fi
    done
    echo ""
}

# Test script headers and shebang
test_script_headers() {
    echo "Testing script headers..."

    for script in "${REQUIRED_SCRIPTS[@]}"; do
        local mac_script="${PROJECT_ROOT}/mac/${script}"
        local linux_script="${PROJECT_ROOT}/linux/${script}"

        # Check shebang
        if head -1 "$mac_script" 2>/dev/null | grep -q "^#!/usr/bin/env bash"; then
            test_pass "macOS shebang correct: $script"
        else
            test_fail "macOS shebang correct: $script" "Invalid shebang"
        fi

        if head -1 "$linux_script" 2>/dev/null | grep -q "^#!/usr/bin/env bash"; then
            test_pass "Linux shebang correct: $script"
        else
            test_fail "Linux shebang correct: $script" "Invalid shebang"
        fi

        # Check for version info
        if grep -q "Version:" "$mac_script" 2>/dev/null; then
            test_pass "macOS version info: $script"
        else
            test_warn "macOS version info: $script" "Version not found"
        fi

        if grep -q "Version:" "$linux_script" 2>/dev/null; then
            test_pass "Linux version info: $script"
        else
            test_warn "Linux version info: $script" "Version not found"
        fi
    done
    echo ""
}

# Test CLI interface parity
test_cli_parity() {
    echo "Testing CLI interface parity..."

    # analyze-disk.sh flags
    local analyze_flags=("--dry-run" "--verbose" "--quiet" "--items" "--help")
    for flag in "${analyze_flags[@]}"; do
        if bash "${PROJECT_ROOT}/mac/analyze-disk.sh" --help 2>&1 | grep -q "$flag"; then
            test_pass "macOS analyze-disk.sh has flag: $flag"
        else
            test_warn "macOS analyze-disk.sh has flag: $flag" "Flag not found in help"
        fi

        if bash "${PROJECT_ROOT}/linux/analyze-disk.sh" --help 2>&1 | grep -q "$flag"; then
            test_pass "Linux analyze-disk.sh has flag: $flag"
        else
            test_warn "Linux analyze-disk.sh has flag: $flag" "Flag not found in help"
        fi
    done

    # cleanup-disk.sh flags
    local cleanup_flags=("--dry-run" "--verbose" "--quiet" "--force" "--min-age" "--help")
    for flag in "${cleanup_flags[@]}"; do
        if bash "${PROJECT_ROOT}/mac/cleanup-disk.sh" --help 2>&1 | grep -q "$flag"; then
            test_pass "macOS cleanup-disk.sh has flag: $flag"
        else
            test_warn "macOS cleanup-disk.sh has flag: $flag" "Flag not found in help"
        fi

        if bash "${PROJECT_ROOT}/linux/cleanup-disk.sh" --help 2>&1 | grep -q "$flag"; then
            test_pass "Linux cleanup-disk.sh has flag: $flag"
        else
            test_warn "Linux cleanup-disk.sh has flag: $flag" "Flag not found in help"
        fi
    done
    echo ""
}

# Test library dependencies
test_library_dependencies() {
    echo "Testing library dependencies..."

    for script in "${REQUIRED_SCRIPTS[@]}"; do
        local mac_script="${PROJECT_ROOT}/mac/${script}"
        local linux_script="${PROJECT_ROOT}/linux/${script}"

        # Check if scripts source common.sh
        if grep -q "lib/common.sh" "$mac_script" 2>/dev/null; then
            test_pass "macOS script sources common.sh: $script"
        else
            test_warn "macOS script sources common.sh: $script" "common.sh not sourced"
        fi

        if grep -q "lib/common.sh" "$linux_script" 2>/dev/null; then
            test_pass "Linux script sources common.sh: $script"
        else
            test_warn "Linux script sources common.sh: $script" "common.sh not sourced"
        fi
    done
    echo ""
}

# Test syntax validity
test_syntax_validity() {
    echo "Testing script syntax validity..."

    for script in "${REQUIRED_SCRIPTS[@]}"; do
        local mac_script="${PROJECT_ROOT}/mac/${script}"
        local linux_script="${PROJECT_ROOT}/linux/${script}"

        if bash -n "$mac_script" 2>/dev/null; then
            test_pass "macOS script syntax valid: $script"
        else
            test_fail "macOS script syntax valid: $script" "Syntax errors found"
        fi

        if bash -n "$linux_script" 2>/dev/null; then
            test_pass "Linux script syntax valid: $script"
        else
            test_fail "Linux script syntax valid: $script" "Syntax errors found"
        fi
    done
    echo ""
}

# Main execution
main() {
    echo "=========================================="
    echo "Platform Parity Tests"
    echo "=========================================="
    echo ""

    test_script_existence
    test_script_executability
    test_script_headers
    test_cli_parity
    test_library_dependencies
    test_syntax_validity

    # Summary
    echo "=========================================="
    echo "Test Summary"
    echo "=========================================="
    echo -e "${COLOR_GREEN}Passed: $PASSED${COLOR_RESET}"
    echo -e "${COLOR_RED}Failed: $FAILED${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}Warnings: $WARNINGS${COLOR_RESET}"
    echo "Total: $((PASSED + FAILED + WARNINGS))"
    echo ""

    if [[ $FAILED -eq 0 ]]; then
        echo "All critical tests passed!"
        exit 0
    else
        echo "Some tests failed. Review the output above."
        exit 1
    fi
}

# Run main function
main "$@"
