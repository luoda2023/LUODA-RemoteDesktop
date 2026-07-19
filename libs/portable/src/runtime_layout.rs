use std::path::{Path, PathBuf};

const RUNTIME_DIR: &str = "runtime";
const READY_PREFIX: &str = "package_id = ";

pub fn runtime_dir(root: &Path, package_id: &str) -> PathBuf {
    root.join(RUNTIME_DIR).join(package_id)
}

pub fn ready_marker(package_id: &str) -> String {
    format!("{READY_PREFIX}{package_id}\n")
}

pub fn ready_marker_matches(marker: &str, package_id: &str) -> bool {
    marker.trim() == format!("{READY_PREFIX}{package_id}")
}

pub fn is_stale_runtime_executable(candidate: &Path, current: &Path, root: &Path) -> bool {
    let normalize = |path: &Path| {
        let mut parts = Vec::new();
        for component in path.components() {
            use std::path::Component;
            match component {
                Component::CurDir => {}
                Component::ParentDir => {
                    parts.pop();
                }
                Component::Prefix(prefix) => {
                    parts.push(prefix.as_os_str().to_string_lossy().to_string())
                }
                Component::RootDir => {}
                Component::Normal(part) => parts.push(part.to_string_lossy().to_string()),
            }
        }
        parts.join("\\").to_lowercase()
    };
    let candidate = normalize(candidate);
    let current = normalize(current);
    let root = format!("{}\\", normalize(root));
    candidate != current && candidate.starts_with(&root)
}
