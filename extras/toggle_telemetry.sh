#!/bin/sh
# toggle_telemetry.sh - Enable or disable telemetry, and keep cp_upload in sync

# --- Telemetry files ---
readonly WEB_SERVER="/usr/bin/web-server"
readonly WEB_SERVER_DISABLED="/usr/bin/web-server.disabled"

readonly WEBRTC="/usr/bin/webrtc"
readonly WEBRTC_DISABLED="/usr/bin/webrtc.disabled"

readonly MONITOR="/usr/bin/Monitor"
readonly MONITOR_DISABLED="/usr/bin/Monitor.disabled"

# --- cp_upload manager ---
readonly CP_UPLOAD_MANAGER="/mnt/UDISK/hi-manager/extras/cp_upload_manager.sh"

# --- Helpers ---

check_telemetry_status() {
    if [ -x "$WEB_SERVER" ] && [ -x "$WEBRTC" ] && [ -x "$MONITOR" ]; then
        echo "enabled"
    elif [ -x "$WEB_SERVER_DISABLED" ] && [ -x "$WEBRTC_DISABLED" ] && [ -x "$MONITOR_DISABLED" ]; then
        echo "disabled"
    else
        echo "mixed"
    fi
}

enable_telemetry() {
    echo "Enabling telemetry..."
    mv "$WEB_SERVER_DISABLED" "$WEB_SERVER" 2>/dev/null
    mv "$WEBRTC_DISABLED" "$WEBRTC" 2>/dev/null
    mv "$MONITOR_DISABLED" "$MONITOR" 2>/dev/null

    # Delegate to cp_upload manager
    [ -x "$CP_UPLOAD_MANAGER" ] && "$CP_UPLOAD_MANAGER" enable
}

disable_telemetry() {
    echo "Disabling telemetry..."
    mv "$WEB_SERVER" "$WEB_SERVER_DISABLED" 2>/dev/null
    mv "$WEBRTC" "$WEBRTC_DISABLED" 2>/dev/null
    mv "$MONITOR" "$MONITOR_DISABLED" 2>/dev/null

    # Delegate to cp_upload manager
    [ -x "$CP_UPLOAD_MANAGER" ] && "$CP_UPLOAD_MANAGER" disable
}

# --- Main ---
case "$1" in
    status)
        state=$(check_telemetry_status)
        echo "Telemetry: $state"
        if [ -x "$CP_UPLOAD_MANAGER" ]; then
            "$CP_UPLOAD_MANAGER" status
        else
            echo "cp_upload: not installed"
        fi
        exit 0
        ;;
esac

state=$(check_telemetry_status)

case "$state" in
    enabled)
        echo "✅ Telemetry is currently ENABLED."
        echo "❌ If you disable it, Creality will stop collecting usage data."
        echo "⚠️ Creality Print will also NO LONGER be able to detect this printer"
        echo "on the LAN nor communicate with it for uploads, control, settings, etc."
        echo
        echo "ℹ️ You will still be able to use Fluidd, Moonraker or other slicers such as OrcaSlicer."
        echo
        read -p "Do you want to disable it? [y/n] " -n 1
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            disable_telemetry
        else
            echo "Telemetry remains enabled."
            exit 0
        fi
        ;;
    disabled)
        echo "❌ Telemetry is currently DISABLED."
        echo "⚠️ If you enable it, Creality will start collecting usage data."
        echo "✅ Creality Print will also be able to detect this printer on the"
        echo "LAN and communicate with it for uploads, control, settings, etc."
        echo
        echo "ℹ️ You will still be able to use Fluidd, Moonraker or other slicers such as OrcaSlicer."
        echo
        read -p "Do you want to enable it? [y/n] " -n 1
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            enable_telemetry
        else
            echo "Telemetry remains disabled."
            exit 0
        fi
        ;;
    mixed)
        echo "⚠️ Telemetry is in a MIXED state (some components enabled, some disabled)."
        echo "Please choose:"
        echo "  [E]nable telemetry"
        echo "  [D]isable telemetry"
        echo "  [I]gnore (leave unchanged)"
        read -p "Your choice [E/D/I]: " -n 1
        echo
        case "$REPLY" in
            [Ee]) enable_telemetry ;;
            [Dd]) disable_telemetry ;;
            *)    echo "Leaving telemetry unchanged." ;;
        esac
        ;;
esac

# Remind the user that telemetry changes will take effect only after a reboot
echo "Remember, telemetry changes will take effect only after a reboot."
