#!/usr/bin/env bash

# Log Viewer Script
# Version: 1.0.0
# Description: Interactive log viewing with filtering and search capabilities

set -euo pipefail

SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${HOME}/.os-optimize/logs"

# Color codes
if command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; then
    COLOR_GREEN=$(tput setaf 2 2>/dev/null || echo '')
    COLOR_YELLOW=$(tput setaf 3 2>/dev/null || echo '')
    COLOR_RED=$(tput setaf 1 2>/dev/null || echo '')
    COLOR_BLUE=$(tput setaf 4 2>/dev/null || echo '')
    COLOR_CYAN=$(tput setaf 6 2>/dev/null || echo '')
    COLOR_RESET=$(tput sgr0 2>/dev/null || echo '')
else
    COLOR_GREEN='\033[0;32m'
    COLOR_YELLOW='\033[1;33m'
    COLOR_RED='\033[0;31m'
    COLOR_BLUE='\033[0;34m'
    COLOR_CYAN='\033[0;36m'
    COLOR_RESET='\033[0m'
fi

# Flags
LEVEL_FILTER=""
SCRIPT_FILTER=""
DATE_FILTER=""
DATE_FROM=""
DATE_TO=""
SEARCH_PATTERN=""
LAST_LINES=100
FOLLOW=false
PLAIN=false
JSON=false
EXPORT_FILE=""
STATS=false

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

show_help() {
    cat << EOF
Log Viewer Script

Usage: $0 [OPTIONS]

Options:
    --level LEVEL         Filter by severity (DEBUG, INFO, WARN, ERROR)
    --script NAME         Show logs from specific script only
    --date DATE           Filter by date (YYYY-MM-DD)
    --from DATE           Start date for range (YYYY-MM-DD)
    --to DATE             End date for range (YYYY-MM-DD)
    --search PATTERN      Search for keywords (supports regex)
    --last N              Show last N lines (default: 100)
    --follow              Follow logs in real-time (tail -f)
    --plain               No colors, suitable for piping
    --json                Export as JSON format
    --export FILE         Save filtered results to file
    --stats               Show summary statistics
    -h, --help            Show this help message

Examples:
    $0                                    # List all logs
    $0 --level ERROR                      # Show only errors
    $0 --script clean-memory --last 50   # Last 50 lines from clean-memory
    $0 --date 2025-12-11                  # Logs from specific date
    $0 --from 2025-12-01 --to 2025-12-11  # Date range
    $0 --search "memory freed"            # Search for keywords
    $0 --follow                           # Real-time monitoring
    $0 --stats                            # Show statistics
EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --level)
                LEVEL_FILTER="$2"
                shift 2
                ;;
            --script)
                SCRIPT_FILTER="$2"
                shift 2
                ;;
            --date)
                DATE_FILTER="$2"
                shift 2
                ;;
            --from)
                DATE_FROM="$2"
                shift 2
                ;;
            --to)
                DATE_TO="$2"
                shift 2
                ;;
            --search)
                SEARCH_PATTERN="$2"
                shift 2
                ;;
            --last)
                LAST_LINES="$2"
                shift 2
                ;;
            --follow)
                FOLLOW=true
                shift
                ;;
            --plain)
                PLAIN=true
                shift
                ;;
            --json)
                JSON=true
                shift
                ;;
            --export)
                EXPORT_FILE="$2"
                shift 2
                ;;
            --stats)
                STATS=true
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
}

list_log_files() {
    if [[ ! -d "$LOG_DIR" ]]; then
        print_warning "Log directory not found: $LOG_DIR"
        return 1
    fi

    print_info "Available log files:"
    print_info ""

    if command -v ls >/dev/null 2>&1; then
        ls -lh "$LOG_DIR"/*.log 2>/dev/null | awk '{print $9, "(" $5 ")"}'
    else
        find "$LOG_DIR" -name "*.log" -type f -exec ls -lh {} \; 2>/dev/null
    fi
}

colorize_log_line() {
    local line="$1"

    if [[ "$PLAIN" == "true" ]]; then
        echo "$line"
        return
    fi

    # Color code by severity level
    if echo "$line" | grep -q "\[ERROR\]"; then
        echo -e "${COLOR_RED}${line}${COLOR_RESET}"
    elif echo "$line" | grep -q "\[WARN\]"; then
        echo -e "${COLOR_YELLOW}${line}${COLOR_RESET}"
    elif echo "$line" | grep -q "\[INFO\]"; then
        echo -e "${COLOR_GREEN}${line}${COLOR_RESET}"
    elif echo "$line" | grep -q "\[DEBUG\]"; then
        echo -e "${COLOR_CYAN}${line}${COLOR_RESET}"
    else
        echo "$line"
    fi
}

filter_logs() {
    local log_file="$1"
    local temp_output=""

    # Check if compressed
    if [[ "$log_file" == *.gz ]]; then
        temp_output=$(zgrep . "$log_file" 2>/dev/null || zcat "$log_file" 2>/dev/null || true)
    else
        temp_output=$(cat "$log_file" 2>/dev/null || true)
    fi

    if [[ -z "$temp_output" ]]; then
        return
    fi

    # Apply filters
    local filtered="$temp_output"

    # Level filter
    if [[ -n "$LEVEL_FILTER" ]]; then
        filtered=$(echo "$filtered" | grep "\[${LEVEL_FILTER}\]" || true)
    fi

    # Script filter
    if [[ -n "$SCRIPT_FILTER" ]]; then
        filtered=$(echo "$filtered" | grep "\[${SCRIPT_FILTER}" || true)
    fi

    # Date filter
    if [[ -n "$DATE_FILTER" ]]; then
        filtered=$(echo "$filtered" | grep "$DATE_FILTER" || true)
    fi

    # Date range filter
    if [[ -n "$DATE_FROM" ]] || [[ -n "$DATE_TO" ]]; then
        # Convert dates to epoch for comparison
        local from_epoch=0
        local to_epoch=$(date +%s)

        if [[ -n "$DATE_FROM" ]]; then
            from_epoch=$(date -j -f "%Y-%m-%d" "$DATE_FROM" +%s 2>/dev/null || date -d "$DATE_FROM" +%s 2>/dev/null || echo "0")
        fi

        if [[ -n "$DATE_TO" ]]; then
            to_epoch=$(date -j -f "%Y-%m-%d" "$DATE_TO" +%s 2>/dev/null || date -d "$DATE_TO" +%s 2>/dev/null || echo "$(date +%s)")
        fi

        # Filter by date range (simplified - checks if date string in line)
        if [[ -n "$DATE_FROM" ]]; then
            filtered=$(echo "$filtered" | awk -v from="$DATE_FROM" '$0 ~ from || $0 > from' || true)
        fi
        if [[ -n "$DATE_TO" ]]; then
            filtered=$(echo "$filtered" | awk -v to="$DATE_TO" '$0 ~ to || $0 < to' || true)
        fi
    fi

    # Search pattern
    if [[ -n "$SEARCH_PATTERN" ]]; then
        filtered=$(echo "$filtered" | grep -i -C 3 "$SEARCH_PATTERN" || true)
    fi

    # Last N lines
    if [[ "$FOLLOW" != "true" ]] && [[ $LAST_LINES -gt 0 ]]; then
        filtered=$(echo "$filtered" | tail -n "$LAST_LINES")
    fi

    echo "$filtered"
}

display_logs() {
    if [[ ! -d "$LOG_DIR" ]]; then
        print_error "Log directory not found: $LOG_DIR"
        exit 1
    fi

    # Find log files
    local log_files=()
    if [[ -n "$SCRIPT_FILTER" ]]; then
        while IFS= read -r file; do
            [[ -f "$file" ]] && log_files+=("$file")
        done < <(find "$LOG_DIR" -name "*${SCRIPT_FILTER}*.log*" -type f 2>/dev/null)
    else
        while IFS= read -r file; do
            [[ -f "$file" ]] && log_files+=("$file")
        done < <(find "$LOG_DIR" -name "*.log*" -type f 2>/dev/null | sort -r)
    fi

    if [[ ${#log_files[@]} -eq 0 ]]; then
        print_warning "No log files found"
        return 1
    fi

    # Follow mode
    if [[ "$FOLLOW" == "true" ]]; then
        print_info "Following logs (press Ctrl+C to exit)..."
        print_info ""

        for log_file in "${log_files[@]}"; do
            if [[ "$log_file" == *.gz ]]; then
                zcat "$log_file" 2>/dev/null | while IFS= read -r line; do
                    colorize_log_line "$line"
                done &
            else
                tail -f "$log_file" 2>/dev/null | while IFS= read -r line; do
                    colorize_log_line "$line"
                done &
            fi
        done
        wait
        return 0
    fi

    # Process and display logs
    local all_output=""

    for log_file in "${log_files[@]}"; do
        local filtered=$(filter_logs "$log_file")
        if [[ -n "$filtered" ]]; then
            all_output="${all_output}${filtered}\n"
        fi
    done

    # JSON export
    if [[ "$JSON" == "true" ]]; then
        echo "["
        local first=true
        echo -e "$all_output" | while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                if [[ "$first" == "true" ]]; then
                    first=false
                else
                    echo ","
                fi

                # Parse log line: [TIMESTAMP] [LEVEL] [SCRIPT:PID] Message
                local timestamp=$(echo "$line" | sed -n 's/^\[\([^\]]*\)\].*/\1/p')
                local level=$(echo "$line" | sed -n 's/.*\[\([A-Z]*\)\].*/\1/p')
                local script_pid=$(echo "$line" | sed -n 's/.*\[\([^:]*\):\([0-9]*\)\].*/\1/p')
                local message=$(echo "$line" | sed -n 's/.*\] \(.*\)/\1/p')

                echo -n "  {"
                echo -n "\"timestamp\": \"$timestamp\","
                echo -n "\"level\": \"$level\","
                echo -n "\"script\": \"$script_pid\","
                echo -n "\"message\": \"$message\""
                echo -n "}"
            fi
        done
        echo ""
        echo "]"
        return 0
    fi

    # Export to file
    if [[ -n "$EXPORT_FILE" ]]; then
        echo -e "$all_output" > "$EXPORT_FILE"
        print_success "Exported to: $EXPORT_FILE"
        return 0
    fi

    # Display with pager or direct output
    if [[ -t 1 ]] && [[ "$PLAIN" != "true" ]] && command -v less >/dev/null 2>&1; then
        echo -e "$all_output" | while IFS= read -r line; do
            colorize_log_line "$line"
        done | less -R
    else
        echo -e "$all_output" | while IFS= read -r line; do
            colorize_log_line "$line"
        done
    fi
}

show_statistics() {
    if [[ ! -d "$LOG_DIR" ]]; then
        print_error "Log directory not found: $LOG_DIR"
        exit 1
    fi

    print_info "Log Statistics"
    print_info "=============="
    print_info ""

    local total_size=0
    local error_count=0
    local warn_count=0
    local info_count=0
    local debug_count=0
    local oldest_date=""
    local newest_date=""

    # Process all log files
    while IFS= read -r log_file; do
        if [[ -f "$log_file" ]]; then
            # Get file size
            if [[ "$(uname -s)" == "Darwin" ]]; then
                local size=$(stat -f "%z" "$log_file" 2>/dev/null || echo "0")
            else
                local size=$(stat -c "%s" "$log_file" 2>/dev/null || echo "0")
            fi
            total_size=$((total_size + size))

            # Count log levels
            local content=""
            if [[ "$log_file" == *.gz ]]; then
                content=$(zcat "$log_file" 2>/dev/null || true)
            else
                content=$(cat "$log_file" 2>/dev/null || true)
            fi

            error_count=$((error_count + $(echo "$content" | grep -c "\[ERROR\]" || echo "0")))
            warn_count=$((warn_count + $(echo "$content" | grep -c "\[WARN\]" || echo "0")))
            info_count=$((info_count + $(echo "$content" | grep -c "\[INFO\]" || echo "0")))
            debug_count=$((debug_count + $(echo "$content" | grep -c "\[DEBUG\]" || echo "0")))

            # Extract dates
            local dates=$(echo "$content" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sort | uniq)
            if [[ -n "$dates" ]]; then
                local first_date=$(echo "$dates" | head -1)
                local last_date=$(echo "$dates" | tail -1)

                if [[ -z "$oldest_date" ]] || [[ "$first_date" < "$oldest_date" ]]; then
                    oldest_date="$first_date"
                fi
                if [[ -z "$newest_date" ]] || [[ "$last_date" > "$newest_date" ]]; then
                    newest_date="$last_date"
                fi
            fi
        fi
    done < <(find "$LOG_DIR" -name "*.log*" -type f 2>/dev/null)

    # Display statistics
    local total_size_mb=$((total_size / 1024 / 1024))
    local total_logs=$((error_count + warn_count + info_count + debug_count))

    print_info "Total Log Size: ${total_size_mb} MB"
    print_info "Oldest Log: ${oldest_date:-N/A}"
    print_info "Newest Log: ${newest_date:-N/A}"
    print_info ""
    print_info "Log Level Counts:"
    print_info "  ERROR: ${error_count}"
    print_info "  WARN:  ${warn_count}"
    print_info "  INFO:  ${info_count}"
    print_info "  DEBUG: ${debug_count}"
    print_info ""

    if [[ $total_logs -gt 0 ]]; then
        local error_rate=$((error_count * 100 / total_logs))
        print_info "Error Rate: ${error_rate}%"
    fi
}

main() {
    parse_arguments "$@"

    if [[ "$STATS" == "true" ]]; then
        show_statistics
        exit 0
    fi

    if [[ "$FOLLOW" != "true" ]] && [[ -z "$SCRIPT_FILTER" ]] && [[ -z "$LEVEL_FILTER" ]] && [[ -z "$DATE_FILTER" ]] && [[ -z "$SEARCH_PATTERN" ]]; then
        list_log_files
        print_info ""
        print_info "Use --help for filtering options"
        exit 0
    fi

    display_logs
}

main "$@"
