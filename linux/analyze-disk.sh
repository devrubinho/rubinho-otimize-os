#!/usr/bin/env bash

# Linux Disk Analysis Script
# Version: 1.0.0
# Description: Analyze disk usage and identify cleanup opportunities

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
ITEMS_COUNT=20

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
        LOG_FILE="${LOG_DIR}/analyze-disk-${timestamp}.log"

        {
            echo "=========================================="
            echo "Linux Disk Analysis Script - Log"
            echo "=========================================="
            echo "Timestamp: $(date)"
            echo "Kernel: $(uname -r 2>/dev/null || echo 'unknown')"
            echo "Distribution: $(cat /etc/os-release 2>/dev/null | grep "^PRETTY_NAME" | cut -d'"' -f2 || echo 'unknown')"
            echo "Hostname: $(hostname 2>/dev/null || echo 'unknown')"
            echo "User: $(whoami 2>/dev/null || echo 'unknown')"
            echo "Script Version: $SCRIPT_VERSION"
            echo "Flags: DRY_RUN=$DRY_RUN, VERBOSE=$VERBOSE, QUIET=$QUIET, ITEMS=$ITEMS_COUNT"
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
            --items)
                ITEMS_COUNT="$2"
                shift 2
                ;;
            --items=*)
                ITEMS_COUNT="${1#*=}"
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

    # Validate ITEMS_COUNT
    if ! [[ "$ITEMS_COUNT" =~ ^[0-9]+$ ]] || [[ "$ITEMS_COUNT" -lt 1 ]]; then
        print_error "Invalid items count: $ITEMS_COUNT (must be a positive integer)"
        exit 1
    fi
}

# Show help message
show_help() {
    cat << EOF
Linux Disk Analysis Script v$SCRIPT_VERSION

Usage: $0 [OPTIONS]

Options:
    --dry-run, -n          Show what would be analyzed without executing
    --verbose, -v          Show detailed output
    --quiet, -q            Suppress non-error output
    --items=N              Show top N items (default: 20)
    -h, --help             Show this help message

Description:
    Analyzes disk usage and identifies cleanup opportunities by:
    - Analyzing categorized disk usage (caches, logs, downloads, etc.)
    - Showing top N largest files and folders
    - Identifying cleanup opportunities

EOF
}

# Get top N largest items (files and folders combined)
get_top_items() {
    local root_path="${1:-/}"
    local count="${2:-20}"
    local items=()

    print_info "Scanning for largest items in $root_path..."

    # Find largest directories
    if command -v du >/dev/null 2>&1; then
        # Use du for directories
        while IFS= read -r line; do
            [[ -n "$line" ]] && items+=("$line")
        done < <(du -h -d 1 "$root_path" 2>/dev/null 2>&1 | sort -rh | head -n $count | awk '{print $1 "|" $2 "|dir"}')

        # Find largest files (limit depth to avoid too many results)
        while IFS= read -r line; do
            [[ -n "$line" ]] && items+=("$line")
        done < <(find "$root_path" -maxdepth 3 -type f -exec du -h {} \; 2>/dev/null | sort -rh | head -n $count | awk '{print $1 "|" $2 "|file"}')
    fi

    # Sort all items by size (approximate)
    printf '%s\n' "${items[@]}" | head -n $count
}

# Display categorized analysis
display_categorized_analysis() {
    print_info ""
    print_info "=========================================="
    print_info "Categorized Disk Usage Analysis"
    print_info "=========================================="
    print_info ""

    local categories=$(get_disk_categories)
    local total_size=0

    printf "%-20s %-50s %15s %15s\n" "Category" "Path" "Size" "Files"
    echo "--------------------------------------------------------------------------------"

    for category in $categories; do
        local path=$(get_category_path "$category")
        
        if [[ -z "$path" ]] || [[ ! -e "$path" ]]; then
            continue
        fi

        local result=$(analyze_disk_usage "$path" "$category")
        if [[ -n "$result" ]]; then
            IFS='|' read -r cat_name path size size_formatted size_mb file_count dir_count <<< "$result"
            printf "%-20s %-50s %15s %15s\n" "$cat_name" "$path" "$size_formatted" "$file_count"
            total_size=$((total_size + size))
        fi
    done

    echo "--------------------------------------------------------------------------------"
    
    local total_formatted=$(format_bytes "$total_size")
    printf "%-20s %-50s %15s %15s\n" "TOTAL" "" "$total_formatted" ""
    print_info ""
}

# Display top N largest items
display_top_items() {
    local count="$1"
    
    print_info "=========================================="
    print_info "Top $count Largest Items (Files & Folders)"
    print_info "=========================================="
    print_info ""

    # Analyze home directory
    local home_items=$(get_top_items "${HOME}" "$count")
    
    printf "%-15s %-60s %10s\n" "Size" "Path" "Type"
    echo "--------------------------------------------------------------------------------"

    local item_count=0
    while IFS='|' read -r size path type && [[ $item_count -lt $count ]]; do
        # Truncate long paths
        local display_path="$path"
        if [[ ${#display_path} -gt 58 ]]; then
            display_path="...${display_path: -55}"
        fi

        printf "%-15s %-60s %10s\n" "$size" "$display_path" "$type"
        item_count=$((item_count + 1))
    done <<< "$home_items"

    print_info ""
}

# Display cleanup opportunities
display_cleanup_opportunities() {
    print_info "=========================================="
    print_info "Cleanup Opportunities"
    print_info "=========================================="
    print_info ""

    local categories=$(get_cleanup_categories)
    local opportunities=()

    for category in $categories; do
        local path=$(get_category_path "$category")
        
        if [[ -z "$path" ]] || [[ ! -e "$path" ]]; then
            continue
        fi

        local result=$(analyze_disk_usage "$path" "$category")
        if [[ -n "$result" ]]; then
            IFS='|' read -r cat_name path size size_formatted size_mb file_count dir_count <<< "$result"
            
            # Highlight if size is above threshold (100MB default)
            if [[ $size_mb -ge ${HIGHLIGHT_THRESHOLD:-100} ]]; then
                opportunities+=("$cat_name|$path|$size_formatted|$size_mb")
            fi
        fi
    done

    if [[ ${#opportunities[@]} -eq 0 ]]; then
        print_info "No significant cleanup opportunities found."
        print_info ""
        return
    fi

    printf "%-20s %-50s %15s\n" "Category" "Path" "Size"
    echo "--------------------------------------------------------------------------------"

    for opp in "${opportunities[@]}"; do
        IFS='|' read -r cat_name path size_formatted size_mb <<< "$opp"
        
        # Truncate long paths
        local display_path="$path"
        if [[ ${#display_path} -gt 48 ]]; then
            display_path="...${display_path: -45}"
        fi

        printf "%-20s %-50s %15s\n" "$cat_name" "$display_path" "$size_formatted"
    done

    print_info ""
    print_info "Tip: Use cleanup-disk.sh to clean these categories"
    print_info ""
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

    print_info "Linux Disk Analysis Script v$SCRIPT_VERSION"
    print_info "=============================================="
    print_info ""

    if is_dry_run; then
        print_warning "DRY-RUN MODE: No changes will be made"
        print_info ""
    fi

    # Display categorized analysis
    display_categorized_analysis

    # Display top N largest items
    display_top_items "$ITEMS_COUNT"

    # Display cleanup opportunities
    display_cleanup_opportunities

    # Summary
    print_info "=============================================="
    print_success "Disk analysis completed!"
    print_info ""

    if [[ -n "$LOG_FILE" ]]; then
        print_info "Log file: $LOG_FILE"
    fi
}

# Run main function
main "$@"

