use std::time::Duration;

pub(crate) const REQUIRED_NO_DISPLAY_SAMPLES: usize = 4;
pub(crate) const FIRST_FRAME_TIMEOUT: Duration = Duration::from_secs(30);
pub(crate) const FIRST_FRAME_WOULD_BLOCK_LIMIT: usize = 3;
const STALE_RDP_GDI_CAPTURE_ERROR: &str = "Failed to copy screen to Windows buffer";

pub(crate) struct DisplayProbe {
    pub online: bool,
    pub headless_virtual: bool,
}

pub(crate) fn should_insert_headless(active_display_samples: &[bool]) -> bool {
    active_display_samples.len() >= REQUIRED_NO_DISPLAY_SAMPLES
        && active_display_samples.iter().all(|active| !active)
}

pub(crate) fn should_prepare_headless_before_disconnect(
    windows_server: bool,
    headless_requested: bool,
    has_usable_display: bool,
    has_headless_virtual: bool,
) -> bool {
    windows_server && headless_requested && has_usable_display && !has_headless_virtual
}

pub(crate) fn usable_display_indices(
    probes: &[DisplayProbe],
    prefer_headless_virtual: bool,
) -> Vec<usize> {
    let mut online = probes
        .iter()
        .enumerate()
        .filter_map(|(index, probe)| probe.online.then_some(index))
        .collect::<Vec<_>>();

    if prefer_headless_virtual {
        online.sort_by_key(|index| !probes[*index].headless_virtual);
    }

    // An online physical display is still a valid capture target even when it
    // reports a small mode (common on low-end machines and RDP sessions).
    // Treating the only small display as absent causes headless recovery to
    // insert a virtual monitor and can briefly blank the real desktop.
    online
}

pub(crate) fn should_restart_first_frame_capture(
    first_frame_sent: bool,
    elapsed: Duration,
) -> bool {
    !first_frame_sent && elapsed >= FIRST_FRAME_TIMEOUT
}

pub(crate) fn should_fallback_first_frame_capture(
    first_frame_captured: bool,
    would_block_count: usize,
) -> bool {
    !first_frame_captured && would_block_count >= FIRST_FRAME_WOULD_BLOCK_LIMIT
}

pub(crate) fn should_recover_headless_after_capture_error(
    windows_server: bool,
    first_frame_sent: bool,
    gdi_capturer: bool,
    error: &str,
) -> bool {
    windows_server
        && !first_frame_sent
        && gdi_capturer
        && error.contains(STALE_RDP_GDI_CAPTURE_ERROR)
}

#[cfg(test)]
mod tests {
    use super::{
        should_fallback_first_frame_capture, should_insert_headless,
        should_prepare_headless_before_disconnect, should_recover_headless_after_capture_error,
        should_restart_first_frame_capture, usable_display_indices, DisplayProbe,
    };
    use std::time::Duration;

    #[test]
    fn inserts_only_after_repeated_no_display_samples() {
        assert!(!should_insert_headless(&[false, false, false]));
        assert!(!should_insert_headless(&[false, true, false, false]));
        assert!(should_insert_headless(&[false, false, false, false]));
    }

    #[test]
    fn prepares_virtual_display_while_windows_server_display_is_still_usable() {
        assert!(should_prepare_headless_before_disconnect(
            true, true, true, false
        ));
        assert!(!should_prepare_headless_before_disconnect(
            true, true, false, false
        ));
        assert!(!should_prepare_headless_before_disconnect(
            true, true, true, true
        ));
        assert!(!should_prepare_headless_before_disconnect(
            false, true, true, false
        ));
    }

    #[test]
    fn ignores_offline_rdp_displays_and_keeps_online_displays() {
        let probes = [
            DisplayProbe {
                online: false,
                headless_virtual: false,
            },
            DisplayProbe {
                online: true,
                headless_virtual: false,
            },
        ];

        assert_eq!(usable_display_indices(&probes, false), [1]);
        assert!(usable_display_indices(&probes[..1], false).is_empty());
    }

    #[test]
    fn keeps_a_single_online_small_display() {
        let probes = [DisplayProbe {
            online: true,
            headless_virtual: false,
        }];

        assert_eq!(usable_display_indices(&probes, false), [0]);
    }

    #[test]
    fn prefers_headless_virtual_display_only_after_capture_recovery() {
        let probes = [
            DisplayProbe {
                online: true,
                headless_virtual: false,
            },
            DisplayProbe {
                online: true,
                headless_virtual: true,
            },
        ];

        assert_eq!(usable_display_indices(&probes, false), [0, 1]);
        assert_eq!(usable_display_indices(&probes, true), [1, 0]);
    }

    #[test]
    fn restarts_capture_only_when_the_first_frame_times_out() {
        assert!(!should_restart_first_frame_capture(
            false,
            Duration::from_secs(7)
        ));
        assert!(!should_restart_first_frame_capture(
            false,
            Duration::from_secs(29)
        ));
        assert!(should_restart_first_frame_capture(
            false,
            Duration::from_secs(30)
        ));
        assert!(!should_restart_first_frame_capture(
            true,
            Duration::from_secs(30)
        ));
    }

    #[test]
    fn falls_back_after_repeated_would_block_before_first_frame() {
        assert!(!should_fallback_first_frame_capture(false, 2));
        assert!(should_fallback_first_frame_capture(false, 3));
        assert!(!should_fallback_first_frame_capture(true, 3));
    }

    #[test]
    fn recovers_stale_rdp_display_only_after_server_gdi_first_frame_failure() {
        let error = "Failed to copy screen to Windows buffer";

        assert!(should_recover_headless_after_capture_error(
            true, false, true, error
        ));
        assert!(!should_recover_headless_after_capture_error(
            false, false, true, error
        ));
        assert!(!should_recover_headless_after_capture_error(
            true, true, true, error
        ));
        assert!(!should_recover_headless_after_capture_error(
            true, false, false, error
        ));
        assert!(!should_recover_headless_after_capture_error(
            true,
            false,
            true,
            "Access denied"
        ));
    }
}
