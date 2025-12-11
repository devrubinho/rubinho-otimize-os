#!/usr/bin/env bash

# Rollback Script
# Version: 1.0.0
# Description: Restore system state from snapshots

set -euo pipefail

SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNAPSHOT_DIR="${HOME}/.os-optimize/backups"

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

DRY_RUN=false
SNAPSHOT_ID=""

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

show_help() {
    cat << EOF
Rollback Script

Usage: $0 [OPTIONS]

Options:
    --snapshot-id ID      Restore specific snapshot (non-interactive)
    -n, --dry-run         Preview restoration without making changes
    -h, --help            Show this help message

Description:
    Restores system state from a previously created snapshot.
    Lists available snapshots and prompts for selection if --snapshot-id not provided.
EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --snapshot-id)
                SNAPSHOT_ID="$2"
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
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

list_snapshots_interactive() {
    if [[ ! -d "$SNAPSHOT_DIR" ]]; then
        print_error "Snapshots directory not found: $SNAPSHOT_DIR"
        return 1
    fi

    local snapshots=()
    while IFS= read -r snapshot; do
        [[ -f "$snapshot" ]] && snapshots+=("$snapshot")
    done < <(find "$SNAPSHOT_DIR" -name "snapshot-*.tar.gz" -type f 2>/dev/null | sort -r)

    if [[ ${#snapshots[@]} -eq 0 ]]; then
        print_warning "No snapshots found"
        return 1
    fi

    print_info "Available Snapshots:"
    print_info ""

    local i=1
    for snapshot in "${snapshots[@]}"; do
        local size=$(du -h "$snapshot" 2>/dev/null | awk '{print $1}')
        local date=$(basename "$snapshot" | sed 's/snapshot-\(.*\)\.tar\.gz/\1/')
        print_info "$i. $date (${size})"
        i=$((i + 1))
    done

    print_info ""
    print_info "Select snapshot to restore (1-${#snapshots[@]}): "
    read -r selection

    if [[ "$selection" =~ ^[0-9]+$ ]] && [[ $selection -ge 1 ]] && [[ $selection -le ${#snapshots[@]} ]]; then
        echo "${snapshots[$((selection - 1))]}"
        return 0
    else
        print_error "Invalid selection"
        return 1
    fi
}

verify_snapshot() {
    local snapshot_file="$1"

    if [[ ! -f "$snapshot_file" ]]; then
        print_error "Snapshot file not found: $snapshot_file"
        return 1
    fi

    # Check checksum if available
    local checksum_file="${snapshot_file%.tar.gz}.sha256"
    if [[ -f "$checksum_file" ]]; then
        if command -v shasum >/dev/null 2>&1; then
            shasum -a 256 -c "$checksum_file" >/dev/null 2>&1 || {
                print_error "Snapshot checksum verification failed"
                return 1
            }
        elif command -v sha256sum >/dev/null 2>&1; then
            sha256sum -c "$checksum_file" >/dev/null 2>&1 || {
                print_error "Snapshot checksum verification failed"
                return 1
            }
        fi
    fi

    return 0
}

restore_snapshot() {
    local snapshot_file="$1"

    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Would restore from: $snapshot_file"
        return 0
    fi

    # Verify snapshot
    if ! verify_snapshot "$snapshot_file"; then
        return 1
    fi

    print_warning "=========================================="
    print_warning "WARNING: This will restore system state"
    print_warning "=========================================="
    print_info ""
    print_info "Continue with restoration? (y/N): "
    read -r response

    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        print_info "Restoration cancelled"
        return 1
    fi

    # Extract snapshot
    local temp_dir=$(mktemp -d)
    tar -xzf "$snapshot_file" -C "$temp_dir" 2>/dev/null || {
        print_error "Failed to extract snapshot"
        rm -rf "$temp_dir"
        return 1
    }

    local snapshot_dir=$(find "$temp_dir" -type d -name "snapshot-*" | head -1)

    if [[ -z "$snapshot_dir" ]] || [[ ! -d "$snapshot_dir" ]]; then
        print_error "Invalid snapshot structure"
        rm -rf "$temp_dir"
        return 1
    fi

    print_info "Restoring system state..."

    # Restore crontab
    if [[ -f "$snapshot_dir/crontab.backup" ]]; then
        if [[ "$DRY_RUN" != "true" ]]; then
            crontab "$snapshot_dir/crontab.backup" 2>/dev/null && {
                print_success "Crontab restored"
            } || {
                print_warning "Failed to restore crontab"
            }
        else
            print_info "[DRY-RUN] Would restore crontab"
        fi
    fi

    # Restore config files (requires sudo)
    local os_type=$(uname -s)
    if [[ "$os_type" == "Linux" ]]; then
        if [[ -f "$snapshot_dir/sysctl.conf.backup" ]]; then
            if [[ "$DRY_RUN" != "true" ]]; then
                if sudo cp "$snapshot_dir/sysctl.conf.backup" /etc/sysctl.conf 2>/dev/null; then
                    print_success "sysctl.conf restored"
                else
                    print_warning "Failed to restore sysctl.conf (may require sudo)"
                fi
            else
                print_info "[DRY-RUN] Would restore sysctl.conf"
            fi
        fi

        if [[ -f "$snapshot_dir/fstab.backup" ]]; then
            if [[ "$DRY_RUN" != "true" ]]; then
                if sudo cp "$snapshot_dir/fstab.backup" /etc/fstab 2>/dev/null; then
                    print_success "fstab restored"
                else
                    print_warning "Failed to restore fstab (may require sudo)"
                fi
            else
                print_info "[DRY-RUN] Would restore fstab"
            fi
        fi
    fi

    # Cleanup
    rm -rf "$temp_dir"

    print_success "Restoration completed"
    print_info ""
    print_info "Note: Some changes may require system restart to take effect"
}

main() {
    parse_arguments "$@"

    print_info "OS Optimization - Rollback Script"
    print_info "=================================="
    print_info ""

    # Select snapshot
    local snapshot_file=""

    if [[ -n "$SNAPSHOT_ID" ]]; then
        snapshot_file="${SNAPSHOT_DIR}/snapshot-${SNAPSHOT_ID}.tar.gz"
        if [[ ! -f "$snapshot_file" ]]; then
            print_error "Snapshot not found: $snapshot_file"
            exit 1
        fi
    else
        snapshot_file=$(list_snapshots_interactive)
        if [[ -z "$snapshot_file" ]]; then
            exit 1
        fi
    fi

    # Restore
    restore_snapshot "$snapshot_file"
}

main "$@"
