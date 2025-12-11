#!/usr/bin/env bash

# Notifications Library
# Version: 1.0.0
# Description: Multi-channel notification system for desktop, email, and webhooks

# Source guard
if [[ -n ${NOTIFICATIONS_SH_LOADED:-} ]]; then
    return 0
fi
readonly NOTIFICATIONS_SH_LOADED=1

# Configuration file path (relative to project root)
# When sourced from scripts/, go up one level to find config
PROJECT_ROOT="${SCRIPT_DIR:-.}"
if [[ "$PROJECT_ROOT" == *"/scripts" ]]; then
    PROJECT_ROOT="${PROJECT_ROOT%/scripts}"
fi
CONFIG_FILE="${PROJECT_ROOT}/config/optimize.conf"

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # Simple config parsing (INI-style)
        ENABLE_DESKTOP_NOTIFICATIONS=$(grep "^enable_desktop_notifications=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' || echo "true")
        ENABLE_EMAIL_NOTIFICATIONS=$(grep "^enable_email_notifications=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' || echo "false")
        ENABLE_WEBHOOKS=$(grep "^enable_webhooks=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' || echo "false")
        SMTP_SERVER=$(grep "^smtp_server=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' || echo "")
        SMTP_PORT=$(grep "^smtp_port=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' || echo "587")
        EMAIL_RECIPIENT=$(grep "^email_recipient=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' || echo "")
        SENDER_EMAIL=$(grep "^sender_email=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' || echo "")
        SLACK_WEBHOOK_URL=$(grep "^slack_webhook_url=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' || echo "")
        DISCORD_WEBHOOK_URL=$(grep "^discord_webhook_url=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' || echo "")
    else
        # Defaults
        ENABLE_DESKTOP_NOTIFICATIONS="true"
        ENABLE_EMAIL_NOTIFICATIONS="false"
        ENABLE_WEBHOOKS="false"
    fi
}

# Replace template variables
replace_template_vars() {
    local message="$1"
    local memory_freed="${2:-0}"
    local duration="${3:-0}"
    local status="${4:-unknown}"
    local timestamp="${5:-$(date '+%Y-%m-%d %H:%M:%S')}"
    local hostname="${6:-$(hostname 2>/dev/null || echo 'unknown')}"
    local errors="${7:-none}"

    message=$(echo "$message" | sed "s/{{MEMORY_FREED}}/$memory_freed/g")
    message=$(echo "$message" | sed "s/{{DURATION}}/$duration/g")
    message=$(echo "$message" | sed "s/{{STATUS}}/$status/g")
    message=$(echo "$message" | sed "s/{{TIMESTAMP}}/$timestamp/g")
    message=$(echo "$message" | sed "s/{{HOSTNAME}}/$hostname/g")
    message=$(echo "$message" | sed "s/{{ERRORS}}/$errors/g")

    echo "$message"
}

# Send desktop notification
send_desktop_notification() {
    local title="$1"
    local message="$2"
    local urgency="${3:-normal}"

    if [[ "$ENABLE_DESKTOP_NOTIFICATIONS" != "true" ]]; then
        return 0
    fi

    local os_type=$(uname -s)

    if [[ "$os_type" == "Darwin" ]]; then
        # macOS: use osascript
        if command -v osascript >/dev/null 2>&1; then
            # Truncate message for desktop notifications (max 256 chars)
            local truncated_msg="$message"
            if [[ ${#truncated_msg} -gt 256 ]]; then
                truncated_msg="${truncated_msg:0:253}..."
            fi

            osascript -e "display notification \"$truncated_msg\" with title \"$title\"" 2>/dev/null || true
        fi
    else
        # Linux: use notify-send
        if command -v notify-send >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
            local notify_urgency="normal"
            case "$urgency" in
                low)
                    notify_urgency="low"
                    ;;
                critical)
                    notify_urgency="critical"
                    ;;
                *)
                    notify_urgency="normal"
                    ;;
            esac

            # Custom icon based on urgency
            local icon=""
            case "$urgency" in
                low)
                    icon="dialog-information"
                    ;;
                critical)
                    icon="dialog-error"
                    ;;
                *)
                    icon="dialog-information"
                    ;;
            esac

            notify-send --urgency="$notify_urgency" --icon="$icon" "$title" "$message" 2>/dev/null || true
        fi
    fi
}

# Send email report
send_email_report() {
    local subject="$1"
    local body="$2"
    local attachments="${3:-}"

    if [[ "$ENABLE_EMAIL_NOTIFICATIONS" != "true" ]] || [[ -z "$EMAIL_RECIPIENT" ]]; then
        return 0
    fi

    # Try mail command first
    if command -v mail >/dev/null 2>&1; then
        if [[ -n "$attachments" ]]; then
            echo "$body" | mail -s "$subject" -A "$attachments" "$EMAIL_RECIPIENT" 2>/dev/null || {
                # Fallback to sendmail
                send_email_via_sendmail "$subject" "$body" "$attachments"
            }
        else
            echo "$body" | mail -s "$subject" "$EMAIL_RECIPIENT" 2>/dev/null || {
                send_email_via_sendmail "$subject" "$body" "$attachments"
            }
        fi
    elif command -v sendmail >/dev/null 2>&1; then
        send_email_via_sendmail "$subject" "$body" "$attachments"
    else
        echo "WARNING: Neither mail nor sendmail available. Email notification skipped." >&2
        return 1
    fi
}

# Send email via sendmail
send_email_via_sendmail() {
    local subject="$1"
    local body="$2"
    local attachments="${3:-}"

    {
        echo "To: $EMAIL_RECIPIENT"
        echo "From: ${SENDER_EMAIL:-os-optimize@$(hostname 2>/dev/null || echo 'localhost')}"
        echo "Subject: $subject"
        echo "Content-Type: text/plain; charset=UTF-8"
        echo ""
        echo "$body"
    } | sendmail "$EMAIL_RECIPIENT" 2>/dev/null || true
}

# Send Slack notification
send_slack_notification() {
    local message="$1"
    local color="${2:-good}"  # good (green), warning (yellow), danger (red)

    if [[ "$ENABLE_WEBHOOKS" != "true" ]] || [[ -z "$SLACK_WEBHOOK_URL" ]]; then
        return 0
    fi

    if ! command -v curl >/dev/null 2>&1; then
        echo "WARNING: curl not available. Slack notification skipped." >&2
        return 1
    fi

    # Build Slack payload
    local payload=$(cat <<EOF
{
  "text": "OS Optimization Complete",
  "username": "OS Optimize Bot",
  "icon_emoji": ":robot_face:",
  "attachments": [
    {
      "color": "$color",
      "text": "$message",
      "footer": "OS Optimization Scripts",
      "ts": $(date +%s)
    }
  ]
}
EOF
)

    # Send with retry logic
    local retry_count=0
    local max_retries=3
    local delay=1

    while [[ $retry_count -lt $max_retries ]]; do
        if curl -X POST -H 'Content-Type: application/json' \
            --data "$payload" \
            --max-time 10 \
            --silent \
            --show-error \
            "$SLACK_WEBHOOK_URL" >/dev/null 2>&1; then
            return 0
        else
            retry_count=$((retry_count + 1))
            if [[ $retry_count -lt $max_retries ]]; then
                sleep $delay
                delay=$((delay * 2))  # Exponential backoff
            fi
        fi
    done

    echo "WARNING: Slack notification failed after $max_retries attempts" >&2
    return 1
}

# Send Discord notification
send_discord_notification() {
    local message="$1"
    local color="${2:-3066993}"  # Green: 3066993, Yellow: 16776960, Red: 15158332

    if [[ "$ENABLE_WEBHOOKS" != "true" ]] || [[ -z "$DISCORD_WEBHOOK_URL" ]]; then
        return 0
    fi

    if ! command -v curl >/dev/null 2>&1; then
        echo "WARNING: curl not available. Discord notification skipped." >&2
        return 1
    fi

    # Map color names to decimal
    case "$color" in
        green|success)
            color=3066993
            ;;
        yellow|warning)
            color=16776960
            ;;
        red|danger|error)
            color=15158332
            ;;
    esac

    # Build Discord payload
    local payload=$(cat <<EOF
{
  "embeds": [
    {
      "title": "OS Optimization Complete",
      "description": "$message",
      "color": $color,
      "footer": {
        "text": "OS Optimization Scripts"
      },
      "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    }
  ]
}
EOF
)

    # Send with retry logic
    local retry_count=0
    local max_retries=3
    local delay=1

    while [[ $retry_count -lt $max_retries ]]; do
        if curl -X POST -H 'Content-Type: application/json' \
            --data "$payload" \
            --max-time 10 \
            --silent \
            --show-error \
            "$DISCORD_WEBHOOK_URL" >/dev/null 2>&1; then
            return 0
        else
            retry_count=$((retry_count + 1))
            if [[ $retry_count -lt $max_retries ]]; then
                sleep $delay
                delay=$((delay * 2))  # Exponential backoff
            fi
        fi
    done

    echo "WARNING: Discord notification failed after $max_retries attempts" >&2
    return 1
}

# Generate summary message
generate_summary() {
    local memory_freed="${1:-0}"
    local duration="${2:-0}"
    local status="${3:-success}"
    local errors="${4:-0}"
    local warnings="${5:-0}"

    local summary=""

    # Format memory freed
    local memory_str=""
    if [[ $memory_freed -gt 1024 ]]; then
        memory_str=$(printf "%.2f GB" $(echo "scale=2; $memory_freed / 1024" | bc 2>/dev/null || echo "$memory_freed"))
    else
        memory_str="${memory_freed} MB"
    fi

    # Format duration
    local duration_str=""
    if [[ $duration -lt 60 ]]; then
        duration_str="${duration} seconds"
    else
        local minutes=$((duration / 60))
        local seconds=$((duration % 60))
        duration_str="${minutes}m ${seconds}s"
    fi

    # Build summary
    summary="Freed ${memory_str} in ${duration_str}"

    if [[ "$status" == "success" ]]; then
        summary="${summary}. Completed successfully."
    else
        summary="${summary}. Completed with errors."
    fi

    if [[ $warnings -gt 0 ]]; then
        summary="${summary} ${warnings} warnings."
    fi

    if [[ $errors -gt 0 ]]; then
        summary="${summary} ${errors} errors."
    fi

    echo "$summary"
}

# Send all notifications
send_all_notifications() {
    local memory_freed="${1:-0}"
    local duration="${2:-0}"
    local status="${3:-success}"
    local errors="${4:-0}"
    local warnings="${5:-0}"
    local log_file="${6:-}"

    # Load config
    load_config

    # Generate summary
    local summary=$(generate_summary "$memory_freed" "$duration" "$status" "$errors" "$warnings")
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local hostname=$(hostname 2>/dev/null || echo 'unknown')

    # Determine urgency and color
    local urgency="normal"
    local color="good"
    if [[ "$status" != "success" ]] || [[ $errors -gt 0 ]]; then
        urgency="critical"
        color="danger"
    elif [[ $warnings -gt 0 ]]; then
        urgency="normal"
        color="warning"
    fi

    # Desktop notification
    send_desktop_notification "OS Optimization" "$summary" "$urgency"

    # Email notification
    if [[ "$ENABLE_EMAIL_NOTIFICATIONS" == "true" ]]; then
        local email_subject="[OS Optimize] Optimization Complete - ${status^^}"
        local email_body=$(cat <<EOF
OS Optimization Report
======================

Summary: $summary
Timestamp: $timestamp
Hostname: $hostname

Memory Freed: ${memory_freed} MB
Duration: ${duration} seconds
Status: $status
Warnings: $warnings
Errors: $errors

$(if [[ -n "$log_file" ]] && [[ -f "$log_file" ]]; then
    echo "Recent Log Entries:"
    echo "-------------------"
    tail -n 50 "$log_file" 2>/dev/null || echo "Log file not accessible"
fi)
EOF
)
        send_email_report "$email_subject" "$email_body" "$log_file"
    fi

    # Slack notification
    if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
        local slack_msg=$(replace_template_vars "$summary" "$memory_freed" "$duration" "$status" "$timestamp" "$hostname" "$errors")
        send_slack_notification "$slack_msg" "$color"
    fi

    # Discord notification
    if [[ -n "$DISCORD_WEBHOOK_URL" ]]; then
        local discord_msg=$(replace_template_vars "$summary" "$memory_freed" "$duration" "$status" "$timestamp" "$hostname" "$errors")
        send_discord_notification "$discord_msg" "$color"
    fi
}

# Test all notification channels
test_notifications() {
    echo "Testing notification channels..."
    echo ""

    load_config

    # Test desktop
    echo "Testing desktop notification..."
    send_desktop_notification "Test Notification" "This is a test notification from OS Optimize" "normal"
    sleep 1

    # Test email
    if [[ "$ENABLE_EMAIL_NOTIFICATIONS" == "true" ]]; then
        echo "Testing email notification..."
        send_email_report "[OS Optimize] Test Notification" "This is a test email from OS Optimize scripts."
        sleep 1
    else
        echo "Email notifications disabled"
    fi

    # Test Slack
    if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
        echo "Testing Slack webhook..."
        send_slack_notification "Test notification from OS Optimize" "good"
        sleep 1
    else
        echo "Slack webhook not configured"
    fi

    # Test Discord
    if [[ -n "$DISCORD_WEBHOOK_URL" ]]; then
        echo "Testing Discord webhook..."
        send_discord_notification "Test notification from OS Optimize" "green"
        sleep 1
    else
        echo "Discord webhook not configured"
    fi

    echo ""
    echo "Notification tests completed"
}
