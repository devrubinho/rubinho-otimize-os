#!/usr/bin/env bash

# OS Optimization Scripts - Main Entry Point
# Version: 1.0.0
# Description: Interactive menu for selecting optimization operations

set -euo pipefail

SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes
if command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; then
    COLOR_GREEN=$(tput setaf 2 2>/dev/null || echo '')
    COLOR_YELLOW=$(tput setaf 3 2>/dev/null || echo '')
    COLOR_RED=$(tput setaf 1 2>/dev/null || echo '')
    COLOR_BLUE=$(tput setaf 4 2>/dev/null || echo '')
    COLOR_RESET=$(tput sgr0 2>/dev/null || echo '')
else
    COLOR_GREEN='\033[0;32m'
    COLOR_YELLOW='\033[1;33m'
    COLOR_RED='\033[0;31m'
    COLOR_BLUE='\033[0;34m'
    COLOR_RESET='\033[0m'
fi

# OS detection
OS_TYPE=""
OS_DIR=""

# Execution flags
DRY_RUN=false
VERBOSE=false
QUIET=false
AGGRESSIVE=false

# Helper functions
print_success() {
    echo -e "${COLOR_GREEN}✓${COLOR_RESET} $1"
}

print_warning() {
    echo -e "${COLOR_YELLOW}⚠${COLOR_RESET} $1"
}

print_error() {
    echo -e "${COLOR_RED}✗${COLOR_RESET} $1"
}

print_info() {
    echo -e "$1"
}

# Detect OS
detect_os() {
    OS_TYPE=$(uname -s)

    case "$OS_TYPE" in
        Darwin)
            OS_DIR="mac"
            ;;
        Linux)
            OS_DIR="linux"
            ;;
        *)
            print_error "Unsupported operating system: $OS_TYPE"
            print_info "Supported systems: macOS (Darwin) and Linux"
            exit 1
            ;;
    esac

    # Validate platform directory exists
    if [[ ! -d "${SCRIPT_DIR}/${OS_DIR}" ]]; then
        print_error "Platform directory not found: ${SCRIPT_DIR}/${OS_DIR}"
        exit 2
    fi
}

# Parse command-line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            -a|--aggressive)
                AGGRESSIVE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            --version)
                show_version
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Validate flag combinations
    if [[ "$QUIET" == "true" ]] && [[ "$VERBOSE" == "true" ]]; then
        print_error "--quiet and --verbose are mutually exclusive"
        exit 1
    fi
}

# Show help
show_help() {
    cat << EOF
OS Optimization Scripts - Main Entry Point

Usage: $0 [OPTIONS]

Options:
    -n, --dry-run      Preview actions without executing
    -v, --verbose      Show detailed logs
    -q, --quiet        Suppress progress output
    -a, --aggressive   Enable aggressive cleaning
    -h, --help         Show this help message
    --version          Show version information

Description:
    Interactive menu for selecting optimization operations:
    1. Clean Memory Only
    2. Optimize CPU Only
    3. Combined Optimization (Memory + CPU)
    4. View Logs
    5. Performance Dashboard
    6. Rollback System
    7. Uninstall
    8. Exit

Examples:
    $0                  # Interactive mode
    $0 --dry-run        # Preview mode
    $0 --aggressive     # Aggressive mode
EOF
}

# Show version
show_version() {
    echo "OS Optimization Scripts v$SCRIPT_VERSION"
}

# Build script arguments
build_script_args() {
    local args=""

    if [[ "$DRY_RUN" == "true" ]]; then
        args="${args} --dry-run"
    fi

    if [[ "$VERBOSE" == "true" ]]; then
        args="${args} --verbose"
    fi

    if [[ "$QUIET" == "true" ]]; then
        args="${args} --quiet"
    fi

    if [[ "$AGGRESSIVE" == "true" ]]; then
        args="${args} --aggressive"
    fi

    echo "$args"
}

# Execute script
execute_script() {
    local script_name="$1"
    local script_path="${SCRIPT_DIR}/${OS_DIR}/${script_name}"

    # Validate script exists and is executable
    if [[ ! -x "$script_path" ]]; then
        print_error "Script not found or not executable: $script_path"
        exit 2
    fi

    print_info ""
    print_info "Executing: ${OS_DIR}/${script_name}"
    print_info "=========================================="
    print_info ""

    # Build arguments
    local script_args=$(build_script_args)

    # Execute script
    set +e  # Disable exit on error for menu loop
    bash "$script_path" $script_args
    local exit_code=$?
    set -e  # Re-enable exit on error

    print_info ""
    print_info "=========================================="

    if [[ $exit_code -eq 0 ]]; then
        print_success "Operation completed successfully!"
    else
        print_error "Operation failed with exit code: $exit_code"
    fi

    print_info ""
    print_info "Press Enter to continue..."
    read -r
}

# Execute utility script
execute_utility() {
    local script_name="$1"
    local script_path="${SCRIPT_DIR}/scripts/${script_name}"

    # Validate script exists and is executable
    if [[ ! -x "$script_path" ]]; then
        print_error "Script not found or not executable: $script_path"
        exit 2
    fi

    print_info ""
    print_info "Executing: scripts/${script_name}"
    print_info "=========================================="
    print_info ""

    # Execute script (utilities handle their own arguments)
    set +e  # Disable exit on error for menu loop
    bash "$script_path" "${@:2}"
    local exit_code=$?
    set -e  # Re-enable exit on error

    print_info ""
    print_info "=========================================="

    if [[ $exit_code -eq 0 ]]; then
        print_success "Operation completed successfully!"
    else
        print_error "Operation failed with exit code: $exit_code"
    fi

    print_info ""
    print_info "Press Enter to continue..."
    read -r
}

# Interactive menu
show_menu() {
    while true; do
        clear 2>/dev/null || true

        print_info "OS Optimization Scripts"
        print_info "======================="
        print_info "Detected OS: $OS_TYPE"
        print_info ""
        print_info "Select an optimization to run:"
        print_info ""
        print_info "1) Clean Memory Only"
        print_info "   - Clears inactive memory and caches"
        print_info ""
        print_info "2) Optimize CPU Only"
        print_info "   - Identifies and manages CPU-intensive processes"
        print_info ""
        print_info "3) Combined Optimization (Memory + CPU)"
        print_info "   - Full system optimization with progress reporting"
        print_info ""
        print_info "4) View Logs"
        print_info "   - Browse and filter optimization logs"
        print_info ""
        print_info "5) Performance Dashboard"
        print_info "   - Real-time system metrics and statistics"
        print_info ""
        print_info "6) Rollback System"
        print_info "   - Restore system from previous snapshot"
        print_info ""
        print_info "7) Uninstall"
        print_info "   - Remove all installed components"
        print_info ""
        print_info "8) Exit"
        print_info ""

        # Check sudo warning
        if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
            print_warning "Some operations may require sudo access"
            print_info ""
        fi

        # Show active flags
        if [[ "$DRY_RUN" == "true" ]] || [[ "$AGGRESSIVE" == "true" ]] || [[ "$VERBOSE" == "true" ]]; then
            print_info "Active flags:"
            [[ "$DRY_RUN" == "true" ]] && print_info "  --dry-run"
            [[ "$AGGRESSIVE" == "true" ]] && print_info "  --aggressive"
            [[ "$VERBOSE" == "true" ]] && print_info "  --verbose"
            print_info ""
        fi

        PS3="Select an option (1-8): "
        select choice in "Clean Memory Only" "Optimize CPU Only" "Combined Optimization (Memory + CPU)" "View Logs" "Performance Dashboard" "Rollback System" "Uninstall" "Exit"; do
            case $REPLY in
                1)
                    execute_script "clean-memory.sh"
                    break
                    ;;
                2)
                    execute_script "optimize-cpu.sh"
                    break
                    ;;
                3)
                    execute_script "optimize-all.sh"
                    break
                    ;;
                4)
                    execute_utility "view-logs.sh"
                    break
                    ;;
                5)
                    execute_utility "dashboard.sh"
                    break
                    ;;
                6)
                    execute_utility "rollback.sh"
                    break
                    ;;
                7)
                    execute_utility "uninstall.sh"
                    break
                    ;;
                8)
                    print_info "Exiting..."
                    exit 0
                    ;;
                *)
                    print_error "Invalid selection. Please choose 1-8."
                    sleep 1
                    break
                    ;;
            esac
        done
    done
}

# Main execution
main() {
    # Parse arguments
    parse_arguments "$@"

    # Detect OS
    detect_os

    # Trap SIGINT
    trap 'print_info ""; print_info "Exiting..."; exit 0' SIGINT

    # Show menu
    show_menu
}

# Run main function
main "$@"
