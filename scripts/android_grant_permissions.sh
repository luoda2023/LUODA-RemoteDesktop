#!/bin/sh
# LDesk - one-click permission grant (bypass Android restricted settings)
# Prereq: USB debugging enabled, device connected, adb in PATH.
PKG="com.luoda.remote"
SV="com.luoda.remote/.InputService"

echo "[1/6] Check adb and device..."
adb get-state >/dev/null 2>&1 || { echo "Error: no adb or no device connected."; exit 1; }

echo "[2/6] Grant runtime permissions..."
adb shell pm grant "$PKG" android.permission.RECORD_AUDIO 2>/dev/null
adb shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS 2>/dev/null

echo "[3/6] Grant storage access (Android 11+)..."
adb shell appops set "$PKG" MANAGE_EXTERNAL_STORAGE allow 2>/dev/null

echo "[4/6] Ignore battery optimization..."
adb shell dumpsys deviceidle whitelist +"$PKG" 2>/dev/null

echo "[5/6] Enable accessibility service (LDesk Input) directly, bypassing restricted settings..."
adb shell settings put secure enabled_accessibility_services "$SV"
adb shell settings put secure accessibility_enabled 1

echo "[6/6] Done. If the restricted-settings dialog still appears, install the APK via 'adb install'."
