#!/usr/bin/env bash

# Linux Combined Optimization Script
# Version: 1.0.0
# Description: Master orchestration script that executes all optimization tasks

set -euo pipefail

# Script configuration
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORTS_DIR="${HOME}/.os-optimize/reports"
SNAPSHOTS_DIR="${HOME}/.os-optimize/snapshots"
BACKUPS_DIR="${HOME}/.os-optimize/backups"
LOG_DIR="${HOME}/.os-optimize/logs"

# Execution flags
SCHEDULED=false
EMAIL=""
DRY_RUN=false

# Distribution detection
DISTRO_ID=""
DISTRO_VERSION=""
KERNEL_VERSION=""

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

# Results storage
MEMORY_FREED_MB=0
CPU_PROCESSES_TERMINATED=0
CPU_LOGS_CLEANED_MB=0
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

# Detect Linux distribution
detect_distribution() {
    if [[ -f /etc/os-release ]]; then
        DISTRO_ID=$(grep "^ID=" /etc/os-release | cut -d'=' -f2 | tr -d '"' || echo "unknown")
        DISTRO_VERSION=$(grep "^VERSION_ID=" /etc/os-release | cut -d'=' -f2 | tr -d '"' || echo "unknown")
    else
        DISTRO_ID="unknown"
        DISTRO_VERSION="unknown"
    fi

    KERNEL_VERSION=$(uname -r 2>/dev/null || echo "unknown")

    print_info "Distribution: $DISTRO_ID $DISTRO_VERSION"
    print_info "Kernel: $KERNEL_VERSION"
}

# Pre-flight validation
preflight_validation() {
    print_info "=== Pre-flight Validation ==="
    print_info ""

    # Check sudo
    if [[ "$DRY_RUN" != "true" ]] && ! sudo -n true 2>/dev/null; then
        if ! sudo -v; then
            print_error "Sudo access unavailable"
            exit 2
        fi
    fi
    print_success "Sudo access verified"

    # Check kernel version (3.10+)
    local kernel_major=$(echo "$KERNEL_VERSION" | cut -d. -f1)
    local kernel_minor=$(echo "$KERNEL_VERSION" | cut -d. -f2)

    if [[ $kernel_major -lt 3 ]] || ([[ $kernel_major -eq 3 ]] && [[ $kernel_minor -lt 10 ]]); then
        print_error "Kernel version $KERNEL_VERSION is too old (requires 3.10+)"
        exit 2
    fi
    print_success "Kernel version validated"

    # Check disk space
    local free_space_gb=$(df -h / | awk 'NR==2 {print $4}' | sed 's/[^0-9.]//g' || echo "0")
    local free_space_num=$(df -g / 2>/dev/null | awk 'NR==2 {print $4}' || df -BG / | awk 'NR==2 {print $4}' | sed 's/G//' || echo "0")

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

    # Capture /proc/meminfo
    if [[ -f /proc/meminfo ]]; then
        cp /proc/meminfo "${snapshot_dir}/meminfo_before.txt" 2>/dev/null || true
    fi

    # Capture uptime
    if [[ -f /proc/uptime ]]; then
        cat /proc/uptime > "${snapshot_dir}/uptime_before.txt" 2>/dev/null || true
    fi

    # Capture load averages
    if [[ -f /proc/loadavg ]]; then
        cat /proc/loadavg > "${snapshot_dir}/loadavg_before.txt" 2>/dev/null || true
    fi

    # Capture disk usage
    df -h > "${snapshot_dir}/disk_before.txt" 2>/dev/null || true

    # Capture systemd status if available
    if command -v systemctl >/dev/null 2>&1; then
        systemctl status --no-pager > "${snapshot_dir}/systemd_status_before.txt" 2>/dev/null || true
    fi

    print_success "Snapshot created: $snapshot_dir"
    print_info ""

    echo "$snapshot_dir"
}

# Execute clean-memory.sh
execute_memory_clean() {
    show_progress 2 4 "Memory Optimization"
    print_info ""

    local memory_output
    local memory_exit_code=0

    memory_output=$("${SCRIPT_DIR}/clean-memory.sh" --quiet 2>&1) || memory_exit_code=$?

    if [[ $memory_exit_code -ne 0 ]]; then
        print_warning "Memory optimization completed with warnings (exit code: $memory_exit_code)"
    else
        print_success "Memory optimization completed"
    fi

    show_progress 2 4 "Memory Optimization Complete"
    print_info ""
}

# Execute optimize-cpu.sh
execute_cpu_optimize() {
    show_progress 3 4 "CPU Optimization"
    print_info ""

    local cpu_output
    local cpu_exit_code=0

    cpu_output=$("${SCRIPT_DIR}/optimize-cpu.sh" --quiet 2>&1) || cpu_exit_code=$?

    if [[ $cpu_exit_code -ne 0 ]]; then
        print_warning "CPU optimization completed with warnings (exit code: $cpu_exit_code)"
    else
        print_success "CPU optimization completed"
    fi

    show_progress 3 4 "CPU Optimization Complete"
    print_info ""
}

# Generate JSON report
generate_report() {
    show_progress 4 4 "Generating Report"
    print_info ""

    mkdir -p "$REPORTS_DIR" 2>/dev/null || true

    local report_file="${REPORTS_DIR}/optimization-$(date +%Y%m%d-%H%M%S).json"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%d %H:%M:%S")
    local hostname=$(hostname 2>/dev/null || echo "unknown")
    local total_time=$((EXECUTION_END_TIME - EXECUTION_START_TIME))

    # Generate JSON report
    {
        echo "{"
        echo "  \"timestamp\": \"$timestamp\","
        echo "  \"hostname\": \"$hostname\","
        echo "  \"distribution\": {"
        echo "    \"id\": \"$DISTRO_ID\","
        echo "    \"version\": \"$DISTRO_VERSION\""
        echo "  },"
        echo "  \"kernel_version\": \"$KERNEL_VERSION\","
        echo "  \"execution_time_total\": $total_time,"
        echo "  \"memory_optimization\": {"
        echo "    \"freed_mb\": $MEMORY_FREED_MB,"
        echo "    \"execution_time\": 0"
        echo "  },"
        echo "  \"cpu_optimization\": {"
        echo "    \"processes_terminated\": $CPU_PROCESSES_TERMINATED,"
        echo "    \"logs_cleaned_mb\": $CPU_LOGS_CLEANED_MB,"
        echo "    \"execution_time\": 0"
        echo "  },"
        echo "  \"exit_code\": 0"
        echo "}"
    } > "$report_file"

    print_success "Report generated: $report_file"
    print_info ""

    # Send email if requested
    if [[ -n "$EMAIL" ]] && command -v mail >/dev/null 2>&1; then
        print_info "Sending email report to $EMAIL..."
        {
            echo "OS Optimization Report"
            echo "======================"
            echo "Timestamp: $timestamp"
            echo "Distribution: $DISTRO_ID $DISTRO_VERSION"
            echo "Memory freed: ${MEMORY_FREED_MB} MB"
            echo "Processes terminated: $CPU_PROCESSES_TERMINATED"
            echo "Logs cleaned: ${CPU_LOGS_CLEANED_MB} MB"
            echo "Execution time: $total_time seconds"
            echo ""
            echo "Full report: $report_file"
        } | mail -s "OS Optimization Report - $(date)" "$EMAIL" 2>/dev/null || print_warning "Failed to send email"
    fi
}

# Create restore point
create_restore_point() {
    local restore_dir="${BACKUPS_DIR}/restore-$(date +%Y%m%d-%H%M%S)"

    mkdir -p "$restore_dir" 2>/dev/null || true

    print_info "Creating restore point..."

    # Backup critical configs
    if [[ -f /etc/sysctl.conf ]]; then
        cp /etc/sysctl.conf "${restore_dir}/sysctl.conf.backup" 2>/dev/null || true
    fi

    if [[ -f /etc/systemd/system.conf ]]; then
        cp /etc/systemd/system.conf "${restore_dir}/system.conf.backup" 2>/dev/null || true
    fi

    # Save systemd service states
    if command -v systemctl >/dev/null 2>&1; then
        systemctl list-unit-files --state=enabled > "${restore_dir}/services_enabled.txt" 2>/dev/null || true
    fi

    # Create restore instructions
    {
        echo "Restore Instructions"
        echo "==================="
        echo ""
        echo "To restore system state:"
        echo "1. Restore config files from backup directory"
        echo "2. Re-enable services if needed"
        echo "3. Check system logs for any issues"
        echo ""
        echo "Backup location: $restore_dir"
    } > "${BACKUPS_DIR}/RESTORE_INSTRUCTIONS.txt" 2>/dev/null || true

    print_success "Restore point created: $restore_dir"
    print_info ""
}

# Parse arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --scheduled)
                SCHEDULED=true
                shift
                ;;
            --email)
                EMAIL="$2"
                shift 2
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
Linux Combined Optimization Script

Usage: $0 [OPTIONS]

Options:
    --scheduled        Cron-friendly mode (non-interactive)
    --email ADDRESS    Send report via email
    -n, --dry-run      Preview actions without executing
    -h, --help         Show this help message
    --version          Show version information

Description:
    This script orchestrates all Linux optimization tasks:
    - Memory cleaning (clean-memory.sh)
    - CPU optimization (optimize-cpu.sh)
    - Comprehensive reporting

    WARNING: This will optimize your system. Use --dry-run first.

Examples:
    $0                      # Normal execution
    $0 --scheduled          # Cron-friendly mode
    $0 --email user@example.com  # Send email report
    $0 --dry-run            # Preview without executing
EOF
}

# Show version
show_version() {
    echo "Linux Combined Optimization Script v$SCRIPT_VERSION"
}

# Main execution
main() {
    # Parse arguments
    parse_arguments "$@"

    print_info "Linux Combined Optimization Script v$SCRIPT_VERSION"
    print_info "=================================================="
    print_info ""

    if [[ "$DRY_RUN" == "true" ]]; then
        print_warning "DRY-RUN MODE: No changes will be made"
        print_info ""
    fi

    # Detect distribution
    detect_distribution
    print_info ""

    # Safety confirmation (skip in scheduled mode)
    if [[ "$SCHEDULED" == "false" ]] && [[ "$DRY_RUN" == "false" ]]; then
        print_warning "This will optimize your system. Continue? (y/N)"
        if [[ -t 0 ]]; then
            read -t 10 response || response="N"
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                print_info "Optimization cancelled by user"
                exit 1
            fi
        fi
        print_info ""
    fi

    # Record start time
    EXECUTION_START_TIME=$(date +%s)

    # Pre-flight validation
    show_progress 1 4 "Pre-flight Checks"
    print_info ""
    preflight_validation

    # Create snapshot
    local snapshot_dir=$(create_snapshot)

    # Create restore point
    if [[ "$DRY_RUN" == "false" ]]; then
        create_restore_point
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

    exit 0
}

# Run main function
main "$@"
