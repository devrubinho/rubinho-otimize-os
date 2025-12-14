#!/usr/bin/env bash

# Linux Disk Cleanup Script
# Version: 1.0.0
# Description: Clean up disk space by removing unnecessary files

set -euo pipefail

# Script configuration
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_DIR="${HOME}/.os-optimize/logs"
LOG_FILE=""

# Execution flags
DRY_RUN=false
VERBOSE=false
QUIET=false
FORCE=false
MIN_AGE_DAYS=0

# Source common libraries
if [[ -f "${PROJECT_ROOT}/lib/common.sh" ]]; then
    source "${PROJECT_ROOT}/lib/common.sh"
else
    echo "Error: lib/common.sh not found" >&2
    exit 1
fi

if [[ -f "${PROJECT_ROOT}/lib/disk_analysis.sh" ]]; then
    source "${PROJECT_ROOT}/lib/disk_analysis.sh"
else
    echo "Error: lib/disk_analysis.sh not found" >&2
    exit 1
fi

if [[ -f "${PROJECT_ROOT}/lib/cleanup_preview.sh" ]]; then
    source "${PROJECT_ROOT}/lib/cleanup_preview.sh"
else
    echo "Error: lib/cleanup_preview.sh not found" >&2
    exit 1
fi

# Initialize logging
init_logging() {
    # Try system log directory first, fallback to user directory
    if [[ -w "/var/log" ]] && sudo -n true 2>/dev/null; then
        if sudo mkdir -p /var/log/os-optimize 2>/dev/null; then
            LOG_DIR="/var/log/os-optimize"
        fi
    fi

    if mkdir -p "$LOG_DIR" 2>/dev/null; then
        chmod 755 "$LOG_DIR" 2>/dev/null || true
        local timestamp=$(date +%Y%m%d-%H%M%S)
        LOG_FILE="${LOG_DIR}/cleanup-disk-${timestamp}.log"

        {
            echo "=========================================="
            echo "Linux Disk Cleanup Script - Log"
            echo "=========================================="
            echo "Timestamp: $(date)"
            echo "Kernel: $(uname -r 2>/dev/null || echo 'unknown')"
            echo "Distribution: $(cat /etc/os-release 2>/dev/null | grep "^PRETTY_NAME" | cut -d'"' -f2 || echo 'unknown')"
            echo "Hostname: $(hostname 2>/dev/null || echo 'unknown')"
            echo "User: $(whoami 2>/dev/null || echo 'unknown')"
            echo "Script Version: $SCRIPT_VERSION"
            echo "Flags: DRY_RUN=$DRY_RUN, VERBOSE=$VERBOSE, QUIET=$QUIET, FORCE=$FORCE, MIN_AGE=$MIN_AGE_DAYS"
            echo "=========================================="
            echo ""
        } >> "$LOG_FILE" 2>/dev/null || true

        log_info "Logging initialized: $LOG_FILE"
        return 0
    else
        print_warning "Cannot create log directory: $LOG_DIR (logging disabled)"
        return 1
    fi
}

# Parse command-line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run|-n)
                DRY_RUN=true
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --quiet|-q)
                QUIET=true
                shift
                ;;
            --force|-f)
                FORCE=true
                FORCE_MODE=true
                shift
                ;;
            --min-age)
                MIN_AGE_DAYS="$2"
                shift 2
                ;;
            --min-age=*)
                MIN_AGE_DAYS="${1#*=}"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Validate MIN_AGE_DAYS
    if ! [[ "$MIN_AGE_DAYS" =~ ^[0-9]+$ ]]; then
        print_error "Invalid min-age: $MIN_AGE_DAYS (must be a non-negative integer)"
        exit 1
    fi
}

# Show help message
show_help() {
    cat << EOF
Linux Disk Cleanup Script v$SCRIPT_VERSION

Usage: $0 [OPTIONS]

Options:
    --dry-run, -n          Show what would be cleaned without executing
    --verbose, -v          Show detailed output
    --quiet, -q            Suppress non-error output
    --force, -f            Skip confirmation prompts
    --min-age=N            Only clean files older than N days (default: 0)
    -h, --help             Show this help message

Description:
    Cleans up disk space by removing unnecessary files from:
    - Caches (user and system)
    - Logs
    - Temporary files
    - Browser trash
    - Downloads (if --min-age specified)
    - Package manager caches (apt, yum, dnf, pacman)
    - Node modules cache
    - Docker containers/images/volumes
    - Snap package cache
    - Old kernels (requires sudo)

Warning: Some operations are irreversible. Use --dry-run first.

EOF
}

# Clean a specific category
clean_category() {
    local category="$1"
    
    log_info "Cleaning category: $category"
    
    if delete_category_files "$category" "$MIN_AGE_DAYS"; then
        print_success "Cleaned category: $category"
        return 0
    else
        print_warning "Failed to clean category: $category"
        return 1
    fi
}

# Main execution
main() {
    # Parse arguments
    parse_arguments "$@"

    # Initialize logging
    init_logging

    # Validate OS
    if ! validate_os; then
        exit 1
    fi

    print_info "Linux Disk Cleanup Script v$SCRIPT_VERSION"
    print_info "=============================================="
    print_info ""

    if is_dry_run; then
        print_warning "DRY-RUN MODE: No files will be deleted"
        print_info ""
    fi

    if [[ "$FORCE" == "true" ]]; then
        print_warning "FORCE MODE: Confirmations disabled"
        print_info ""
    fi

    # Show cleanup preview first
    print_info "Previewing cleanup opportunities..."
    print_info ""
    show_cleanup_preview "$MIN_AGE_DAYS"

    # Confirm before proceeding (unless force or dry-run)
    if ! is_dry_run && [[ "$FORCE" != "true" ]]; then
        if ! confirm "Proceed with cleanup? (y/N)" "N"; then
            print_info "Cleanup cancelled by user"
            exit 0
        fi
        print_info ""
    fi

    # Clean each category
    local categories=$(get_cleanup_categories)
    local cleaned=0
    local failed=0

    print_info "Starting cleanup..."
    print_info ""

    for category in $categories; do
        if clean_category "$category"; then
            cleaned=$((cleaned + 1))
        else
            failed=$((failed + 1))
        fi
    done

    # Summary
    print_info ""
    print_info "=============================================="
    print_success "Cleanup completed!"
    print_info "Categories cleaned: $cleaned"
    if [[ $failed -gt 0 ]]; then
        print_warning "Categories failed: $failed"
    fi
    print_info ""

    if [[ -n "$LOG_FILE" ]]; then
        print_info "Log file: $LOG_FILE"
    fi
}

# Run main function
main "$@"

