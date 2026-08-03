pub(crate) const UDP_REGISTRATION_FAILURE_LIMIT: i64 = 4;

pub(crate) fn should_start_with_tcp(
    test_tcp: bool,
    proxy: bool,
    websocket: bool,
    udp_disabled: bool,
    _windows_server: bool,
) -> bool {
    // NOTE: Do NOT force TCP for Windows Server.  The hbbs TCP listener does
    // not handle RegisterPeer – peer registration only works over UDP.
    // Forcing TCP on VPS causes "Connecting to LUODA network" forever.
    test_tcp || proxy || websocket || udp_disabled
}

pub(crate) fn should_fallback_to_tcp(consecutive_failures: i64) -> bool {
    consecutive_failures >= UDP_REGISTRATION_FAILURE_LIMIT
}

#[cfg(test)]
mod tests {
    use super::{should_fallback_to_tcp, should_start_with_tcp};

    #[test]
    fn windows_server_uses_udp_like_other_platforms() {
        // hbbs TCP does not support RegisterPeer, so Windows Server must use UDP
        assert!(!should_start_with_tcp(false, false, false, false, true));
        assert!(!should_start_with_tcp(false, false, false, false, false));
    }

    #[test]
    fn udp_is_default_unless_tcp_is_requested() {
        assert!(!should_start_with_tcp(false, false, false, false, false));
        assert!(should_start_with_tcp(false, false, true, false, false));
        assert!(should_start_with_tcp(false, false, false, true, false));
    }

    #[test]
    fn repeated_udp_registration_timeouts_trigger_tcp_fallback() {
        assert!(!should_fallback_to_tcp(1));
        assert!(should_fallback_to_tcp(2));
        assert!(should_fallback_to_tcp(3));
    }
}
