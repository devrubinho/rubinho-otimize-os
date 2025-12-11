#!/usr/bin/env bash

# Linux Memory Cleaning Script
# Version: 1.0.0
# Description: Safely drops caches and manages swap on Linux systems

set -euo pipefail

# Script configuration
SCRIPT_VERSION="1.0.0"
LOG_DIR="${HOME}/.os-optimize/logs"
LOG_FILE=""

# Execution flags
DRY_RUN=false
AGGRESSIVE=false
QUIET=false
VERBOSE=false
PRESERVE_PACKAGE_CACHE=false
CACHE_LEVEL=3

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

# Memory statistics (before/after)
MEM_TOTAL_BEFORE=0
MEM_FREE_BEFORE=0
MEM_AVAILABLE_BEFORE=0
MEM_CACHED_BEFORE=0
SWAP_TOTAL_BEFORE=0
SWAP_FREE_BEFORE=0

MEM_TOTAL_AFTER=0
MEM_FREE_AFTER=0
MEM_AVAILABLE_AFTER=0
MEM_CACHED_AFTER=0
SWAP_TOTAL_AFTER=0
SWAP_FREE_AFTER=0

# Distribution detection
DISTRO_ID=""
DISTRO_VERSION=""

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
    # Try system log directory first, fallback to user directory
    if [[ -w "/var/log" ]] && sudo -n true 2>/dev/null; then
        if sudo mkdir -p /var/log/os-optimize 2>/dev/null; then
            LOG_DIR="/var/log/os-optimize"
        fi
    fi

    if mkdir -p "$LOG_DIR" 2>/dev/null; then
        chmod 755 "$LOG_DIR" 2>/dev/null || true
        local timestamp=$(date +%Y%m%d-%H%M%S)
        LOG_FILE="${LOG_DIR}/clean-memory-${timestamp}.log"

        {
            echo "=========================================="
            echo "Linux Memory Clean Script - Log"
            echo "=========================================="
            echo "Timestamp: $(date)"
            echo "Distribution: $DISTRO_ID $DISTRO_VERSION"
            echo "Kernel: $(uname -r 2>/dev/null || echo 'unknown')"
            echo "Hostname: $(hostname 2>/dev/null || echo 'unknown')"
            echo "User: $(whoami 2>/dev/null || echo 'unknown')"
            echo "Script Version: $SCRIPT_VERSION"
            echo "Flags: DRY_RUN=$DRY_RUN, AGGRESSIVE=$AGGRESSIVE, CACHE_LEVEL=$CACHE_LEVEL"
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

# Detect Linux distribution
detect_distribution() {
    if [[ -f /etc/os-release ]]; then
        DISTRO_ID=$(grep "^ID=" /etc/os-release | cut -d'=' -f2 | tr -d '"' || echo "unknown")
        DISTRO_VERSION=$(grep "^VERSION_ID=" /etc/os-release | cut -d'=' -f2 | tr -d '"' || echo "unknown")
    elif [[ -f /etc/lsb-release ]]; then
        DISTRO_ID=$(grep "^DISTRIB_ID=" /etc/lsb-release | cut -d'=' -f2 | tr -d '"' || echo "unknown")
        DISTRO_VERSION=$(grep "^DISTRIB_RELEASE=" /etc/lsb-release | cut -d'=' -f2 | tr -d '"' || echo "unknown")
    else
        DISTRO_ID="unknown"
        DISTRO_VERSION="unknown"
    fi

    print_debug "Detected distribution: $DISTRO_ID $DISTRO_VERSION"
}

# Get memory statistics from /proc/meminfo
get_memory_stats() {
    if [[ ! -f /proc/meminfo ]]; then
        print_error "/proc/meminfo not found"
        return 1
    fi

    # Parse /proc/meminfo (values are in KB)
    MEM_TOTAL_BEFORE=$(grep "^MemTotal:" /proc/meminfo | awk '{print $2}' || echo "0")
    MEM_FREE_BEFORE=$(grep "^MemFree:" /proc/meminfo | awk '{print $2}' || echo "0")
    MEM_AVAILABLE_BEFORE=$(grep "^MemAvailable:" /proc/meminfo | awk '{print $2}' || echo "0")
    MEM_CACHED_BEFORE=$(grep "^Cached:" /proc/meminfo | awk '{print $2}' || echo "0")
    SWAP_TOTAL_BEFORE=$(grep "^SwapTotal:" /proc/meminfo | awk '{print $2}' || echo "0")
    SWAP_FREE_BEFORE=$(grep "^SwapFree:" /proc/meminfo | awk '{print $2}' || echo "0")

    # Convert KB to MB
    MEM_TOTAL_BEFORE=$((MEM_TOTAL_BEFORE / 1024))
    MEM_FREE_BEFORE=$((MEM_FREE_BEFORE / 1024))
    MEM_AVAILABLE_BEFORE=$((MEM_AVAILABLE_BEFORE / 1024))
    MEM_CACHED_BEFORE=$((MEM_CACHED_BEFORE / 1024))
    SWAP_TOTAL_BEFORE=$((SWAP_TOTAL_BEFORE / 1024))
    SWAP_FREE_BEFORE=$((SWAP_FREE_BEFORE / 1024))

    print_debug "Memory stats: Total=${MEM_TOTAL_BEFORE}MB, Free=${MEM_FREE_BEFORE}MB, Cached=${MEM_CACHED_BEFORE}MB"
}

# Display memory statistics
display_memory_stats() {
    local label="$1"
    local mode="$2"  # "before" or "after"

    local total free available cached swap_total swap_free

    if [[ "$mode" == "before" ]]; then
        total=$MEM_TOTAL_BEFORE
        free=$MEM_FREE_BEFORE
        available=$MEM_AVAILABLE_BEFORE
        cached=$MEM_CACHED_BEFORE
        swap_total=$SWAP_TOTAL_BEFORE
        swap_free=$SWAP_FREE_BEFORE
    else
        total=$MEM_TOTAL_AFTER
        free=$MEM_FREE_AFTER
        available=$MEM_AVAILABLE_AFTER
        cached=$MEM_CACHED_AFTER
        swap_total=$SWAP_TOTAL_AFTER
        swap_free=$SWAP_FREE_AFTER
    fi

    print_info ""
    print_info "=== $label ==="
    print_info "Total Memory:    ${total} MB"
    print_info "Free:            ${free} MB"
    print_info "Available:       ${available} MB"
    print_info "Cached:          ${cached} MB"

    if [[ $swap_total -gt 0 ]]; then
        local swap_used=$((swap_total - swap_free))
        local swap_percent=$((swap_used * 100 / swap_total))
        print_info "Swap Total:      ${swap_total} MB"
        print_info "Swap Free:       ${swap_free} MB"
        print_info "Swap Used:       ${swap_percent}%"
    fi

    # Calculate utilization
    if [[ $total -gt 0 ]]; then
        local used=$((total - free))
        local utilization=$((used * 100 / total))
        print_info "Utilization:     ${utilization}%"
    fi
    print_info ""
}

# Safe cache dropping
drop_caches() {
    print_info "=== Cache Dropping ==="

    if [[ "$CACHE_LEVEL" -lt 1 ]] || [[ "$CACHE_LEVEL" -gt 3 ]]; then
        print_error "Invalid cache level: $CACHE_LEVEL (must be 1, 2, or 3)"
        return 1
    fi

    if is_dry_run; then
        print_info "[DRY-RUN] Would execute: sync && echo $CACHE_LEVEL | sudo tee /proc/sys/vm/drop_caches"
        print_info "  Cache level $CACHE_LEVEL:"
        case "$CACHE_LEVEL" in
            1) print_info "    - Pagecache only" ;;
            2) print_info "    - Dentries and inodes" ;;
            3) print_info "    - All caches (pagecache, dentries, inodes)" ;;
        esac
        return 0
    fi

    # Check sudo
    if ! sudo -n true 2>/dev/null; then
        if ! sudo -v; then
            print_error "Sudo access required for cache dropping"
            return 1
        fi
    fi

    print_info "Flushing filesystem buffers (sync)..."
    sync

    print_info "Dropping caches (level $CACHE_LEVEL)..."

    if echo "$CACHE_LEVEL" | sudo tee /proc/sys/vm/drop_caches >/dev/null 2>&1; then
        print_success "Cache dropped successfully"
        log_message "INFO" "Cache dropped: level $CACHE_LEVEL"
        return 0
    else
        print_error "Failed to drop caches"
        log_message "ERROR" "Cache drop failed"
        return 1
    fi
}

# Swap management
manage_swap() {
    print_info "=== Swap Management ==="

    if [[ $SWAP_TOTAL_BEFORE -eq 0 ]]; then
        print_info "No swap configured on this system"
        return 0
    fi

    local swap_used=$((SWAP_TOTAL_BEFORE - SWAP_FREE_BEFORE))
    local swap_percent=$((swap_used * 100 / SWAP_TOTAL_BEFORE))

    print_info "Swap usage: ${swap_percent}% (${swap_used} MB / ${SWAP_TOTAL_BEFORE} MB)"

    # Only clear swap if usage > 50% and sufficient RAM available
    if [[ $swap_percent -lt 50 ]]; then
        print_info "Swap usage is low (<50%), skipping swap clearing"
        return 0
    fi

    # Check if sufficient RAM available (at least 2x swap used)
    local required_ram=$((swap_used * 2))
    if [[ $MEM_AVAILABLE_BEFORE -lt $required_ram ]]; then
        print_warning "Insufficient RAM available (${MEM_AVAILABLE_BEFORE}MB) to safely clear swap (requires ${required_ram}MB)"
        return 1
    fi

    if is_dry_run; then
        print_info "[DRY-RUN] Would execute: sudo swapoff -a && sudo swapon -a"
        return 0
    fi

    if [[ "$AGGRESSIVE" != "true" ]]; then
        print_warning "Swap clearing requires confirmation (use --aggressive to skip)"
        print_info "Clear swap? This will temporarily disable swap. Continue? (y/N): "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_info "Swap clearing cancelled"
            return 0
        fi
    fi

    # Check sudo
    if ! sudo -n true 2>/dev/null; then
        if ! sudo -v; then
            print_error "Sudo access required for swap management"
            return 1
        fi
    fi

    print_info "Clearing swap (this may take a moment)..."

    if sudo swapoff -a 2>/dev/null && sudo swapon -a 2>/dev/null; then
        print_success "Swap cleared successfully"
        log_message "INFO" "Swap cleared: ${swap_used}MB freed"
        return 0
    else
        print_error "Failed to clear swap"
        log_message "ERROR" "Swap clear failed"
        return 1
    fi
}

# Clean package manager cache
clean_package_cache() {
    print_info "=== Package Manager Cache Cleanup ==="

    if [[ "$PRESERVE_PACKAGE_CACHE" == "true" ]]; then
        print_info "Package cache preservation enabled, skipping cleanup"
        return 0
    fi

    local space_freed=0

    case "$DISTRO_ID" in
        ubuntu|debian)
            if command -v apt-get >/dev/null 2>&1; then
                if is_dry_run; then
                    print_info "[DRY-RUN] Would execute: sudo apt-get clean"
                else
                    if sudo -n true 2>/dev/null || sudo -v; then
                        print_info "Cleaning apt cache..."
                        if sudo apt-get clean >/dev/null 2>&1; then
                            print_success "Apt cache cleaned"
                            log_message "INFO" "Apt cache cleaned"
                        fi
                    fi
                fi
            fi
            ;;
        fedora|rhel|centos)
            if command -v dnf >/dev/null 2>&1; then
                if is_dry_run; then
                    print_info "[DRY-RUN] Would execute: sudo dnf clean all"
                else
                    if sudo -n true 2>/dev/null || sudo -v; then
                        print_info "Cleaning dnf cache..."
                        if sudo dnf clean all >/dev/null 2>&1; then
                            print_success "Dnf cache cleaned"
                            log_message "INFO" "Dnf cache cleaned"
                        fi
                    fi
                fi
            fi
            ;;
        arch|manjaro)
            if command -v pacman >/dev/null 2>&1; then
                if is_dry_run; then
                    print_info "[DRY-RUN] Would execute: sudo pacman -Sc --noconfirm"
                else
                    if sudo -n true 2>/dev/null || sudo -v; then
                        print_info "Cleaning pacman cache..."
                        if sudo pacman -Sc --noconfirm >/dev/null 2>&1; then
                            print_success "Pacman cache cleaned"
                            log_message "INFO" "Pacman cache cleaned"
                        fi
                    fi
                fi
            fi
            ;;
        *)
            print_info "Package manager not detected or not supported: $DISTRO_ID"
            ;;
    esac
}

# Clean systemd journal
clean_journal() {
    print_info "=== Systemd Journal Cleanup ==="

    if ! command -v journalctl >/dev/null 2>&1; then
        print_info "Systemd journal not available (non-systemd system)"
        return 0
    fi

    if is_dry_run; then
        print_info "[DRY-RUN] Would execute: sudo journalctl --vacuum-time=7d"
        return 0
    fi

    # Check sudo
    if ! sudo -n true 2>/dev/null; then
        if ! sudo -v; then
            print_warning "Sudo access required for journal cleanup"
            return 1
        fi
    fi

    print_info "Vacuuming systemd journal (keeping last 7 days)..."

    local journal_size_before=$(journalctl --disk-usage 2>/dev/null | awk '{print $1}' || echo "0")

    if sudo journalctl --vacuum-time=7d >/dev/null 2>&1; then
        local journal_size_after=$(journalctl --disk-usage 2>/dev/null | awk '{print $1}' || echo "0")
        print_success "Journal cleaned (before: $journal_size_before, after: $journal_size_after)"
        log_message "INFO" "Systemd journal vacuumed: kept last 7 days"
        return 0
    else
        print_warning "Failed to vacuum journal"
        return 1
    fi
}

# Clean thumbnail cache
clean_thumbnail_cache() {
    print_info "=== Thumbnail Cache Cleanup ==="

    local thumbnail_dir="${HOME}/.cache/thumbnails"

    if [[ ! -d "$thumbnail_dir" ]]; then
        print_info "Thumbnail cache directory not found"
        return 0
    fi

    if is_dry_run; then
        local size=$(du -sh "$thumbnail_dir" 2>/dev/null | awk '{print $1}' || echo "unknown")
        print_info "[DRY-RUN] Would delete thumbnail cache (size: $size)"
        return 0
    fi

    if [[ "$AGGRESSIVE" != "true" ]]; then
        print_info "Delete thumbnail cache? (will be regenerated) (y/N): "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_info "Thumbnail cache cleanup cancelled"
            return 0
        fi
    fi

    local size=$(du -sh "$thumbnail_dir" 2>/dev/null | awk '{print $1}' || echo "unknown")

    if rm -rf "$thumbnail_dir"/* 2>/dev/null; then
        print_success "Thumbnail cache cleaned (freed: $size)"
        log_message "INFO" "Thumbnail cache cleaned: $size"
        return 0
    else
        print_warning "Failed to clean thumbnail cache"
        return 1
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
            -a|--aggressive)
                AGGRESSIVE=true
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
            --cache-level)
                CACHE_LEVEL="$2"
                shift 2
                ;;
            --preserve-package-cache)
                PRESERVE_PACKAGE_CACHE=true
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

    # Validate cache level
    if ! [[ "$CACHE_LEVEL" =~ ^[1-3]$ ]]; then
        print_error "Cache level must be 1, 2, or 3"
        exit 1
    fi
}

# Show help
show_help() {
    cat << EOF
Linux Memory Cleaning Script

Usage: $0 [OPTIONS]

Options:
    -n, --dry-run              Preview actions without executing
    -a, --aggressive           Enable aggressive cleaning (swap, browser cache)
    -q, --quiet                Suppress progress output
    -v, --verbose              Show detailed logs
    --cache-level N            Cache drop level: 1=pagecache, 2=dentries/inodes, 3=all (default: 3)
    --preserve-package-cache   Skip package manager cache cleanup
    -h, --help                 Show this help message
    --version                  Show version information

Description:
    This script safely drops caches and manages swap on Linux systems.
    It performs the following operations:

    - Memory cache dropping (pagecache, dentries, inodes)
    - Swap management (clear if usage >50%)
    - Package manager cache cleanup (apt/dnf/pacman)
    - Systemd journal vacuum (keep last 7 days)
    - Thumbnail cache cleanup

    WARNING: Some operations require sudo. Use --dry-run first.

Examples:
    $0                          # Normal execution
    $0 --dry-run                # Preview without making changes
    $0 --aggressive              # Enable aggressive cleaning
    $0 --cache-level 1          # Drop only pagecache
EOF
}

# Show version
show_version() {
    echo "Linux Memory Cleaning Script v$SCRIPT_VERSION"
}

# Check if dry-run
is_dry_run() {
    [[ "$DRY_RUN" == "true" ]]
}

# Main execution
main() {
    # Parse arguments
    parse_arguments "$@"

    # Detect distribution
    detect_distribution

    # Initialize logging
    init_logging

    print_info "Linux Memory Cleaning Script v$SCRIPT_VERSION"
    print_info "Distribution: $DISTRO_ID $DISTRO_VERSION"
    print_info "=============================================="
    print_info ""

    if is_dry_run; then
        print_warning "DRY-RUN MODE: No changes will be made"
        print_info ""
    fi

    # Capture initial memory stats
    print_info "Capturing initial memory statistics..."
    get_memory_stats
    display_memory_stats "Initial Memory State" "before"

    # Drop caches
    if drop_caches; then
        sleep 2  # Brief delay for stats to update
        get_memory_stats
        # Store as "after" stats
        MEM_TOTAL_AFTER=$MEM_TOTAL_BEFORE
        MEM_FREE_AFTER=$MEM_FREE_BEFORE
        MEM_AVAILABLE_AFTER=$MEM_AVAILABLE_BEFORE
        MEM_CACHED_AFTER=$MEM_CACHED_BEFORE

        display_memory_stats "Memory State After Cache Drop" "after"

        # Calculate freed memory
        local freed_memory=$((MEM_FREE_AFTER - MEM_FREE_BEFORE))
        if [[ $freed_memory -gt 0 ]]; then
            print_success "Memory freed: ${freed_memory} MB"
        fi
    fi
    print_info ""

    # Manage swap
    manage_swap
    print_info ""

    # Clean package cache
    clean_package_cache
    print_info ""

    # Clean journal
    clean_journal
    print_info ""

    # Clean thumbnail cache
    clean_thumbnail_cache
    print_info ""

    # Final summary
    print_info "=============================================="
    print_success "Memory cleaning completed!"
    print_info ""

    if [[ -n "$LOG_FILE" ]]; then
        print_info "Log file: $LOG_FILE"
    fi
}

# Run main function
main "$@"
