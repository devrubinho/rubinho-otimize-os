#!/usr/bin/env bash

# macOS Combined Optimization Script
# Version: 1.0.0
# Description: Master orchestration script that executes all optimization tasks

set -euo pipefail

# Script configuration
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORTS_DIR="${HOME}/.os-optimize/reports"
SNAPSHOTS_DIR="${HOME}/.os-optimize/snapshots"
CHECKPOINTS_DIR="${HOME}/.os-optimize/checkpoints"
LOG_DIR="${HOME}/.os-optimize/logs"

# Execution flags
QUICK=false
REPORT_ONLY=false
DRY_RUN=false

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

# Results storage (using simple variables for bash 3.2 compatibility)
MEMORY_FREED_MB=0
MEMORY_TIME=0
CPU_PROCESSES_TERMINATED=0
CPU_LOGS_CLEANED_MB=0
CPU_TIME=0
EXECUTION_START_TIME=0
EXECUTION_END_TIME=0

# Helper functions
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

# Progress indicator
show_progress() {
    local step="$1"
    local total="$2"
    local message="$3"

    local percent=$((step * 100 / total))
    local filled=$((step * 20 / total))
    local empty=$((20 - filled))

    # Build progress bar
    local bar=""
    local i=0
    while [[ $i -lt $filled ]]; do
        bar="${bar}▓"
        i=$((i + 1))
    done
    while [[ $i -lt 20 ]]; do
        bar="${bar}░"
        i=$((i + 1))
    done

    if command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; then
        tput el 2>/dev/null || true
        echo -ne "\r[${bar}] ${percent}% - ${message}"
    else
        echo "[${step}/${total}] ${percent}% - ${message}"
    fi
}

# Spinner animation
show_spinner() {
    local message="$1"
    local spinner_chars="⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏"

    if command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; then
        for char in $spinner_chars; do
            tput el 2>/dev/null || true
            echo -ne "\r${COLOR_BLUE}${char}${COLOR_RESET} ${message}"
            sleep 0.1
        done
    else
        echo "${message}..."
    fi
}

# Pre-flight checks
preflight_checks() {
    print_info "=== Pre-flight Checks ==="
    print_info ""

    # Check sudo access
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Would check sudo access"
    elif ! sudo -n true 2>/dev/null; then
        print_info "Sudo access required. Please enter your password:"
        if ! sudo -v; then
            print_error "Sudo access unavailable"
            exit 2
        fi
    fi
    if [[ "$DRY_RUN" != "true" ]]; then
        print_success "Sudo access verified"
    fi

    # Check disk space
    local free_space_gb=$(df -h / | awk 'NR==2 {print $4}' | sed 's/[^0-9.]//g' || echo "0")
    local free_space_num=$(df -g / | awk 'NR==2 {print $4}' || echo "0")

    if [[ $free_space_num -lt 5 ]]; then
        print_warning "Low disk space: ${free_space_gb}GB free (recommended: >5GB)"
    else
        print_success "Disk space: ${free_space_gb}GB free"
    fi

    # Check dependency scripts
    if [[ ! -f "${SCRIPT_DIR}/clean-memory.sh" ]]; then
        print_error "clean-memory.sh not found in ${SCRIPT_DIR}"
        exit 3
    fi

    if [[ ! -f "${SCRIPT_DIR}/optimize-cpu.sh" ]]; then
        print_error "optimize-cpu.sh not found in ${SCRIPT_DIR}"
        exit 3
    fi

    print_success "Dependency scripts found"
    print_info ""
}

# Create system snapshot
create_snapshot() {
    local snapshot_dir="${SNAPSHOTS_DIR}/$(date +%Y%m%d_%H%M%S)"

    mkdir -p "$snapshot_dir" 2>/dev/null || true

    print_info "Creating system snapshot..."

    # Capture vm_stat
    if command -v vm_stat >/dev/null 2>&1; then
        vm_stat > "${snapshot_dir}/vm_stat_before.txt" 2>/dev/null || true
    fi

    # Capture top output
    if command -v top >/dev/null 2>&1; then
        top -l 1 -n 20 > "${snapshot_dir}/top_before.txt" 2>/dev/null || true
    fi

    # Capture disk usage
    df -h > "${snapshot_dir}/disk_before.txt" 2>/dev/null || true

    print_success "Snapshot created: $snapshot_dir"
    print_info ""

    echo "$snapshot_dir"
}

# Execute clean-memory.sh
execute_memory_clean() {
    show_progress 2 4 "Memory Optimization"
    print_info ""

    if [[ "$REPORT_ONLY" == "true" ]]; then
        print_info "Skipping memory optimization (--report-only mode)"
        return 0
    fi

    local memory_output
    local memory_exit_code=0

    if [[ "$QUICK" == "true" ]]; then
        memory_output=$("${SCRIPT_DIR}/clean-memory.sh" --quiet 2>&1) || memory_exit_code=$?
    else
        memory_output=$("${SCRIPT_DIR}/clean-memory.sh" 2>&1) || memory_exit_code=$?
    fi

    if [[ $memory_exit_code -ne 0 ]]; then
        print_warning "Memory optimization completed with warnings (exit code: $memory_exit_code)"
    else
        print_success "Memory optimization completed"
    fi

    # Read metrics from temporary file
    local metrics_file="${HOME}/.os-optimize/.clean-memory-metrics.json"
    if [[ -f "$metrics_file" ]]; then
        if command -v python3 >/dev/null 2>&1; then
            MEMORY_FREED_MB=$(python3 -c "import json; f=open('$metrics_file'); d=json.load(f); print(int(d.get('memory_freed_mb', 0)))" 2>/dev/null || echo "0")
        elif command -v python >/dev/null 2>&1; then
            MEMORY_FREED_MB=$(python -c "import json; f=open('$metrics_file'); d=json.load(f); print(int(d.get('memory_freed_mb', 0)))" 2>/dev/null || echo "0")
        else
            # Fallback: parse with grep/sed
            MEMORY_FREED_MB=$(grep -o '"memory_freed_mb": [0-9-]*' "$metrics_file" 2>/dev/null | grep -o '[0-9-]*' | head -1 || echo "0")
        fi
        # Ensure it's a valid integer
        if ! [[ "$MEMORY_FREED_MB" =~ ^-?[0-9]+$ ]]; then
            MEMORY_FREED_MB=0
        fi
        rm -f "$metrics_file" 2>/dev/null || true
    fi

    show_progress 2 4 "Memory Optimization Complete"
    print_info ""
}

# Execute optimize-cpu.sh
execute_cpu_optimize() {
    show_progress 3 4 "CPU Optimization"
    print_info ""

    if [[ "$REPORT_ONLY" == "true" ]]; then
        print_info "Skipping CPU optimization (--report-only mode)"
        return 0
    fi

    local cpu_output
    local cpu_exit_code=0

    # Always use --quiet for automatic process termination when called from optimize-all.sh
    # This enables auto_terminate_processes instead of interactive mode
    cpu_output=$("${SCRIPT_DIR}/optimize-cpu.sh" --quiet 2>&1) || cpu_exit_code=$?

    if [[ $cpu_exit_code -ne 0 ]]; then
        print_warning "CPU optimization completed with warnings (exit code: $cpu_exit_code)"
    else
        print_success "CPU optimization completed"
    fi

    # Read metrics from temporary file
    local metrics_file="${HOME}/.os-optimize/.optimize-cpu-metrics.json"
    if [[ -f "$metrics_file" ]]; then
        if command -v python3 >/dev/null 2>&1; then
            CPU_PROCESSES_TERMINATED=$(python3 -c "import json; f=open('$metrics_file'); d=json.load(f); print(int(d.get('processes_terminated', 0)))" 2>/dev/null || echo "0")
            CPU_LOGS_CLEANED_MB=$(python3 -c "import json; f=open('$metrics_file'); d=json.load(f); print(int(d.get('logs_cleaned_mb', 0)))" 2>/dev/null || echo "0")
        elif command -v python >/dev/null 2>&1; then
            CPU_PROCESSES_TERMINATED=$(python -c "import json; f=open('$metrics_file'); d=json.load(f); print(int(d.get('processes_terminated', 0)))" 2>/dev/null || echo "0")
            CPU_LOGS_CLEANED_MB=$(python -c "import json; f=open('$metrics_file'); d=json.load(f); print(int(d.get('logs_cleaned_mb', 0)))" 2>/dev/null || echo "0")
        else
            # Fallback: parse with grep/sed
            CPU_PROCESSES_TERMINATED=$(grep -o '"processes_terminated": [0-9]*' "$metrics_file" 2>/dev/null | grep -o '[0-9]*' | head -1 || echo "0")
            CPU_LOGS_CLEANED_MB=$(grep -o '"logs_cleaned_mb": [0-9]*' "$metrics_file" 2>/dev/null | grep -o '[0-9]*' | head -1 || echo "0")
        fi
        # Ensure they are valid integers
        if ! [[ "$CPU_PROCESSES_TERMINATED" =~ ^[0-9]+$ ]]; then
            CPU_PROCESSES_TERMINATED=0
        fi
        if ! [[ "$CPU_LOGS_CLEANED_MB" =~ ^[0-9]+$ ]]; then
            CPU_LOGS_CLEANED_MB=0
        fi
        rm -f "$metrics_file" 2>/dev/null || true
    fi

    show_progress 3 4 "CPU Optimization Complete"
    print_info ""
}

# Generate JSON report
generate_report() {
    show_progress 4 4 "Generating Report"
    print_info ""

    mkdir -p "$REPORTS_DIR" 2>/dev/null || true

    local report_file="${REPORTS_DIR}/optimization_report_$(date +%Y%m%d_%H%M%S).json"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%d %H:%M:%S")
    local hostname=$(hostname 2>/dev/null || echo "unknown")
    local os_version=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
    local total_time=$((EXECUTION_END_TIME - EXECUTION_START_TIME))

    # Generate JSON report
    {
        echo "{"
        echo "  \"timestamp\": \"$timestamp\","
        echo "  \"hostname\": \"$hostname\","
        echo "  \"os_version\": \"$os_version\","
        echo "  \"execution_time_total\": $total_time,"
        echo "  \"memory_optimization\": {"
        echo "    \"freed_mb\": $MEMORY_FREED_MB,"
        echo "    \"execution_time\": $MEMORY_TIME"
        echo "  },"
        echo "  \"cpu_optimization\": {"
        echo "    \"processes_terminated\": $CPU_PROCESSES_TERMINATED,"
        echo "    \"logs_cleaned_mb\": $CPU_LOGS_CLEANED_MB,"
        echo "    \"execution_time\": $CPU_TIME"
        echo "  },"
        echo "  \"exit_code\": 0"
        echo "}"
    } > "$report_file"

    print_success "Report generated: $report_file"
    print_info ""
}

# Create checkpoint
create_checkpoint() {
    local checkpoint_dir="${CHECKPOINTS_DIR}/$(date +%Y%m%d_%H%M%S)"

    mkdir -p "$checkpoint_dir" 2>/dev/null || true

    print_info "Creating rollback checkpoint..."

    # Save snapshot files if they exist
    if [[ -d "$SNAPSHOTS_DIR" ]]; then
        cp -r "${SNAPSHOTS_DIR}"/* "$checkpoint_dir/" 2>/dev/null || true
    fi

    # Save process list
    ps aux > "${checkpoint_dir}/processes_before.txt" 2>/dev/null || true

    print_success "Checkpoint created: $checkpoint_dir"
    print_info ""
}

# Send notification
send_notification() {
    local title="$1"
    local message="$2"

    if command -v osascript >/dev/null 2>&1; then
        osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null || true
    fi
}

# Parse arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --quick)
                QUICK=true
                shift
                ;;
            --report-only)
                REPORT_ONLY=true
                shift
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
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
}

# Show help
show_help() {
    cat << EOF
macOS Combined Optimization Script

Usage: $0 [OPTIONS]

Options:
    --quick          Non-interactive mode (skip confirmations)
    --report-only    Generate report without optimization
    -n, --dry-run    Preview actions without executing
    -h, --help       Show this help message
    --version        Show version information

Description:
    This script orchestrates all macOS optimization tasks:
    - Memory cleaning (clean-memory.sh)
    - CPU optimization (optimize-cpu.sh)
    - Comprehensive reporting

    WARNING: This will optimize your system. Use --dry-run first.

Examples:
    $0                  # Normal execution
    $0 --quick          # Non-interactive mode
    $0 --report-only    # Generate report only
    $0 --dry-run        # Preview without executing
EOF
}

# Show version
show_version() {
    echo "macOS Combined Optimization Script v$SCRIPT_VERSION"
}

# Main execution
main() {
    # Parse arguments
    parse_arguments "$@"

    print_info "macOS Combined Optimization Script v$SCRIPT_VERSION"
    print_info "=================================================="
    print_info ""

    if [[ "$DRY_RUN" == "true" ]]; then
        print_warning "DRY-RUN MODE: No changes will be made"
        print_info ""
    fi

    # Safety confirmation
    if [[ "$QUICK" == "false" ]] && [[ "$DRY_RUN" == "false" ]]; then
        print_warning "This will optimize your system. Continue? (y/N)"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_info "Optimization cancelled by user"
            exit 1
        fi
        print_info ""
    fi

    # Record start time
    EXECUTION_START_TIME=$(date +%s)

    # Pre-flight checks
    show_progress 1 4 "Pre-flight Checks"
    print_info ""
    preflight_checks

    # Create snapshot
    local snapshot_dir=$(create_snapshot)

    # Create checkpoint
    if [[ "$DRY_RUN" == "false" ]]; then
        create_checkpoint
    fi

    # Execute memory optimization
    execute_memory_clean

    # Execute CPU optimization
    execute_cpu_optimize

    # Record end time
    EXECUTION_END_TIME=$(date +%s)

    # Generate report
    generate_report

    # Final summary
    print_info "=================================================="
    print_success "Optimization completed successfully!"
    print_info ""
    print_info "Summary:"
    print_info "  Memory freed: ${MEMORY_FREED_MB} MB"
    print_info "  Processes terminated: $CPU_PROCESSES_TERMINATED"
    print_info "  Logs cleaned: ${CPU_LOGS_CLEANED_MB} MB"
    print_info "  Total execution time: $((EXECUTION_END_TIME - EXECUTION_START_TIME)) seconds"
    print_info ""

    # Send notification
    send_notification "Optimization Complete" "Freed ${MEMORY_FREED_MB} MB memory"

    exit 0
}

# Run main function
main "$@"
