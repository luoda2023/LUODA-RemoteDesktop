use std::time::Duration;

pub(crate) const REQUIRED_NO_DISPLAY_SAMPLES: usize = 4;
pub(crate) const FIRST_FRAME_TIMEOUT: Duration = Duration::from_secs(8);
pub(crate) const FIRST_FRAME_WOULD_BLOCK_LIMIT: usize = 3;

pub(crate) struct DisplayProbe {
    pub online: bool,
    pub width: usize,
    pub height: usize,
    pub has_large_mode: bool,
}

pub(crate) fn should_insert_headless(active_display_samples: &[bool]) -> bool {
    active_display_samples.len() >= REQUIRED_NO_DISPLAY_SAMPLES
        && active_display_samples.iter().all(|active| !active)
}

pub(crate) fn usable_display_indices(probes: &[DisplayProbe], dummy_side_max: usize) -> Vec<usize> {
    let online = probes
        .iter()
        .enumerate()
        .filter_map(|(index, probe)| probe.online.then_some(index))
        .collect::<Vec<_>>();

    if online.len() != 1 {
        return online;
    }

    let index = online[0];
    let probe = &probes[index];
    if probe.width > dummy_side_max || probe.height > dummy_side_max || probe.has_large_mode {
        online
    } else {
        Vec::new()
    }
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

#[cfg(test)]
mod tests {
    use super::{
        should_fallback_first_frame_capture, should_insert_headless,
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
    fn ignores_offline_rdp_displays_and_keeps_online_displays() {
        let probes = [
            DisplayProbe {
                online: false,
                width: 1920,
                height: 1080,
                has_large_mode: true,
            },
            DisplayProbe {
                online: true,
                width: 1920,
                height: 1080,
                has_large_mode: true,
            },
        ];

        assert_eq!(usable_display_indices(&probes, 1024), [1]);
        assert!(usable_display_indices(&probes[..1], 1024).is_empty());
    }

    #[test]
    fn restarts_capture_only_when_the_first_frame_times_out() {
        assert!(!should_restart_first_frame_capture(
            false,
            Duration::from_secs(7)
        ));
        assert!(should_restart_first_frame_capture(
            false,
            Duration::from_secs(8)
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
}
