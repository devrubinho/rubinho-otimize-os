#!/usr/bin/env bash

# macOS Disk Analysis Script
# Version: 1.0.0
# Description: Analyze disk usage and identify cleanup opportunities

set -euo pipefail

SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_DIR="${HOME}/.os-optimize/logs"
LOG_FILE=""

DRY_RUN=false
VERBOSE=false
QUIET=false
ITEMS_COUNT=20

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

# ============ Logging Initialization ============

init_logging() {
    if mkdir -p "$LOG_DIR" 2>/dev/null; then
        chmod 755 "$LOG_DIR" 2>/dev/null || true
        local timestamp=$(date +%Y%m%d-%H%M%S)
        LOG_FILE="${LOG_DIR}/analyze-disk-${timestamp}.log"

        {
            echo "=========================================="
            echo "macOS Disk Analysis Script - Log"
            echo "=========================================="
            echo "Timestamp: $(date)"
            echo "macOS Version: $(sw_vers -productVersion 2>/dev/null || echo 'unknown')"
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

show_help() {
    cat << EOF
macOS Disk Analysis Script v$SCRIPT_VERSION

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

# ============ Disk Analysis Functions ============

get_top_items() {
    local root_path="${1:-${HOME}}"
    local count="${2:-20}"
    local items=()

    print_info "Scanning for largest items in $root_path..."
    print_info "This may take a moment for large directories..."

    # Find largest directories (optimized - limit depth and use timeout)
    if command -v du >/dev/null 2>&1; then
        # Use du for top-level directories only (much faster)
        # Limit to depth 1 to avoid scanning entire directory tree
        local dirs_found=0
        while IFS= read -r line && [[ $dirs_found -lt $count ]]; do
            [[ -z "$line" ]] && continue
            local size=$(echo "$line" | awk '{print $1}')
            local path=$(echo "$line" | awk '{print $2}')
            # Skip if path is the root itself
            [[ "$path" == "$root_path" ]] && continue
            # Skip protected directories (.git, .claude, .cursor, .task-flow)
            local basename_path=$(basename "$path")
            if [[ "$basename_path" == ".git" ]] || \
               [[ "$basename_path" == ".claude" ]] || \
               [[ "$basename_path" == ".cursor" ]] || \
               [[ "$basename_path" == ".task-flow" ]]; then
                continue
            fi
            items+=("${size}|${path}|dir")
            dirs_found=$((dirs_found + 1))
        done < <(
            if command -v timeout >/dev/null 2>&1; then
                timeout 30 du -h -d 1 "$root_path" 2>/dev/null | sort -rh | head -n $((count * 2))
            elif command -v gtimeout >/dev/null 2>&1; then
                gtimeout 30 du -h -d 1 "$root_path" 2>/dev/null | sort -rh | head -n $((count * 2))
            else
                # Fallback: limit results immediately to prevent hanging
                du -h -d 1 "$root_path" 2>/dev/null | sort -rh | head -n $((count * 2))
            fi
        )

        # Find largest files (optimized - use du on directories, then find largest files within)
        # Strategy: Find largest directories first, then find largest files within those directories
        # This avoids scanning the entire home directory

        # Get top directories by size (already have this from above)
        # Now find largest files within the largest directories
        local files_found=0
        local top_dirs=()

        # Collect top directories (excluding the root itself)
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local dir_path=$(echo "$line" | awk -F'|' '{print $2}')
            [[ "$dir_path" == "$root_path" ]] && continue
            [[ -d "$dir_path" ]] && top_dirs+=("$dir_path")
        done < <(printf '%s\n' "${items[@]}" | grep "|dir$" | head -10)

        # Find largest files in top directories (limit to prevent hanging)
        for dir in "${top_dirs[@]}"; do
            [[ $files_found -ge $count ]] && break
            [[ ! -d "$dir" ]] && continue

            # Use find with very limited scope and timeout
            while IFS= read -r file && [[ $files_found -lt $count ]]; do
                [[ -z "$file" ]] || [[ ! -f "$file" ]] && continue

                # Get file size using stat (much faster than du)
                local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
                # Only include files larger than 50MB to focus on truly large files
                if [[ "$size" =~ ^[0-9]+$ ]] && [[ $size -gt 52428800 ]]; then
                    # Convert to human-readable format
                    local size_mb=$((size / 1024 / 1024))
                    if [[ $size_mb -ge 1024 ]]; then
                        local size_gb=$(awk "BEGIN {printf \"%.2f\", $size / 1073741824}")
                        local size_human="${size_gb}G"
                    else
                        local size_human="${size_mb}M"
                    fi
                    items+=("${size_human}|${file}|file")
                    files_found=$((files_found + 1))
                fi
            done < <(
                if command -v timeout >/dev/null 2>&1; then
                    timeout 10 find "$dir" \( -name ".git" -o -name ".claude" -o -name ".cursor" -o -name ".task-flow" \) -prune -o -maxdepth 2 -type f -size +50M -print 2>/dev/null | head -20
                elif command -v gtimeout >/dev/null 2>&1; then
                    gtimeout 10 find "$dir" \( -name ".git" -o -name ".claude" -o -name ".cursor" -o -name ".task-flow" \) -prune -o -maxdepth 2 -type f -size +50M -print 2>/dev/null | head -20
                else
                    # Fallback: use head immediately to limit results
                    find "$dir" \( -name ".git" -o -name ".claude" -o -name ".cursor" -o -name ".task-flow" \) -prune -o -maxdepth 2 -type f -size +50M -print 2>/dev/null | head -20
                fi
            )
        done
    fi

    # Sort all items by size (convert human-readable sizes to bytes for sorting)
    # Simple approach: sort by the size string (works for most cases)
    printf '%s\n' "${items[@]}" | head -n $count
}

# Format size in MB or GB (user preference)
format_size_mb() {
    local bytes="$1"
    local size_mb=$((bytes / 1024 / 1024))

    if [[ $size_mb -ge 1024 ]]; then
        # If >= 1GB, show in GB
        local size_gb=$(awk "BEGIN {printf \"%.2f\", $bytes / 1073741824}")
        echo "${size_gb} GB"
    else
        # Show in MB
        local size_mb_float=$(awk "BEGIN {printf \"%.2f\", $bytes / 1048576}")
        echo "${size_mb_float} MB"
    fi
}

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
            local size_mb_formatted=$(format_size_mb "$size")
            printf "%-20s %-50s %15s %15s\n" "$cat_name" "$path" "$size_mb_formatted" "$file_count"
            total_size=$((total_size + size))
        fi
    done

    echo "--------------------------------------------------------------------------------"

    local total_formatted=$(format_size_mb "$total_size")
    printf "%-20s %-50s %15s %15s\n" "TOTAL" "" "$total_formatted" ""
    print_info ""
}

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

    # Validate macOS version
    if ! validate_os; then
        exit 1
    fi

    print_info "macOS Disk Analysis Script v$SCRIPT_VERSION"
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
