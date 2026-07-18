pub(crate) const UDP_REGISTRATION_FAILURE_LIMIT: i64 = 2;

pub(crate) fn should_fallback_to_tcp(consecutive_failures: i64) -> bool {
    consecutive_failures >= UDP_REGISTRATION_FAILURE_LIMIT
}

#[cfg(test)]
mod tests {
    use super::should_fallback_to_tcp;

    #[test]
    fn repeated_udp_registration_timeouts_trigger_tcp_fallback() {
        assert!(!should_fallback_to_tcp(1));
        assert!(should_fallback_to_tcp(2));
        assert!(should_fallback_to_tcp(3));
    }
}
