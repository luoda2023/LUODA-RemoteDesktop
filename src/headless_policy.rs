pub(crate) const REQUIRED_NO_DISPLAY_SAMPLES: usize = 4;

pub(crate) fn should_insert_headless(active_display_samples: &[bool]) -> bool {
    active_display_samples.len() >= REQUIRED_NO_DISPLAY_SAMPLES
        && active_display_samples.iter().all(|active| !active)
}

#[cfg(test)]
mod tests {
    use super::should_insert_headless;

    #[test]
    fn inserts_only_after_repeated_no_display_samples() {
        assert!(!should_insert_headless(&[false, false, false]));
        assert!(!should_insert_headless(&[false, true, false, false]));
        assert!(should_insert_headless(&[false, false, false, false]));
    }
}
