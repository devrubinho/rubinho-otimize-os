#!/usr/bin/env bash

# OS Optimization Scripts - Installation Script
# Version: 1.0.0
# Description: Creates project directory structure and validates setup

set -euo pipefail

# Color codes using tput (with fallback to ANSI codes)
if command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; then
    COLOR_GREEN=$(tput setaf 2 2>/dev/null || echo '')
    COLOR_YELLOW=$(tput setaf 3 2>/dev/null || echo '')
    COLOR_RED=$(tput setaf 1 2>/dev/null || echo '')
    COLOR_RESET=$(tput sgr0 2>/dev/null || echo '')
else
    COLOR_GREEN='\033[0;32m'
    COLOR_YELLOW='\033[1;33m'
    COLOR_RED='\033[0;31m'
    COLOR_RESET='\033[0m'
fi

# Project root directory (where this script is located)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

# Dry-run mode flag
DRY_RUN=false
VERBOSE=false

# OS detection
OS_TYPE=$(uname -s)

# Logging configuration
LOG_DIR="${HOME}/.os-optimize/logs"
BACKUP_DIR="${HOME}/.os-optimize/backups"
LOG_FILE=""
LOG_ENABLED=true

# Directories to create
DIRECTORIES=(
    "mac"
    "linux"
    "lib"
    "config"
)

# Error tracking
ERROR_COUNT=0
CRITICAL_ERROR=false

# Function to print colored messages
print_success() {
    local message="$1"
    echo -e "${COLOR_GREEN}✓${COLOR_RESET} $message"
    log_message "SUCCESS" "$message"
}

print_warning() {
    local message="$1"
    echo -e "${COLOR_YELLOW}⚠${COLOR_RESET} $message"
    log_message "WARN" "$message"
}

print_error() {
    local message="$1"
    echo -e "${COLOR_RED}✗${COLOR_RESET} $message"
    log_message "ERROR" "$message"
    ERROR_COUNT=$((ERROR_COUNT + 1))
}

print_info() {
    local message="$1"
    echo -e "$message"
    log_message "INFO" "$message"
}

# Function to log messages with timestamp
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if [[ "$LOG_ENABLED" == "true" ]] && [[ -n "$LOG_FILE" ]]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
    fi

    # Also log to system logger if available
    if command -v logger >/dev/null 2>&1; then
        logger -t "os-optimize-install" "[$level] $message" 2>/dev/null || true
    fi
}

# Function to initialize logging
init_logging() {
    # Create log directory
    if mkdir -p "$LOG_DIR" 2>/dev/null; then
        chmod 755 "$LOG_DIR" 2>/dev/null || true
    else
        LOG_ENABLED=false
        print_warning "Cannot create log directory: $LOG_DIR (logging disabled)"
        return 1
    fi

    # Create backup directory
    if mkdir -p "$BACKUP_DIR" 2>/dev/null; then
        chmod 755 "$BACKUP_DIR" 2>/dev/null || true
    fi

    # Generate timestamped log file
    local timestamp=$(date +%Y%m%d_%H%M%S)
    LOG_FILE="${LOG_DIR}/install_${timestamp}.log"

    # Rotate old logs (keep last 10)
    if [[ -d "$LOG_DIR" ]]; then
        local log_count=$(find "$LOG_DIR" -name "install_*.log" -type f 2>/dev/null | wc -l | tr -d ' ')
        if [[ $log_count -gt 10 ]]; then
            find "$LOG_DIR" -name "install_*.log" -type f -printf '%T@ %p\n' 2>/dev/null | \
                sort -rn | tail -n +11 | cut -d' ' -f2- | xargs rm -f 2>/dev/null || \
            find "$LOG_DIR" -name "install_*.log" -type f -exec stat -f "%m %N" {} \; 2>/dev/null | \
                sort -rn | tail -n +11 | cut -d' ' -f2- | xargs rm -f 2>/dev/null || true
        fi
    fi

    log_message "INFO" "Logging initialized: $LOG_FILE"
    return 0
}

# Function to check if command exists
check_command() {
    local cmd="$1"
    local required="${2:-false}"

    if command -v "$cmd" >/dev/null 2>&1; then
        if [[ "$VERBOSE" == "true" ]]; then
            print_success "Command '$cmd' found"
        fi
        return 0
    else
        if [[ "$required" == "true" ]]; then
            print_error "Required command '$cmd' not found"
            CRITICAL_ERROR=true
            return 1
        else
            print_warning "Optional command '$cmd' not found"
            return 1
        fi
    fi
}

# Function to check bash version
check_bash_version() {
    local bash_version="${BASH_VERSION:-}"

    if [[ -z "$bash_version" ]]; then
        print_error "Cannot determine bash version"
        CRITICAL_ERROR=true
        return 1
    fi

    # Extract major and minor version numbers
    local major=$(echo "$bash_version" | cut -d. -f1)
    local minor=$(echo "$bash_version" | cut -d. -f2)

    # Check if version is >= 4.0
    # On macOS, bash 3.2 is the default, so we'll warn but not fail
    if [[ $major -lt 4 ]]; then
        if [[ "$OS_TYPE" == "Darwin" ]]; then
            print_warning "Bash version $bash_version is old. Recommended: >= 4.0"
            print_info "  On macOS, install newer bash: brew install bash"
            print_info "  Then use: /usr/local/bin/bash or /opt/homebrew/bin/bash"
        else
            print_error "Bash version $bash_version is too old. Required: >= 4.0"
            CRITICAL_ERROR=true
            return 1
        fi
    fi

    # Warn if version < 5.0
    if [[ $major -lt 5 ]]; then
        print_warning "Bash version $bash_version is recommended to be >= 5.0 (current: $bash_version)"
    else
        if [[ "$VERBOSE" == "true" ]]; then
            print_success "Bash version $bash_version is acceptable"
        fi
    fi

    return 0
}

# Function to provide installation guidance
get_installation_guidance() {
    local cmd="$1"
    local os="$2"

    case "$os" in
        Darwin)
            case "$cmd" in
                sudo)
                    echo "sudo is typically pre-installed on macOS"
                    ;;
                tput)
                    echo "tput is typically pre-installed on macOS"
                    ;;
                logger)
                    echo "logger is typically pre-installed on macOS"
                    ;;
                *)
                    echo "Install via Homebrew: brew install $cmd"
                    ;;
            esac
            ;;
        Linux)
            # Try to detect package manager
            if command -v apt-get >/dev/null 2>&1; then
                echo "Install via apt: sudo apt-get install $cmd"
            elif command -v yum >/dev/null 2>&1; then
                echo "Install via yum: sudo yum install $cmd"
            elif command -v dnf >/dev/null 2>&1; then
                echo "Install via dnf: sudo dnf install $cmd"
            elif command -v pacman >/dev/null 2>&1; then
                echo "Install via pacman: sudo pacman -S $cmd"
            else
                echo "Install $cmd using your system's package manager"
            fi
            ;;
        *)
            echo "Install $cmd using your system's package manager"
            ;;
    esac
}

# Function to validate dependencies
validate_dependencies() {
    print_info "Validating dependencies..."
    print_info ""

    local missing_required=()
    local missing_optional=()

    # Check bash version
    if ! check_bash_version; then
        missing_required+=("bash (version >= 4.0)")
    fi

    # Check required commands
    if ! check_command "uname" true; then
        missing_required+=("uname")
    fi

    # Check optional but recommended commands
    check_command "sudo" false
    check_command "tput" false
    check_command "logger" false

    print_info ""

    # Summary
    if [[ ${#missing_required[@]} -gt 0 ]]; then
        print_error "Missing required dependencies:"
        for dep in "${missing_required[@]}"; do
            print_error "  - $dep"
            local guidance=$(get_installation_guidance "$dep" "$OS_TYPE")
            if [[ -n "$guidance" ]]; then
                print_info "    $guidance"
            fi
        done
        print_info ""
        return 1
    fi

    if [[ "$CRITICAL_ERROR" == "true" ]]; then
        return 1
    fi

    print_success "All dependencies validated"
    print_info ""
    return 0
}

# Error handler function
error_handler() {
    local exit_code=$?
    local line_number=$1

    if [[ $exit_code -ne 0 ]]; then
        print_error "Error occurred at line $line_number (exit code: $exit_code)"
        log_message "ERROR" "Script error at line $line_number (exit code: $exit_code)"

        # Suggest solutions based on error
        case $exit_code in
            1)
                print_info "  Suggestion: Check file permissions and disk space"
                ;;
            2)
                print_info "  Suggestion: Verify all required dependencies are installed"
                ;;
            126)
                print_info "  Suggestion: Check script execution permissions"
                ;;
            127)
                print_info "  Suggestion: Verify command exists and is in PATH"
                ;;
            *)
                print_info "  Suggestion: Review error messages above for details"
                ;;
        esac
    fi
}

# Cleanup function
cleanup() {
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        log_message "ERROR" "Script exited with error code: $exit_code"
    else
        log_message "INFO" "Script completed successfully"
    fi

    # Final log message
    if [[ -n "$LOG_FILE" ]] && [[ "$LOG_ENABLED" == "true" ]]; then
        log_message "INFO" "Log file: $LOG_FILE"
    fi
}

# Set up error handling traps
trap 'error_handler $? $LINENO' ERR
trap 'cleanup' EXIT

# Function to create directory with validation
create_directory() {
    local dir_path="$1"
    local full_path="${PROJECT_ROOT}/${dir_path}"

    if [[ -d "$full_path" ]]; then
        print_warning "Directory '$dir_path' already exists"
        return 0
    fi

    if mkdir -p "$full_path" 2>/dev/null; then
        # Set permissions to 755 (rwxr-xr-x)
        chmod 755 "$full_path"
        print_success "Created directory: $dir_path"
        return 0
    else
        print_error "Failed to create directory: $dir_path"
        return 1
    fi
}

# Function to verify directory exists and has correct permissions
verify_directory() {
    local dir_path="$1"
    local full_path="${PROJECT_ROOT}/${dir_path}"
    local errors=0

    # Check if directory exists
    if [[ ! -d "$full_path" ]]; then
        print_error "Directory '$dir_path' does not exist"
        return 1
    fi

    # Check if directory is writable
    if [[ ! -w "$full_path" ]]; then
        print_error "Directory '$dir_path' is not writable"
        errors=$((errors + 1))
    fi

    # Check permissions (should be 755 or at least readable/executable)
    local perms="unknown"
    if [[ "$(uname -s)" == "Darwin" ]]; then
        perms=$(stat -f "%OLp" "$full_path" 2>/dev/null || echo "unknown")
    else
        perms=$(stat -c "%a" "$full_path" 2>/dev/null || echo "unknown")
    fi
    if [[ "$perms" != "755" ]] && [[ "$perms" != "unknown" ]]; then
        print_warning "Directory '$dir_path' has permissions $perms (expected 755)"
    fi

    if [[ $errors -eq 0 ]]; then
        print_success "Verified directory: $dir_path (permissions: ${perms})"
        return 0
    else
        return 1
    fi
}

# Function to create .gitkeep file in empty directory
create_gitkeep() {
    local dir_path="$1"
    local full_path="${PROJECT_ROOT}/${dir_path}"
    local gitkeep_path="${full_path}/.gitkeep"

    if [[ -d "$full_path" ]] && [[ ! -f "$gitkeep_path" ]]; then
        touch "$gitkeep_path"
        chmod 644 "$gitkeep_path"
        print_success "Created .gitkeep in: $dir_path"
    fi
}

# Function to check if file is executable
is_executable() {
    local file_path="$1"
    [[ -x "$file_path" ]]
}

# Function to find all .sh scripts in project
find_scripts() {
    find "$PROJECT_ROOT" -type f -name '*.sh' ! -path '*/\.*' 2>/dev/null
}

# Function to set executable permissions on scripts
set_script_permissions() {
    local dry_run="${1:-false}"
    local verbose="${2:-false}"

    print_info "Setting executable permissions on shell scripts..."
    print_info ""

    local scripts=()
    local script_count=0
    local modified_count=0
    local skipped_count=0
    local error_count=0

    # Find all .sh files
    while IFS= read -r script; do
        scripts+=("$script")
    done < <(find_scripts)

    script_count=${#scripts[@]}

    if [[ $script_count -eq 0 ]]; then
        print_warning "No .sh scripts found in project"
        return 0
    fi

    print_info "Found $script_count shell script(s)"
    print_info ""

    # Process each script
    for script in "${scripts[@]}"; do
        local script_name="${script#$PROJECT_ROOT/}"

        # Check if already executable
        if is_executable "$script"; then
            if [[ "$verbose" == "true" ]]; then
                print_info "  [SKIP] $script_name (already executable)"
            fi
            skipped_count=$((skipped_count + 1))
            continue
        fi

        # Check if file is readable
        if [[ ! -r "$script" ]]; then
            print_error "Cannot read: $script_name"
            error_count=$((error_count + 1))
            continue
        fi

        # Set permissions
        if [[ "$dry_run" == "true" ]]; then
            print_info "  [DRY-RUN] Would execute: chmod +x $script_name"
            modified_count=$((modified_count + 1))
        else
            if chmod +x "$script" 2>/dev/null; then
                if [[ "$verbose" == "true" ]]; then
                    print_success "  Set executable: $script_name"
                fi
                modified_count=$((modified_count + 1))
            else
                print_error "  Failed to set permissions: $script_name"
                error_count=$((error_count + 1))
            fi
        fi
    done

    print_info ""

    # Summary
    if [[ "$dry_run" == "true" ]]; then
        print_info "Dry-run summary:"
        print_info "  Total scripts: $script_count"
        print_info "  Would modify: $modified_count"
        print_info "  Would skip: $skipped_count"
    else
        print_info "Permission summary:"
        print_info "  Total scripts: $script_count"
        print_info "  Modified: $modified_count"
        print_info "  Skipped (already executable): $skipped_count"
        if [[ $error_count -gt 0 ]]; then
            print_error "  Errors: $error_count"
        fi
    fi

    if [[ $error_count -gt 0 ]]; then
        return 1
    fi

    return 0
}

# Function to parse command-line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--dry-run)
                DRY_RUN=true
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
            *)
                print_error "Unknown option: $1"
                print_info "Use --help for usage information"
                exit 2
                ;;
        esac
    done
}

# Function to show help message
show_help() {
    cat << EOF
OS Optimization Scripts - Installation Script

Usage: $0 [OPTIONS]

Options:
    -n, --dry-run    Show what would be done without making changes
    -v, --verbose    Show detailed output for each operation
    -h, --help       Show this help message

Description:
    This script creates the project directory structure and sets executable
    permissions on all shell scripts in the project.

Examples:
    $0                  # Normal installation
    $0 --dry-run        # Preview changes without executing
    $0 --verbose        # Show detailed output
EOF
}

# Main execution
main() {
    # Parse command-line arguments
    parse_arguments "$@"

    # Initialize logging
    init_logging

    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "OS Optimization Scripts - Installation (DRY-RUN MODE)"
        print_info "====================================================="
    else
        print_info "OS Optimization Scripts - Installation"
        print_info "========================================"
    fi
    print_info ""

    # Validate dependencies before proceeding
    if ! validate_dependencies; then
        print_error "Dependency validation failed. Please install missing dependencies and try again."
        exit 2
    fi

    local failed_dirs=()
    local success_count=0

    # Create all directories
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Would create directory structure..."
        for dir in "${DIRECTORIES[@]}"; do
            local full_path="${PROJECT_ROOT}/${dir}"
            if [[ -d "$full_path" ]]; then
                print_info "  [SKIP] Directory '$dir' already exists"
            else
                print_info "  [WOULD CREATE] $dir"
            fi
        done
    else
        print_info "Creating directory structure..."
        for dir in "${DIRECTORIES[@]}"; do
            if create_directory "$dir"; then
                success_count=$((success_count + 1))
            else
                failed_dirs+=("$dir")
            fi
        done
    fi

    print_info ""

    # Create .gitkeep files in empty directories
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Would create .gitkeep files..."
        for dir in "${DIRECTORIES[@]}"; do
            local full_path="${PROJECT_ROOT}/${dir}"
            local gitkeep_path="${full_path}/.gitkeep"
            if [[ -f "$gitkeep_path" ]]; then
                print_info "  [SKIP] .gitkeep already exists in: $dir"
            else
                print_info "  [WOULD CREATE] .gitkeep in: $dir"
            fi
        done
    else
        print_info "Creating .gitkeep files..."
        for dir in "${DIRECTORIES[@]}"; do
            create_gitkeep "$dir"
        done
    fi

    print_info ""

    # Verify all directories
    print_info "Validating directory structure..."
    local verify_errors=0
    for dir in "${DIRECTORIES[@]}"; do
        if ! verify_directory "$dir"; then
            verify_errors=$((verify_errors + 1))
        fi
    done

    print_info ""

    # Set script permissions
    if ! set_script_permissions "$DRY_RUN" "$VERBOSE"; then
        print_warning "Some scripts could not be set as executable"
    fi

    print_info ""

    # Summary
    print_info ""
    print_info "========================================"
    if [[ ${#failed_dirs[@]} -eq 0 ]] && [[ $verify_errors -eq 0 ]] && [[ $ERROR_COUNT -eq 0 ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            print_success "Dry-run completed successfully!"
            print_info "No changes were made. Run without --dry-run to apply changes."
        else
            print_success "Installation completed successfully!"
            print_info "Created ${success_count} directories with proper permissions."
        fi
        print_info ""
        print_info "Summary:"
        print_info "  - Directories created: ${success_count}"
        print_info "  - Scripts processed: $(find_scripts | wc -l | tr -d ' ')"
        print_info "  - Dependencies: All validated"
        print_info ""
        print_info "Directory structure:"
        for dir in "${DIRECTORIES[@]}"; do
            print_info "  - ${PROJECT_ROOT}/${dir}/"
        done
        if [[ -n "$LOG_FILE" ]] && [[ "$LOG_ENABLED" == "true" ]]; then
            print_info ""
            print_info "Log file: $LOG_FILE"
        fi
        exit 0
    else
        print_error "Installation completed with errors!"
        if [[ ${#failed_dirs[@]} -gt 0 ]]; then
            print_error "Failed to create: ${failed_dirs[*]}"
        fi
        if [[ $verify_errors -gt 0 ]]; then
            print_error "Verification failed for $verify_errors directory(ies)"
        fi
        if [[ $ERROR_COUNT -gt 0 ]]; then
            print_error "Total errors encountered: $ERROR_COUNT"
        fi
        exit 1
    fi
}

# Run main function
main "$@"
