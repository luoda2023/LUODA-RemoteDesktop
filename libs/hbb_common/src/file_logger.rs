use chrono::Local;
use log::{LevelFilter, Log, Metadata, Record, SetLoggerError};
use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::path::PathBuf;
use std::sync::Mutex;

/// A logger that writes to a daily log file.
/// Log file location: %PROGRAMDATA%/LUODA/logs/luoda-YYYY-MM-DD.log
pub struct FileLogger {
    file: Mutex<Option<File>>,
    level: LevelFilter,
}

impl FileLogger {
    pub fn new(level: LevelFilter) -> Self {
        Self {
            file: Mutex::new(None),
            level,
        }
    }

    fn log_path() -> Option<PathBuf> {
        let base = std::env::var("ALLUSERSPROFILE")
            .unwrap_or_else(|_| "C:\\ProgramData".to_string());
        let dir = PathBuf::from(base).join("LUODA").join("logs");
        fs::create_dir_all(&dir).ok()?;
        let date = Local::now().format("%Y-%m-%d");
        Some(dir.join(format!("luoda-{}.log", date)))
    }

    fn write_log(&self, msg: &str) {
        if let Ok(mut guard) = self.file.lock() {
            if guard.is_none() {
                if let Some(path) = Self::log_path() {
                    *guard = OpenOptions::new()
                        .create(true)
                        .append(true)
                        .open(&path)
                        .ok();
                }
            }
            if let Some(ref mut file) = *guard {
                let _ = file.write_all(msg.as_bytes());
                let _ = file.flush();
            }
        }
    }

    /// Initialize the global logger with FileLogger.
    /// Call this once at program startup.
    pub fn init(level: LevelFilter) -> Result<(), SetLoggerError> {
        log::set_boxed_logger(Box::new(Self::new(level)))?;
        log::set_max_level(level);
        Ok(())
    }
}

impl Log for FileLogger {
    fn enabled(&self, metadata: &Metadata) -> bool {
        metadata.level() <= self.level
    }

    fn log(&self, record: &Record) {
        if !self.enabled(record.metadata()) {
            return;
        }
        let ts = Local::now().format("%Y-%m-%d %H:%M:%S%.3f");
        let target = record.target();
        let msg = format!("[{}] [{}] [{}] {}\n", ts, record.level(), target, record.args());
        self.write_log(&msg);
        // Also output to stderr
        eprint!("{}", msg);
    }

    fn flush(&self) {
        if let Ok(mut guard) = self.file.lock() {
            if let Some(ref mut file) = *guard {
                let _ = file.flush();
            }
        }
    }
}

/// Set up a panic hook that writes panic info to the log file
/// and shows an error dialog on Windows.
pub fn setup_panic_hook() {
    let prev = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        let msg = format!("{}", info);
        log::error!("=== PANIC ===");
        log::error!("{}", msg);
        log::error!("Backtrace not available in release build");
        // Show error dialog on Windows
        #[cfg(windows)]
        {
            let text = format!(
                "LUODA encountered an error:\n\n{}\n\nPlease check the log file at:\n%PROGRAMDATA%\\LUODA\\logs\\",
                msg
            );
            let text_wide: Vec<u16> = text.encode_utf16().chain(std::iter::once(0)).collect();
            let title_wide: Vec<u16> = "LUODA Error".encode_utf16().chain(std::iter::once(0)).collect();
            unsafe {
                winapi::um::winuser::MessageBoxW(
                    std::ptr::null_mut(),
                    text_wide.as_ptr(),
                    title_wide.as_ptr(),
                    winapi::um::winuser::MB_OK | winapi::um::winuser::MB_ICONERROR,
                );
            }
        }
        prev(info);
    }));
}
