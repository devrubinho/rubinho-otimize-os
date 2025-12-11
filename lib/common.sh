#!/usr/bin/env bash

# Common Utility Functions Library
# Version: 1.0.0
# Description: Reusable shell functions for OS optimization scripts
# Usage: source lib/common.sh

# Source guard to prevent double-loading
if [[ -n "${COMMON_SH_LOADED:-}" ]]; then
    return 0
fi

readonly COMMON_SH_LOADED=1
readonly VERSION="1.0.0"

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_FAILURE=1
readonly EXIT_USER_CANCELLED=1
readonly EXIT_PERMISSION_DENIED=2
readonly EXIT_OPTIMIZATION_FAILED=3

# Color codes initialization
if command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; then
    readonly COLOR_RED=$(tput setaf 1 2>/dev/null || echo '')
    readonly COLOR_GREEN=$(tput setaf 2 2>/dev/null || echo '')
    readonly COLOR_YELLOW=$(tput setaf 3 2>/dev/null || echo '')
    readonly COLOR_BLUE=$(tput setaf 4 2>/dev/null || echo '')
    readonly COLOR_RESET=$(tput sgr0 2>/dev/null || echo '')
else
    readonly COLOR_RED='\033[0;31m'
    readonly COLOR_GREEN='\033[0;32m'
    readonly COLOR_YELLOW='\033[1;33m'
    readonly COLOR_BLUE='\033[0;34m'
    readonly COLOR_RESET='\033[0m'
fi

# Global flags
DRY_RUN="${DRY_RUN:-false}"
AUTO_CONFIRM="${AUTO_CONFIRM:-false}"

# Logging configuration
LOG_DIR="${HOME}/.os-optimize/logs"
LOG_FILE=""

# Check if terminal is interactive
is_terminal() {
    [[ -t 1 ]]
}

# Color echo function
color_echo() {
    local color="$1"
    shift
    local message="$*"

    if is_terminal; then
        case "$color" in
            red) echo -e "${COLOR_RED}${message}${COLOR_RESET}" ;;
            green) echo -e "${COLOR_GREEN}${message}${COLOR_RESET}" ;;
            yellow) echo -e "${COLOR_YELLOW}${message}${COLOR_RESET}" ;;
            blue) echo -e "${COLOR_BLUE}${message}${COLOR_RESET}" ;;
            *) echo "$message" ;;
        esac
    else
        echo "$message"
    fi
}

# Logging functions
init_logging() {
    local script_name="${1:-unknown}"

    if mkdir -p "$LOG_DIR" 2>/dev/null; then
        chmod 755 "$LOG_DIR" 2>/dev/null || true
        local timestamp=$(date +%Y%m%d-%H%M%S)
        LOG_FILE="${LOG_DIR}/${script_name}-${timestamp}.log"

        {
            echo "=========================================="
            echo "Log started: $(date)"
            echo "Script: $script_name"
            echo "User: $(whoami 2>/dev/null || echo 'unknown')"
            echo "Hostname: $(hostname 2>/dev/null || echo 'unknown')"
            echo "=========================================="
            echo ""
        } >> "$LOG_FILE" 2>/dev/null || true

        return 0
    else
        return 1
    fi
}

log_message() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if [[ -n "$LOG_FILE" ]]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

log_info() {
    log_message "INFO" "$@"
}

log_warn() {
    log_message "WARN" "$@"
}

log_error() {
    log_message "ERROR" "$@"
}

log_success() {
    log_message "SUCCESS" "$@"
}

log_debug() {
    log_message "DEBUG" "$@"
}

# Validation functions
require_sudo() {
    if [[ $EUID -eq 0 ]]; then
        return 0
    fi

    if sudo -n true 2>/dev/null; then
        return 0
    fi

    if [[ -t 0 ]]; then
        print_warning "Sudo access required. Please enter your password:"
        if sudo -v; then
            return 0
        fi
    fi

    print_error "Sudo access unavailable"
    return 1
}

check_command() {
    local cmd="$1"

    if command -v "$cmd" >/dev/null 2>&1; then
        return 0
    else
        print_error "Required command not found: $cmd"
        return 1
    fi
}

validate_os() {
    local os_type=$(uname -s)

    case "$os_type" in
        Darwin)
            local os_version=$(sw_vers -productVersion 2>/dev/null || echo "0.0.0")
            local major=$(echo "$os_version" | cut -d. -f1)
            local minor=$(echo "$os_version" | cut -d. -f2)

            if [[ $major -lt 10 ]] || ([[ $major -eq 10 ]] && [[ $minor -lt 13 ]]); then
                print_error "macOS 10.13+ required (detected: $os_version)"
                return 1
            fi
            ;;
        Linux)
            # Linux validation is distribution-specific
            if [[ -f /etc/os-release ]]; then
                local distro_id=$(grep "^ID=" /etc/os-release | cut -d'=' -f2 | tr -d '"' || echo "unknown")
                print_debug "Detected Linux distribution: $distro_id"
            fi
            ;;
        *)
            print_error "Unsupported operating system: $os_type"
            return 1
            ;;
    esac

    return 0
}

check_disk_space() {
    local path="${1:-/}"
    local min_gb="${2:-5}"

    local free_space_gb=0

    if [[ "$(uname -s)" == "Darwin" ]]; then
        free_space_gb=$(df -g "$path" | awk 'NR==2 {print $4}' || echo "0")
    else
        free_space_gb=$(df -BG "$path" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//' || df -g "$path" | awk 'NR==2 {print $4}' || echo "0")
    fi

    if [[ $free_space_gb -lt $min_gb ]]; then
        print_warning "Insufficient disk space: ${free_space_gb}GB free (required: ${min_gb}GB)"
        return 1
    fi

    return 0
}

# User interaction functions
show_progress() {
    local percent="$1"
    local message="${2:-}"

    if [[ $percent -lt 0 ]]; then
        percent=0
    elif [[ $percent -gt 100 ]]; then
        percent=100
    fi

    local filled=$((percent * 20 / 100))
    local empty=$((20 - filled))

    local bar=""
    local i=0
    while [[ $i -lt $filled ]]; do
        bar="${bar}█"
        i=$((i + 1))
    done
    while [[ $i -lt 20 ]]; do
        bar="${bar}░"
        i=$((i + 1))
    done

    if is_terminal && command -v tput >/dev/null 2>&1; then
        tput el 2>/dev/null || true
        echo -ne "\r[${bar}] ${percent}% ${message}"
    else
        echo "[${bar}] ${percent}% ${message}"
    fi
}

confirm() {
    local prompt="${1:-Continue?}"
    local default="${2:-N}"
    local timeout="${3:-0}"

    if [[ "$AUTO_CONFIRM" == "true" ]]; then
        return 0
    fi

    if [[ ! -t 0 ]]; then
        # Non-interactive mode, use default
        if [[ "$default" == "Y" ]] || [[ "$default" == "y" ]]; then
            return 0
        else
            return 1
        fi
    fi

    local response=""

    if [[ $timeout -gt 0 ]]; then
        read -t "$timeout" -p "$(color_echo yellow "$prompt (y/N): ")" response || response="$default"
    else
        read -p "$(color_echo yellow "$prompt (y/N): ")" response
    fi

    if [[ -z "$response" ]]; then
        response="$default"
    fi

    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# Error handling
die() {
    local message="$1"
    local exit_code="${2:-$EXIT_FAILURE}"

    log_error "$message"
    print_error "$message"
    exit "$exit_code"
}

cleanup() {
    # Cleanup function - can be overridden by scripts
    true
}

# Register cleanup handlers
CLEANUP_HANDLERS=()

register_cleanup() {
    CLEANUP_HANDLERS+=("$1")
}

# System information functions
get_os_type() {
    uname -s 2>/dev/null || echo "unknown"
}

get_os_version() {
    local os_type=$(get_os_type)

    case "$os_type" in
        Darwin)
            sw_vers -productVersion 2>/dev/null || echo "unknown"
            ;;
        Linux)
            if [[ -f /etc/os-release ]]; then
                grep "^VERSION_ID=" /etc/os-release | cut -d'=' -f2 | tr -d '"' || echo "unknown"
            else
                echo "unknown"
            fi
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

get_mem_total() {
    local os_type=$(get_os_type)
    local mem_mb=0

    case "$os_type" in
        Darwin)
            local mem_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo "0")
            mem_mb=$((mem_bytes / 1024 / 1024))
            ;;
        Linux)
            if [[ -f /proc/meminfo ]]; then
                local mem_kb=$(grep "^MemTotal:" /proc/meminfo | awk '{print $2}' || echo "0")
                mem_mb=$((mem_kb / 1024))
            fi
            ;;
    esac

    echo "$mem_mb"
}

get_cpu_count() {
    local os_type=$(get_os_type)

    case "$os_type" in
        Darwin)
            sysctl -n hw.ncpu 2>/dev/null || echo "1"
            ;;
        Linux)
            nproc 2>/dev/null || echo "1"
            ;;
        *)
            echo "1"
            ;;
    esac
}

get_arch() {
    uname -m 2>/dev/null || echo "unknown"
}

# File operations
safe_delete() {
    local file="$1"

    if [[ ! -e "$file" ]]; then
        print_warning "File does not exist: $file"
        return 1
    fi

    if is_dry_run; then
        print_info "[DRY-RUN] Would delete: $file"
        return 0
    fi

    if confirm "Delete $file?" "N"; then
        if rm -rf "$file" 2>/dev/null; then
            print_success "Deleted: $file"
            log_info "Deleted file: $file"
            return 0
        else
            print_error "Failed to delete: $file"
            return 1
        fi
    else
        print_info "Deletion cancelled"
        return 1
    fi
}

backup_file() {
    local file="$1"
    local backup_dir="${HOME}/.os-optimize/backups"

    if [[ ! -f "$file" ]]; then
        print_warning "File does not exist: $file"
        return 1
    fi

    mkdir -p "$backup_dir" 2>/dev/null || true

    local timestamp=$(date +%Y%m%d-%H%M%S)
    local basename=$(basename "$file")
    local backup_path="${backup_dir}/${basename}.${timestamp}.backup"

    if cp "$file" "$backup_path" 2>/dev/null; then
        print_success "Backed up: $file -> $backup_path"
        log_info "Backed up file: $file to $backup_path"
        echo "$backup_path"
        return 0
    else
        print_error "Failed to backup: $file"
        return 1
    fi
}

restore_file() {
    local file="$1"
    local backup_dir="${HOME}/.os-optimize/backups"
    local basename=$(basename "$file")

    # Find latest backup
    local latest_backup=$(ls -t "${backup_dir}/${basename}."*.backup 2>/dev/null | head -1)

    if [[ -z "$latest_backup" ]] || [[ ! -f "$latest_backup" ]]; then
        print_error "No backup found for: $file"
        return 1
    fi

    if is_dry_run; then
        print_info "[DRY-RUN] Would restore: $file from $latest_backup"
        return 0
    fi

    if confirm "Restore $file from backup?" "N"; then
        if cp "$latest_backup" "$file" 2>/dev/null; then
            print_success "Restored: $file from $latest_backup"
            log_info "Restored file: $file from $latest_backup"
            return 0
        else
            print_error "Failed to restore: $file"
            return 1
        fi
    else
        print_info "Restore cancelled"
        return 1
    fi
}

# Lock file management
acquire_lock() {
    local lock_file="${1:-/tmp/os-optimize.lock}"
    local timeout="${2:-300}"  # 5 minutes default

    # Check for existing lock
    if [[ -f "$lock_file" ]]; then
        local lock_pid=$(cat "$lock_file" 2>/dev/null || echo "")

        # Check if process is still running
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            print_error "Another optimization is already running (PID: $lock_pid)"
            return 1
        else
            # Stale lock, remove it
            print_warning "Removing stale lock file"
            rm -f "$lock_file" 2>/dev/null || true
        fi
    fi

    # Create lock file
    if (set -C; echo $$ > "$lock_file") 2>/dev/null; then
        log_info "Lock acquired: $lock_file (PID: $$)"
        return 0
    else
        print_error "Failed to acquire lock: $lock_file"
        return 1
    fi
}

release_lock() {
    local lock_file="${1:-/tmp/os-optimize.lock}"

    if [[ -f "$lock_file" ]]; then
        local lock_pid=$(cat "$lock_file" 2>/dev/null || echo "")

        if [[ "$lock_pid" == "$$" ]]; then
            rm -f "$lock_file" 2>/dev/null || true
            log_info "Lock released: $lock_file"
            return 0
        else
            print_warning "Lock file owned by different process (PID: $lock_pid)"
            return 1
        fi
    fi

    return 0
}

# Version comparison
version_compare() {
    local version1="$1"
    local version2="$2"

    local IFS='.'
    local v1_parts=($version1)
    local v2_parts=($version2)

    local max_len=${#v1_parts[@]}
    if [[ ${#v2_parts[@]} -gt $max_len ]]; then
        max_len=${#v2_parts[@]}
    fi

    local i=0
    while [[ $i -lt $max_len ]]; do
        local v1_part=${v1_parts[$i]:-0}
        local v2_part=${v2_parts[$i]:-0}

        if [[ $v1_part -lt $v2_part ]]; then
            echo "-1"
            return
        elif [[ $v1_part -gt $v2_part ]]; then
            echo "1"
            return
        fi

        i=$((i + 1))
    done

    echo "0"
}

# JSON utilities
json_escape() {
    local str="$1"
    echo "$str" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g; s/\r/\\r/g; s/\t/\\t/g'
}

json_object() {
    local key="$1"
    local value="$2"
    local escaped_value=$(json_escape "$value")
    echo "\"$key\": \"$escaped_value\""
}

# Dry-run check
is_dry_run() {
    [[ "$DRY_RUN" == "true" ]]
}

# Print functions (using color_echo)
print_success() {
    color_echo green "✓ $*"
    log_success "$*"
}

print_warning() {
    color_echo yellow "⚠ $*"
    log_warn "$*"
}

print_error() {
    color_echo red "✗ $*"
    log_error "$*"
}

print_info() {
    echo "$*"
    log_info "$*"
}

print_debug() {
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        color_echo blue "[DEBUG] $*"
        log_debug "$*"
    fi
}

# Setup error handling
trap 'cleanup; for handler in "${CLEANUP_HANDLERS[@]}"; do $handler; done' EXIT INT TERM

# Error handler
error_handler() {
    local line_num="$1"
    local command="$2"
    log_error "Error at line $line_num: $command"
}

trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
