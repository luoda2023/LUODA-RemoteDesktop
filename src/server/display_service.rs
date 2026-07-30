use super::*;
use crate::common::SimpleCallOnReturn;
#[cfg(target_os = "linux")]
use crate::platform::linux::is_x11;
#[cfg(windows)]
use crate::virtual_display_manager;
#[cfg(windows)]
use hbb_common::get_version_number;
use hbb_common::protobuf::MessageField;
use scrap::Display;
use std::sync::atomic::{AtomicBool, Ordering};

// https://github.com/luoda/luoda/discussions/6042, avoiding dbus call

pub const NAME: &'static str = "display";

struct ChangedResolution {
    original: (i32, i32),
    changed: (i32, i32),
}

lazy_static::lazy_static! {
    static ref IS_CAPTURER_MAGNIFIER_SUPPORTED: bool = is_capturer_mag_supported();
    static ref CHANGED_RESOLUTIONS: Arc<RwLock<HashMap<String, ChangedResolution>>> = Default::default();
    // Initial primary display index.
    // It should not be updated when displays changed.
    pub static ref PRIMARY_DISPLAY_IDX: usize = get_primary();
    static ref SYNC_DISPLAYS: Arc<Mutex<SyncDisplaysInfo>> = Default::default();
}

// https://github.com/luoda/luoda/pull/8537
static TEMP_IGNORE_DISPLAYS_CHANGED: AtomicBool = AtomicBool::new(false);
#[cfg(windows)]
static PREFER_HEADLESS_VIRTUAL_DISPLAY: AtomicBool = AtomicBool::new(false);

#[derive(Default)]
struct SyncDisplaysInfo {
    displays: Vec<DisplayInfo>,
    is_synced: bool,
}

impl SyncDisplaysInfo {
    fn check_changed(&mut self, displays: Vec<DisplayInfo>) {
        if self.displays.len() != displays.len() {
            self.displays = displays;
            if !TEMP_IGNORE_DISPLAYS_CHANGED.load(Ordering::Relaxed) {
                self.is_synced = false;
            }
            return;
        }
        for (i, d) in displays.iter().enumerate() {
            if d != &self.displays[i] {
                self.displays = displays;
                if !TEMP_IGNORE_DISPLAYS_CHANGED.load(Ordering::Relaxed) {
                    self.is_synced = false;
                }
                return;
            }
        }
    }

    fn get_update_sync_displays(&mut self) -> Option<Vec<DisplayInfo>> {
        if self.is_synced {
            return None;
        }
        self.is_synced = true;
        Some(self.displays.clone())
    }
}

pub fn temp_ignore_displays_changed() -> SimpleCallOnReturn {
    TEMP_IGNORE_DISPLAYS_CHANGED.store(true, std::sync::atomic::Ordering::Relaxed);
    SimpleCallOnReturn {
        b: true,
        f: Box::new(move || {
            // Wait for a while to make sure check_display_changed() is called
            // after video service has sending its `SwitchDisplay` message(`try_broadcast_display_changed()`).
            std::thread::sleep(Duration::from_millis(1000));
            TEMP_IGNORE_DISPLAYS_CHANGED.store(false, Ordering::Relaxed);
            // Trigger the display changed message.
            SYNC_DISPLAYS.lock().unwrap().is_synced = false;
        }),
    }
}

// This function is really useful, though a duplicate check if display changed.
// The video server will then send the following messages to the client:
//  1. the supported resolutions of the {idx} display
//  2. the switch resolution message, so that the client can record the custom resolution.
pub(super) fn check_display_changed(
    ndisplay: usize,
    idx: usize,
    (x, y, w, h): (i32, i32, usize, usize),
) -> Option<DisplayInfo> {
    #[cfg(target_os = "linux")]
    {
        // wayland do not support changing display for now
        if !is_x11() {
            return None;
        }
    }

    let lock = SYNC_DISPLAYS.lock().unwrap();
    // If plugging out a monitor && lock.displays.get(idx) is None.
    //  1. The client version < 1.2.4. The client side has to reconnect.
    //  2. The client version > 1.2.4, The client side can handle the case because sync peer info message will be sent.
    // But it is acceptable to for the user to reconnect manually, because the monitor is unplugged.
    let d = lock.displays.get(idx)?;
    if ndisplay != lock.displays.len() {
        return Some(d.clone());
    }
    if !(d.x == x && d.y == y && d.width == w as i32 && d.height == h as i32) {
        Some(d.clone())
    } else {
        None
    }
}

#[inline]
pub fn set_last_changed_resolution(display_name: &str, original: (i32, i32), changed: (i32, i32)) {
    let mut lock = CHANGED_RESOLUTIONS.write().unwrap();
    match lock.get_mut(display_name) {
        Some(res) => res.changed = changed,
        None => {
            lock.insert(
                display_name.to_owned(),
                ChangedResolution { original, changed },
            );
        }
    }
}

#[inline]
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn restore_resolutions() {
    for (name, res) in CHANGED_RESOLUTIONS.read().unwrap().iter() {
        let (w, h) = res.original;
        log::info!("Restore resolution of display '{}' to ({}, {})", name, w, h);
        if let Err(e) = crate::platform::change_resolution(name, w as _, h as _) {
            log::error!(
                "Failed to restore resolution of display '{}' to ({},{}): {}",
                name,
                w,
                h,
                e
            );
        }
    }
    // Can be cleared because restore resolutions is called when there is no client connected.
    CHANGED_RESOLUTIONS.write().unwrap().clear();
}

#[inline]
fn is_capturer_mag_supported() -> bool {
    #[cfg(windows)]
    return scrap::CapturerMag::is_supported();
    #[cfg(not(windows))]
    false
}

#[inline]
pub fn capture_cursor_embedded() -> bool {
    scrap::is_cursor_embedded()
}

#[inline]
#[cfg(windows)]
pub fn is_privacy_mode_mag_supported() -> bool {
    return *IS_CAPTURER_MAGNIFIER_SUPPORTED
        && get_version_number(&crate::VERSION) > get_version_number("1.1.9");
}

pub fn new() -> GenericService {
    let svc = EmptyExtraFieldService::new(NAME.to_owned(), true);
    GenericService::run(&svc.clone(), run);
    svc.sp
}

fn displays_to_msg(displays: Vec<DisplayInfo>) -> Message {
    let mut pi = PeerInfo {
        ..Default::default()
    };
    pi.displays = displays.clone();

    #[cfg(windows)]
    if crate::platform::is_installed() {
        let m = crate::virtual_display_manager::get_platform_additions();
        pi.platform_additions = serde_json::to_string(&m).unwrap_or_default();
    }

    // current_display should not be used in server.
    // It is set to 0 for compatibility with old clients.
    pi.current_display = 0;
    let mut msg_out = Message::new();
    msg_out.set_peer_info(pi);
    msg_out
}

fn check_get_displays_changed_msg() -> Option<Message> {
    #[cfg(target_os = "linux")]
    {
        if !is_x11() {
            return get_displays_msg();
        }
    }
    check_update_displays(&try_get_displays().ok()?);
    get_displays_msg()
}

pub fn check_displays_changed() -> ResultType<()> {
    #[cfg(target_os = "linux")]
    {
        // Currently, wayland need to call wayland::clear() before call Display::all(), otherwise it will cause
        // block, or even crash here, https://github.com/luoda/luoda/blob/0bb4d43e9ea9d9dfb9c46c8d27d1a97cd0ad6bea/libs/scrap/src/wayland/pipewire.rs#L235
        if !is_x11() {
            return Ok(());
        }
    }
    check_update_displays(&try_get_displays()?);
    Ok(())
}

fn get_displays_msg() -> Option<Message> {
    let displays = SYNC_DISPLAYS.lock().unwrap().get_update_sync_displays()?;
    Some(displays_to_msg(displays))
}

fn run(sp: EmptyExtraFieldService) -> ResultType<()> {
    while sp.ok() {
        sp.snapshot(|sps| {
            if !TEMP_IGNORE_DISPLAYS_CHANGED.load(Ordering::Relaxed) {
                if sps.has_subscribes() {
                    SYNC_DISPLAYS.lock().unwrap().is_synced = false;
                    bail!("new subscriber");
                }
            }
            Ok(())
        })?;

        if let Some(msg_out) = check_get_displays_changed_msg() {
            sp.send(msg_out);
            log::info!("Displays changed");
        }
        std::thread::sleep(Duration::from_millis(300));
    }

    Ok(())
}

#[inline]
pub(super) fn get_original_resolution(
    display_name: &str,
    w: usize,
    h: usize,
) -> MessageField<Resolution> {
    #[cfg(windows)]
    let is_luoda_virtual_display =
        crate::virtual_display_manager::luoda_idd::is_virtual_display(&display_name);
    #[cfg(not(windows))]
    let is_luoda_virtual_display = false;
    Some(if is_luoda_virtual_display {
        Resolution {
            width: 0,
            height: 0,
            ..Default::default()
        }
    } else {
        let changed_resolutions = CHANGED_RESOLUTIONS.write().unwrap();
        let (width, height) = match changed_resolutions.get(display_name) {
            Some(res) => {
                res.original
                /*
                The resolution change may not happen immediately, `changed` has been updated,
                but the actual resolution is old, it will be mistaken for a third-party change.
                if res.changed.0 != w as i32 || res.changed.1 != h as i32 {
                    // If the resolution is changed by third process, remove the record in changed_resolutions.
                    changed_resolutions.remove(display_name);
                    (w as _, h as _)
                } else {
                    res.original
                }
                */
            }
            None => (w as _, h as _),
        };
        Resolution {
            width,
            height,
            ..Default::default()
        }
    })
    .into()
}

pub(super) fn get_sync_displays() -> Vec<DisplayInfo> {
    SYNC_DISPLAYS.lock().unwrap().displays.clone()
}

pub(super) fn get_display_info(idx: usize) -> Option<DisplayInfo> {
    SYNC_DISPLAYS.lock().unwrap().displays.get(idx).cloned()
}

// Display to DisplayInfo
// The DisplayInfo is be sent to the peer.
pub(super) fn check_update_displays(all: &Vec<Display>) {
    // For compatibility: if only one display, scale remains 1.0 and we use the physical size for `uinput`.
    // If there are multiple displays, we use the logical size for `uinput` by setting scale to d.scale().
    #[cfg(target_os = "linux")]
    let use_logical_scale = !is_x11()
        && crate::is_server()
        && scrap::wayland::display::get_displays().displays.len() > 1;
    let displays = all
        .iter()
        .map(|d| {
            let display_name = d.name();
            #[allow(unused_assignments)]
            #[allow(unused_mut)]
            let mut scale = 1.0;
            #[cfg(target_os = "macos")]
            {
                scale = d.scale();
            }
            #[cfg(target_os = "linux")]
            {
                if use_logical_scale {
                    scale = d.scale();
                }
            }
            let original_resolution = get_original_resolution(
                &display_name,
                ((d.width() as f64) / scale).round() as usize,
                (d.height() as f64 / scale).round() as usize,
            );
            DisplayInfo {
                x: d.origin().0 as _,
                y: d.origin().1 as _,
                width: d.width() as _,
                height: d.height() as _,
                name: display_name,
                online: d.is_online(),
                cursor_embedded: false,
                original_resolution,
                scale,
                ..Default::default()
            }
        })
        .collect::<Vec<DisplayInfo>>();
    SYNC_DISPLAYS.lock().unwrap().check_changed(displays);
}

pub fn is_inited_msg() -> Option<Message> {
    #[cfg(target_os = "linux")]
    if !is_x11() {
        return super::wayland::is_inited();
    }
    None
}

pub async fn update_get_sync_displays_on_login() -> ResultType<Vec<DisplayInfo>> {
    #[cfg(target_os = "linux")]
    {
        if !is_x11() {
            return super::wayland::get_displays().await;
        }
    }
    #[cfg(not(windows))]
    let displays = display_service::try_get_displays();
    #[cfg(windows)]
    let displays = display_service::try_get_displays_add_amyuni_headless();
    check_update_displays(&displays?);
    Ok(SYNC_DISPLAYS.lock().unwrap().displays.clone())
}

#[inline]
pub fn get_primary() -> usize {
    #[cfg(target_os = "linux")]
    {
        if !is_x11() {
            return match super::wayland::get_primary() {
                Ok(n) => n,
                Err(_) => 0,
            };
        }
    }

    try_get_displays().map(|d| get_primary_2(&d)).unwrap_or(0)
}

#[inline]
pub fn get_primary_2(all: &Vec<Display>) -> usize {
    all.iter().position(|d| d.is_primary()).unwrap_or(0)
}

#[cfg(windows)]
fn retain_usable_displays(displays: &mut Vec<Display>) {
    let prefer_headless_virtual = PREFER_HEADLESS_VIRTUAL_DISPLAY.load(Ordering::Relaxed);
    let probes = displays
        .iter()
        .map(|display| crate::headless_policy::DisplayProbe {
            online: display.is_online(),
            headless_virtual: prefer_headless_virtual
                && virtual_display_manager::amyuni_idd::is_my_display(&display.name()),
        })
        .collect::<Vec<_>>();
    let usable = crate::headless_policy::usable_display_indices(&probes, prefer_headless_virtual);
    if usable.len() != displays.len() {
        log::warn!(
            "ignoring {} offline or unusable display(s) before capture",
            displays.len() - usable.len()
        );
    }
    let mut indexed = displays.drain(..).map(Some).collect::<Vec<_>>();
    *displays = usable
        .into_iter()
        .filter_map(|index| indexed.get_mut(index).and_then(|display| display.take()))
        .collect();
}

#[cfg(windows)]
fn has_usable_headless_virtual_display(displays: &[Display]) -> bool {
    displays.iter().any(|display| {
        display.is_online() && virtual_display_manager::amyuni_idd::is_my_display(&display.name())
    })
}

#[cfg(windows)]
fn prepare_headless_before_disconnect(displays: &mut Vec<Display>, headless_requested: bool) {
    if !crate::headless_policy::should_prepare_headless_before_disconnect(
        true, // headless_capable: any Windows may run headless on VPS/VM
        headless_requested,
        !displays.is_empty(),
        has_usable_headless_virtual_display(displays),
    ) {
        return;
    }

    log::info!("preparing virtual display before session disconnect");
    if let Err(error) = virtual_display_manager::plug_in_headless() {
        log::warn!(
            "failed to prepare virtual display before disconnect: {}",
            error
        );
        return;
    }

    let started = std::time::Instant::now();
    while started.elapsed() < std::time::Duration::from_secs(5) {
        if let Ok(mut found) = Display::all() {
            retain_usable_displays(&mut found);
            if has_usable_headless_virtual_display(&found) {
                log::info!(
                    "virtual display prepared before disconnect after {:?}",
                    started.elapsed()
                );
                *displays = found;
                return;
            }
        }
        std::thread::sleep(std::time::Duration::from_millis(250));
    }

    log::warn!("virtual display did not become usable before disconnect");
}

#[cfg(windows)]
pub(super) fn prepare_headless_on_portable_host_startup() {
    // Allow headless virtual display on any Windows - VPS / VM environments
    // running regular (non-Server) Windows also need a virtual display to
    // remain capturable after MSTSC disconnect.
    //
    // NOTE: Do NOT skip when is_installed() is true. Even installed copies on
    // a VPS lose their display session when MSTSC disconnects, and the virtual
    // display is the only way to remain capturable in headless mode.
    if !virtual_display_manager::is_virtual_display_supported()
        || !virtual_display_manager::is_amyuni_idd()
    {
        return;
    }

    let Ok(mut displays) = Display::all() else {
        log::warn!("failed to enumerate displays before portable host startup");
        return;
    };
    retain_usable_displays(&mut displays);
    prepare_headless_before_disconnect(&mut displays, true);
}

#[cfg(windows)]
pub(super) fn recover_headless_after_capture_failure(
    display_idx: usize,
    capture_error: &str,
) -> bool {
    if PREFER_HEADLESS_VIRTUAL_DISPLAY.swap(true, Ordering::SeqCst) {
        return true;
    }

    crate::runtime_logger::warn(
        "HEADLESS",
        &format!(
            "uncapturable display; inserting virtual display; display={display_idx}; error={capture_error}"
        ),
    );
    log::warn!(
        "uncapturable display {}, starting virtual display recovery: {}",
        display_idx,
        capture_error
    );

    if virtual_display_manager::amyuni_idd::get_monitor_count() > 0 {
        log::info!("existing virtual display will be preferred for headless capture");
        return true;
    }

    match virtual_display_manager::plug_in_headless() {
        Ok(()) => {
            log::info!("virtual display inserted after first-frame capture failure");
            true
        }
        Err(error) => {
            PREFER_HEADLESS_VIRTUAL_DISPLAY.store(false, Ordering::SeqCst);
            crate::runtime_logger::error(
                "HEADLESS",
                &format!("virtual display recovery failed: {error}"),
            );
            log::error!("virtual display recovery failed: {}", error);
            false
        }
    }
}

#[inline]
#[cfg(not(windows))]
pub fn try_get_displays() -> ResultType<Vec<Display>> {
    Ok(Display::all()?)
}

#[inline]
#[cfg(windows)]
pub fn try_get_displays() -> ResultType<Vec<Display>> {
    try_get_displays_(false)
}

// We can't get full control of the virtual display if we use amyuni idd.
// If we add a virtual display, we cannot remove it automatically.
// So when using amyuni idd, we only add a virtual display for headless if it is required.
// eg. when the client is connecting.
#[inline]
#[cfg(windows)]
pub fn try_get_displays_add_amyuni_headless() -> ResultType<Vec<Display>> {
    try_get_displays_(true)
}

#[inline]
#[cfg(windows)]
pub fn try_get_displays_(add_amyuni_headless: bool) -> ResultType<Vec<Display>> {
    let (mut displays, initial_error) = match Display::all() {
        Ok(displays) => (displays, String::new()),
        Err(error) => {
            log::warn!(
                "display enumeration failed before headless recovery: {}",
                error
            );
            (Vec::new(), error.to_string())
        }
    };
    retain_usable_displays(&mut displays);

    // Portable builds package the signed driver and can request elevation for
    // its one-time installation, so headless recovery must not require a
    // previously installed LUODA service.
    if !virtual_display_manager::is_virtual_display_supported() {
        return Ok(displays);
    }

    if virtual_display_manager::is_amyuni_idd() {
        prepare_headless_before_disconnect(&mut displays, add_amyuni_headless);
    }

    // Enable headless virtual display when
    // 1. `amyuni` idd is not used.
    // 2. `amyuni` idd is used and `add_amyuni_headless` is true.
    if virtual_display_manager::is_amyuni_idd() && !add_amyuni_headless {
        return Ok(displays);
    }

    // The following code causes a bug.
    // The virtual display cannot be added when there's no session(eg. when exiting from RDP).
    // Because `crate::platform::desktop_changed()` always returns true at that time.
    //
    // The code only solves a rare case:
    // 1. The control side is connecting.
    // 2. The windows session is switching, no displays are detected, but they're there.
    // Then the controlled side plugs in a virtual display for "headless".
    //
    // No need to do the following check. But the code is kept here for marking the issue.
    // If there're someones reporting the issue, we may add a better check by waiting for a while. (switching session).
    // But I don't think it's good to add the timeout check without any issue.
    //
    // If is switching session, no displays may be detected.
    // if displays.is_empty() && crate::platform::desktop_changed() {
    //     return Ok(displays);
    // }

    if displays.is_empty() {
        log::warn!("no usable displays, starting on-demand headless recovery");
        let started = std::time::Instant::now();
        let wait_timeout = std::time::Duration::from_secs(60);
        let mut last_plug_attempt = None;
        let mut last_error = initial_error;
        while started.elapsed() < wait_timeout {
            if last_plug_attempt
                .map(|attempt: std::time::Instant| {
                    attempt.elapsed() >= std::time::Duration::from_secs(4)
                })
                .unwrap_or(true)
            {
                last_plug_attempt = Some(std::time::Instant::now());
                match virtual_display_manager::plug_in_headless_if_needed() {
                    Ok(true) => {}
                    Ok(false) => {
                        last_error = "active display detected; virtual display skipped".to_owned();
                    }
                    Err(error) => {
                        last_error = error.to_string();
                        log::warn!("headless plug attempt is not ready yet: {}", error);
                        if last_error.contains("Failed to install driver") {
                            break;
                        }
                    }
                }
            }

            match Display::all() {
                Ok(mut found) => {
                    retain_usable_displays(&mut found);
                    if found.is_empty() {
                        std::thread::sleep(std::time::Duration::from_millis(500));
                        continue;
                    }
                    displays = found;
                    log::info!(
                        "headless display recovered after {:?}, count={}",
                        started.elapsed(),
                        displays.len()
                    );
                    break;
                }
                Err(error) => last_error = error.to_string(),
            }
            std::thread::sleep(std::time::Duration::from_millis(500));
        }

        if displays.is_empty() {
            log::error!(
                "headless display recovery failed after {:?}: {}",
                started.elapsed(),
                last_error
            );
            bail!("No displays");
        }
    }
    Ok(displays)
}
