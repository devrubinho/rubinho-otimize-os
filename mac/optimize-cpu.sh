#!/usr/bin/env bash

# macOS CPU Optimization Script
# Version: 1.0.0
# Description: Identifies resource-heavy processes and cleans system logs

set -euo pipefail

# Script configuration
SCRIPT_VERSION="1.0.0"
LOG_DIR="${HOME}/.os-optimize/logs"
CONFIG_DIR="${HOME}/.os-optimize"
PROTECTED_PROCESSES_FILE="${CONFIG_DIR}/protected-processes.txt"
LOG_FILE=""

# Execution flags
DRY_RUN=false
QUIET=false
VERBOSE=false

# Metrics tracking
PROCESSES_TERMINATED=0
LOGS_CLEANED_MB=0
PROCESS_THRESHOLD=20

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

# Safe-kill list (critical processes that should never be killed)
SAFE_KILL_LIST=(
    "kernel_task"
    "launchd"
    "WindowServer"
    "systemstats"
    "hidd"
    "loginwindow"
    "UserEventAgent"
    "cfprefsd"
    "Dock"
    "Finder"
    "Cursor"
    "cursor"
    "Code"
    "code"
    "Xcode"
    "xcode"
    "Sublime Text"
    "sublime"
    "Atom"
    "atom"
    "WebStorm"
    "webstorm"
    "IntelliJ"
    "intellij"
    "Terminal"
    "terminal"
    "iTerm"
    "iterm"
    "zsh"
    "bash"
    "fish"
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

        # Log header
        {
            echo "=========================================="
            echo "macOS CPU Optimization Script - Log"
            echo "=========================================="
            echo "Timestamp: $(date)"
            echo "macOS Version: $(sw_vers -productVersion 2>/dev/null || echo 'unknown')"
            echo "Hostname: $(hostname 2>/dev/null || echo 'unknown')"
            echo "User: $(whoami 2>/dev/null || echo 'unknown')"
            echo "Script Version: $SCRIPT_VERSION"
            echo "Flags: DRY_RUN=$DRY_RUN, QUIET=$QUIET, VERBOSE=$VERBOSE"
            echo "Process Threshold: ${PROCESS_THRESHOLD}%"
            echo "=========================================="
            echo ""
            echo "Rollback Reference:"
            echo "To restart a terminated process, use:"
            echo "  - For applications: open -a 'Application Name'"
            echo "  - For services: launchctl load ~/Library/LaunchAgents/com.example.service.plist"
            echo "  - Check log file for full command line of terminated processes"
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
    if command -v sysctl >/dev/null 2>&1; then
        sysctl -n vm.loadavg 2>/dev/null | sed 's/{ //;s/ }//' | awk '{printf "%.2f %.2f %.2f", $1, $2, $3}' || echo "0.00 0.00 0.00"
    else
        uptime 2>/dev/null | awk -F'load average:' '{print $2}' | sed 's/,//g' | awk '{printf "%.2f %.2f %.2f", $1, $2, $3}' || echo "0.00 0.00 0.00"
    fi
}

# Display load averages
display_load_averages() {
    local label="$1"
    local load_avg="$2"

    print_info ""
    print_info "=== $label ==="
    print_info "Load Average (1min, 5min, 15min): $load_avg"
    print_info ""
}

# Check if process is protected
is_protected_process() {
    local process_name="$1"
    local pid="$2"
    local user="$3"

    # Check PID protection (0, 1, and low PIDs)
    if [[ $pid -eq 0 ]] || [[ $pid -eq 1 ]] || [[ $pid -lt 100 ]]; then
        return 0  # Protected
    fi

    # Protect processes owned by current user (to avoid killing user's active applications)
    local current_user=$(whoami 2>/dev/null || echo "")
    if [[ -n "$user" ]] && [[ "$user" == "$current_user" ]]; then
        # Additional check: only protect if it's a GUI application or important process
        # Check if it's in /Applications (GUI app)
        if ps -p "$pid" -o command= 2>/dev/null | grep -q "/Applications/"; then
            return 0  # Protected - GUI application
        fi
    fi

    # Check safe-kill list (case-insensitive)
    local process_lower=$(echo "$process_name" | tr '[:upper:]' '[:lower:]')
    for protected in "${SAFE_KILL_LIST[@]}"; do
        local protected_lower=$(echo "$protected" | tr '[:upper:]' '[:lower:]')
        if [[ "$process_lower" == "$protected_lower" ]] || [[ "$process_lower" == *"$protected_lower"* ]]; then
            return 0  # Protected
        fi
    done

    # Check protected processes file if it exists
    if [[ -f "$PROTECTED_PROCESSES_FILE" ]]; then
        while IFS= read -r line; do
            # Skip comments and empty lines
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue

            # Check for regex pattern (starts with ^)
            if [[ "$line" =~ ^\^ ]]; then
                if echo "$process_name" | grep -qE "$line"; then
                    return 0  # Protected
                fi
            elif [[ "$process_name" == "$line" ]]; then
                return 0  # Protected
            fi
        done < "$PROTECTED_PROCESSES_FILE"
    fi

    return 1  # Not protected
}

# Get top CPU processes
get_top_cpu_processes() {
    local threshold="$1"

    if ! command -v top >/dev/null 2>&1; then
        print_error "top command not found"
        return 1
    fi

    # Use ps aux as fallback (more reliable on macOS)
    if command -v ps >/dev/null 2>&1; then
        ps aux | awk -v threshold="$threshold" '
            NR > 1 && $3 + 0 >= threshold {
                pid = $2
                cpu = $3
                user = $1
                # Command is from column 11 onwards
                cmd = ""
                for (i = 11; i <= NF; i++) {
                    cmd = cmd " " $i
                }
                gsub(/^ /, "", cmd)
                # Truncate long commands
                if (length(cmd) > 50) {
                    cmd = substr(cmd, 1, 47) "..."
                }
                printf "%s|%.1f|%s|%s|high\n", pid, cpu, user, cmd
            }
        ' | sort -t'|' -k2 -rn | head -10
    else
        print_error "ps command not found"
        return 1
    fi
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

# Kill process safely
kill_process_safe() {
    local pid="$1"
    local process_name="$2"
    local cpu="$3"
    local user="$4"
    local command_line="$5"

    # Check if protected
    if is_protected_process "$process_name" "$pid" "$user"; then
        print_warning "Process $process_name (PID $pid) is protected and cannot be killed"
        log_message "PROTECTED" "PID=$pid, Name=$process_name, CPU=$cpu%, User=$user, Command=$command_line"
        return 1
    fi

    # Log before killing
    log_message "KILLED" "PID=$pid, Name=$process_name, CPU=$cpu%, User=$user, Command=$command_line"

    if is_dry_run; then
        print_info "[DRY-RUN] Would kill process: $process_name (PID $pid, CPU $cpu%)"
        return 0
    fi

    # Try SIGTERM first
    if kill -TERM "$pid" 2>/dev/null; then
        print_info "Sent SIGTERM to $process_name (PID $pid)"
        sleep 2

        # Check if still running
        if kill -0 "$pid" 2>/dev/null; then
            print_warning "Process still running after SIGTERM, sending SIGKILL..."
            if kill -KILL "$pid" 2>/dev/null; then
                print_success "Process $process_name (PID $pid) terminated"
                PROCESSES_TERMINATED=$((PROCESSES_TERMINATED + 1))
                return 0
            else
                print_error "Failed to kill process $process_name (PID $pid)"
                return 1
            fi
        else
            print_success "Process $process_name (PID $pid) terminated gracefully"
            PROCESSES_TERMINATED=$((PROCESSES_TERMINATED + 1))
            return 0
        fi
    else
        print_error "Failed to send signal to process $process_name (PID $pid)"
        return 1
    fi
}

# Clean ASL logs
clean_asl_logs() {
    print_info "=== ASL Log Cleanup ==="

    local asl_dir="/var/log/asl"

    if is_dry_run; then
        print_info "[DRY-RUN] Would execute: sudo rm -rf $asl_dir/*.asl"
        return 0
    fi

    # Check sudo
    if ! sudo -n true 2>/dev/null; then
        if ! sudo -v; then
            print_error "Sudo access required for ASL log cleanup"
            return 1
        fi
    fi

    if [[ ! -d "$asl_dir" ]]; then
        print_warning "ASL log directory not found: $asl_dir"
        return 1
    fi

    print_info "Cleaning ASL logs..."

    local count=$(find "$asl_dir" -name "*.asl" -type f 2>/dev/null | wc -l | tr -d ' ')

    if [[ $count -gt 0 ]]; then
        # Calculate size before deletion
        local size_bytes=0
        if command -v du >/dev/null 2>&1; then
            # Use du for more reliable size calculation
            size_bytes=$(du -sk "$asl_dir"/*.asl 2>/dev/null | awk '{sum+=$1} END {print sum*1024+0}')
        else
            # Fallback to stat
            size_bytes=$(find "$asl_dir" -name "*.asl" -type f -exec stat -f "%z" {} \; 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
        fi
        local size_mb=$((size_bytes / 1024 / 1024))
        # Ensure non-negative
        if [[ $size_mb -lt 0 ]]; then
            size_mb=0
        fi

        if sudo rm -rf "$asl_dir"/*.asl 2>/dev/null; then
            print_success "Removed $count ASL log file(s)"
            log_message "INFO" "ASL logs cleaned: $count files removed"
            LOGS_CLEANED_MB=$((LOGS_CLEANED_MB + size_mb))
            return 0
        else
            print_error "Failed to remove ASL logs"
            return 1
        fi
    else
        print_info "No ASL logs to clean"
        return 0
    fi
}

# Optimize unified logs
optimize_unified_logs() {
    print_info "=== Unified Log Optimization ==="

    if is_dry_run; then
        print_info "[DRY-RUN] Would execute: sudo log erase --all --ttl 30"
        return 0
    fi

    # Check sudo
    if ! sudo -n true 2>/dev/null; then
        if ! sudo -v; then
            print_warning "Sudo access required for unified log optimization. Skipping (optional)."
            return 0  # Don't fail the script for optional optimization
        fi
    fi

    if ! command -v log >/dev/null 2>&1; then
        print_warning "log command not found. Skipping unified log optimization (optional)."
        return 0  # Don't fail the script for optional optimization
    fi

    print_info "Optimizing unified logs (keeping last 30 days)..."

    # Try to optimize unified logs - this is optional, so don't fail if it doesn't work
    # The log command syntax varies by macOS version, so we try multiple approaches
    local success=false

    # Try method 1: log erase with TTL (macOS 10.12+)
    # This removes logs older than 30 days without creating archive files
    if sudo log erase --ttl 30d 2>/dev/null; then
        success=true
    # Try method 2: log config to set TTL
    # This configures the system to automatically prune logs older than 30 days
    elif sudo log config --ttl 30d 2>/dev/null; then
        success=true
    # Note: We don't use "log collect" as it creates archive files (system_logs.logarchive)
    # which we want to avoid
    fi

    if [[ "$success" == "true" ]]; then
        print_success "Unified logs optimized (TTL: 30 days)"
        log_message "INFO" "Unified logs optimized: TTL set to 30 days"
    else
        # This is an optional optimization - don't fail the script
        print_warning "Could not optimize unified logs (optional feature, safe to skip)"
        log_message "WARN" "Unified log optimization skipped (command syntax may vary by macOS version)"
    fi

    return 0  # Always return success since this is optional
}

# Automatic process termination (for non-interactive mode)
auto_terminate_processes() {
    local processes="$1"
    local terminated=0
    local skipped=0

    if [[ -z "$processes" ]] || [[ -z "${processes// }" ]]; then
        return 0
    fi

    if is_dry_run; then
        print_info "[DRY-RUN] Would automatically terminate high CPU processes"
        return 0
    fi

    print_info ""
    print_info "Automatically terminating high CPU processes..."

    # Use process substitution to avoid subshell issues
    while IFS='|' read -r pid cpu user cmd level; do
        if [[ -z "$pid" ]]; then
            continue
        fi

        # Extract process name from command (first word)
        local process_name=$(echo "$cmd" | awk '{print $1}' | xargs basename 2>/dev/null || echo "$cmd")

        # Skip if process no longer exists
        if ! kill -0 "$pid" 2>/dev/null; then
            log_message "INFO" "Process $process_name (PID $pid) no longer exists, skipping"
            skipped=$((skipped + 1))
            continue
        fi

        # Check if process is protected
        if is_protected_process "$process_name" "$pid" "$user"; then
            log_message "PROTECTED" "Skipping protected process: $process_name (PID $pid, CPU $cpu%, User=$user)"
            skipped=$((skipped + 1))
            continue
        fi

        # Terminate the process
        if kill_process_safe "$pid" "$process_name" "$cpu" "$user" "$cmd"; then
            terminated=$((terminated + 1))
            PROCESSES_TERMINATED=$((PROCESSES_TERMINATED + 1))
            log_message "INFO" "Automatically terminated: $process_name (PID $pid, CPU $cpu%)"
        else
            skipped=$((skipped + 1))
        fi
    done < <(echo "$processes")

    if [[ $terminated -gt 0 ]]; then
        print_success "Terminated $terminated process(es) automatically"
    fi
    if [[ $skipped -gt 0 ]]; then
        print_info "Skipped $skipped protected or failed process(es)"
    fi
}

# Interactive process management
interactive_process_management() {
    local processes="$1"

    if [[ -z "$processes" ]] || [[ -z "${processes// }" ]]; then
        return 0
    fi

    if is_dry_run; then
        print_info "[DRY-RUN] Interactive process management would be available here"
        return 0
    fi

    print_info ""
    print_info "Interactive Process Management"
    print_info "Enter process numbers to kill (comma-separated, e.g., 1,3,5) or 'q' to quit:"

    local selection
    read -r selection

    if [[ "$selection" == "q" ]] || [[ "$selection" == "Q" ]]; then
        print_info "Skipping process termination"
        return 0
    fi

    # Parse comma-separated selection
    local IFS=','
    local selected_pids=()
    local process_array=()
    local index=1

    # Convert processes string to array
    echo "$processes" | while IFS='|' read -r pid cpu user cmd level; do
        if [[ -n "$pid" ]]; then
            process_array+=("$pid|$cpu|$user|$cmd")
        fi
    done

    # Process selection (simplified - would need array handling in bash 3.2)
    print_info "Process termination feature (simplified implementation)"
    print_info "Full interactive mode requires bash 4.0+ for array support"
}

# Check Spotlight indexing
check_spotlight_indexing() {
    print_info "=== Spotlight Indexing Check ==="

    if ! command -v mdutil >/dev/null 2>&1; then
        print_warning "mdutil command not found. Skipping Spotlight check."
        return 1
    fi

    print_info "Checking Spotlight indexing status..."

    local status=$(mdutil -s / 2>/dev/null | head -1)

    if echo "$status" | grep -qi "indexing enabled"; then
        print_info "Spotlight indexing: Enabled"
        log_message "INFO" "Spotlight indexing: Enabled"
    elif echo "$status" | grep -qi "indexing disabled"; then
        print_info "Spotlight indexing: Disabled"
        log_message "INFO" "Spotlight indexing: Disabled"
    else
        print_info "Spotlight status: $status"
    fi

    # Check for Spotlight metadata size
    if [[ -d "/.Spotlight-V100" ]]; then
        local size=$(du -sh /.Spotlight-V100 2>/dev/null | awk '{print $1}' || echo "unknown")
        print_info "Spotlight metadata size: $size"
    fi

    return 0
}

# Audit launch daemons (basic implementation)
audit_launch_daemons() {
    print_info "=== Launch Daemon Audit ==="

    print_info "Scanning launch daemons and agents..."

    local daemon_count=0
    local agent_count=0

    # Count system launch daemons
    if [[ -d "/Library/LaunchDaemons" ]]; then
        daemon_count=$(find /Library/LaunchDaemons -name "*.plist" -type f 2>/dev/null | wc -l | tr -d ' ')
    fi

    # Count user launch agents
    if [[ -d "${HOME}/Library/LaunchAgents" ]]; then
        agent_count=$(find "${HOME}/Library/LaunchAgents" -name "*.plist" -type f 2>/dev/null | wc -l | tr -d ' ')
    fi

    print_info "Found:"
    print_info "  System launch daemons: $daemon_count"
    print_info "  User launch agents: $agent_count"

    log_message "INFO" "Launch daemon audit: $daemon_count daemons, $agent_count agents"

    print_info "Note: Interactive disabling requires user confirmation (not implemented in basic version)"

    return 0
}

# Initialize protected processes file
init_protected_processes_file() {
    if [[ ! -f "$PROTECTED_PROCESSES_FILE" ]]; then
        print_debug "Creating default protected processes file..."

        {
            echo "# Protected Processes Whitelist"
            echo "# One process name per line"
            echo "# Lines starting with # are comments"
            echo "# Regex patterns supported (e.g., ^kernel.*)"
            echo ""
            echo "# Default protected processes:"
            for proc in "${SAFE_KILL_LIST[@]}"; do
                echo "$proc"
            done
        } > "$PROTECTED_PROCESSES_FILE" 2>/dev/null || true

        print_debug "Created protected processes file: $PROTECTED_PROCESSES_FILE"
    fi
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
macOS CPU Optimization Script

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
    - ASL log cleanup
    - Unified log optimization

    WARNING: Process termination is irreversible. Use --dry-run first.

Examples:
    $0                          # Normal execution
    $0 --dry-run                # Preview without making changes
    $0 --process-threshold 30   # Show processes using >= 30% CPU
EOF
}

# Show version
show_version() {
    echo "macOS CPU Optimization Script v$SCRIPT_VERSION"
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

    # Create config directory
    mkdir -p "$CONFIG_DIR" 2>/dev/null || true

    # Initialize protected processes file
    init_protected_processes_file

    print_info "macOS CPU Optimization Script v$SCRIPT_VERSION"
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

        # Automatic process termination for non-interactive mode
        if [[ "$QUIET" == "true" ]] && [[ "$DRY_RUN" == "false" ]]; then
            auto_terminate_processes "$processes"
        # Interactive process management for interactive mode
        elif [[ "$QUIET" == "false" ]] && [[ "$DRY_RUN" == "false" ]]; then
            interactive_process_management "$processes"
        elif [[ "$DRY_RUN" == "true" ]]; then
            print_info "[DRY-RUN] Would terminate processes in non-dry-run mode"
        fi

        # Log summary if in quiet mode
        if [[ "$QUIET" == "true" ]] && [[ $PROCESSES_TERMINATED -gt 0 ]]; then
            print_info "Automatically terminated $PROCESSES_TERMINATED process(es)"
        fi
    fi

    print_info ""

    # Check Spotlight indexing
    check_spotlight_indexing
    print_info ""

    # Audit launch daemons
    audit_launch_daemons
    print_info ""

    # Clean ASL logs
    clean_asl_logs
    print_info ""

    # Optimize unified logs (optional - don't fail if it doesn't work)
    set +e  # Temporarily disable exit on error for optional optimization
    optimize_unified_logs
    set -e  # Re-enable exit on error
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

    # Write metrics to temporary file for parent script
    local metrics_file="${HOME}/.os-optimize/.optimize-cpu-metrics.json"
    mkdir -p "$(dirname "$metrics_file")" 2>/dev/null || true
    {
        echo "{"
        echo "  \"processes_terminated\": $PROCESSES_TERMINATED,"
        echo "  \"logs_cleaned_mb\": $LOGS_CLEANED_MB"
        echo "}"
    } > "$metrics_file" 2>/dev/null || true
}

# Run main function
main "$@"
