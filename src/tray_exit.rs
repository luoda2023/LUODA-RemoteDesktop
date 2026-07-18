pub(crate) const CLEANUP_ARG: &str = "--tray-exit-cleanup";
pub(crate) const CLEANUP_PENDING_OPTION: &str = "tray-exit-cleanup-pending";

pub(crate) fn cleanup_target_pids<S: AsRef<str>>(
    processes: &[(u32, String)],
    executable_names: &[S],
    keep_pid: u32,
) -> Vec<u32> {
    let names: Vec<String> = executable_names
        .iter()
        .map(|name| {
            let name = name.as_ref().to_lowercase();
            if name.ends_with(".exe") {
                name
            } else {
                format!("{name}.exe")
            }
        })
        .collect();
    processes
        .iter()
        .filter(|(pid, name)| *pid != keep_pid && names.contains(&name.to_lowercase()))
        .map(|(pid, _)| *pid)
        .collect()
}

pub(crate) fn should_clear_stop_service(processes_terminated: bool, service_stopped: bool) -> bool {
    processes_terminated && service_stopped
}

pub(crate) fn should_recover_stop_service(
    cleanup_pending: bool,
    has_other_processes: bool,
    service_running: bool,
) -> bool {
    cleanup_pending && !has_other_processes && !service_running
}

#[cfg(test)]
mod tests {
    use super::{
        cleanup_target_pids, should_clear_stop_service, should_recover_stop_service, CLEANUP_ARG,
        CLEANUP_PENDING_OPTION,
    };

    #[test]
    fn cleanup_uses_a_dedicated_mode_and_preserves_its_own_process() {
        assert_eq!(CLEANUP_ARG, "--tray-exit-cleanup");
        assert_eq!(CLEANUP_PENDING_OPTION, "tray-exit-cleanup-pending");
    }

    #[test]
    fn cleanup_targets_matching_processes_by_pid_and_preserves_helper() {
        let processes = vec![
            (41, "luoda.exe".to_owned()),
            (42, "LUODA.exe".to_owned()),
            (43, "other.exe".to_owned()),
            (44, "custom-client.exe".to_owned()),
        ];
        assert_eq!(
            cleanup_target_pids(&processes, &["LUODA", "custom-client.exe"], 42),
            vec![41, 44]
        );
    }

    #[test]
    fn stop_service_flag_is_only_cleared_after_everything_stops() {
        assert!(should_clear_stop_service(true, true));
        assert!(!should_clear_stop_service(false, true));
        assert!(!should_clear_stop_service(true, false));
        assert!(!should_clear_stop_service(false, false));
    }

    #[test]
    fn pending_exit_is_recovered_only_after_old_host_is_gone() {
        assert!(should_recover_stop_service(true, false, false));
        assert!(!should_recover_stop_service(false, false, false));
        assert!(!should_recover_stop_service(true, true, false));
        assert!(!should_recover_stop_service(true, false, true));
    }
}
