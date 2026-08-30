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
use std::fs::{File, OpenOptions, create_dir_all};
use std::io::Write;
use std::time::{SystemTime, UNIX_EPOCH};
use std::sync::Mutex;
use once_cell::sync::Lazy;

static LOGGER: Lazy<Mutex<RuntimeLog>> = Lazy::new(|| {
Mutex::new(RuntimeLog::new())
});

const MAX_LOG_SIZE: u64 = 5 * 1024 * 1024; // 5 MB rotation limit
const FLUSH_INTERVAL: u64 = 64 * 1024; // Flush after 64KB of buffered writes

struct RuntimeLog {
 log_path: PathBuf,
 file: Option<File>,
 written: u64,
 unflushed: u64,
 enabled: bool,
}

impl RuntimeLog {
fn new() -> Self {
let base = if cfg!(target_os = "windows") {
std::env::var("APPDATA").map(|p| PathBuf::from(p).join("LDesk").join("logs"))
.unwrap_or_else(|_| PathBuf::from("C:\\LDesk\\logs"))
} else if cfg!(target_os = "macos") {
PathBuf::from(std::env::var("HOME").unwrap_or_default())
.join("Library").join("Logs").join("LDesk")
} else {
PathBuf::from(std::env::var("HOME").unwrap_or_default())
.join(".config").join("ldesk").join("logs")
};
let log_file = base.join("ldesk_runtime.log");
let _ = create_dir_all(&base);
let mut written = 0u64;
let file = OpenOptions::new().create(true).append(true).open(&log_file).ok().map(|mut f| {
let _ = writeln!(f, "[{}] [INIT] Runtime logger initialized", SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs());
// estimate current file size from metadata
if let Ok(meta) = f.metadata() { written = meta.len(); }
f
});
RuntimeLog { log_path: log_file, file, written, unflushed: 0, enabled: true }
}

fn reopen(&mut self) {
self.file = OpenOptions::new().create(true).append(true).open(&self.log_path).ok();
self.written = 0;
}

fn log(&mut self, level: &str, tag: &str, msg: &str) {
 if !self.enabled { return; }
 // Rotate if file exceeds size limit
 if self.written >= MAX_LOG_SIZE {
 // Rename current log to .old
 let old = self.log_path.with_extension("log.old");
 let _ = std::fs::rename(&self.log_path, &old);
 self.reopen();
 }
 if self.file.is_none() {
 self.reopen();
 }
 if let Some(f) = self.file.as_mut() {
 let ts = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs();
 let line = format!("[{}] [{}] [{}] {}\n", ts, level, tag, msg);
 let _ = f.write_all(line.as_bytes());
 // Only flush on ERROR or when buffer threshold is reached, reducing I/O on hot paths.
 let is_error = level == "ERROR";
 self.unflushed += line.len() as u64;
 if is_error || self.unflushed >= FLUSH_INTERVAL {
 let _ = f.flush();
 self.unflushed = 0;
 }
 self.written += line.len() as u64;
 }
 }
}
pub fn info(tag: &str, msg: &str) { if let Ok(mut g) = LOGGER.lock() { g.log("INFO", tag, msg); } }
pub fn warn(tag: &str, msg: &str) { if let Ok(mut g) = LOGGER.lock() { g.log("WARN", tag, msg); } }
pub fn error(tag: &str, msg: &str) { if let Ok(mut g) = LOGGER.lock() { g.log("ERROR", tag, msg); } }
pub fn debug(tag: &str, msg: &str) { if let Ok(mut g) = LOGGER.lock() { g.log("DEBUG", tag, msg); } }
pub fn init() {
info("SYSTEM", &format!("LDesk v{} starting on {}", env!("CARGO_PKG_VERSION"), std::env::consts::OS));
info("SYSTEM", &format!("Args: {:?}", std::env::args().collect::<Vec<_>>()));
}
}
// === END RUNTIME LOGGER ===
