#!/usr/bin/env bash

# Disk Analysis Library
# Version: 1.0.0
# Description: Functions for analyzing disk usage and categorizing files
# Usage: source lib/disk_analysis.sh

# Source guard to prevent double-loading
if [[ -n "${DISK_ANALYSIS_SH_LOADED:-}" ]]; then
    return 0
fi

readonly DISK_ANALYSIS_SH_LOADED=1
readonly DISK_ANALYSIS_VERSION="1.0.0"

# Configuration
HIGHLIGHT_THRESHOLD="${HIGHLIGHT_THRESHOLD:-100}"  # MB
ANALYSIS_TIMEOUT="${ANALYSIS_TIMEOUT:-300}"  # seconds

# Source common.sh for logging and platform detection
if [[ -z "${COMMON_SH_LOADED:-}" ]]; then
    # Try to source from same directory as this script
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "${script_dir}/common.sh" ]]; then
        source "${script_dir}/common.sh"
    else
        echo "Error: common.sh not found. Please source it before disk_analysis.sh" >&2
        return 1
    fi
fi

# Format bytes to human-readable format
format_bytes() {
    local bytes="$1"
    local precision="${2:-2}"

    if [[ -z "$bytes" ]] || [[ "$bytes" -lt 0 ]]; then
        echo "0 B"
        return
    fi

    local units=("B" "KB" "MB" "GB" "TB" "PB")
    local unit_index=0
    local size=$(echo "$bytes" | awk '{printf "%.2f", $1}')

    while [[ $(echo "$size >= 1024" | bc 2>/dev/null || echo "0") -eq 1 ]] && [[ $unit_index -lt $((${#units[@]} - 1)) ]]; do
        size=$(echo "scale=$precision; $size / 1024" | bc 2>/dev/null || echo "0")
        unit_index=$((unit_index + 1))
    done

    # Fallback to awk if bc not available
    if ! command -v bc >/dev/null 2>&1; then
        local size_float="$bytes"
        unit_index=0
        while [[ $size_float -ge 1024 ]] && [[ $unit_index -lt $((${#units[@]} - 1)) ]]; do
            size_float=$((size_float / 1024))
            unit_index=$((unit_index + 1))
        done
        echo "${size_float} ${units[$unit_index]}"
    else
        echo "${size} ${units[$unit_index]}"
    fi
}

# Get disk categories for the current platform
get_disk_categories() {
    if is_macos; then
        echo "caches logs downloads temp browser_trash xcode node_modules docker volumes"
    elif is_linux; then
        echo "caches logs temp browser_trash apt yum pacman node_modules docker volumes snap"
    else
        echo "caches logs temp"
    fi
}

# Analyze disk usage for a specific path
analyze_disk_usage() {
    local path="${1:-}"
    local category="${2:-unknown}"
    local max_depth="${3:-3}"

    if [[ -z "$path" ]] || [[ ! -e "$path" ]]; then
        log_warn "Path does not exist: $path"
        return 1
    fi

    local total_size=0
    local file_count=0
    local dir_count=0

    # Use du command for accurate size calculation
    if command -v du >/dev/null 2>&1; then
        # Get total size in bytes (or KB on some systems)
        local size_output=$(du -sk "$path" 2>/dev/null | awk '{print $1}')
        total_size=$((size_output * 1024))  # Convert KB to bytes

        # Count files and directories
        file_count=$(find "$path" -maxdepth "$max_depth" -type f 2>/dev/null | wc -l | tr -d ' ')
        dir_count=$(find "$path" -maxdepth "$max_depth" -type d 2>/dev/null | wc -l | tr -d ' ')
    else
        log_warn "du command not found, using find as fallback"
        # Fallback: use find and stat
        local sizes=$(find "$path" -maxdepth "$max_depth" -type f -exec stat -f%z {} \; 2>/dev/null || find "$path" -maxdepth "$max_depth" -type f -exec stat -c%s {} \; 2>/dev/null)
        for size in $sizes; do
            total_size=$((total_size + size))
        done
        file_count=$(find "$path" -maxdepth "$max_depth" -type f 2>/dev/null | wc -l | tr -d ' ')
        dir_count=$(find "$path" -maxdepth "$max_depth" -type d 2>/dev/null | wc -l | tr -d ' ')
    fi

    # Format output
    local size_formatted=$(format_bytes "$total_size")
    local size_mb=$((total_size / 1024 / 1024))

    # Create result string
    echo "${category}|${path}|${total_size}|${size_formatted}|${size_mb}|${file_count}|${dir_count}"
}

# Get category path based on platform and category name
get_category_path() {
    local category="$1"

    case "$category" in
        caches)
            if is_macos; then
                echo "${HOME}/Library/Caches"
            else
                echo "${HOME}/.cache"
            fi
            ;;
        logs)
            if is_macos; then
                echo "${HOME}/Library/Logs"
            else
                echo "/var/log"
            fi
            ;;
        downloads)
            echo "${HOME}/Downloads"
            ;;
        temp)
            if is_macos; then
                echo "/tmp"
            else
                echo "/tmp"
            fi
            ;;
        browser_trash)
            if is_macos; then
                echo "${HOME}/.Trash"
            else
                echo "${HOME}/.local/share/Trash"
            fi
            ;;
        xcode)
            if is_macos; then
                echo "${HOME}/Library/Developer/Xcode/DerivedData"
            else
                echo ""
            fi
            ;;
        node_modules)
            echo "${HOME}/.node_modules"
            ;;
        docker)
            if is_macos; then
                echo "${HOME}/Library/Containers/com.docker.docker/Data/vms"
            else
                echo "/var/lib/docker"
            fi
            ;;
        volumes)
            echo ""
            ;;
        apt)
            if is_linux; then
                echo "/var/cache/apt"
            else
                echo ""
            fi
            ;;
        yum)
            if is_linux; then
                echo "/var/cache/yum"
            else
                echo ""
            fi
            ;;
        pacman)
            if is_linux; then
                echo "/var/cache/pacman/pkg"
            else
                echo ""
            fi
            ;;
        snap)
            if is_linux; then
                echo "/var/lib/snapd/cache"
            else
                echo ""
            fi
            ;;
        *)
            echo ""
            ;;
    esac
}

# Analyze all disk categories
analyze_all_categories() {
    local categories=$(get_disk_categories)
    local results=()

    log_info "Starting disk usage analysis..."

    for category in $categories; do
        local path=$(get_category_path "$category")

        if [[ -z "$path" ]] || [[ ! -e "$path" ]]; then
            log_debug "Skipping category $category (path not found: $path)"
            continue
        fi

        log_info "Analyzing category: $category ($path)"
        local result=$(analyze_disk_usage "$path" "$category")
        if [[ -n "$result" ]]; then
            results+=("$result")
        fi
    done

    # Return results as newline-separated string
    printf '%s\n' "${results[@]}"
}

# Export functions
export -f format_bytes
export -f get_disk_categories
export -f analyze_disk_usage
export -f get_category_path
export -f analyze_all_categories
