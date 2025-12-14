#!/usr/bin/env bash

# Cleanup Preview Library
# Version: 1.0.0
# Description: Functions for previewing and managing cleanup operations
# Usage: source lib/cleanup_preview.sh

# Source guard to prevent double-loading
if [[ -n "${CLEANUP_PREVIEW_SH_LOADED:-}" ]]; then
    return 0
fi

readonly CLEANUP_PREVIEW_SH_LOADED=1
readonly CLEANUP_PREVIEW_VERSION="1.0.0"

# Source common.sh for logging and platform detection
if [[ -z "${COMMON_SH_LOADED:-}" ]]; then
    # Try to source from same directory as this script
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "${script_dir}/common.sh" ]]; then
        source "${script_dir}/common.sh"
    else
        echo "Error: common.sh not found. Please source it before cleanup_preview.sh" >&2
        return 1
    fi
fi

# Source disk_analysis.sh if available
if [[ -z "${DISK_ANALYSIS_SH_LOADED:-}" ]]; then
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "${script_dir}/disk_analysis.sh" ]]; then
        source "${script_dir}/disk_analysis.sh"
    fi
fi

# Global flags
FORCE_MODE="${FORCE_MODE:-false}"

# Get cleanup categories based on platform
get_cleanup_categories() {
    if is_macos; then
        echo "caches logs downloads temp browser_trash xcode node_modules docker"
    elif is_linux; then
        echo "caches logs temp browser_trash apt yum pacman node_modules docker snap"
    else
        echo "caches logs temp"
    fi
}

# Scan a cleanup category for files that can be cleaned
scan_cleanup_category() {
    local category="$1"
    local min_age_days="${2:-0}"  # Default: no age filter
    local path=""

    # Get path for category
    if command -v get_category_path >/dev/null 2>&1; then
        path=$(get_category_path "$category")
    else
        # Fallback path detection
        case "$category" in
            caches)
                path=$(is_macos && echo "${HOME}/Library/Caches" || echo "${HOME}/.cache")
                ;;
            logs)
                path=$(is_macos && echo "${HOME}/Library/Logs" || echo "/var/log")
                ;;
            downloads)
                path="${HOME}/Downloads"
                ;;
            temp)
                path="/tmp"
                ;;
            browser_trash)
                path=$(is_macos && echo "${HOME}/.Trash" || echo "${HOME}/.local/share/Trash")
                ;;
            *)
                log_warn "Unknown category: $category"
                return 1
                ;;
        esac
    fi

    if [[ -z "$path" ]] || [[ ! -e "$path" ]]; then
        log_debug "Category $category: path not found ($path)"
        return 1
    fi

    log_info "Scanning category: $category ($path)"

    local files=()
    local total_size=0

    # Find files based on age filter
    if [[ $min_age_days -gt 0 ]]; then
        # Find files older than min_age_days
        local cutoff_date=$(date -v-${min_age_days}d 2>/dev/null || date -d "${min_age_days} days ago" 2>/dev/null)

        if is_macos; then
            while IFS= read -r file; do
                [[ -n "$file" ]] && files+=("$file")
            done < <(find "$path" -type f -mtime +${min_age_days} -print0 2>/dev/null | xargs -0)
        else
            while IFS= read -r file; do
                [[ -n "$file" ]] && files+=("$file")
            done < <(find "$path" -type f -mtime +${min_age_days} -print0 2>/dev/null | xargs -0)
        fi
    else
        # Find all files
        while IFS= read -r file; do
            [[ -n "$file" ]] && files+=("$file")
        done < <(find "$path" -type f -print0 2>/dev/null | xargs -0)
    fi

    # Calculate total size
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
            total_size=$((total_size + size))
        fi
    done

    # Return: category|path|file_count|total_size
    echo "${category}|${path}|${#files[@]}|${total_size}"
}

# Show cleanup preview
show_cleanup_preview() {
    local min_age_days="${1:-0}"
    local categories=$(get_cleanup_categories)

    print_info "=========================================="
    print_info "Cleanup Preview"
    print_info "=========================================="
    print_info ""

    if [[ $min_age_days -gt 0 ]]; then
        print_info "Showing files older than $min_age_days days"
    else
        print_info "Showing all cleanable files"
    fi
    print_info ""

    local total_files=0
    local total_size=0
    local results=()

    for category in $categories; do
        local result=$(scan_cleanup_category "$category" "$min_age_days")
        if [[ -n "$result" ]]; then
            IFS='|' read -r cat_name path file_count size <<< "$result"
            results+=("$result")
            total_files=$((total_files + file_count))
            total_size=$((total_size + size))
        fi
    done

    # Display results
    printf "%-20s %-40s %10s %15s\n" "Category" "Path" "Files" "Size"
    echo "--------------------------------------------------------------------------------"

    for result in "${results[@]}"; do
        IFS='|' read -r cat_name path file_count size <<< "$result"
        local size_formatted=""

        if command -v format_bytes >/dev/null 2>&1; then
            size_formatted=$(format_bytes "$size")
        else
            # Simple fallback formatting
            if [[ $size -ge 1073741824 ]]; then
                size_formatted=$(printf "%.2f GB" $(echo "scale=2; $size / 1073741824" | bc 2>/dev/null || echo "0"))
            elif [[ $size -ge 1048576 ]]; then
                size_formatted=$(printf "%.2f MB" $(echo "scale=2; $size / 1048576" | bc 2>/dev/null || echo "0"))
            elif [[ $size -ge 1024 ]]; then
                size_formatted=$(printf "%.2f KB" $(echo "scale=2; $size / 1024" | bc 2>/dev/null || echo "0"))
            else
                size_formatted="${size} B"
            fi
        fi

        # Truncate long paths
        local display_path="$path"
        if [[ ${#display_path} -gt 38 ]]; then
            display_path="...${display_path: -35}"
        fi

        printf "%-20s %-40s %10s %15s\n" "$cat_name" "$display_path" "$file_count" "$size_formatted"
    done

    echo "--------------------------------------------------------------------------------"

    # Format total size
    local total_formatted=""
    if command -v format_bytes >/dev/null 2>&1; then
        total_formatted=$(format_bytes "$total_size")
    else
        if [[ $total_size -ge 1073741824 ]]; then
            total_formatted=$(printf "%.2f GB" $(echo "scale=2; $total_size / 1073741824" | bc 2>/dev/null || echo "0"))
        elif [[ $total_size -ge 1048576 ]]; then
            total_formatted=$(printf "%.2f MB" $(echo "scale=2; $total_size / 1048576" | bc 2>/dev/null || echo "0"))
        else
            total_formatted="${total_size} B"
        fi
    fi

    printf "%-20s %-40s %10s %15s\n" "TOTAL" "" "$total_files" "$total_formatted"
    print_info ""
}

# Interactive cleanup file confirmation
cleanup_files_interactive() {
    local category="$1"
    local files=("${@:2}")
    local total_size=0

    # Calculate total size
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
            total_size=$((total_size + size))
        fi
    done

    local size_formatted=""
    if command -v format_bytes >/dev/null 2>&1; then
        size_formatted=$(format_bytes "$total_size")
    else
        size_formatted="${total_size} bytes"
    fi

    print_warning "About to delete ${#files[@]} files from category: $category"
    print_info "Total size: $size_formatted"

    if [[ "$FORCE_MODE" == "true" ]] || is_dry_run; then
        if is_dry_run; then
            print_info "[DRY-RUN] Would delete ${#files[@]} files"
        else
            print_info "[FORCE MODE] Deleting ${#files[@]} files without confirmation"
        fi
        return 0
    fi

    if ! confirm "Delete these files? (y/N)" "N"; then
        log_info "User cancelled cleanup for category: $category"
        return 1
    fi

    return 0
}

# Delete files from a category
delete_category_files() {
    local category="$1"
    local min_age_days="${2:-0}"

    # Safety check: never delete in dry-run or without confirmation
    if is_dry_run; then
        log_info "[DRY-RUN] Would delete files from category: $category"
        return 0
    fi

    local path=""
    if command -v get_category_path >/dev/null 2>&1; then
        path=$(get_category_path "$category")
    else
        log_error "get_category_path function not available"
        return 1
    fi

    if [[ -z "$path" ]] || [[ ! -e "$path" ]]; then
        log_warn "Category $category: path not found ($path)"
        return 1
    fi

    # Get list of files to delete
    local files=()
    if [[ $min_age_days -gt 0 ]]; then
        while IFS= read -r file; do
            [[ -n "$file" ]] && files+=("$file")
        done < <(find "$path" -type f -mtime +${min_age_days} -print0 2>/dev/null | xargs -0)
    else
        while IFS= read -r file; do
            [[ -n "$file" ]] && files+=("$file")
        done < <(find "$path" -type f -print0 2>/dev/null | xargs -0)
    fi

    if [[ ${#files[@]} -eq 0 ]]; then
        log_info "No files found to delete in category: $category"
        return 0
    fi

    # Interactive confirmation
    if ! cleanup_files_interactive "$category" "${files[@]}"; then
        return 1
    fi

    # Delete files
    local deleted=0
    local failed=0

    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            if rm -f "$file" 2>/dev/null; then
                deleted=$((deleted + 1))
            else
                failed=$((failed + 1))
                log_warn "Failed to delete: $file"
            fi
        fi
    done

    log_success "Deleted $deleted files from category: $category"
    if [[ $failed -gt 0 ]]; then
        log_warn "$failed files could not be deleted"
    fi

    return 0
}

# Export functions
export -f get_cleanup_categories
export -f scan_cleanup_category
export -f show_cleanup_preview
export -f cleanup_files_interactive
export -f delete_category_files
