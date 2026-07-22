pub(crate) const UDP_REGISTRATION_FAILURE_LIMIT: i64 = 2;

pub(crate) fn should_start_with_tcp(
    test_tcp: bool,
    proxy: bool,
    websocket: bool,
    udp_disabled: bool,
) -> bool {
    test_tcp || proxy || websocket || udp_disabled
}

pub(crate) fn should_fallback_to_tcp(consecutive_failures: i64) -> bool {
    consecutive_failures >= UDP_REGISTRATION_FAILURE_LIMIT
}

#[cfg(test)]
mod tests {
    use super::{should_fallback_to_tcp, should_start_with_tcp};

    #[test]
    fn udp_is_default_unless_tcp_is_requested() {
        assert!(!should_start_with_tcp(false, false, false, false));
        assert!(should_start_with_tcp(false, false, true, false));
        assert!(should_start_with_tcp(false, false, false, true));
    }

    #[test]
    fn repeated_udp_registration_timeouts_trigger_tcp_fallback() {
        assert!(!should_fallback_to_tcp(1));
        assert!(should_fallback_to_tcp(2));
        assert!(should_fallback_to_tcp(3));
    }
}
