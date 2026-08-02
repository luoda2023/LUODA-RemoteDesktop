#[cfg(target_os = "android")]
mod android_opus_stub;
mod keyboard;
/// cbindgen:ignore
pub mod platform;
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub use platform::{
    clip_cursor, get_cursor, get_cursor_data, get_cursor_pos, get_focused_display,
    set_cursor_pos, start_os_service,
};
#[cfg(not(any(target_os = "ios")))]
/// cbindgen:ignore
mod server;
#[cfg(not(any(target_os = "ios")))]
pub use self::server::*;
mod client;
mod direct_access;
#[cfg(windows)]
mod headless_policy;
mod shared_counter;
#[cfg(not(any(target_os = "android", target_os = "ios")))]
mod host_startup;
mod lan;
#[cfg(not(any(target_os = "ios")))]
mod rendezvous_mediator;
#[cfg(not(any(target_os = "ios")))]
mod rendezvous_transport;
#[cfg(not(any(target_os = "ios")))]
pub use self::rendezvous_mediator::*;
/// cbindgen:ignore
pub mod common;
#[cfg(not(any(target_os = "ios")))]
pub mod ipc;
#[cfg(not(any(
    target_os = "android",
    target_os = "ios",
    feature = "cli",
    feature = "flutter"
)))]
pub mod ui;
mod version;
pub use version::*;
#[cfg(any(target_os = "android", target_os = "ios", feature = "flutter"))]
mod bridge_generated;
#[cfg(any(target_os = "android", target_os = "ios", feature = "flutter"))]
pub mod flutter;
#[cfg(any(target_os = "android", target_os = "ios", feature = "flutter"))]
pub mod flutter_ffi;
use common::*;
mod auth_2fa;
#[cfg(feature = "cli")]
pub mod cli;
#[cfg(not(target_os = "ios"))]
mod clipboard;
#[cfg(not(any(target_os = "android", target_os = "ios", feature = "cli")))]
pub mod core_main;
mod custom_server;
mod lang;
#[cfg(not(any(target_os = "android", target_os = "ios")))]
mod port_forward;

// UPnP 端口自动映射模块：让外网能直接通过 公网IP:端口 访问本机，
// 不需要用户手动配置路由器端口转发。仅在桌面平台启用。
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub mod upnp;

#[cfg(all(feature = "flutter", feature = "plugin_framework"))]
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub mod plugin;

#[cfg(not(any(target_os = "android", target_os = "ios")))]
mod tray;
#[cfg(not(any(target_os = "android", target_os = "ios")))]
mod tray_exit;

#[cfg(not(any(target_os = "android", target_os = "ios")))]
mod whiteboard;

#[cfg(not(any(target_os = "android", target_os = "ios")))]
mod updater;

mod ui_cm_interface;
mod ui_interface;
mod ui_session_interface;

mod hbbs_http;

#[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
pub mod clipboard_file;

pub mod privacy_mode;

#[cfg(windows)]
pub mod virtual_display_manager;

mod kcp_stream;

// === AUTO-INJECTED RUNTIME LOGGER ===
pub mod runtime_logger {
use std::path::PathBuf;
use std::fs::{OpenOptions, create_dir_all, metadata, rename};
use std::io::Write;
use std::time::{SystemTime, UNIX_EPOCH};
use std::sync::Mutex;
use once_cell::sync::Lazy;

static LOGGER: Lazy<Mutex<RuntimeLog>> = Lazy::new(|| {
Mutex::new(RuntimeLog::new())
});

/// Maximum log file size before rotation (5 MB).
const LOG_ROTATION_SIZE: u64 = 5 * 1024 * 1024;

struct RuntimeLog {
 log_path: PathBuf,
 enabled: bool,
 file: Option<std::fs::File>,
}

impl RuntimeLog {
 fn new() -> Self {
 let base = if cfg!(target_os = "windows") {
 std::env::var("APPDATA").map(|p| PathBuf::from(p).join("LUODA").join("logs"))
 .unwrap_or_else(|_| PathBuf::from("C:\\LUODA\\logs"))
 } else if cfg!(target_os = "macos") {
 PathBuf::from(std::env::var("HOME").unwrap_or_default())
 .join("Library").join("Logs").join("LUODA")
 } else {
 PathBuf::from(std::env::var("HOME").unwrap_or_default())
 .join(".config").join("luoda").join("logs")
 };
 let log_file = base.join("luoda_runtime.log");
 let _ = create_dir_all(&base);
 // Open once and keep the handle; no per-log open/close overhead.
 let file = OpenOptions::new().create(true).append(true).open(&log_file).ok();
 if let Some(ref mut f) = file.as_ref() {
 let _ = f.write_all(format!(
 "[{}] [INIT] Runtime logger initialized\n",
 SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs()
 ).as_bytes());
 }
 RuntimeLog { log_path: log_file, enabled: true, file }
 }

 /// Rotate the log file if it exceeds LOG_ROTATION_SIZE.
 /// Renames current file to `.1` and opens a fresh one.
 fn maybe_rotate(&mut self) {
 if self.file.is_none() { return; }
 let should_rotate = metadata(&self.log_path)
 .map(|m| m.len() >= LOG_ROTATION_SIZE)
 .unwrap_or(false);
 if !should_rotate { return; }
 // Close current handle.
 self.file = None;
 let backup = self.log_path.with_extension("log.1");
 let _ = rename(&self.log_path, &backup);
 // Reopen fresh.
 self.file = OpenOptions::new().create(true).append(true).open(&self.log_path).ok();
 }

 fn log(&mut self, level: &str, tag: &str, msg: &str) {
 if !self.enabled { return; }
 self.maybe_rotate();
 if let Some(ref mut file) = self.file {
 let ts = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs();
 let _ = writeln!(file, "[{}] [{}] [{}] {}", ts, level, tag, msg);
 }
 }
}
pub fn info(tag: &str, msg: &str) { if let Ok(mut g) = LOGGER.lock() { g.log("INFO", tag, msg); } }
pub fn warn(tag: &str, msg: &str) { if let Ok(mut g) = LOGGER.lock() { g.log("WARN", tag, msg); } }
pub fn error(tag: &str, msg: &str) { if let Ok(mut g) = LOGGER.lock() { g.log("ERROR", tag, msg); } }
pub fn debug(tag: &str, msg: &str) { if let Ok(mut g) = LOGGER.lock() { g.log("DEBUG", tag, msg); } }
    pub fn init() {
        info("SYSTEM", &format!("LUODA v{} starting on {}", env!("CARGO_PKG_VERSION"), std::env::consts::OS));
        info("SYSTEM", &format!("Args: {:?}", std::env::args().collect::<Vec<_>>()));
    }
}
// === END RUNTIME LOGGER ===
