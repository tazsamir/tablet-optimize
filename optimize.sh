#!/usr/bin/env bash
#============================================================
# Samsung Tablet Optimizer
# Purpose: Speed up and debloat Samsung Galaxy tablets (A7/A8)
#          via ADB — no root required.
#
# What it does:
#   1. Installs Lawnchair launcher (Pixel-style home screen)
#   2. Reduces animation scales (faster feel)
#   3. Disables bloatware packages
#   4. Removes unwanted user apps (A7)
#   5. Sets browser role to Chrome/Firefox
#   6. Compiles speed profiles for key apps
#   7. Trims cached data
#
# Usage:
#   ./optimize.sh [--tablet SERIAL] [--model SM-X200|SM-T220]
#   ./optimize.sh --restore-original   # undo changes
#   ./optimize.sh --info              # show device info
#
# Prerequisites:
#   - ADB installed:  sudo dnf install android-tools
#   - USB debugging enabled on tablet
#   - Tablet connected via USB and authorized
#   - Lawnchair APK in ./lawnchair/ directory
#
# Tested on:
#   - Samsung Galaxy Tab A8 (SM-X200)
#   - Samsung Galaxy Tab A7 Lite (SM-T220)
#============================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="${SCRIPT_DIR}/packages"
LAWNCHAIR_DIR="${SCRIPT_DIR}/lawnchair"

# Defaults
TARGET=""
MODEL=""
ACTION="optimize"

# ----- CLI Args -----
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tablet)
            TARGET="$2"; shift 2 ;;
        --model)
            MODEL="$2"; shift 2 ;;
        --restore-original)
            ACTION="restore"; shift ;;
        --info)
            ACTION="info"; shift ;;
        --help|-h)
            ACTION="help"; shift ;;
        *)
            echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ----- Helpers -----
warn()  { printf '\033[1;33mWARNING: %s\033[0m\n' "$1" >&2; }
info()  { printf '\033[1;34m==> %s\033[0m\n' "$1"; }
ok()    { printf '\033[1;32m[OK]\033[0m %s\n' "$1"; }

# ADB with optional serial
adb() {
    if [[ -n "$TARGET" ]]; then
        command adb -s "$TARGET" "$@"
    else
        command adb "$@"
    fi
}

# Wait for device
wait_for_device() {
    info "Waiting for tablet..."
    adb wait-for-device
    if ! adb get-state >/dev/null 2>&1; then
        echo "ERROR: No device found. Is USB debugging on and the tablet authorized?"
        exit 1
    fi
    ok "Device connected: $(adb shell getprop ro.product.model | tr -d '\r')"
}

# Check Lawnchair APK exists
check_lawnchair() {
    local apk
    # Find any lawnchair APK in the directory
    apk=$(ls "${LAWNCHAIR_DIR}"/*.apk 2>/dev/null | head -1)
    if [[ -z "$apk" ]]; then
        warn "No Lawnchair APK found in ${LAWNCHAIR_DIR}/"
        warn "Download from: https://github.com/LawnchairLauncher/lawnchair/releases"
        warn "Place it as: ${LAWNCHAIR_DIR}/Lawnchair.apk"
        return 1
    fi
    LAWNCHAIR_APK="$apk"
    info "Found Lawnchair: $(basename "$LAWNCHAIR_APK")"
}

# ----- Detect or validate model -----
detect_model() {
    local model
    model=$(adb shell getprop ro.product.model | tr -d '\r')
    echo "$model"
}

validate_model() {
    local detected
    detected=$(detect_model)

    if [[ -n "$MODEL" ]]; then
        if [[ "$detected" != "$MODEL" ]]; then
            echo "ERROR: Detected model '$detected' but expected '$MODEL'. Use --model to override."
            exit 1
        fi
        ok "Model validated: $detected"
    else
        MODEL="$detected"
        info "Detected model: $MODEL"
    fi

    case "$MODEL" in
        SM-X200)  TABLET_TYPE="a8" ;;
        SM-T220)  TABLET_TYPE="a7" ;;
        *)
            warn "Unknown model '$MODEL'. Continuing anyway..."
            TABLET_TYPE="unknown"
            ;;
    esac
}

# ----- Actions -----
do_info() {
    wait_for_device
    echo
    echo "=== Device Info ==="
    adb shell getprop ro.product.model
    adb shell getprop ro.product.manufacturer
    adb shell getprop ro.build.version.release
    adb shell getprop ro.serialno
    echo
    echo "=== Storage ==="
    adb shell df -h /data
    echo
    echo "=== Memory ==="
    adb shell cat /proc/meminfo | grep -E "^(MemTotal|MemFree|MemAvailable):"
    echo
    echo "=== Disabled packages ==="
    adb shell pm list packages -d | wc -l
    echo "(count)"
}

do_restore() {
    wait_for_device
    info "Restoring bloatware packages..."
    # Re-enable all the packages we disabled
    for pkg in \
        com.samsung.android.app.appsedge \
        com.samsung.android.app.clipboardedge \
        com.samsung.android.app.cocktailbarservice \
        com.samsung.android.app.dressroom \
        com.samsung.android.app.routines \
        com.samsung.android.app.settings.bixby \
        com.samsung.android.app.sharelive \
        com.samsung.android.app.spage \
        com.samsung.android.app.taskedge \
        com.samsung.android.dynamiclock \
        com.samsung.android.kidsinstaller \
        com.samsung.android.mobileservice \
        com.samsung.android.rubin.app \
        com.samsung.android.scloud \
        com.samsung.android.smartswitchassistant \
        com.samsung.android.stickercenter \
        com.sec.android.app.samsungapps \
        com.sec.android.app.billing \
        com.google.android.googlequicksearchbox; do
        adb shell pm enable --user 0 "$pkg" 2>/dev/null && ok "Enabled: $pkg" || true
    done

    # Restore animation scales
    adb shell settings put global window_animation_scale 1.0
    adb shell settings put global transition_animation_scale 1.0
    adb shell settings put global animator_duration_scale 1.0
    ok "Animation scales restored"

    # Restore Samsung launcher
    adb shell cmd package set-home-activity com.sec.android.app.launcher 2>/dev/null || true
    ok "Samsung launcher restored as default"

    echo
    ok "Restore complete. Reboot recommended: adb reboot"
}

do_optimize() {
    wait_for_device
    validate_model
    check_lawnchair

    local disabled_file="${PKG_DIR}/${TABLET_TYPE}-disabled.txt"

    if [[ ! -f "$disabled_file" ]]; then
        echo "ERROR: Package list not found: ${disabled_file}"
        echo "Available: $(ls "$PKG_DIR"/)"
        exit 1
    fi

    info "Starting optimizations for ${MODEL}..."

    # --- 1. Install / verify Lawnchair ---
    if ! adb shell pm path app.lawnchair >/dev/null 2>&1; then
        info "Installing Lawnchair..."
        adb install -r "$LAWNCHAIR_APK"
        ok "Lawnchair installed"
    else
        info "Lawnchair already installed, skipping"
    fi

    # --- 2. Reduce animation scales ---
    info "Reducing animation scales..."
    adb shell settings put global window_animation_scale 0.5
    adb shell settings put global transition_animation_scale 0.5
    adb shell settings put global animator_duration_scale 0.5
    adb shell settings put global disable_window_blurs 1
    adb shell settings put system edge_lighting 0
    ok "Animation scales set to 0.5x"

    # --- 3. Disable bloatware ---
    info "Disabling bloatware packages..."
    local disabled_count=0
    while IFS= read -r pkg; do
        [[ -z "$pkg" || "$pkg" == \#* ]] && continue
        if adb shell pm path "$pkg" >/dev/null 2>&1; then
            if adb shell pm disable-user --user 0 "$pkg" >/dev/null 2>&1; then
                ((disabled_count++)) || true
            fi
        fi
    done < "$disabled_file"
    ok "Disabled ${disabled_count} packages"

    # --- 4. A7-specific: remove user apps ---
    if [[ "$TABLET_TYPE" == "a7" ]]; then
        local removed_file="${PKG_DIR}/a7-removed-user.txt"
        if [[ -f "$removed_file" ]]; then
            info "Removing unwanted user apps (A7)..."
            local removed_count=0
            while IFS= read -r pkg; do
                [[ -z "$pkg" ]] && continue
                if adb shell pm list packages "$pkg" 2>/dev/null | grep -q "^package:${pkg}$"; then
                    adb uninstall "$pkg" >/dev/null 2>&1 && ((removed_count++)) || true
                fi
            done < "$removed_file"
            ok "Removed ${removed_count} user apps"
        fi

        local uninstalled_file="${PKG_DIR}/a7-uninstalled-system.txt"
        if [[ -f "$uninstalled_file" ]]; then
            info "Uninstalling system apps (A7)..."
            while IFS= read -r pkg; do
                [[ -z "$pkg" ]] && continue
                if adb shell pm list packages 2>/dev/null | grep -q "^package:${pkg}$"; then
                    adb shell pm uninstall --user 0 "$pkg" >/dev/null 2>&1 || true
                fi
            done < "$uninstalled_file"
            ok "System app uninstall attempted"
        fi
    fi

    # --- 5. Set browser role ---
    info "Setting default browser..."
    if adb shell pm list packages com.android.chrome 2>/dev/null | grep -q 'package:com.android.chrome'; then
        adb shell cmd role add-role-holder android.app.role.BROWSER com.android.chrome 0 2>/dev/null || true
        ok "Chrome set as default browser"
    elif adb shell pm list packages org.mozilla.firefox 2>/dev/null | grep -q 'package:org.mozilla.firefox'; then
        adb shell cmd role add-role-holder android.app.role.BROWSER org.mozilla.firefox 0 2>/dev/null || true
        ok "Firefox set as default browser"
    else
        warn "No recognized browser found, skipping"
    fi

    # --- 6. Set Lawnchair as home ---
    adb shell cmd package set-home-activity app.lawnchair/.LawnchairLauncher 2>/dev/null || true
    ok "Lawnchair set as home launcher"

    # --- 7. Compile speed profiles for key apps ---
    info "Compiling speed profiles (this takes ~30s)..."
    local compile_list=(
        app.lawnchair
        com.android.chrome
        com.google.android.youtube
        com.google.android.apps.docs
        com.google.android.gms
        com.android.vending
    )
    # Add tablet-specific apps
    if [[ "$TABLET_TYPE" == "a8" ]]; then
        compile_list+=(com.samsung.android.calendar org.mozilla.firefox)
    fi

    local compiled=0
    for pkg in "${compile_list[@]}"; do
        if adb shell pm path "$pkg" >/dev/null 2>&1; then
            adb shell cmd package compile -m speed-profile -f "$pkg" >/dev/null 2>&1 && ((compiled++)) || true
        fi
    done
    ok "Compiled ${compiled} speed profiles"

    # --- 8. Trim caches ---
    info "Trimming cached data..."
    adb shell pm trim-caches 8G 2>/dev/null || true
    ok "Cache trim complete"

    # --- 9. Return to home ---
    adb shell am start -a android.intent.action.MAIN -c android.intent.category.HOME >/dev/null 2>&1 || true

    echo
    echo "========================================"
    ok "Optimization complete for ${MODEL}!"
    echo "========================================"
    echo
    echo "Recommended next steps:"
    echo "  1. Reboot: adb${TARGET:+ -s $TARGET} reboot"
    echo "  2. Set up Lawnchair (long-press home screen → Settings)"
    echo "  3. Check Settings → Apps → disabled tab for re-enables"
    echo
    echo "To restore original state:"
    echo "  $0 --tablet ${TARGET:-SERIAL} --restore-original"
}

# ----- Help -----
do_help() {
    cat <<EOF
Samsung Tablet Optimizer

USAGE:
  $0 [options]

OPTIONS:
  --tablet SERIAL      ADB serial of tablet (run: adb devices)
  --model MODEL        Force model check (SM-X200 or SM-T220)
  --restore-original  Re-enable all packages, restore animations
  --info              Show device storage, memory, and package info
  --help              Show this help

EXAMPLES:
  # Auto-detect tablet (must be only one connected)
  $0 --info

  # Optimize an A8 (SM-X200)
  $0 --tablet YOUR_TABLET_SERIAL

  # Optimize an A7 Lite (SM-T220)
  $0 --tablet YOUR_TABLET_SERIAL --model SM-T220

  # Restore original state
  $0 --tablet YOUR_TABLET_SERIAL --restore-original

PREREQUISITES:
  sudo dnf install android-tools
  # On tablet: Settings → About → Developer Options → USB debugging ON
  # Authorize this computer when prompted on tablet

DOWNLOAD LAWNCHAIR:
  https://github.com/LawnchairLauncher/lawnchair/releases
  Place APK in: ./lawnchair/Lawnchair.apk
EOF
}

# ----- Main -----
case "$ACTION" in
    help)    do_help ;;
    info)    do_info ;;
    restore) do_restore ;;
    optimize)
        if [[ -z "$TARGET" ]]; then
            # Try to auto-detect if only one device is connected
            local count
            count=$(adb devices 2>/dev/null | grep -c 'device$' || true)
            if [[ "$count" -eq 1 ]]; then
                TARGET=$(adb devices 2>/dev/null | grep 'device$' | awk '{print $1}' | head -1)
                info "Auto-detected tablet: $TARGET"
            elif [[ "$count" -eq 0 ]]; then
                echo "ERROR: No tablet found. Connect tablet and authorize USB debugging."
                exit 1
            else
                echo "ERROR: Multiple devices found. Specify --tablet SERIAL"
                echo "Devices:"
                adb devices
                exit 1
            fi
        fi
        do_optimize
        ;;
esac
