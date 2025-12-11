#!/usr/bin/env bash

# macOS Memory Cleaning Script
# Version: 1.0.0
# Description: Safely clears inactive memory, purges disk cache, and cleans system caches

set -euo pipefail

# Script configuration
SCRIPT_VERSION="1.0.0"
MIN_MACOS_VERSION="10.13"
LOG_DIR="${HOME}/.os-optimize/logs"
LOG_FILE=""

# Execution flags
DRY_RUN=false
AGGRESSIVE=false
QUIET=false
VERBOSE=false

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

# Memory statistics storage (using simple variables for bash 3.2 compatibility)
MEM_TOTAL_BEFORE=0
MEM_FREE_BEFORE=0
MEM_ACTIVE_BEFORE=0
MEM_INACTIVE_BEFORE=0
MEM_WIRED_BEFORE=0
MEM_COMPRESSED_BEFORE=0

MEM_TOTAL_AFTER=0
MEM_FREE_AFTER=0
MEM_ACTIVE_AFTER=0
MEM_INACTIVE_AFTER=0
MEM_WIRED_AFTER=0
MEM_COMPRESSED_AFTER=0

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
        LOG_FILE="${LOG_DIR}/memory-clean-${timestamp}.log"

        # Log header with system info
        {
            echo "=========================================="
            echo "macOS Memory Clean Script - Log"
            echo "=========================================="
            echo "Timestamp: $(date)"
            echo "macOS Version: $(sw_vers -productVersion 2>/dev/null || echo 'unknown')"
            echo "Hostname: $(hostname 2>/dev/null || echo 'unknown')"
            echo "User: $(whoami 2>/dev/null || echo 'unknown')"
            echo "Script Version: $SCRIPT_VERSION"
            echo "Flags: DRY_RUN=$DRY_RUN, AGGRESSIVE=$AGGRESSIVE, QUIET=$QUIET, VERBOSE=$VERBOSE"
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

# Check if dry-run mode
is_dry_run() {
    [[ "$DRY_RUN" == "true" ]]
}

# Check if aggressive mode
is_aggressive() {
    [[ "$AGGRESSIVE" == "true" ]]
}

# Check if should log
should_log() {
    [[ "$QUIET" == "false" ]] || [[ -n "$LOG_FILE" ]]
}

# Validate macOS version
check_macos_version() {
    local macos_version=$(sw_vers -productVersion 2>/dev/null || echo "0.0.0")
    local major=$(echo "$macos_version" | cut -d. -f1)
    local minor=$(echo "$macos_version" | cut -d. -f2)

    if [[ $major -lt 10 ]] || ([[ $major -eq 10 ]] && [[ $minor -lt 13 ]]); then
        print_error "macOS version $macos_version is too old. Required: >= $MIN_MACOS_VERSION"
        return 1
    fi

    print_debug "macOS version validated: $macos_version"
    return 0
}

# Get page size
get_page_size() {
    if command -v pagesize >/dev/null 2>&1; then
        pagesize
    elif command -v sysctl >/dev/null 2>&1; then
        sysctl -n hw.pagesize 2>/dev/null || echo "4096"
    else
        echo "4096"  # Default fallback
    fi
}

# Parse vm_stat output and convert to MB
parse_vm_stat() {
    local page_size=$(get_page_size)
    local vm_stat_output

    if ! command -v vm_stat >/dev/null 2>&1; then
        print_error "vm_stat command not found"
        return 1
    fi

    vm_stat_output=$(vm_stat)

    # Extract memory values (handles both "Pages free: 12345." and "Pages free: 12345")
    local pages_free=$(echo "$vm_stat_output" | grep -i "Pages free" | awk '{print $3}' | sed 's/\.$//')
    local pages_active=$(echo "$vm_stat_output" | grep -i "Pages active" | awk '{print $3}' | sed 's/\.$//')
    local pages_inactive=$(echo "$vm_stat_output" | grep -i "Pages inactive" | awk '{print $3}' | sed 's/\.$//')
    local pages_speculative=$(echo "$vm_stat_output" | grep -i "Pages speculative" | awk '{print $3}' | sed 's/\.$//' || echo "0")
    local pages_wired=$(echo "$vm_stat_output" | grep -i "Pages wired down" | awk '{print $4}' | sed 's/\.$//')
    local pages_compressed=$(echo "$vm_stat_output" | grep -i "Pages occupied by compressor" | awk '{print $5}' | sed 's/\.$//' || echo "0")
    local pages_stored=$(echo "$vm_stat_output" | grep -i "Pages stored in compressor" | awk '{print $5}' | sed 's/\.$//' || echo "0")

    # Convert pages to MB (pages * page_size / 1024 / 1024)
    local mb_free=$((pages_free * page_size / 1024 / 1024))
    local mb_active=$((pages_active * page_size / 1024 / 1024))
    local mb_inactive=$((pages_inactive * page_size / 1024 / 1024))
    local mb_speculative=$((pages_speculative * page_size / 1024 / 1024))
    local mb_wired=$((pages_wired * page_size / 1024 / 1024))
    local mb_compressed=$((pages_compressed * page_size / 1024 / 1024))
    local mb_stored=$((pages_stored * page_size / 1024 / 1024))

    # Calculate total (approximate)
    local mb_total=$((mb_free + mb_active + mb_inactive + mb_speculative + mb_wired + mb_compressed))

    # Store in simple variables (bash 3.2 compatible)
    MEM_TOTAL_BEFORE=$mb_total
    MEM_FREE_BEFORE=$mb_free
    MEM_ACTIVE_BEFORE=$mb_active
    MEM_INACTIVE_BEFORE=$mb_inactive
    MEM_WIRED_BEFORE=$mb_wired
    MEM_COMPRESSED_BEFORE=$mb_compressed

    print_debug "Memory stats parsed: Total=${mb_total}MB, Free=${mb_free}MB, Inactive=${mb_inactive}MB"
}

# Display memory statistics
display_memory_stats() {
    local label="$1"
    local mode="$2"  # "before" or "after"

    local total free active inactive wired compressed

    if [[ "$mode" == "before" ]]; then
        total=$MEM_TOTAL_BEFORE
        free=$MEM_FREE_BEFORE
        active=$MEM_ACTIVE_BEFORE
        inactive=$MEM_INACTIVE_BEFORE
        wired=$MEM_WIRED_BEFORE
        compressed=$MEM_COMPRESSED_BEFORE
    else
        total=$MEM_TOTAL_AFTER
        free=$MEM_FREE_AFTER
        active=$MEM_ACTIVE_AFTER
        inactive=$MEM_INACTIVE_AFTER
        wired=$MEM_WIRED_AFTER
        compressed=$MEM_COMPRESSED_AFTER
    fi

    print_info ""
    print_info "=== $label ==="
    print_info "Total Memory:    ${total} MB"
    print_info "Free:            ${free} MB"
    print_info "Active:          ${active} MB"
    print_info "Inactive:        ${inactive} MB"
    print_info "Wired:           ${wired} MB"
    print_info "Compressed:      ${compressed} MB"

    # Calculate utilization
    if [[ $total -gt 0 ]]; then
        local used=$((total - free))
        local utilization=$((used * 100 / total))
        print_info "Utilization:     ${utilization}%"
    fi
    print_info ""
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

    # Validate flag combinations
    if [[ "$QUIET" == "true" ]] && [[ "$VERBOSE" == "true" ]]; then
        print_error "--quiet and --verbose are mutually exclusive"
        exit 1
    fi
}

# Show help message
show_help() {
    cat << EOF
macOS Memory Cleaning Script

Usage: $0 [OPTIONS]

Options:
    -n, --dry-run      Preview actions without executing
    -a, --aggressive   Enable aggressive cache cleaning (with prompts)
    -q, --quiet        Suppress progress output, only show summary
    -v, --verbose      Show detailed operation logs
    -h, --help         Show this help message
    --version          Show version information

Description:
    This script safely clears inactive memory, purges disk cache, and cleans
    system caches on macOS. It performs the following operations:

    - Memory purge using sudo purge
    - User cache cleaning (~/Library/Caches/)
    - System cache cleaning (/Library/Caches/) - requires sudo
    - DNS cache flush
    - Font cache clearing

    WARNING: Some operations are irreversible. Use --dry-run first to preview.

Examples:
    $0                  # Normal execution
    $0 --dry-run        # Preview without making changes
    $0 --aggressive     # Enable aggressive cleaning with prompts
    $0 --verbose        # Show detailed logs
EOF
}

# Show version
show_version() {
    echo "macOS Memory Cleaning Script v$SCRIPT_VERSION"
    echo "Compatible with macOS $MIN_MACOS_VERSION+"
}

# Check SIP status
check_sip_status() {
    if command -v csrutil >/dev/null 2>&1; then
        local sip_status=$(csrutil status 2>/dev/null | grep -i "System Integrity Protection" || echo "unknown")
        if echo "$sip_status" | grep -qi "disabled"; then
            print_warning "System Integrity Protection (SIP) is disabled"
            print_info "  Some operations may behave differently with SIP disabled"
        else
            print_debug "SIP status: $sip_status"
        fi
    fi
}

# Safe purge function
safe_purge() {
    print_info "=== Memory Purge ==="

    # Check sudo availability
    if ! command -v sudo >/dev/null 2>&1; then
        print_error "sudo command not found. Cannot execute purge."
        return 1
    fi

    # Check if purge command exists (macOS 10.9+)
    if ! command -v purge >/dev/null 2>&1; then
        print_error "purge command not found. Requires macOS 10.9+"
        return 1
    fi

    if is_dry_run; then
        print_info "[DRY-RUN] Would execute: sudo purge"
        print_info "  This would clear inactive memory"
        return 0
    fi

    # Check sudo access
    if ! sudo -n true 2>/dev/null; then
        print_info "Sudo access required for memory purge. Please enter your password:"
        if ! sudo -v; then
            print_error "Failed to obtain sudo access"
            return 1
        fi
    fi

    print_info "Executing memory purge (this may take a moment)..."

    # Execute purge with timeout (5 minutes max)
    if timeout 300 sudo purge 2>/dev/null || sudo purge 2>/dev/null; then
        print_success "Memory purge completed"
        log_message "INFO" "Memory purge executed successfully"
        return 0
    else
        print_error "Memory purge failed or timed out"
        log_message "ERROR" "Memory purge failed"
        return 1
    fi
}

# DNS cache flush
flush_dns_cache() {
    print_info "=== DNS Cache Flush ==="

    if is_dry_run; then
        print_info "[DRY-RUN] Would execute:"
        print_info "  sudo dscacheutil -flushcache"
        print_info "  sudo killall -HUP mDNSResponder"
        return 0
    fi

    # Check sudo
    if ! sudo -n true 2>/dev/null; then
        if ! sudo -v; then
            print_error "Sudo access required for DNS cache flush"
            return 1
        fi
    fi

    print_info "Flushing DNS cache..."

    # Flush Directory Services cache
    if sudo dscacheutil -flushcache 2>/dev/null; then
        print_debug "Directory Services cache flushed"
    else
        print_warning "Failed to flush Directory Services cache"
    fi

    # Restart mDNSResponder with retry
    local retry_count=0
    local max_retries=3

    while [[ $retry_count -lt $max_retries ]]; do
        if sudo killall -HUP mDNSResponder 2>/dev/null; then
            print_success "DNS cache flushed successfully"
            log_message "INFO" "DNS cache flushed"
            return 0
        else
            retry_count=$((retry_count + 1))
            if [[ $retry_count -lt $max_retries ]]; then
                print_debug "Retrying mDNSResponder restart (attempt $retry_count/$max_retries)..."
                sleep 1
            fi
        fi
    done

    print_warning "Failed to restart mDNSResponder after $max_retries attempts"
    log_message "WARN" "mDNSResponder restart failed"
    return 1
}

# Font cache clearing
clear_font_cache() {
    print_info "=== Font Cache Clear ==="

    if is_dry_run; then
        print_info "[DRY-RUN] Would execute: atsutil databases -remove"
        return 0
    fi

    if ! command -v atsutil >/dev/null 2>&1; then
        print_warning "atsutil command not found. Skipping font cache clear."
        return 1
    fi

    print_info "Clearing font cache..."

    if atsutil databases -remove 2>/dev/null; then
        print_success "Font cache cleared"
        log_message "INFO" "Font cache cleared"
        return 0
    else
        print_warning "Font cache clear failed (may require sudo on some macOS versions)"
        log_message "WARN" "Font cache clear failed"
        return 1
    fi
}

# User cache cleaning (basic implementation)
clean_user_cache() {
    print_info "=== User Cache Cleaning ==="

    local cache_dir="${HOME}/Library/Caches"
    local preserved_caches=(
        "com.apple.dt.Xcode"
        "Homebrew"
        "com.google.Chrome"
        "com.apple.Safari"
    )

    if [[ ! -d "$cache_dir" ]]; then
        print_warning "User cache directory not found: $cache_dir"
        return 1
    fi

    print_info "Scanning user cache directory..."

    local total_freed=0
    local folders_processed=0
    local folders_preserved=0

    # Find cache folders older than 30 days
    if command -v find >/dev/null 2>&1; then
        while IFS= read -r cache_folder; do
            if [[ -z "$cache_folder" ]]; then
                continue
            fi

            local folder_name=$(basename "$cache_folder")
            local should_preserve=false

            # Check if in preserve list
            for preserved in "${preserved_caches[@]}"; do
                if [[ "$folder_name" == "$preserved" ]] || [[ "$folder_name" == *"$preserved"* ]]; then
                    should_preserve=true
                    break
                fi
            done

            if [[ "$should_preserve" == "true" ]]; then
                folders_preserved=$((folders_preserved + 1))
                print_debug "Preserved: $folder_name"
                continue
            fi

            # Check if older than 30 days
            if find "$cache_folder" -type f -mtime +30 2>/dev/null | head -1 | grep -q .; then
                folders_processed=$((folders_processed + 1))

                if is_dry_run; then
                    local size=$(du -sh "$cache_folder" 2>/dev/null | awk '{print $1}' || echo "unknown")
                    print_info "[DRY-RUN] Would delete: $folder_name (size: $size)"
                elif is_aggressive; then
                    local size=$(du -sh "$cache_folder" 2>/dev/null | awk '{print $1}' || echo "unknown")
                    print_info "Found old cache: $folder_name (size: $size)"
                    print_info "Delete this cache? (y/N): "
                    read -r response
                    if [[ "$response" =~ ^[Yy]$ ]]; then
                        if rm -rf "$cache_folder" 2>/dev/null; then
                            print_success "Deleted: $folder_name"
                            log_message "INFO" "Deleted user cache: $folder_name"
                        else
                            print_warning "Failed to delete: $folder_name (may be locked)"
                        fi
                    fi
                else
                    print_debug "Skipping $folder_name (use --aggressive to clean old caches)"
                fi
            fi
        done < <(find "$cache_dir" -maxdepth 1 -type d ! -path "$cache_dir" 2>/dev/null)
    fi

    print_info "User cache scan complete:"
    print_info "  Folders processed: $folders_processed"
    print_info "  Folders preserved: $folders_preserved"
}

# System cache cleaning (basic implementation)
clean_system_cache() {
    print_info "=== System Cache Cleaning ==="

    local system_cache_dir="/Library/Caches"
    local preserved_caches=(
        "com.apple.kext.caches"
        "com.apple.metal"
        "bootcaches"
    )

    if is_dry_run; then
        print_info "[DRY-RUN] Would scan system cache directory: $system_cache_dir"
        print_info "  (Requires sudo privileges)"
        return 0
    fi

    # Check sudo
    if ! sudo -n true 2>/dev/null; then
        print_warning "Sudo access required for system cache cleaning. Skipping."
        return 1
    fi

    if [[ ! -d "$system_cache_dir" ]]; then
        print_warning "System cache directory not found"
        return 1
    fi

    print_warning "System cache cleaning is a sensitive operation"
    print_info "Skipping system cache cleaning in basic implementation"
    print_info "  (Critical system caches are preserved by default)"

    log_message "INFO" "System cache cleaning skipped (safety)"
    return 0
}

# Show rollback warnings
show_rollback_warnings() {
    print_warning "=========================================="
    print_warning "IMPORTANT: Some operations are IRREVERSIBLE"
    print_warning "=========================================="
    print_info ""
    print_info "The following operations cannot be undone:"
    print_info "  - System cache deletion (if enabled)"
    print_info "  - Memory purge (immediate effect)"
    print_info ""
    print_info "User cache deletion can be regenerated by applications."
    print_info ""

    if [[ "$AGGRESSIVE" == "true" ]]; then
        print_warning "AGGRESSIVE MODE ENABLED:"
        print_warning "  - User cache deletion will prompt for each folder"
        print_warning "  - System cache cleaning may be more thorough"
        print_info ""
    fi

    if is_dry_run; then
        print_info "DRY-RUN MODE: No actual changes will be made."
        print_info ""
    fi
}

# Main execution
main() {
    # Parse arguments
    parse_arguments "$@"

    # Initialize logging
    init_logging

    # Validate macOS version
    if ! check_macos_version; then
        exit 1
    fi

    print_info "macOS Memory Cleaning Script v$SCRIPT_VERSION"
    print_info "=============================================="
    print_info ""

    # Show rollback warnings
    show_rollback_warnings

    # Check SIP status
    check_sip_status
    print_info ""

    # Capture initial memory stats
    print_info "Capturing initial memory statistics..."
    parse_vm_stat
    display_memory_stats "Initial Memory State" "before"

    # Execute memory purge
    if safe_purge; then
        # Capture memory stats after purge
        sleep 2  # Brief delay for stats to update
        parse_vm_stat
        # Store as "after" stats
        MEM_TOTAL_AFTER=$MEM_TOTAL_BEFORE
        MEM_FREE_AFTER=$MEM_FREE_BEFORE
        MEM_ACTIVE_AFTER=$MEM_ACTIVE_BEFORE
        MEM_INACTIVE_AFTER=$MEM_INACTIVE_BEFORE
        MEM_WIRED_AFTER=$MEM_WIRED_BEFORE
        MEM_COMPRESSED_AFTER=$MEM_COMPRESSED_BEFORE

        display_memory_stats "Memory State After Purge" "after"

        # Calculate freed memory
        local freed_memory=$((MEM_FREE_AFTER - MEM_FREE_BEFORE))
        if [[ $freed_memory -gt 0 ]]; then
            print_success "Memory freed: ${freed_memory} MB"
        fi
    fi
    print_info ""

    # Flush DNS cache
    flush_dns_cache
    print_info ""

    # Clear font cache
    clear_font_cache
    print_info ""

    # Clean user cache
    clean_user_cache
    print_info ""

    # Clean system cache (basic, safe implementation)
    clean_system_cache
    print_info ""

    # Final summary
    print_info "=============================================="
    print_success "Memory cleaning completed!"
    print_info ""

    if [[ -n "$LOG_FILE" ]]; then
        print_info "Log file: $LOG_FILE"

        # Log rotation (keep last 10)
        if [[ -d "$LOG_DIR" ]]; then
            local log_count=$(find "$LOG_DIR" -name "memory-clean-*.log" -type f 2>/dev/null | wc -l | tr -d ' ')
            if [[ $log_count -gt 10 ]]; then
                find "$LOG_DIR" -name "memory-clean-*.log" -type f -printf '%T@ %p\n' 2>/dev/null | \
                    sort -rn | tail -n +11 | cut -d' ' -f2- | xargs rm -f 2>/dev/null || \
                find "$LOG_DIR" -name "memory-clean-*.log" -type f -exec stat -f "%m %N" {} \; 2>/dev/null | \
                    sort -rn | tail -n +11 | cut -d' ' -f2- | xargs rm -f 2>/dev/null || true
                log_message "INFO" "Log rotation: kept last 10 logs"
            fi
        fi
    fi
}

# Run main function
main "$@"
