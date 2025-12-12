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

get_cpu_usage() {
    # Get overall CPU usage percentage
    if [[ "$(uname -s)" == "Darwin" ]]; then
        # macOS: use top command to get CPU usage
        local cpu_line=$(top -l 1 | grep "CPU usage" 2>/dev/null)
        if [[ -n "$cpu_line" ]]; then
            # Extract user + sys percentage (e.g., "CPU usage: 5.23% user, 2.45% sys")
            local user_cpu=$(echo "$cpu_line" | awk '{print $3}' | sed 's/%//' | cut -d. -f1)
            local sys_cpu=$(echo "$cpu_line" | awk '{print $5}' | sed 's/%//' | cut -d. -f1)
            local total_cpu=$((user_cpu + sys_cpu))
            echo "$total_cpu"
        else
            echo "0"
        fi
    else
        # Linux: calculate from top command
        local cpu_line=$(top -bn1 | grep "Cpu(s)" 2>/dev/null)
        if [[ -n "$cpu_line" ]]; then
            # Extract CPU usage (100 - idle), get integer part
            local idle=$(echo "$cpu_line" | awk -F'id,' '{print $1}' | awk '{print $NF}' | sed 's/%//' | cut -d. -f1)
            local cpu_usage=$((100 - idle))
            echo "$cpu_usage"
        else
            echo "0"
        fi
    fi
}

get_top_memory_processes() {
    # Get top 20 processes by memory usage
    # ps aux columns: USER PID %CPU %MEM VSZ RSS TTY STAT START TIME COMMAND
    # We want %MEM (col 4) and COMMAND (col 11+)
    ps aux | awk 'NR>1 {
        mem_pct = $4
        mem_kb = $6
        # Command starts at column 11, join all remaining columns
        cmd = $11
        for (i=12; i<=NF; i++) cmd = cmd " " $i
        # Truncate long command names
        if (length(cmd) > 38) cmd = substr(cmd, 1, 35) "..."
        printf "%-40s %8.1f MB\n", cmd, mem_kb/1024
    }' | sort -rnk2 | head -20
}

get_top_cpu_processes() {
    # Get top 20 processes by CPU usage
    # ps aux columns: USER PID %CPU %MEM VSZ RSS TTY STAT START TIME COMMAND
    # We want %CPU (col 3) and COMMAND (col 11+)
    ps aux | awk 'NR>1 {
        cpu_pct = $3
        # Command starts at column 11, join all remaining columns
        cmd = $11
        for (i=12; i<=NF; i++) cmd = cmd " " $i
        # Truncate long command names
        if (length(cmd) > 38) cmd = substr(cmd, 1, 35) "..."
        printf "%-40s %6.1f%%\n", cmd, cpu_pct
    }' | sort -rnk2 | head -20
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
    local date_time=$(date '+%Y-%m-%d %H:%M:%S')

    # Header
    echo -e "${COLOR_BOLD}${COLOR_CYAN}OS Optimization Dashboard${COLOR_RESET}"
    echo "=========================================="
    echo "Time: $date_time"
    echo "=========================================="
    echo ""

    # Memory section
    local mem_stats=$(get_memory_stats)
    local mem_total=$(echo "$mem_stats" | awk '{print $1}')
    local mem_used=$(echo "$mem_stats" | awk '{print $2}')
    local mem_free=$(echo "$mem_stats" | awk '{print $3}')
    local mem_percent=$((mem_used * 100 / mem_total))

    echo -e "${COLOR_BOLD}Memória${COLOR_RESET}"
    echo "----------------------------------------"
    echo "Uso: ${mem_used} MB / ${mem_total} MB (${mem_percent}%)"
    draw_bar "$mem_used" "$mem_total" 50 "Uso"
    echo ""

    # Top 20 Memory Processes
    echo -e "${COLOR_BOLD}Top 20 Processos por Uso de Memória${COLOR_RESET}"
    echo "----------------------------------------"
    echo -e "${COLOR_YELLOW}Nota: Mostrando apenas os 20 primeiros processos${COLOR_RESET}"
    echo ""
    printf "%-40s %10s\n" "Processo" "Memória (MB)"
    echo "----------------------------------------"
    get_top_memory_processes
    echo ""

    # CPU section
    local cpu_usage=$(get_cpu_usage)
    local cpu_total=100

    echo -e "${COLOR_BOLD}Processador${COLOR_RESET}"
    echo "----------------------------------------"
    echo "Uso: ${cpu_usage}% / ${cpu_total}%"
    draw_bar "$cpu_usage" "$cpu_total" 50 "Uso"
    echo ""

    # Top 20 CPU Processes
    echo -e "${COLOR_BOLD}Top 20 Processos por Uso de Processador${COLOR_RESET}"
    echo "----------------------------------------"
    echo -e "${COLOR_YELLOW}Nota: Mostrando apenas os 20 primeiros processos${COLOR_RESET}"
    echo ""
    printf "%-40s %10s\n" "Processo" "CPU (%)"
    echo "----------------------------------------"
    get_top_cpu_processes
    echo ""

    echo "Pressione 'q' para sair, 'r' para atualizar"
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
