#!/usr/bin/env bash

# Test Runner Script
# Version: 1.0.0
# Description: Master test runner that executes all tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Test configuration
TEST_OS="${TEST_OS:-}"
TEST_CATEGORY="${TEST_CATEGORY:-all}"
VERBOSE="${VERBOSE:-false}"

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

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

print_success() {
    echo -e "${COLOR_GREEN}✓${COLOR_RESET} $1"
}

print_error() {
    echo -e "${COLOR_RED}✗${COLOR_RESET} $1"
}

print_warning() {
    echo -e "${COLOR_YELLOW}⚠${COLOR_RESET} $1"
}

print_info() {
    echo "$1"
}

# Run shellcheck on all scripts
run_shellcheck() {
    print_info "Running shellcheck on all scripts..."

    local errors=0
    local files=$(find "$PROJECT_ROOT" -name "*.sh" -not -path "*/tests/mocks/*" -not -path "*/.git/*")

    for file in $files; do
        if ! shellcheck -x -S warning "$file" 2>/dev/null; then
            print_error "Shellcheck errors in: $file"
            errors=$((errors + 1))
        fi
    done

    if [[ $errors -eq 0 ]]; then
        print_success "Shellcheck passed"
        return 0
    else
        print_error "Shellcheck found $errors file(s) with errors"
        return 1
    fi
}

# Run unit tests
run_unit_tests() {
    print_info "Running unit tests..."

    local unit_tests=$(find "$SCRIPT_DIR/unit" -name "*.bats" -o -name "*.sh" 2>/dev/null || true)

    if [[ -z "$unit_tests" ]]; then
        print_warning "No unit tests found"
        return 0
    fi

    # Basic test execution (BATS would be used if available)
    for test in $unit_tests; do
        if [[ -x "$test" ]]; then
            if bash "$test" 2>/dev/null; then
                print_success "Passed: $(basename "$test")"
                TESTS_PASSED=$((TESTS_PASSED + 1))
            else
                print_error "Failed: $(basename "$test")"
                TESTS_FAILED=$((TESTS_FAILED + 1))
            fi
        fi
    done
}

# Run integration tests
run_integration_tests() {
    print_info "Running integration tests..."

    local integration_tests=$(find "$SCRIPT_DIR/integration" -name "*.bats" -o -name "*.sh" 2>/dev/null || true)

    if [[ -z "$integration_tests" ]]; then
        print_warning "No integration tests found"
        return 0
    fi

    for test in $integration_tests; do
        if [[ -x "$test" ]]; then
            if bash "$test" 2>/dev/null; then
                print_success "Passed: $(basename "$test")"
                TESTS_PASSED=$((TESTS_PASSED + 1))
            else
                print_error "Failed: $(basename "$test")"
                TESTS_FAILED=$((TESTS_FAILED + 1))
            fi
        fi
    done
}

# Main test execution
main() {
    print_info "=========================================="
    print_info "OS Optimization Scripts - Test Suite"
    print_info "=========================================="
    print_info ""

    # Check for shellcheck
    if ! command -v shellcheck >/dev/null 2>&1; then
        print_warning "shellcheck not found (install with: brew install shellcheck or apt-get install shellcheck)"
    else
        if ! run_shellcheck; then
            TESTS_FAILED=$((TESTS_FAILED + 1))
        else
            TESTS_PASSED=$((TESTS_PASSED + 1))
        fi
        print_info ""
    fi

    # Run unit tests
    if [[ "$TEST_CATEGORY" == "all" ]] || [[ "$TEST_CATEGORY" == "unit" ]]; then
        run_unit_tests
        print_info ""
    fi

    # Run integration tests
    if [[ "$TEST_CATEGORY" == "all" ]] || [[ "$TEST_CATEGORY" == "integration" ]]; then
        run_integration_tests
        print_info ""
    fi

    # Summary
    print_info "=========================================="
    print_info "Test Summary:"
    print_success "Passed: $TESTS_PASSED"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        print_error "Failed: $TESTS_FAILED"
    fi
    if [[ $TESTS_SKIPPED -gt 0 ]]; then
        print_warning "Skipped: $TESTS_SKIPPED"
    fi
    print_info "=========================================="

    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

main "$@"
