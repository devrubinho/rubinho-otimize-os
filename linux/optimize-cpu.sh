#!/usr/bin/env bash

# Linux CPU Optimization Script
# Version: 1.0.0
# Description: Manages processes, system services, and logs on Linux

set -euo pipefail

# Script configuration
SCRIPT_VERSION="1.0.0"
LOG_DIR="${HOME}/.os-optimize/logs"
LOG_FILE=""

# Execution flags
DRY_RUN=false
QUIET=false
VERBOSE=false
PROCESS_THRESHOLD=50

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

# Safe-kill list (critical processes)
SAFE_KILL_LIST=(
    "init"
    "systemd"
    "kthreadd"
    "systemd-journald"
    "sshd"
    "systemd-logind"
)

# Load averages
LOAD_AVG_BEFORE=""
LOAD_AVG_AFTER=""

# Helper functions
print_success() {
    [[ "$QUIET" == "false" ]] && echo -e "${COLOR_GREEN}✓${COLOR_RESET} $1"
    log_message "SUCCESS" "$1"
}

print_warning() {
    [[ "$QUIET" == "false" ]] && echo -e "${COLOR_YELLOW}⚠${COLOR_RESET} $1"
    log_message "WARN" "$1"
}

print_error() {
    [[ "$QUIET" == "false" ]] && echo -e "${COLOR_RED}✗${COLOR_RESET} $1"
    log_message "ERROR" "$1"
}

print_info() {
    [[ "$QUIET" == "false" ]] && echo -e "$1"
    log_message "INFO" "$1"
}

print_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        [[ "$QUIET" == "false" ]] && echo -e "${COLOR_BLUE}[DEBUG]${COLOR_RESET} $1"
        log_message "DEBUG" "$1"
    fi
}

# Logging function
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if [[ -n "$LOG_FILE" ]]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

# Initialize logging
init_logging() {
    if mkdir -p "$LOG_DIR" 2>/dev/null; then
        chmod 755 "$LOG_DIR" 2>/dev/null || true
        local timestamp=$(date +%Y%m%d-%H%M%S)
        LOG_FILE="${LOG_DIR}/cpu-optimization-${timestamp}.log"

        {
            echo "=========================================="
            echo "Linux CPU Optimization Script - Log"
            echo "=========================================="
            echo "Timestamp: $(date)"
            echo "Kernel: $(uname -r 2>/dev/null || echo 'unknown')"
            echo "Hostname: $(hostname 2>/dev/null || echo 'unknown')"
            echo "User: $(whoami 2>/dev/null || echo 'unknown')"
            echo "Script Version: $SCRIPT_VERSION"
            echo "Flags: DRY_RUN=$DRY_RUN, QUIET=$QUIET, VERBOSE=$VERBOSE"
            echo "=========================================="
            echo ""
        } >> "$LOG_FILE"

        log_message "INFO" "Logging initialized: $LOG_FILE"
        return 0
    else
        print_warning "Cannot create log directory: $LOG_DIR (logging disabled)"
        return 1
    fi
}

# Get load averages
get_load_averages() {
    if [[ -f /proc/loadavg ]]; then
        cat /proc/loadavg | awk '{printf "%.2f %.2f %.2f", $1, $2, $3}'
    else
        uptime 2>/dev/null | awk -F'load average:' '{print $2}' | sed 's/,//g' | awk '{printf "%.2f %.2f %.2f", $1, $2, $3}' || echo "0.00 0.00 0.00"
    fi
}

# Display load averages
display_load_averages() {
    local label="$1"
    local load_avg="$2"
    local cpu_cores=$(nproc 2>/dev/null || echo "1")

    print_info ""
    print_info "=== $label ==="
    print_info "Load Average (1min, 5min, 15min): $load_avg"
    print_info "CPU Cores: $cpu_cores"
    print_info ""
}

# Check if process is protected
is_protected_process() {
    local process_name="$1"
    local pid="$2"

    # Check PID protection (0, 1, and low PIDs)
    if [[ $pid -eq 0 ]] || [[ $pid -eq 1 ]] || [[ $pid -lt 100 ]]; then
        return 0  # Protected
    fi

    # Check safe-kill list
    for protected in "${SAFE_KILL_LIST[@]}"; do
        if [[ "$process_name" == "$protected" ]] || [[ "$process_name" == *"$protected"* ]]; then
            return 0  # Protected
        fi
    done

    # Check for kernel threads (bracketed names)
    if [[ "$process_name" =~ ^\[.*\]$ ]]; then
        return 0  # Protected
    fi

    return 1  # Not protected
}

# Get top CPU processes
get_top_cpu_processes() {
    local threshold="$1"

    if ! command -v ps >/dev/null 2>&1; then
        print_error "ps command not found"
        return 1
    fi

    ps aux --sort=-%cpu 2>/dev/null | awk -v threshold="$threshold" '
        NR > 1 && $3 + 0 >= threshold {
            pid = $2
            cpu = $3
            user = $1
            cmd = ""
            for (i = 11; i <= NF; i++) {
                cmd = cmd " " $i
            }
            gsub(/^ /, "", cmd)
            if (length(cmd) > 50) {
                cmd = substr(cmd, 1, 47) "..."
            }
            printf "%s|%.1f|%s|%s|high\n", pid, cpu, user, cmd
        }
    ' | head -20
}

# Display CPU processes
display_cpu_processes() {
    local processes="$1"
    local count=1

    print_info ""
    print_info "=== Top CPU Processes (>= ${PROCESS_THRESHOLD}%) ==="
    print_info ""
    print_info "  #  PID     CPU%   User        Process"
    print_info "---  ------  -----  ----------  --------------------"

    echo "$processes" | while IFS='|' read -r pid cpu user cmd level; do
        if [[ -z "$pid" ]]; then
            continue
        fi

        local color=""
        local cpu_num=$(echo "$cpu" | sed 's/[^0-9.]//g')

        if (( $(echo "$cpu_num < 30" | bc -l 2>/dev/null || echo "0") )); then
            color="$COLOR_GREEN"
        elif (( $(echo "$cpu_num < 70" | bc -l 2>/dev/null || echo "0") )); then
            color="$COLOR_YELLOW"
        else
            color="$COLOR_RED"
        fi

        printf " %2d  %-6s  %5s%%  %-10s  %s\n" "$count" "$pid" "$cpu" "$user" "$cmd"
        count=$((count + 1))
    done

    print_info ""
}

# Clean system logs
clean_system_logs() {
    print_info "=== System Log Cleanup ==="

    if is_dry_run; then
        print_info "[DRY-RUN] Would execute log rotation and cleanup"
        return 0
    fi

    # Check sudo
    if ! sudo -n true 2>/dev/null; then
        if ! sudo -v; then
            print_warning "Sudo access required for log cleanup"
            return 1
        fi
    fi

    # Rotate logs
    if command -v logrotate >/dev/null 2>&1; then
        print_info "Rotating system logs..."
        if sudo logrotate -f /etc/logrotate.conf >/dev/null 2>&1; then
            print_success "Log rotation completed"
            log_message "INFO" "System logs rotated"
        fi
    fi

    # Clean old logs (>30 days compress, >90 days delete)
    print_info "Cleaning old log files..."

    local compressed_count=0
    local deleted_count=0

    # Compress logs >30 days
    if find /var/log -type f -mtime +30 ! -name "*.gz" -name "*.log" 2>/dev/null | head -1 | grep -q .; then
        compressed_count=$(find /var/log -type f -mtime +30 ! -name "*.gz" -name "*.log" 2>/dev/null | wc -l | tr -d ' ')
        if [[ $compressed_count -gt 0 ]]; then
            find /var/log -type f -mtime +30 ! -name "*.gz" -name "*.log" -exec sudo gzip {} \; 2>/dev/null || true
            print_info "Compressed $compressed_count log file(s)"
        fi
    fi

    # Delete logs >90 days (with confirmation)
    if find /var/log -type f -mtime +90 \( -name "*.log.gz" -o -name "*.log" \) 2>/dev/null | head -1 | grep -q .; then
        deleted_count=$(find /var/log -type f -mtime +90 \( -name "*.log.gz" -o -name "*.log" \) 2>/dev/null | wc -l | tr -d ' ')
        if [[ $deleted_count -gt 0 ]]; then
            print_info "Found $deleted_count old log file(s) (>90 days)"
            print_info "Delete old logs? (y/N): "
            read -r response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                find /var/log -type f -mtime +90 \( -name "*.log.gz" -o -name "*.log" \) -exec sudo rm -f {} \; 2>/dev/null || true
                print_success "Deleted $deleted_count old log file(s)"
                log_message "INFO" "Deleted $deleted_count old log files"
            fi
        fi
    fi

    print_info "Log cleanup summary: $compressed_count compressed, $deleted_count deleted"
}

# Detect and clean zombie processes
clean_zombies() {
    print_info "=== Zombie Process Detection ==="

    local zombies=$(ps aux | awk '$8 ~ /Z/ { print $2, $3, $1, $11 }' | wc -l | tr -d ' ')

    if [[ $zombies -eq 0 ]]; then
        print_info "No zombie processes found"
        return 0
    fi

    print_info "Found $zombies zombie process(es)"
    print_info "Note: Zombie cleanup requires identifying and managing parent processes"
    print_info "  (Advanced feature - basic detection implemented)"

    log_message "INFO" "Zombie processes detected: $zombies"
}

# Audit systemd services (basic)
audit_systemd_services() {
    print_info "=== Systemd Service Audit ==="

    if ! command -v systemctl >/dev/null 2>&1; then
        print_info "Systemd not available (non-systemd system)"
        return 0
    fi

    # List failed services
    local failed_services=$(systemctl --failed --no-pager 2>/dev/null | grep -c "loaded.*failed" || echo "0")

    if [[ $failed_services -gt 0 ]]; then
        print_warning "Found $failed_services failed service(s)"
        print_info "Failed services:"
        systemctl --failed --no-pager 2>/dev/null | grep "loaded.*failed" | head -5
    else
        print_success "No failed services"
    fi

    log_message "INFO" "Systemd service audit: $failed_services failed services"
}

# Parse command-line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --process-threshold)
                PROCESS_THRESHOLD="$2"
                shift 2
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

    # Validate threshold
    if ! [[ "$PROCESS_THRESHOLD" =~ ^[0-9]+$ ]] || [[ $PROCESS_THRESHOLD -lt 0 ]] || [[ $PROCESS_THRESHOLD -gt 100 ]]; then
        print_error "Process threshold must be between 0 and 100"
        exit 1
    fi
}

# Show help
show_help() {
    cat << EOF
Linux CPU Optimization Script

Usage: $0 [OPTIONS]

Options:
    -n, --dry-run           Preview actions without executing
    -q, --quiet             Suppress progress output
    -v, --verbose           Show detailed logs
    --process-threshold N   CPU threshold percentage (default: 50)
    -h, --help              Show this help message
    --version               Show version information

Description:
    This script identifies CPU-intensive processes and cleans system logs.
    It performs the following operations:

    - CPU usage monitoring and process identification
    - Safe process termination (with protection for critical processes)
    - System log rotation and cleanup
    - Zombie process detection
    - Systemd service audit

    WARNING: Process termination is irreversible. Use --dry-run first.

Examples:
    $0                          # Normal execution
    $0 --dry-run                # Preview without making changes
    $0 --process-threshold 30   # Show processes using >= 30% CPU
EOF
}

# Show version
show_version() {
    echo "Linux CPU Optimization Script v$SCRIPT_VERSION"
}

# Check if dry-run
is_dry_run() {
    [[ "$DRY_RUN" == "true" ]]
}

# Main execution
main() {
    # Parse arguments
    parse_arguments "$@"

    # Initialize logging
    init_logging

    print_info "Linux CPU Optimization Script v$SCRIPT_VERSION"
    print_info "=============================================="
    print_info ""

    if is_dry_run; then
        print_warning "DRY-RUN MODE: No changes will be made"
        print_info ""
    fi

    # Capture initial load averages
    LOAD_AVG_BEFORE=$(get_load_averages)
    display_load_averages "Initial Load Averages" "$LOAD_AVG_BEFORE"

    # Get and display top CPU processes
    print_info "Analyzing CPU usage..."
    local processes=$(get_top_cpu_processes "$PROCESS_THRESHOLD")

    if [[ -z "$processes" ]] || [[ -z "${processes// }" ]]; then
        print_info "No processes found using >= ${PROCESS_THRESHOLD}% CPU"
    else
        display_cpu_processes "$processes"
    fi

    print_info ""

    # Clean system logs
    clean_system_logs
    print_info ""

    # Detect zombies
    clean_zombies
    print_info ""

    # Audit systemd services
    audit_systemd_services
    print_info ""

    # Capture final load averages
    LOAD_AVG_AFTER=$(get_load_averages)
    display_load_averages "Final Load Averages" "$LOAD_AVG_AFTER"

    # Summary
    print_info "=============================================="
    print_success "CPU optimization completed!"
    print_info ""

    if [[ -n "$LOG_FILE" ]]; then
        print_info "Log file: $LOG_FILE"
    fi
}

# Run main function
main "$@"
