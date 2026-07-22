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

#[cfg(test)]
mod tests {
    use super::can_start_rendezvous;

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
}
