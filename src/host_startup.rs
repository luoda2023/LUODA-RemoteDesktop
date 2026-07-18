pub(crate) fn can_start_rendezvous(ipc_ready: Option<Result<(), String>>) -> bool {
    matches!(ipc_ready, Some(Ok(())))
}

#[cfg(test)]
mod tests {
    use super::can_start_rendezvous;

    #[test]
    fn rendezvous_requires_primary_ipc_ownership() {
        assert!(can_start_rendezvous(Some(Ok(()))));
        assert!(!can_start_rendezvous(Some(Err("occupied".to_owned()))));
        assert!(!can_start_rendezvous(None));
    }
}
