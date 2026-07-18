pub(crate) const CLEANUP_ARG: &str = "--tray-exit-cleanup";

pub(crate) fn taskkill_other_instances_args(exe_name: &str, keep_pid: u32) -> Vec<String> {
    vec![
        "/f".to_owned(),
        "/im".to_owned(),
        format!("{exe_name}.exe"),
        "/fi".to_owned(),
        format!("PID ne {keep_pid}"),
    ]
}

#[cfg(test)]
mod tests {
    use super::{taskkill_other_instances_args, CLEANUP_ARG};

    #[test]
    fn cleanup_uses_a_dedicated_mode_and_preserves_its_own_process() {
        assert_eq!(CLEANUP_ARG, "--tray-exit-cleanup");
        assert_eq!(
            taskkill_other_instances_args("LUODA", 42),
            ["/f", "/im", "LUODA.exe", "/fi", "PID ne 42"]
        );
    }
}
