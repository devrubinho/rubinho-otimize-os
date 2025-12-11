#!/usr/bin/env bash

# Performance Dashboard Script
# Version: 1.0.0
# Description: Real-time system metrics and optimization history dashboard

set -euo pipefail

SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
METRICS_DIR="${HOME}/.os-optimize/metrics"
LOG_DIR="${HOME}/.os-optimize/logs"

# Color codes
if command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; then
    COLOR_GREEN=$(tput setaf 2 2>/dev/null || echo '')
    COLOR_YELLOW=$(tput setaf 3 2>/dev/null || echo '')
    COLOR_RED=$(tput setaf 1 2>/dev/null || echo '')
    COLOR_BLUE=$(tput setaf 4 2>/dev/null || echo '')
    COLOR_CYAN=$(tput setaf 6 2>/dev/null || echo '')
    COLOR_RESET=$(tput sgr0 2>/dev/null || echo '')
    COLOR_BOLD=$(tput bold 2>/dev/null || echo '')
else
    COLOR_GREEN='\033[0;32m'
    COLOR_YELLOW='\033[1;33m'
    COLOR_RED='\033[0;31m'
    COLOR_BLUE='\033[0;34m'
    COLOR_CYAN='\033[0;36m'
    COLOR_RESET='\033[0m'
    COLOR_BOLD='\033[1m'
fi

REFRESH_INTERVAL=2
COMPACT=false
FULL=false

print_info() {
    echo -e "$1"
}

detect_os() {
    case "$(uname -s)" in
        Darwin)
            echo "macOS"
            ;;
        Linux)
            echo "Linux"
            ;;
        *)
            echo "Unknown"
            ;;
    esac
}

get_memory_stats() {
    local os_type=$(detect_os)

    if [[ "$os_type" == "macOS" ]]; then
        # macOS: use vm_stat
        local pages_free=$(vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
        local pages_active=$(vm_stat | grep "Pages active" | awk '{print $3}' | sed 's/\.//')
        local pages_inactive=$(vm_stat | grep "Pages inactive" | awk '{print $3}' | sed 's/\.//')
        local pages_wired=$(vm_stat | grep "Pages wired down" | awk '{print $4}' | sed 's/\.//')
        local page_size=$(pagesize 2>/dev/null || echo "4096")

        local total_mb=$(( (pages_free + pages_active + pages_inactive + pages_wired) * page_size / 1024 / 1024 ))
        local free_mb=$(( pages_free * page_size / 1024 / 1024 ))
        local used_mb=$((total_mb - free_mb))

        echo "$total_mb $used_mb $free_mb"
    else
        # Linux: use free
        free -m | awk '/^Mem:/ {print $2, $3, $4}'
    fi
}

get_cpu_load() {
    if [[ "$(uname -s)" == "Darwin" ]]; then
        sysctl -n vm.loadavg | awk '{print $1, $2, $3}'
    else
        cat /proc/loadavg | awk '{print $1, $2, $3}'
    fi
}

get_disk_usage() {
    df -h / | tail -1 | awk '{print $5}' | sed 's/%//'
}

get_uptime() {
    if [[ "$(uname -s)" == "Darwin" ]]; then
        uptime | sed 's/.*up \([^,]*\),.*/\1/'
    else
        uptime -p 2>/dev/null || uptime | sed 's/.*up \([^,]*\),.*/\1/'
    fi
}

draw_bar() {
    local value=$1
    local max=$2
    local width=${3:-50}
    local label="$4"

    local percentage=$((value * 100 / max))
    local filled=$((value * width / max))
    local empty=$((width - filled))

    # Color based on percentage
    local color="$COLOR_GREEN"
    if [[ $percentage -ge 90 ]]; then
        color="$COLOR_RED"
    elif [[ $percentage -ge 70 ]]; then
        color="$COLOR_YELLOW"
    fi

    printf "%-20s [%s%s%s] %3d%%\n" "$label" "$color" "$(printf '█%.0s' $(seq 1 $filled))" "$COLOR_RESET$(printf '░%.0s' $(seq 1 $empty))" "$percentage"
}

display_dashboard() {
    clear 2>/dev/null || true

    local os_type=$(detect_os)
    local hostname=$(hostname 2>/dev/null || echo "unknown")
    local uptime=$(get_uptime)
    local date_time=$(date '+%Y-%m-%d %H:%M:%S')
    local os_version=""

    if [[ "$os_type" == "macOS" ]]; then
        os_version=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
    else
        os_version=$(cat /etc/os-release 2>/dev/null | grep VERSION_ID | cut -d'"' -f2 || echo "unknown")
    fi

    # Header
    echo -e "${COLOR_BOLD}${COLOR_CYAN}OS Optimization Dashboard${COLOR_RESET}"
    echo "=========================================="
    echo "Hostname: $hostname"
    echo "OS: $os_type $os_version"
    echo "Uptime: $uptime"
    echo "Time: $date_time"
    echo "=========================================="
    echo ""

    # Memory section
    local mem_stats=$(get_memory_stats)
    local mem_total=$(echo "$mem_stats" | awk '{print $1}')
    local mem_used=$(echo "$mem_stats" | awk '{print $2}')
    local mem_free=$(echo "$mem_stats" | awk '{print $3}')

    echo -e "${COLOR_BOLD}Memory${COLOR_RESET}"
    echo "----------------------------------------"
    echo "Total: ${mem_total} MB"
    echo "Used:  ${mem_used} MB"
    echo "Free:  ${mem_free} MB"
    draw_bar "$mem_used" "$mem_total" 40 "Usage"
    echo ""

    # CPU section
    local cpu_load=$(get_cpu_load)
    local load_1=$(echo "$cpu_load" | awk '{print $1}')
    local load_5=$(echo "$cpu_load" | awk '{print $2}')
    local load_15=$(echo "$cpu_load" | awk '{print $3}')

    echo -e "${COLOR_BOLD}CPU Load Average${COLOR_RESET}"
    echo "----------------------------------------"
    echo "1 min:  $load_1"
    echo "5 min:  $load_5"
    echo "15 min: $load_15"
    echo ""

    # Disk section
    local disk_usage=$(get_disk_usage)
    echo -e "${COLOR_BOLD}Disk Usage${COLOR_RESET}"
    echo "----------------------------------------"
    draw_bar "$disk_usage" 100 40 "Root /"
    echo ""

    # Optimization history
    if [[ -d "$LOG_DIR" ]]; then
        echo -e "${COLOR_BOLD}Recent Optimizations${COLOR_RESET}"
        echo "----------------------------------------"

        local recent_logs=$(find "$LOG_DIR" -name "*.log" -type f -mtime -7 2>/dev/null | head -5)
        if [[ -n "$recent_logs" ]]; then
            local count=0
            while IFS= read -r log_file && [[ $count -lt 5 ]]; do
                local log_name=$(basename "$log_file")
                local log_date=$(stat -f "%Sm" "$log_file" 2>/dev/null || stat -c "%y" "$log_file" 2>/dev/null | cut -d' ' -f1)
                echo "  $log_name (${log_date})"
                count=$((count + 1))
            done <<< "$recent_logs"
        else
            echo "  No recent optimizations"
        fi
        echo ""
    fi

    echo "Press 'q' to quit, 'r' to refresh, 'h' for help"
}

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --refresh-interval)
                REFRESH_INTERVAL="$2"
                shift 2
                ;;
            --compact)
                COMPACT=true
                shift
                ;;
            --full)
                FULL=true
                shift
                ;;
            -h|--help)
                cat << EOF
Performance Dashboard

Usage: $0 [OPTIONS]

Options:
    --refresh-interval N    Refresh interval in seconds (default: 2)
    --compact              Compact display mode
    --full                 Full detailed display
    -h, --help             Show this help message

Controls:
    q                      Quit
    r                      Refresh immediately
    h                      Toggle help
EOF
                exit 0
                ;;
            *)
                print_info "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # Create metrics directory
    mkdir -p "$METRICS_DIR" 2>/dev/null || true

    # Trap SIGINT for graceful exit
    trap 'clear 2>/dev/null; echo ""; echo "Dashboard closed."; exit 0' SIGINT

    # Main loop
    if command -v watch >/dev/null 2>&1; then
        # Use watch command if available
        watch -n "$REFRESH_INTERVAL" -t -c "$0 --display-once" 2>/dev/null || {
            # Fallback to manual refresh loop
            while true; do
                display_dashboard
                sleep "$REFRESH_INTERVAL"
            done
        }
    else
        # Manual refresh loop
        while true; do
            display_dashboard
            sleep "$REFRESH_INTERVAL"
        done
    fi
}

# Check if called with --display-once (internal use)
if [[ "${1:-}" == "--display-once" ]]; then
    display_dashboard
    exit 0
fi

main "$@"
