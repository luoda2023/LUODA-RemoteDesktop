#[path = "../src/runtime_layout.rs"]
mod runtime_layout;

use std::path::Path;

#[test]
fn different_packages_use_different_runtime_directories() {
    let root = Path::new(r"C:\Users\tester\AppData\Local\LUODA");

    let normal = runtime_layout::runtime_dir(root, "normal-package-id");
    let client = runtime_layout::runtime_dir(root, "client-package-id");

    assert_ne!(normal, client);
    assert!(normal.starts_with(root));
    assert!(client.starts_with(root));
}

#[test]
fn runtime_is_ready_only_for_its_complete_package() {
    let marker = runtime_layout::ready_marker("normal-package-id");

    assert!(runtime_layout::ready_marker_matches(
        &marker,
        "normal-package-id"
    ));
    assert!(!runtime_layout::ready_marker_matches(
        &marker,
        "client-package-id"
    ));
    assert!(!runtime_layout::ready_marker_matches(
        "",
        "normal-package-id"
    ));
}

#[test]
fn only_other_luoda_runtime_executables_are_stale() {
    let root = Path::new(r"C:\Users\tester\AppData\Local\LUODA");
    let current = root.join(r"runtime\normal-package-id\.\luoda.exe");
    let running_current = root.join(r"runtime\normal-package-id\luoda.exe");
    let old = root.join("luoda.exe");
    let other_package = root.join(r"runtime\client-package-id\luoda.exe");
    let installed = Path::new(r"C:\Program Files\LUODA\luoda.exe");

    assert!(runtime_layout::is_stale_runtime_executable(
        &old, &current, root
    ));
    assert!(runtime_layout::is_stale_runtime_executable(
        &other_package,
        &current,
        root
    ));
    assert!(!runtime_layout::is_stale_runtime_executable(
        &running_current,
        &current,
        root
    ));
    assert!(!runtime_layout::is_stale_runtime_executable(
        installed, &current, root
    ));
}
