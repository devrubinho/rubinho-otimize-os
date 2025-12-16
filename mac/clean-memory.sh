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
    local script_name=$(basename "$0")
    local pid=$$

    # Format: [TIMESTAMP] [LEVEL] [SCRIPT:PID] Message
    local log_entry="[$timestamp] [$level] [${script_name}:${pid}] $message"

    # Write to log file if available
    if [[ -n "$LOG_FILE" ]]; then
        echo "$log_entry" >> "$LOG_FILE" 2>/dev/null || true
    fi

    # Write directly to console to avoid recursion (don't call print_* functions)
    # The print_* functions call log_message, which would create infinite recursion
    if [[ "$QUIET" != "true" ]] && ([[ "$level" != "DEBUG" ]] || [[ "$VERBOSE" == "true" ]]); then
        # Color code based on level (direct echo, no function calls)
        case "$level" in
            ERROR)
                echo -e "${COLOR_RED}✗${COLOR_RESET} $message" >&2
                ;;
            WARN)
                echo -e "${COLOR_YELLOW}⚠${COLOR_RESET} $message"
                ;;
            SUCCESS)
                echo -e "${COLOR_GREEN}✓${COLOR_RESET} $message"
                ;;
            INFO|DEBUG)
                echo -e "$message"
                ;;
        esac
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

# Clear user caches selectively
clear_user_caches() {
    print_info "=== User Cache Cleanup ==="

    local cache_dir="${HOME}/Library/Caches"

    if [[ ! -d "$cache_dir" ]]; then
        print_info "User cache directory not found: $cache_dir"
        return 0
    fi

    # Preserve list (critical caches)
    local preserve_list=(
        "com.apple.dt.Xcode"
        "Homebrew"
        "com.google.Chrome"
        "com.apple.Safari"
    )

    print_info "Scanning user cache directory..."

    local folders_processed=0
    local folders_deleted=0
    local folders_preserved=0
    local total_freed_mb=0

    # Find cache folders
    while IFS= read -r cache_folder; do
        if [[ -z "$cache_folder" ]] || [[ ! -d "$cache_folder" ]]; then
            continue
        fi

        folders_processed=$((folders_processed + 1))
        local folder_name=$(basename "$cache_folder")

        # Check if should preserve
        local should_preserve=false
        for preserve_item in "${preserve_list[@]}"; do
            if [[ "$folder_name" == "$preserve_item" ]] || [[ "$folder_name" == *"$preserve_item"* ]]; then
                should_preserve=true
                break
            fi
        done

        if [[ "$should_preserve" == "true" ]]; then
            folders_preserved=$((folders_preserved + 1))
            print_debug "Preserved: $folder_name"
            continue
        fi

        # Calculate size
        local size_str=$(du -sh "$cache_folder" 2>/dev/null | awk '{print $1}' || echo "0")
        local size_mb=$(du -sm "$cache_folder" 2>/dev/null | awk '{print $1}' || echo "0")

        # Check if old (>30 days)
        local is_old=false
        if find "$cache_folder" -type f -mtime +30 2>/dev/null | head -1 | grep -q .; then
            is_old=true
        fi

        # In aggressive mode, prompt for each cache
        if [[ "$AGGRESSIVE" == "true" ]] && [[ "$is_old" == "true" ]]; then
            if is_dry_run; then
                print_info "[DRY-RUN] Would delete: $folder_name (${size_str}, old cache)"
            else
                print_info "Delete cache: $folder_name (${size_str}, old cache)? (y/N): "
                read -r response
                if [[ ! "$response" =~ ^[Yy]$ ]]; then
                    folders_preserved=$((folders_preserved + 1))
                    continue
                fi
            fi
        elif [[ "$is_old" == "false" ]]; then
            # Skip non-old caches unless aggressive
            if [[ "$AGGRESSIVE" != "true" ]]; then
                folders_preserved=$((folders_preserved + 1))
                continue
            fi
        fi

        # Delete cache
        if is_dry_run; then
            print_info "[DRY-RUN] Would delete: $folder_name (${size_str})"
            total_freed_mb=$((total_freed_mb + size_mb))
            folders_deleted=$((folders_deleted + 1))
        else
            if rm -rf "$cache_folder" 2>/dev/null; then
                print_success "Deleted: $folder_name (${size_str})"
                log_message "INFO" "Deleted user cache: $folder_name (${size_str})"
                total_freed_mb=$((total_freed_mb + size_mb))
                folders_deleted=$((folders_deleted + 1))
            else
                print_warning "Failed to delete: $folder_name (may be locked)"
                log_message "WARN" "Failed to delete user cache: $folder_name"
            fi
        fi
    done < <(find "$cache_dir" -maxdepth 1 -type d ! -path "$cache_dir" 2>/dev/null)

    print_info ""
    print_info "Summary:"
    print_info "  Folders processed: $folders_processed"
    print_info "  Folders deleted: $folders_deleted"
    print_info "  Folders preserved: $folders_preserved"
    if [[ $total_freed_mb -gt 0 ]]; then
        print_success "  Space freed: ${total_freed_mb} MB"
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

    # Check macOS version compatibility
    local macos_version=$(sw_vers -productVersion 2>/dev/null | cut -d. -f1,2)
    if [[ -n "$macos_version" ]] && (( $(echo "$macos_version < 10.9" | bc -l 2>/dev/null || echo 0) )); then
        print_error "purge command requires macOS 10.9 or later"
        return 1
    fi

    # Check SIP status
    check_sip_status

    if is_dry_run; then
        print_info "[DRY-RUN] Would execute: sudo purge"
        print_info "  This would clear inactive memory"
        # Capture stats for dry-run display
        parse_vm_stat
        display_memory_stats "Memory State (Before Purge - DRY RUN)" "before"
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

    # Capture memory stats before purge
    print_info "Capturing memory state before purge..."
    parse_vm_stat
    display_memory_stats "Memory State Before Purge" "before"

    print_info "Executing memory purge (this may take a moment)..."

    # Execute purge with timeout protection (5 minutes max)
    local purge_start=$(date +%s)
    local purge_timeout=300

    if command -v timeout >/dev/null 2>&1; then
        if timeout $purge_timeout sudo purge 2>/dev/null; then
            print_success "Memory purge completed"
        else
            local elapsed=$(($(date +%s) - purge_start))
            if [[ $elapsed -ge $purge_timeout ]]; then
                print_error "Memory purge timed out after ${purge_timeout} seconds"
                log_message "ERROR" "Memory purge timed out"
                return 1
            else
                print_error "Memory purge failed"
                log_message "ERROR" "Memory purge failed"
                return 1
            fi
        fi
    else
        # Fallback without timeout command
        if sudo purge 2>/dev/null; then
            print_success "Memory purge completed"
        else
            print_error "Memory purge failed"
            log_message "ERROR" "Memory purge failed"
            return 1
        fi
    fi

    # Wait a moment for memory stats to stabilize
    sleep 2

    # Capture memory stats after purge
    print_info "Capturing memory state after purge..."
    # Save current BEFORE values before parsing new stats
    local saved_total=$MEM_TOTAL_BEFORE
    local saved_free=$MEM_FREE_BEFORE
    local saved_active=$MEM_ACTIVE_BEFORE
    local saved_inactive=$MEM_INACTIVE_BEFORE
    local saved_wired=$MEM_WIRED_BEFORE
    local saved_compressed=$MEM_COMPRESSED_BEFORE

    # Parse new stats (this overwrites BEFORE variables)
    parse_vm_stat

    # Store new stats as AFTER
    MEM_TOTAL_AFTER=$MEM_TOTAL_BEFORE
    MEM_FREE_AFTER=$MEM_FREE_BEFORE
    MEM_ACTIVE_AFTER=$MEM_ACTIVE_BEFORE
    MEM_INACTIVE_AFTER=$MEM_INACTIVE_BEFORE
    MEM_WIRED_AFTER=$MEM_WIRED_BEFORE
    MEM_COMPRESSED_AFTER=$MEM_COMPRESSED_BEFORE

    # Restore original BEFORE values
    MEM_TOTAL_BEFORE=$saved_total
    MEM_FREE_BEFORE=$saved_free
    MEM_ACTIVE_BEFORE=$saved_active
    MEM_INACTIVE_BEFORE=$saved_inactive
    MEM_WIRED_BEFORE=$saved_wired
    MEM_COMPRESSED_BEFORE=$saved_compressed

    display_memory_stats "Memory State After Purge" "after"

    # Validate purge success
    local freed_memory=$((MEM_FREE_AFTER - MEM_FREE_BEFORE))
    local inactive_reduced=$((MEM_INACTIVE_BEFORE - MEM_INACTIVE_AFTER))

    if [[ $freed_memory -gt 0 ]] || [[ $inactive_reduced -gt 0 ]]; then
        if [[ $freed_memory -gt 0 ]]; then
            print_success "Memory freed: ${freed_memory} MB"
        fi
        if [[ $inactive_reduced -gt 0 ]]; then
            print_success "Inactive memory reduced: ${inactive_reduced} MB"
        fi
        log_message "INFO" "Memory purge executed successfully - Freed: ${freed_memory}MB, Inactive reduced: ${inactive_reduced}MB"
        return 0
    else
        print_warning "Memory purge completed but no significant memory was freed"
        print_info "  This may indicate the system already had minimal inactive memory"
        log_message "WARN" "Memory purge completed but no significant memory freed"
        return 0
    fi
}

# DNS cache flush
flush_dns_cache() {
    print_info "=== DNS Cache Flush ==="

    print_warning "Note: DNS cache flush may cause brief connectivity disruption"
    print_info "  Active network connections may be temporarily interrupted"

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
        log_message "INFO" "Directory Services cache flushed"
    else
        print_warning "Failed to flush Directory Services cache"
        log_message "WARN" "Directory Services cache flush failed"
    fi

    # Restart mDNSResponder with retry logic
    local retry_count=0
    local max_retries=3
    local success=false

    while [[ $retry_count -lt $max_retries ]]; do
        if sudo killall -HUP mDNSResponder 2>/dev/null; then
            success=true
            break
        else
            retry_count=$((retry_count + 1))
            if [[ $retry_count -lt $max_retries ]]; then
                print_debug "Retrying mDNSResponder restart (attempt $retry_count/$max_retries)..."
                sleep 1
            fi
        fi
    done

    if [[ "$success" == "true" ]]; then
        print_success "DNS cache flushed successfully"
        log_message "INFO" "DNS cache flushed - mDNSResponder restarted"

        # Optional DNS resolution test (informational only)
        if command -v host >/dev/null 2>&1 || command -v nslookup >/dev/null 2>&1; then
            print_debug "DNS resolution test: checking google.com..."
            if host google.com >/dev/null 2>&1 || nslookup google.com >/dev/null 2>&1; then
                print_debug "DNS resolution working correctly"
            else
                print_debug "DNS resolution test inconclusive (may be network issue)"
            fi
        fi

        return 0
    else
        print_warning "Failed to restart mDNSResponder after $max_retries attempts"
        print_info "  DNS cache may still be flushed, but mDNSResponder restart failed"
        log_message "WARN" "mDNSResponder restart failed after $max_retries attempts"
        return 1
    fi
}

# Font cache clearing
clear_font_cache() {
    print_info "=== Font Cache Clear ==="

    if is_dry_run; then
        print_info "[DRY-RUN] Would execute: atsutil databases -remove"
        print_info "  This may require sudo on some macOS versions"
        return 0
    fi

    if ! command -v atsutil >/dev/null 2>&1; then
        print_warning "atsutil command not found. Skipping font cache clear."
        print_info "  atsutil is typically available on macOS 10.5+"
        log_message "WARN" "atsutil command not found, skipping font cache clear"
        return 1
    fi

    print_info "Clearing font cache..."
    print_info "  Note: Fonts will be re-indexed on next use"

    # Try without sudo first
    if atsutil databases -remove 2>/dev/null; then
        print_success "Font cache cleared"
        log_message "INFO" "Font cache cleared successfully"
        return 0
    fi

    # If that fails, try with sudo (some macOS versions require it)
    print_debug "Attempting font cache clear with sudo..."

    if ! sudo -n true 2>/dev/null; then
        if ! sudo -v; then
            print_warning "Font cache clear failed and sudo access unavailable"
            print_info "  Font cache may require elevated privileges on this macOS version"
            log_message "WARN" "Font cache clear failed - sudo access unavailable"
            return 1
        fi
    fi

    if sudo atsutil databases -remove 2>/dev/null; then
        print_success "Font cache cleared (with sudo)"
        log_message "INFO" "Font cache cleared successfully with sudo"
        return 0
    else
        print_warning "Font cache clear failed even with sudo"
        print_info "  This may be normal on some macOS versions or if fonts are in use"
        log_message "WARN" "Font cache clear failed even with sudo"
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

    # Critical system caches to preserve
    local preserve_list=(
        "com.apple.kext.caches"
        "com.apple.metal"
        "bootcaches"
        "kernel"
        "com.apple.ATS"
    )

    if is_dry_run; then
        print_info "[DRY-RUN] Would scan system cache directory: $system_cache_dir"
        print_info "  (Requires sudo privileges)"
        print_info "  Would preserve critical caches: ${preserve_list[*]}"
        return 0
    fi

    # Check sudo
    if ! sudo -n true 2>/dev/null; then
        print_warning "Sudo access required for system cache cleaning. Skipping."
        log_message "WARN" "System cache cleaning skipped - no sudo access"
        return 1
    fi

    if [[ ! -d "$system_cache_dir" ]]; then
        print_warning "System cache directory not found: $system_cache_dir"
        return 1
    fi

    print_warning "=========================================="
    print_warning "WARNING: System cache deletion is IRREVERSIBLE"
    print_warning "=========================================="
    print_info ""

    # Safety check: never delete caches modified in last 7 days
    local min_age_days=7
    print_info "Safety: Only caches older than ${min_age_days} days will be considered"

    local folders_processed=0
    local folders_deleted=0
    local folders_preserved=0
    local total_freed_mb=0

    print_info "Scanning system cache directory (requires sudo)..."
    print_info ""

    # Find cache folders (using sudo)
    while IFS= read -r cache_folder; do
        if [[ -z "$cache_folder" ]] || [[ ! -d "$cache_folder" ]]; then
            continue
        fi

        folders_processed=$((folders_processed + 1))
        local folder_name=$(basename "$cache_folder")

        # Check if should preserve (critical caches)
        local should_preserve=false
        for preserve_item in "${preserve_list[@]}"; do
            if [[ "$folder_name" == "$preserve_item" ]] || [[ "$folder_name" == *"$preserve_item"* ]]; then
                should_preserve=true
                break
            fi
        done

        if [[ "$should_preserve" == "true" ]]; then
            folders_preserved=$((folders_preserved + 1))
            print_debug "Preserved (critical): $folder_name"
            continue
        fi

        # Check modification time (must be older than min_age_days)
        local cache_age_days=0
        if [[ "$(uname -s)" == "Darwin" ]]; then
            # macOS: use stat -f
            local mtime=$(stat -f "%m" "$cache_folder" 2>/dev/null || echo "0")
            local now=$(date +%s)
            cache_age_days=$(( (now - mtime) / 86400 ))
        else
            # Fallback: use find
            cache_age_days=$(find "$cache_folder" -maxdepth 0 -mtime +${min_age_days} 2>/dev/null | wc -l | tr -d ' ')
        fi

        if [[ $cache_age_days -lt $min_age_days ]]; then
            folders_preserved=$((folders_preserved + 1))
            print_debug "Preserved (recently modified, ${cache_age_days} days old): $folder_name"
            continue
        fi

        # Calculate size
        local size_str=$(sudo du -sh "$cache_folder" 2>/dev/null | awk '{print $1}' || echo "0")
        local size_mb=$(sudo du -sm "$cache_folder" 2>/dev/null | awk '{print $1}' || echo "0")

        # In aggressive mode, prompt for each cache
        if [[ "$AGGRESSIVE" == "true" ]]; then
            print_info "Delete system cache: $folder_name (${size_str}, ${cache_age_days} days old)? (y/N): "
            read -r response
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                folders_preserved=$((folders_preserved + 1))
                continue
            fi
        else
            # Non-aggressive: skip system cache deletion for safety
            folders_preserved=$((folders_preserved + 1))
            print_debug "Skipped (use --aggressive to enable): $folder_name"
            continue
        fi

        # Delete cache (with sudo)
        if sudo rm -rf "$cache_folder" 2>/dev/null; then
            print_success "Deleted: $folder_name (${size_str})"
            log_message "INFO" "Deleted system cache: $folder_name (${size_str})"
            total_freed_mb=$((total_freed_mb + size_mb))
            folders_deleted=$((folders_deleted + 1))
        else
            print_warning "Failed to delete: $folder_name (may be locked or in use)"
            log_message "WARN" "Failed to delete system cache: $folder_name"
        fi
    done < <(sudo find "$system_cache_dir" -maxdepth 1 -type d ! -path "$system_cache_dir" 2>/dev/null)

    print_info ""
    print_info "System Cache Summary:"
    print_info "  Folders processed: $folders_processed"
    print_info "  Folders deleted: $folders_deleted"
    print_info "  Folders preserved: $folders_preserved"
    if [[ $total_freed_mb -gt 0 ]]; then
        print_success "  Space freed: ${total_freed_mb} MB"
    fi
    print_info ""

    if [[ $folders_deleted -eq 0 ]] && [[ "$AGGRESSIVE" != "true" ]]; then
        print_info "No system caches deleted (use --aggressive flag to enable)"
    fi

    log_message "INFO" "System cache cleaning completed - Processed: $folders_processed, Deleted: $folders_deleted, Preserved: $folders_preserved, Freed: ${total_freed_mb}MB"
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

        # Save current BEFORE values (they will be overwritten by parse_vm_stat)
        local temp_total=$MEM_TOTAL_BEFORE
        local temp_free=$MEM_FREE_BEFORE
        local temp_active=$MEM_ACTIVE_BEFORE
        local temp_inactive=$MEM_INACTIVE_BEFORE
        local temp_wired=$MEM_WIRED_BEFORE
        local temp_compressed=$MEM_COMPRESSED_BEFORE

        # Get fresh stats (this will overwrite BEFORE variables)
        parse_vm_stat

        # Store the fresh stats as AFTER
        MEM_TOTAL_AFTER=$MEM_TOTAL_BEFORE
        MEM_FREE_AFTER=$MEM_FREE_BEFORE
        MEM_ACTIVE_AFTER=$MEM_ACTIVE_BEFORE
        MEM_INACTIVE_AFTER=$MEM_INACTIVE_BEFORE
        MEM_WIRED_AFTER=$MEM_WIRED_BEFORE
        MEM_COMPRESSED_AFTER=$MEM_COMPRESSED_BEFORE

        # Restore original BEFORE values
        MEM_TOTAL_BEFORE=$temp_total
        MEM_FREE_BEFORE=$temp_free
        MEM_ACTIVE_BEFORE=$temp_active
        MEM_INACTIVE_BEFORE=$temp_inactive
        MEM_WIRED_BEFORE=$temp_wired
        MEM_COMPRESSED_BEFORE=$temp_compressed

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

    # Clean user cache (selective deletion)
    clear_user_caches
    print_info ""

    # Clean system cache (basic, safe implementation)
    clean_system_cache
    print_info ""

    # Final summary
    print_info "=============================================="
    print_success "Memory cleaning completed!"
    print_info ""

    # Generate operation summary
    local operations_done=""
    local operations_skipped=""
    local total_space_freed=0

    # Count operations
    if [[ "$DRY_RUN" != "true" ]]; then
        operations_done="Memory purge, DNS cache flush, Font cache clear"
        if [[ "$AGGRESSIVE" == "true" ]]; then
            operations_done="${operations_done}, User cache cleaning, System cache cleaning"
        else
            operations_skipped="System cache cleaning (use --aggressive to enable)"
        fi
    else
        operations_done="[DRY-RUN] All operations previewed"
    fi

    # Log summary
    if [[ -n "$LOG_FILE" ]]; then
        {
            echo ""
            echo "=========================================="
            echo "Operation Summary"
            echo "=========================================="
            echo "Operations Performed: $operations_done"
            if [[ -n "$operations_skipped" ]]; then
                echo "Operations Skipped: $operations_skipped"
            fi
            echo "Memory Stats:"
            echo "  Before: Total=${MEM_TOTAL_BEFORE}MB, Free=${MEM_FREE_BEFORE}MB, Inactive=${MEM_INACTIVE_BEFORE}MB"
            echo "  After:  Total=${MEM_TOTAL_AFTER}MB, Free=${MEM_FREE_AFTER}MB, Inactive=${MEM_INACTIVE_AFTER}MB"
            local memory_freed=$((MEM_FREE_AFTER - MEM_FREE_BEFORE))
            if [[ $memory_freed -gt 0 ]]; then
                echo "  Memory Freed: ${memory_freed} MB"
            fi
            echo "Total Impact: Memory optimization completed"
            echo "=========================================="
        } >> "$LOG_FILE"
    fi

    # Write metrics to temporary file for parent script
    local metrics_file="${HOME}/.os-optimize/.clean-memory-metrics.json"
    local memory_freed=$((MEM_FREE_AFTER - MEM_FREE_BEFORE))
    mkdir -p "$(dirname "$metrics_file")" 2>/dev/null || true
    {
        echo "{"
        echo "  \"memory_freed_mb\": $memory_freed"
        echo "}"
    } > "$metrics_file" 2>/dev/null || true

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
