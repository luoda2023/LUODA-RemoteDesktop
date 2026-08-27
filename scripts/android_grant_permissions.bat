@echo off
chcp 65001 >nul
REM LDesk - 一键授权脚本（绕开 Android 受限设置）
REM 前提：手机开启 USB 调试并已连接电脑，adb 在 PATH 中。
set PKG=com.luoda.remote
set SV=com.luoda.remote/.InputService

echo [1/6] 检查 adb 与设备...
adb get-state >nul 2>&1
if errorlevel 1 (
  echo 错误：未检测到 adb 或未连接设备，请先开启 USB 调试并连接手机。
  exit /b 1
)

echo [2/6] 授予运行时权限...
adb shell pm grant %PKG% android.permission.RECORD_AUDIO 2>nul
adb shell pm grant %PKG% android.permission.POST_NOTIFICATIONS 2>nul

echo [3/6] 授予存储访问权限（Android 11+）...
adb shell appops set %PKG% MANAGE_EXTERNAL_STORAGE allow 2>nul

echo [4/6] 忽略电池优化...
adb shell dumpsys deviceidle whitelist +%PKG% 2>nul

echo [5/6] 直接启用无障碍服务（LDesk Input），绕开受限设置拦截...
adb shell settings put secure enabled_accessibility_services %SV%
adb shell settings put secure accessibility_enabled 1

echo [6/6] 完成。若桌面仍显示受限设置提示，请改用 adb 安装（adb install）安装 APK，
echo 以 adb 方式安装的应用不受未知来源限制。
pause
