#!/usr/bin/env bash

# Snapshot Library
# Version: 1.0.0
# Description: System state snapshot creation and management

# Source guard
if [[ -n ${SNAPSHOT_SH_LOADED:-} ]]; then
    return 0
fi
readonly SNAPSHOT_SH_LOADED=1

readonly SNAPSHOT_DIR="${HOME}/.os-optimize/backups"
readonly MAX_SNAPSHOTS=3

create_snapshot() {
    local optimization_type="${1:-unknown}"
    local script_version="${2:-1.0.0}"

    local timestamp=$(date +%Y%m%d-%H%M%S)
    local snapshot_path="${SNAPSHOT_DIR}/snapshot-${timestamp}"

    mkdir -p "$snapshot_path" 2>/dev/null || {
        echo "ERROR: Cannot create snapshot directory: $snapshot_path" >&2
        return 1
    }

    echo "Creating system snapshot: $snapshot_path"

    # Capture system state
    local os_type=$(uname -s)

    # Memory stats
    if [[ "$os_type" == "Darwin" ]]; then
        vm_stat > "$snapshot_path/memory_stats.txt" 2>/dev/null || true
    else
        free -h > "$snapshot_path/memory_stats.txt" 2>/dev/null || true
        cat /proc/meminfo > "$snapshot_path/meminfo.txt" 2>/dev/null || true
    fi

    # Running processes
    ps aux > "$snapshot_path/processes.txt" 2>/dev/null || true

    # Disk usage
    df -h > "$snapshot_path/disk_usage.txt" 2>/dev/null || true

    # System services
    if [[ "$os_type" == "Darwin" ]]; then
        launchctl list > "$snapshot_path/launchd_services.txt" 2>/dev/null || true
    else
        systemctl list-units > "$snapshot_path/systemd_services.txt" 2>/dev/null || true
    fi

    # Crontab
    crontab -l > "$snapshot_path/crontab.backup" 2>/dev/null || true

    # Critical config files
    if [[ "$os_type" == "Linux" ]]; then
        [[ -f /etc/sysctl.conf ]] && cp /etc/sysctl.conf "$snapshot_path/sysctl.conf.backup" 2>/dev/null || true
        [[ -f /etc/fstab ]] && cp /etc/fstab "$snapshot_path/fstab.backup" 2>/dev/null || true
    fi

    # Create manifest
    cat > "$snapshot_path/manifest.json" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "script_version": "$script_version",
  "optimization_type": "$optimization_type",
  "os_type": "$os_type",
  "hostname": "$(hostname 2>/dev/null || echo 'unknown')",
  "user": "$(whoami 2>/dev/null || echo 'unknown')"
}
EOF

    # Compress snapshot
    if command -v tar >/dev/null 2>&1; then
        cd "$SNAPSHOT_DIR" 2>/dev/null || return 1
        tar -czf "snapshot-${timestamp}.tar.gz" "snapshot-${timestamp}" 2>/dev/null && {
            rm -rf "snapshot-${timestamp}"
            echo "Snapshot compressed: snapshot-${timestamp}.tar.gz"
        } || {
            echo "WARNING: Failed to compress snapshot" >&2
        }
    fi

    # Calculate checksum
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "${SNAPSHOT_DIR}/snapshot-${timestamp}.tar.gz" > "${SNAPSHOT_DIR}/snapshot-${timestamp}.sha256" 2>/dev/null || true
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "${SNAPSHOT_DIR}/snapshot-${timestamp}.tar.gz" > "${SNAPSHOT_DIR}/snapshot-${timestamp}.sha256" 2>/dev/null || true
    fi

    # Cleanup old snapshots
    cleanup_old_snapshots

    echo "$snapshot_path"
}

list_snapshots() {
    if [[ ! -d "$SNAPSHOT_DIR" ]]; then
        echo "No snapshots directory found"
        return 1
    fi

    echo "Available Snapshots:"
    echo "==================="

    local count=0
    while IFS= read -r snapshot; do
        if [[ -f "$snapshot" ]]; then
            count=$((count + 1))
            local size=$(du -h "$snapshot" 2>/dev/null | awk '{print $1}')
            local date=$(basename "$snapshot" | sed 's/snapshot-\(.*\)\.tar\.gz/\1/')
            echo "$count. $date (${size})"
        fi
    done < <(find "$SNAPSHOT_DIR" -name "snapshot-*.tar.gz" -type f 2>/dev/null | sort -r)

    if [[ $count -eq 0 ]]; then
        echo "No snapshots found"
    fi
}

cleanup_old_snapshots() {
    if [[ ! -d "$SNAPSHOT_DIR" ]]; then
        return 0
    fi

    local snapshot_count=$(find "$SNAPSHOT_DIR" -name "snapshot-*.tar.gz" -type f 2>/dev/null | wc -l | tr -d ' ')

    if [[ $snapshot_count -gt $MAX_SNAPSHOTS ]]; then
        local to_delete=$((snapshot_count - MAX_SNAPSHOTS))

        find "$SNAPSHOT_DIR" -name "snapshot-*.tar.gz" -type f -printf '%T@ %p\n' 2>/dev/null | \
            sort -rn | tail -n +$((MAX_SNAPSHOTS + 1)) | cut -d' ' -f2- | while read -r old_snapshot; do
                rm -f "$old_snapshot" "${old_snapshot%.tar.gz}.sha256" 2>/dev/null || true
            done || \
        find "$SNAPSHOT_DIR" -name "snapshot-*.tar.gz" -type f -exec stat -f "%m %N" {} \; 2>/dev/null | \
            sort -rn | tail -n +$((MAX_SNAPSHOTS + 1)) | cut -d' ' -f2- | while read -r old_snapshot; do
                rm -f "$old_snapshot" "${old_snapshot%.tar.gz}.sha256" 2>/dev/null || true
            done || true
    fi
}
