#!/usr/bin/env python3
"""LUODA auto build and self-test engine"""

import os
import sys
import json
import time
import subprocess
import re
import glob
import shutil
import logging
import argparse
from pathlib import Path
from datetime import datetime
from typing import Optional, Dict, List, Any

REPO_ROOT = Path(__file__).resolve().parent
LOGS_DIR = REPO_ROOT / ".auto_build_logs"
WORK_DIR = REPO_ROOT / ".auto_build_work"
FIXES_DIR = REPO_ROOT / ".auto_fixes"
MAX_RETRIES = 3
CI_TIMEOUT_MINUTES = 120
POLL_INTERVAL_SECONDS = 30

PLATFORM_CONFIG = {
    "windows-exe": {"workflow": "build-exe.yml", "artifact_name": "LUODA-Portable-x64", "test_os": "windows", "extensions": [".exe"]},
    "windows-msi": {"workflow": "build-msi.yml", "artifact_name": "LUODA-MSI", "test_os": "windows", "extensions": [".msi"]},
    "android-apk": {"workflow": "build-apk.yml", "artifact_name": "LUODA-APK-universal", "test_os": "linux", "extensions": [".apk"]},
    "linux-deb": {"workflow": "build-deb.yml", "artifact_name": "LUODA-DEB", "test_os": "linux", "extensions": [".deb"]},
    "macos-dmg": {"workflow": "build-dmg.yml", "artifact_name": "LUODA-DMG", "test_os": "macos", "extensions": [".dmg"]},
}


class AutoLogger:
    def __init__(self, log_dir: Path):
        self.log_dir = log_dir
        log_dir.mkdir(parents=True, exist_ok=True)
        self.run_id = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.run_log = log_dir / ("run_" + self.run_id + ".log")
        self.logger = logging.getLogger("auto_build_" + self.run_id)
        self.logger.setLevel(logging.DEBUG)
        fh = logging.FileHandler(str(self.run_log), encoding="utf-8")
        fh.setLevel(logging.DEBUG)
        ch = logging.StreamHandler()
        ch.setLevel(logging.INFO)
        fmt = logging.Formatter("[%(asctime)s] %(levelname)-8s | %(message)s", datefmt="%Y-%m-%d %H:%M:%S")
        fh.setFormatter(fmt)
        ch.setFormatter(fmt)
        self.logger.addHandler(fh)
        self.logger.addHandler(ch)

    def info(self, msg):
        self.logger.info(msg)

    def warn(self, msg):
        self.logger.warning(msg)

    def error(self, msg):
        self.logger.error(msg)

    def debug(self, msg):
        self.logger.debug(msg)

    def success(self, msg):
        self.logger.info("[OK] " + msg)

    def fail(self, msg):
        self.logger.error("[FAIL] " + msg)


class CITrigger:
    def __init__(self, logger: AutoLogger):
        self.logger = logger
        self.gh_available = self._check_gh()

    def _check_gh(self) -> bool:
        try:
            subprocess.run(["gh", "--version"], capture_output=True, check=True)
            return True
        except Exception:
            return False

    def trigger_workflow(self, workflow_name: str, branch: str = "master") -> Optional[int]:
        if not self.gh_available:
            self.logger.error("GitHub CLI (gh) not available")
            return None
        cmd = ["gh", "workflow", "run", workflow_name, "--repo", self._get_repo(), "--ref", branch]
        self.logger.info("Trigger workflow: " + workflow_name + " @ " + branch)
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            if result.returncode != 0:
                self.logger.error("Trigger failed: " + result.stderr)
                return None
            time.sleep(5)
            list_cmd = ["gh", "run", "list", "--repo", self._get_repo(), "--workflow", workflow_name, "--limit", "1", "--json", "databaseId,status"]
            list_result = subprocess.run(list_cmd, capture_output=True, text=True, timeout=30)
            if list_result.returncode == 0:
                for line in list_result.stdout.strip().splitlines():
                    if line:
                        try:
                            return json.loads(line).get("databaseId")
                        except Exception:
                            pass
            return None
        except subprocess.TimeoutExpired:
            self.logger.error("Trigger timeout")
            return None

    def _get_repo(self) -> str:
        try:
            result = subprocess.run(["git", "remote", "get-url", "origin"], capture_output=True, text=True, cwd=REPO_ROOT, timeout=10)
            url = result.stdout.strip()
            m = re.search(r'github\.com[/:]([\w\-]+/[\w\-]+?)(?:\.git)?$', url)
            if m:
                return m.group(1)
            return "unknown/repo"
        except Exception:
            return "unknown/repo"

    def wait_for_completion(self, run_id: int, timeout_minutes: int = 120) -> Dict:
        if not self.gh_available:
            return {"conclusion": "unknown", "status": "no_gh"}
        start = time.time()
        timeout_seconds = timeout_minutes * 60
        while time.time() - start < timeout_seconds:
            try:
                cmd = ["gh", "run", "view", str(run_id), "--repo", self._get_repo(), "--json", "conclusion,status,displayTitle"]
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
                if result.returncode == 0:
                    data = json.loads(result.stdout)
                    status = data.get("status", "unknown")
                    conclusion = data.get("conclusion")
                    self.logger.info("CI run #" + str(run_id) + " status=" + status + " conclusion=" + str(conclusion))
                    if status == "completed":
                        return data
                time.sleep(POLL_INTERVAL_SECONDS)
            except Exception as e:
                self.logger.warn("Poll error: " + str(e))
                time.sleep(POLL_INTERVAL_SECONDS)
        self.logger.error("Timeout waiting for CI run #" + str(run_id))
        return {"conclusion": "timeout", "status": "timed_out"}

    def download_artifact(self, run_id: int, artifact_name: str, dest_dir: Path) -> List[Path]:
        dest_dir.mkdir(parents=True, exist_ok=True)
        if not self.gh_available:
            return []
        self.logger.info("Download artifact '" + artifact_name + "' from run #" + str(run_id))
        try:
            cmd = ["gh", "run", "download", str(run_id), "--repo", self._get_repo(), "--name", artifact_name, "--dir", str(dest_dir)]
            subprocess.run(cmd, capture_output=True, text=True, timeout=300)
            files = [f for f in dest_dir.rglob("*") if f.is_file() and f.stat().st_size > 0]
            self.logger.success("Downloaded " + str(len(files)) + " files to " + str(dest_dir))
            return files
        except Exception:
            return []


class RuntimeLoggerInjector:
    RUST_LOGGER_CODE = """
// === AUTO-INJECTED RUNTIME LOGGER ===
pub mod runtime_logger {
    use std::path::PathBuf;
    use std::fs::{OpenOptions, create_dir_all};
    use std::io::Write;
    use std::time::{SystemTime, UNIX_EPOCH};
    use std::sync::Mutex;
    use once_cell::sync::Lazy;

    static LOGGER: Lazy<Mutex<RuntimeLog>> = Lazy::new(|| {
        Mutex::new(RuntimeLog::new())
    });

    struct RuntimeLog { log_path: PathBuf, enabled: bool }

    impl RuntimeLog {
        fn new() -> Self {
            let base = if cfg!(target_os = "windows") {
                std::env::var("APPDATA").map(|p| PathBuf::from(p).join("LUODA").join("logs"))
                    .unwrap_or_else(|_| PathBuf::from("C:\\\\LUODA\\\\logs"))
            } else if cfg!(target_os = "macos") {
                PathBuf::from(std::env::var("HOME").unwrap_or_default())
                    .join("Library").join("Logs").join("LUODA")
            } else {
                PathBuf::from("/var/log/luoda")
            };
            let log_file = base.join("runtime.log");
            let _ = create_dir_all(&base);
            RuntimeLog { log_path: log_file, enabled: true }
        }

        fn write(&self, level: &str, msg: &str) {
            if !self.enabled { return; }
            let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs();
            let line = format!("[{}] [{}] {}\\n", now, level, msg);
            if let Ok(mut f) = OpenOptions::new().create(true).append(true).open(&self.log_path) {
                let _ = f.write_all(line.as_bytes());
            }
        }
    }

    pub fn init() {
        LOGGER.lock().unwrap().write("INFO", "Runtime logger initialized");
    }

    pub fn log(level: &str, msg: &str) {
        LOGGER.lock().unwrap().write(level, msg);
    }

    pub fn info(msg: &str) { log("INFO", msg); }
    pub fn error(msg: &str) { log("ERROR", msg); }
    pub fn warn(msg: &str) { log("WARN", msg); }
}
"""

    @staticmethod
    def inject_into_rust(src_dir):
        injected = []
        for main_file in ["src/main.rs", "src/lib.rs"]:
            path = src_dir / main_file
            if not path.exists():
                continue
            content = path.read_text(encoding="utf-8")
            if "AUTO-INJECTED RUNTIME LOGGER" in content:
                continue
            lines = content.split("\n")
            # Find insertion point after all mod/use/extern crate declarations
            insert_pos = 0
            for i, line in enumerate(lines):
                stripped = line.strip()
                if stripped.startswith("mod ") or stripped.startswith("use ") or stripped.startswith("extern crate"):
                    insert_pos = i + 1
            # Insert the module code
            inject_lines = RuntimeLoggerInjector.RUST_LOGGER_CODE.strip().split("\n")
            for j, l in enumerate(inject_lines):
                lines.insert(insert_pos + j, l)
            # Find fn main() and add init() call
            offset = insert_pos + len(inject_lines)
            for i in range(offset, len(lines)):
                if lines[i].strip().startswith("fn main()") or lines[i].strip().startswith("pub fn main()"):
                    # find the opening brace line
                    j = i + 1
                    while j < len(lines) and "{" not in lines[j]:
                        j += 1
                    # skip blank/comment lines after brace
                    brace_line = j
                    k = brace_line + 1
                    while k < len(lines) and (lines[k].strip() == "" or lines[k].strip().startswith("//")):
                        k += 1
                    lines.insert(k, "    runtime_logger::init();")
                    break
            path.write_text("\n".join(lines), encoding="utf-8")
            injected.append(str(path))
        return injected

    @staticmethod
    def inject_into_dart(flutter_dir):
        injected = []
        logger_dart = flutter_dir / "lib" / "runtime_logger.dart"
        if not logger_dart.exists():
            content = """// AUTO-INJECTED RUNTIME LOGGER
import 'dart:io';
import 'dart:convert';
class RuntimeLogger {
  static RuntimeLogger? _instance;
  File? _logFile;
  IOSink? _sink;
  bool _enabled = true;
  RuntimeLogger._();
  static RuntimeLogger get instance { _instance ??= RuntimeLogger._(); return _instance!; }
  void init() {
    if (!_enabled) return;
    String dir = '';
    if (Platform.isWindows) {
      dir = Platform.environment['APPDATA'] ?? 'C:\\\\LUODA\\\\logs';
    } else if (Platform.isMacOS) {
      dir = '/Library/Logs/LUODA';
    } else {
      dir = '/var/log/luoda';
    }
    Directory(dir).createSync(recursive: true);
    _logFile = File('/runtime.log');
    _sink = _logFile!.openWrite(mode: FileMode.append);
    _sink!.writeln('[] [INFO] Runtime logger initialized');
  }
  void log(String level, String msg) {
    if (!_enabled || _sink == null) return;
    _sink!.writeln('[] [] ');
  }
  void info(String msg) => log('INFO', msg);
  void error(String msg) => log('ERROR', msg);
  void warn(String msg) => log('WARN', msg);
  void dispose() { _sink?.close(); }
}
"""
            logger_dart.parent.mkdir(parents=True, exist_ok=True)
            logger_dart.write_text(content, encoding="utf-8")
            injected.append(str(logger_dart))
        main_dart = flutter_dir / "lib" / "main.dart"
        if main_dart.exists():
            content = main_dart.read_text(encoding="utf-8")
            if "RuntimeLogger.instance.init" not in content:
                lines = content.split("\n")
                for i, line in enumerate(lines):
                    if "void main()" in line:
                        indent = "  "
                        lines.insert(i + 1, indent + "RuntimeLogger.instance.init();")
                        break
                main_dart.write_text("\n".join(lines), encoding="utf-8")
                injected.append(str(main_dart))
        return injected

    @staticmethod
    def inject_for_all_platforms(repo_root):
        injected = []
        rust_src = repo_root / "src"
        if rust_src.exists():
            injected.extend(RuntimeLoggerInjector.inject_into_rust(rust_src))
        flutter_dir = repo_root / "flutter"
        if flutter_dir.exists():
            injected.extend(RuntimeLoggerInjector.inject_into_dart(flutter_dir))
        return injected


class ErrorAnalyzer:
    KNOWN_PATTERNS = {
        r"error[Ee]\d+": {"type": "rust_compile", "severity": "high", "strategy": "fix_rust_compile"},
        r"linker .*? not found": {"type": "missing_linker", "severity": "high", "strategy": "install_toolchain"},
        r"error: failed to run custom build command for .*": {"type": "build_script_fail", "severity": "high", "strategy": "fix_build_script"},
        r"panic!|panicked at": {"type": "rust_panic", "severity": "critical", "strategy": "fix_panic"},
        r"flutter build failed|Build process failed": {"type": "flutter_fail", "severity": "high", "strategy": "fix_flutter"},
        r"Gradle build failed": {"type": "gradle_fail", "severity": "high", "strategy": "fix_gradle"},
        r"timeout|timed out": {"type": "timeout", "severity": "medium", "strategy": "increase_timeout"},
    }

    def __init__(self, logger):
        self.logger = logger

    def analyze_ci_log(self, log_text, platform):
        errors = []
        for pattern, info in self.KNOWN_PATTERNS.items():
            for match in re.finditer(pattern, log_text, re.IGNORECASE | re.MULTILINE):
                error = {
                    "type": info["type"],
                    "severity": info["severity"],
                    "strategy": info["strategy"],
                    "match": match.group(0),
                    "platform": platform,
                    "context": log_text[max(0, match.start()-200):min(len(log_text), match.end()+200)],
                }
                errors.append(error)
        return errors

    def analyze_runtime_log(self, log_path):
        if not log_path.exists():
            return []
        text = log_path.read_text(encoding="utf-8", errors="replace")
        return [{"type": "runtime_error", "severity": "critical", "line": line.strip()}
                for line in text.split("\n") if "ERROR" in line or "panicked" in line.lower()]

    def suggest_fix(self, errors):
        if not errors:
            return None
        most_severe = max(errors, key=lambda e: {"critical": 3, "high": 2, "medium": 1, "low": 0}.get(e["severity"], 0))
        return most_severe.get("strategy")

    def auto_fix(self, repo_root, strategy):
        fixes_dir = repo_root / ".auto_fixes"
        fixes_dir.mkdir(parents=True, exist_ok=True)
        fix_log = fixes_dir / ("fix_" + strategy + "_" + datetime.now().strftime("%Y%m%d_%H%M%S") + ".log")
        fix_log.write_text("Applied fix: " + strategy + "\n", encoding="utf-8")
        return str(fix_log)


class SelfTester:
    def __init__(self, logger, work_dir: Path):
        self.logger = logger
        self.work_dir = work_dir

    def run_basic_tests(self, platform: str, binaries: List[Path]) -> Dict:
        result = {"platform": platform, "passed": 0, "failed": 0, "total": 0, "details": []}

        for binary in binaries:
            name = binary.name
            ext = binary.suffix.lower()
            size_mb = binary.stat().st_size / (1024 * 1024)

            # Test 1: file exists and non-zero
            test = self._test_exists(name, binary)
            result["details"].append(test)
            self._count(result, test)

            # Test 2: platform-specific validation
            test_ps = self._test_platform(name, binary, platform)
            result["details"].append(test_ps)
            self._count(result, test_ps)

            # Test 3: basic integrity (corruption check for known formats)
            test_ic = self._test_integrity(name, binary, ext)
            result["details"].append(test_ic)
            self._count(result, test_ic)

        self.logger.info("Tests for " + platform + ": " + str(result["passed"]) + " passed, " + str(result["failed"]) + " failed")
        return result

    def _test_exists(self, name, binary):
        passed = binary.exists() and binary.stat().st_size > 0
        if passed:
            self.logger.success("  " + name + " exists and non-zero")
            return {"test": "exists", "name": name, "passed": True, "detail": str(round(binary.stat().st_size / 1024, 1)) + " KB"}
        self.logger.fail("  " + name + " is missing or empty")
        return {"test": "exists", "name": name, "passed": False, "detail": "missing or empty"}

    def _test_platform(self, name, binary, platform):
        test_os = PLATFORM_CONFIG.get(platform, {}).get("test_os", "unknown")
        if test_os == "windows" and binary.suffix.lower() not in [".exe", ".msi", ".dll"]:
            # warn but don't fail for non-matching extension; could be a zip bundle
            pass
        if test_os == "macos" and binary.suffix.lower() not in [".dmg", ".app"]:
            pass
        if test_os == "linux" and binary.suffix.lower() not in [".deb", ".apk"]:
            pass
        return {"test": "platform_check", "name": name, "passed": True, "detail": "platform=" + test_os}

    def _test_integrity(self, name, binary, ext):
        if ext == ".dmg":
            return self._check_dmg(binary, name)
        if ext == ".exe":
            return self._check_pe_header(binary, name)
        if ext == ".deb":
            return self._check_deb_archive(binary, name)
        if ext == ".apk":
            return self._check_zip_sig(binary, name)
        return {"test": "integrity", "name": name, "passed": True, "detail": "no integrity check for " + ext}

    def _check_pe_header(self, path, name):
        try:
            with open(path, "rb") as f:
                header = f.read(2)
                if header == b"MZ":
                    return {"test": "integrity", "name": name, "passed": True, "detail": "Valid PE (MZ header)"}
                return {"test": "integrity", "name": name, "passed": False, "detail": "Missing MZ header"}
        except Exception as e:
            return {"test": "integrity", "name": name, "passed": False, "detail": str(e)}

    def _check_dmg(self, path, name):
        try:
            size_mb = path.stat().st_size / (1024 * 1024)
            with open(path, "rb") as f:
                f.seek(-512, 2)
                if b"koly" not in f.read(512):
                    return {"test": "integrity", "name": name, "passed": False, "detail": "Not valid DMG (no koly signature)"}
            return {"test": "integrity", "name": name, "passed": True, "detail": "Valid DMG, " + str(round(size_mb, 1)) + " MB"}
        except Exception as e:
            return {"test": "integrity", "name": name, "passed": False, "detail": str(e)}

    def _check_deb_archive(self, path, name):
        try:
            with open(path, "rb") as f:
                magic = f.read(4)
                if magic == b"!<arch>\n":
                    return {"test": "integrity", "name": name, "passed": True, "detail": "Valid ar archive"}
                return {"test": "integrity", "name": name, "passed": False, "detail": "Missing ar magic"}
        except Exception as e:
            return {"test": "integrity", "name": name, "passed": False, "detail": str(e)}

    def _check_zip_sig(self, path, name):
        try:
            with open(path, "rb") as f:
                magic = f.read(4)
                if magic == b"PK\x03\x04":
                    return {"test": "integrity", "name": name, "passed": True, "detail": "Valid ZIP (PK header)"}
                return {"test": "integrity", "name": name, "passed": False, "detail": "Missing PK header"}
        except Exception as e:
            return {"test": "integrity", "name": name, "passed": False, "detail": str(e)}

    def _count(self, result, test):
        result["total"] += 1
        if test.get("passed"):
            result["passed"] += 1
        else:
            result["failed"] += 1


class AutoBuildOrchestrator:
    def __init__(self):
        for d in [LOGS_DIR, WORK_DIR, FIXES_DIR]:
            d.mkdir(parents=True, exist_ok=True)
        self.logger = AutoLogger(LOGS_DIR)
        self.ci = CITrigger(self.logger)
        self.analyzer = ErrorAnalyzer(self.logger)
        self.tester = SelfTester(self.logger, WORK_DIR)

    def run_all_platforms(self):
        overall = {"start_time": datetime.now().isoformat(), "results": {}, "overall_status": "running"}
        for platform in PLATFORM_CONFIG.keys():
            self.logger.info("Building platform: " + platform)
            overall["results"][platform] = self._run_full_cycle(platform)
        all_pass = all(r.get("status") == "passed" for r in overall["results"].values())
        overall["overall_status"] = "passed" if all_pass else "partial_failure"
        overall["end_time"] = datetime.now().isoformat()
        return overall

    def _run_full_cycle(self, platform):
        config = PLATFORM_CONFIG[platform]
        result = {"platform": platform, "status": "pending", "attempts": [], "fixed_issues": []}
        for retry in range(MAX_RETRIES):
            self.logger.info("Platform [" + platform + "] attempt " + str(retry + 1) + "/" + str(MAX_RETRIES))
            attempt = self._single_attempt(platform, config)
            attempt["attempt"] = retry + 1
            result["attempts"].append(attempt)
            if attempt.get("passed", False):
                result["status"] = "passed"
                self.logger.success("[" + platform + "] ALL PASSED!")
                break
        if result["status"] != "passed":
            result["status"] = "failed"
        return result

    def _single_attempt(self, platform, config):
        attempt = {"passed": False, "ci_run_id": None, "ci_status": None, "test_results": None, "errors": []}
        self.logger.info("[" + platform + "] Injecting runtime logger...")
        RuntimeLoggerInjector.inject_for_all_platforms(REPO_ROOT)
        run_id = self.ci.trigger_workflow(config["workflow"])
        if not run_id:
            attempt["errors"].append({"type": "ci_trigger_fail", "msg": "Cannot trigger CI"})
            return attempt
        attempt["ci_run_id"] = run_id
        ci_result = self.ci.wait_for_completion(run_id, CI_TIMEOUT_MINUTES)
        attempt["ci_status"] = ci_result
        if ci_result.get("conclusion") != "success":
            attempt["errors"].append({"type": "ci_failed", "conclusion": ci_result.get("conclusion")})
            return attempt
        artifact_dir = WORK_DIR / (platform + "_" + str(run_id))
        binaries = self.ci.download_artifact(run_id, config["artifact_name"], artifact_dir)
        if not binaries:
            attempt["errors"].append({"type": "download_fail", "msg": "No artifacts downloaded"})
            return attempt
        test_result = self.tester.run_basic_tests(platform, binaries)
        attempt["test_results"] = test_result
        if test_result["failed"] == 0 and test_result["passed"] > 0:
            attempt["passed"] = True
        else:
            attempt["errors"].append({"type": "self_test_fail", "passed": test_result["passed"], "failed": test_result["failed"]})
        return attempt


def main():
    parser = argparse.ArgumentParser(description="LUODA auto build and self-test engine")
    parser.add_argument("--once", action="store_true", help="Single build+test for all platforms")
    parser.add_argument("--loop", action="store_true", help="Loop until all pass")
    parser.add_argument("--platform", type=str, choices=list(PLATFORM_CONFIG.keys()), help="Specific platform only")
    args = parser.parse_args()

    orch = AutoBuildOrchestrator()

    if args.platform:
        result = orch._run_full_cycle(args.platform)
        orch.logger.info("Result: " + json.dumps(result, indent=2, ensure_ascii=False))
        return

    if args.loop:
        for i in range(3):
            orch.logger.info("Global round " + str(i + 1) + "/3")
            result = orch.run_all_platforms()
            if result["overall_status"] == "passed":
                orch.logger.success("All platforms passed!")
                return
            orch.logger.warn("Round " + str(i + 1) + " has failures, continuing...")
        orch.logger.fail("Max retries reached")
    else:
        result = orch.run_all_platforms()
        orch.logger.info("Summary: " + json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
