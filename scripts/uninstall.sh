#!/usr/bin/env bash

# Uninstall Script
# Version: 1.0.0
# Description: Remove OS optimization scripts and clean up

set -euo pipefail

SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes
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

# Flags
FORCE=false
PRESERVE_LOGS=false
DRY_RUN=false

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

# Parse arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)
                FORCE=true
                shift
                ;;
            --preserve-logs)
                PRESERVE_LOGS=true
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
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    cat << EOF
Uninstall Script

Usage: $0 [OPTIONS]

Options:
    --force           Skip confirmation prompts
    --preserve-logs   Keep log files
    -n, --dry-run     Preview actions without executing
    -h, --help        Show this help message

Description:
    Removes OS optimization scripts and cleans up:
    - Scripts in project directory
    - Log files (~/.os-optimize/logs/)
    - Backup files (~/.os-optimize/backups/)
    - Cron jobs (if scheduled)
    - Systemd timers/services (if installed)
    - Launchd plists (if installed)
EOF
}

# Remove cron jobs
remove_cron_jobs() {
    print_info "Checking for cron jobs..."

    if ! command -v crontab >/dev/null 2>&1; then
        print_info "crontab not available"
        return 0
    fi

    local cron_entries=$(crontab -l 2>/dev/null | grep -i "os-optimize\|optimize" || true)

    if [[ -z "$cron_entries" ]]; then
        print_info "No cron jobs found"
        return 0
    fi

    if is_dry_run; then
        print_info "[DRY-RUN] Would remove cron jobs:"
        echo "$cron_entries"
        return 0
    fi

    if [[ "$FORCE" != "true" ]]; then
        print_warning "Found cron jobs:"
        echo "$cron_entries"
        print_info "Remove cron jobs? (y/N): "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_info "Skipping cron job removal"
            return 0
        fi
    fi

    # Remove cron entries
    crontab -l 2>/dev/null | grep -v -i "os-optimize\|optimize" | crontab - 2>/dev/null || true

    print_success "Cron jobs removed"
}

# Remove systemd timers/services
remove_systemd_services() {
    print_info "Checking for systemd services..."

    if ! command -v systemctl >/dev/null 2>&1; then
        print_info "systemd not available"
        return 0
    fi

    local services=$(systemctl list-unit-files 2>/dev/null | grep -i "os-optimize\|optimize" || true)

    if [[ -z "$services" ]]; then
        print_info "No systemd services found"
        return 0
    fi

    if is_dry_run; then
        print_info "[DRY-RUN] Would remove systemd services:"
        echo "$services"
        return 0
    fi

    if [[ "$FORCE" != "true" ]]; then
        print_warning "Found systemd services:"
        echo "$services"
        print_info "Remove systemd services? (y/N): "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_info "Skipping systemd service removal"
            return 0
        fi
    fi

    # Disable and remove services
    echo "$services" | awk '{print $1}' | while read -r service; do
        sudo systemctl stop "$service" 2>/dev/null || true
        sudo systemctl disable "$service" 2>/dev/null || true
        sudo rm -f "/etc/systemd/system/${service}" 2>/dev/null || true
    done

    sudo systemctl daemon-reload 2>/dev/null || true

    print_success "Systemd services removed"
}

# Remove launchd plists
remove_launchd_plists() {
    print_info "Checking for launchd plists..."

    if [[ "$(uname -s)" != "Darwin" ]]; then
        print_info "Not macOS, skipping launchd check"
        return 0
    fi

    local plists=$(find ~/Library/LaunchAgents /Library/LaunchDaemons 2>/dev/null | grep -i "os-optimize\|optimize" || true)

    if [[ -z "$plists" ]]; then
        print_info "No launchd plists found"
        return 0
    fi

    if is_dry_run; then
        print_info "[DRY-RUN] Would remove launchd plists:"
        echo "$plists"
        return 0
    fi

    if [[ "$FORCE" != "true" ]]; then
        print_warning "Found launchd plists:"
        echo "$plists"
        print_info "Remove launchd plists? (y/N): "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_info "Skipping launchd plist removal"
            return 0
        fi
    fi

    # Unload and remove plists
    echo "$plists" | while read -r plist; do
        launchctl unload "$plist" 2>/dev/null || true
        rm -f "$plist" 2>/dev/null || true
    done

    print_success "Launchd plists removed"
}

# Clean up directories
cleanup_directories() {
    local log_dir="${HOME}/.os-optimize/logs"
    local backup_dir="${HOME}/.os-optimize/backups"

    # Clean logs
    if [[ -d "$log_dir" ]]; then
        local log_size=$(du -sh "$log_dir" 2>/dev/null | awk '{print $1}' || echo "0")

        if is_dry_run; then
            print_info "[DRY-RUN] Would remove log directory: $log_dir (${log_size})"
        elif [[ "$PRESERVE_LOGS" == "true" ]]; then
            print_info "Preserving logs: $log_dir"
        else
            if [[ "$FORCE" != "true" ]]; then
                print_info "Log directory size: ${log_size}"
                print_info "Remove log directory? (y/N): "
                read -r response
                if [[ ! "$response" =~ ^[Yy]$ ]]; then
                    print_info "Skipping log directory removal"
                else
                    rm -rf "$log_dir"
                    print_success "Log directory removed"
                fi
            else
                rm -rf "$log_dir"
                print_success "Log directory removed"
            fi
        fi
    fi

    # Clean backups
    if [[ -d "$backup_dir" ]]; then
        local backup_size=$(du -sh "$backup_dir" 2>/dev/null | awk '{print $1}' || echo "0")

        if is_dry_run; then
            print_info "[DRY-RUN] Would remove backup directory: $backup_dir (${backup_size})"
        else
            if [[ "$FORCE" != "true" ]]; then
                print_info "Backup directory size: ${backup_size}"
                print_info "Remove backup directory? (y/N): "
                read -r response
                if [[ ! "$response" =~ ^[Yy]$ ]]; then
                    print_info "Skipping backup directory removal"
                else
                    rm -rf "$backup_dir"
                    print_success "Backup directory removed"
                fi
            else
                rm -rf "$backup_dir"
                print_success "Backup directory removed"
            fi
        fi
    fi
}

# Check if dry-run
is_dry_run() {
    [[ "$DRY_RUN" == "true" ]]
}

# Main execution
main() {
    parse_arguments "$@"

    print_info "OS Optimization Scripts - Uninstaller"
    print_info "====================================="
    print_info ""

    if is_dry_run; then
        print_warning "DRY-RUN MODE: No changes will be made"
        print_info ""
    fi

    if [[ "$FORCE" != "true" ]] && [[ "$DRY_RUN" != "true" ]]; then
        print_warning "This will remove OS optimization scripts and clean up directories."
        print_info "Continue? (y/N): "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_info "Uninstall cancelled"
            exit 0
        fi
        print_info ""
    fi

    # Remove cron jobs
    remove_cron_jobs
    print_info ""

    # Remove systemd services
    remove_systemd_services
    print_info ""

    # Remove launchd plists
    remove_launchd_plists
    print_info ""

    # Clean up directories
    cleanup_directories
    print_info ""

    # Summary
    print_info "====================================="
    print_success "Uninstall completed!"
    print_info ""
    print_info "Note: Script files in this directory were not removed."
    print_info "To completely remove, delete the project directory manually."
    print_info ""
}

main "$@"
