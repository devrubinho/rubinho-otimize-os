#!/usr/bin/env bash

# macOS Disk Cleanup Script
# Version: 1.0.0
# Description: Clean up disk space by removing unnecessary files

set -euo pipefail

SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_DIR="${HOME}/.os-optimize/logs"
LOG_FILE=""

DRY_RUN=false
VERBOSE=false
QUIET=false
FORCE=false
MIN_AGE_DAYS=0

# ============ Library Dependencies ============
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

# ============ Logging Initialization ============

init_logging() {
    if mkdir -p "$LOG_DIR" 2>/dev/null; then
        chmod 755 "$LOG_DIR" 2>/dev/null || true
        local timestamp=$(date +%Y%m%d-%H%M%S)
        LOG_FILE="${LOG_DIR}/cleanup-disk-${timestamp}.log"

        {
            echo "=========================================="
            echo "macOS Disk Cleanup Script - Log"
            echo "=========================================="
            echo "Timestamp: $(date)"
            echo "macOS Version: $(sw_vers -productVersion 2>/dev/null || echo 'unknown')"
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

# ============ Argument Parsing ============

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

show_help() {
    cat << EOF
macOS Disk Cleanup Script v$SCRIPT_VERSION

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
    - Xcode derived data
    - Node modules cache
    - Docker volumes

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

    # Validate macOS version
    if ! validate_os; then
        exit 1
    fi

    print_info "macOS Disk Cleanup Script v$SCRIPT_VERSION"
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

    # Note: Use analyze-disk.sh to preview what will be cleaned
    if ! is_dry_run && [[ "$FORCE" != "true" ]]; then
        print_info "Note: Use 'analyze-disk.sh' to preview disk usage before cleaning"
        print_info ""
    fi

    # Clean each category with individual confirmation
    local categories=$(get_cleanup_categories)
    local cleaned=0
    local failed=0

    print_info "Starting cleanup..."
    print_info ""

    for category in $categories; do
        # Ask for confirmation for each category (unless force or dry-run)
        if ! is_dry_run && [[ "$FORCE" != "true" ]]; then
            # Get category path for display
            local category_path=""
            if command -v get_category_path >/dev/null 2>&1; then
                category_path=$(get_category_path "$category")
            fi

            # Special handling for categories without single path
            if [[ -z "$category_path" ]]; then
                case "$category" in
                    node_modules)
                        category_path="Multiple project directories"
                        ;;
                    volumes)
                        category_path="Docker volumes (unused only)"
                        ;;
                    build_artifacts)
                        category_path="Multiple project directories"
                        ;;
                    *)
                        category_path="Various locations"
                        ;;
                esac
            fi

            # Format category name for display
            local category_display="$category"
            case "$category" in
                browser_trash)
                    category_display="Browser Trash"
                    ;;
                node_modules)
                    category_display="node_modules"
                    ;;
                build_artifacts)
                    category_display="Build Artifacts"
                    ;;
                orphaned_apps)
                    category_display="Orphaned Apps (Deleted Apps Configs)"
                    ;;
                *)
                    category_display=$(echo "$category" | sed 's/_/ /g' | awk '{for(i=1;i<=NF;i++)sub(/./,toupper(substr($i,1,1)),$i)}1')
                    ;;
            esac

            if ! confirm "Clean category: $category_display ($category_path)? (y/N)" "N"; then
                print_info "Skipping category: $category"
                continue
            fi
        fi

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
