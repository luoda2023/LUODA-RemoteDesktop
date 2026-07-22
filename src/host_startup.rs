pub(crate) fn can_start_rendezvous(
    ipc_ready: Option<Result<(), String>>,
    owner_online: Option<i64>,
) -> bool {
    if matches!(ipc_ready, Some(Ok(()))) {
        return true;
    }

    // IPC endpoint occupied by a stale process (old version with bugs).
    // Always allow the new process to take over, because the old process
    // may be stuck and not actually online.
    if matches!(ipc_ready, Some(Err(_))) {
        return true;
    }

    // Fallback: new startup with no existing IPC owner
    owner_online.map(|online| online <= 0).unwrap_or(true)
}

pub(crate) fn should_start_portable_service(
    is_installed: bool,
    args_empty: bool,
    explicit_quick_support: bool,
    pre_elevate_service: bool,
) -> bool {
    !is_installed && args_empty && (explicit_quick_support || pre_elevate_service)
}

#[cfg(test)]
mod tests {
    use super::{can_start_rendezvous, should_start_portable_service};

    #[test]
    fn offline_ipc_owner_allows_rendezvous_recovery() {
        assert!(can_start_rendezvous(Some(Ok(())), None));
        assert!(can_start_rendezvous(
            Some(Err("occupied".to_owned())),
            Some(1)
        ));
        assert!(can_start_rendezvous(
            Some(Err("occupied".to_owned())),
            Some(0)
        ));
        assert!(can_start_rendezvous(None, None));
    }

    #[test]
    fn normal_portable_does_not_start_portable_capture_service() {
        assert!(!should_start_portable_service(false, true, false, false));
        assert!(should_start_portable_service(false, true, true, false));
        assert!(should_start_portable_service(false, true, false, true));
        assert!(!should_start_portable_service(true, true, true, true));
    }
}
