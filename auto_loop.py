#!/usr/bin/env python3
"""
LUODA CI Auto-Build Loop
Continuously monitors for build failures, applies fixes, and triggers rebuilds.
"""
import subprocess, sys, json, os, time, re, hashlib, argparse, atexit
from pathlib import Path

GITHUB_TOKEN = os.environ.get("GH_TOKEN", "")
REPO = "luoda2023/LUODA-RemoteDesktop"
BRANCH = "branding-ci-v2"
WORKDIR = Path.cwd()
MAX_LOOP = 50

FIX_TASKS = {
    # key: (pattern_to_match_in_output, fix_script_lines)
}

def run(cmd, **kw):
    kw.setdefault("capture_output", True)
    kw.setdefault("text", True)
    kw.setdefault("cwd", WORKDIR)
    print(f"  $ {cmd}", flush=True)
    r = subprocess.run(cmd, shell=True, **kw)
    return r

def git_status_clean():
    r = run("git status --porcelain")
    return r.returncode == 0 and r.stdout.strip() == ""

def git_commit_and_push(msg):
    run("git add -A")
    rc = run(f'git commit -m "{msg}"').returncode
    if rc != 0:
        print("  Nothing to commit, skipping push")
        return True
    r = run(f"git push origin {BRANCH}")
    return r.returncode == 0

def check_latest_ci_status():
    """Check the latest workflow run status via GitHub API."""
    import urllib.request
    url = f"https://api.github.com/repos/{REPO}/actions/runs?branch={BRANCH}&per_page=1&status=completed"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {GITHUB_TOKEN}", "Accept": "application/vnd.github+json"})
    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read())
            if data.get("total_count", 0) == 0:
                return None
            run_data = data["workflow_runs"][0]
            return {
                "id": run_data["id"],
                "conclusion": run_data.get("conclusion"),
                "status": run_data.get("status"),
                "head_branch": run_data.get("head_branch"),
                "html_url": run_data.get("html_url"),
            }
    except Exception as e:
        print(f"  API error: {e}")
        return None

def trigger_workflow_dispatch():
    """Trigger a workflow_dispatch event via GitHub API."""
    import urllib.request
    url = f"https://api.github.com/repos/{REPO}/actions/workflows/build-exe.yml/dispatches"
    data = json.dumps({"ref": BRANCH}).encode()
    req = urllib.request.Request(url, data=data, method="POST",
        headers={"Authorization": f"Bearer {GITHUB_TOKEN}", "Accept": "application/vnd.github+json", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as resp:
            print(f"  Build-exe dispatch: {resp.status}")
    except Exception as e:
        print(f"  Dispatch error: {e}")
    url2 = f"https://api.github.com/repos/{REPO}/actions/workflows/build-msi.yml/dispatches"
    data2 = json.dumps({"ref": BRANCH}).encode()
    req2 = urllib.request.Request(url2, data=data2, method="POST",
        headers={"Authorization": f"Bearer {GITHUB_TOKEN}", "Accept": "application/vnd.github+json", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req2) as resp2:
            print(f"  Build-msi dispatch: {resp2.status}")
    except Exception as e:
        print(f"  Dispatch error: {e}")

def get_failed_job_logs(run_id):
    """Fetch logs for a failed workflow run."""
    import urllib.request
    url = f"https://api.github.com/repos/{REPO}/actions/runs/{run_id}/jobs"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {GITHUB_TOKEN}", "Accept": "application/vnd.github+json"})
    try:
        with urllib.request.urlopen(req) as resp:
            jobs = json.loads(resp.read())
            failed_jobs = [j for j in jobs.get("jobs", []) if j.get("conclusion") == "failure"]
            for job in failed_jobs:
                print(f"  Failed job: {job['name']}")
                # Try to get steps
                for step in job.get("steps", []):
                    if step.get("conclusion") == "failure":
                        print(f"    Failed step: {step['name']}")
            return failed_jobs
    except Exception as e:
        print(f"  Failed to fetch job logs: {e}")
        return []

def auto_fix_loop():
    print(f"=== LUODA CI Auto-Build Loop ===")
    print(f"Repo: {REPO}, Branch: {BRANCH}")
    print(f"Max iterations: {MAX_LOOP}")
    print()

    if GITHUB_TOKEN:
        print(f"GitHub token configured (len={len(GITHUB_TOKEN)})")
    else:
        print("WARNING: GH_TOKEN not set. Will use git push only.")

    for iteration in range(1, MAX_LOOP + 1):
        print(f"\n{'='*60}")
        print(f"  Iteration {iteration}/{MAX_LOOP}")
        print(f"{'='*60}")

        # Step 1: Commit and push current changes
        print("\n[1] Commit & push local changes...")
        if git_commit_and_push(f"auto: fix iteration {iteration} for CI auto-build loop"):
            print("  Push successful")
        else:
            print("  Push failed (network/token error)")
            if GITHUB_TOKEN and iteration == 1:
                trigger_workflow_dispatch()

        # Step 2: Wait for CI to finish
        print("\n[2] Waiting for CI to complete (up to 30 min)...")
        time.sleep(30)  # Initial wait

        ci_done = False
        ci_conclusion = None
        for wait_min in range(30):
            time.sleep(60)
            status = check_latest_ci_status()
            if status is None:
                print(f"  Waiting... ({wait_min+1}/30 min)", end="\r")
                continue
            if status.get("status") == "completed":
                ci_done = True
                ci_conclusion = status.get("conclusion")
                print(f"\n  CI completed: {ci_conclusion}")
                if ci_conclusion == "success":
                    print(f"\n{'='*60}")
                    print(f"  BUILD PASSED after {iteration} iterations!")
                    print(f"{'='*60}")
                    return True
                break
            print(f"  Waiting... ({wait_min+1}/30 min)", end="\r")

        if not ci_done:
            print("\n  CI timeout or unavailable. Retrying...")
            continue

        # Step 3: Fetch logs and apply fixes
        print("\n[3] Analyzing build failure...")
        last_run = check_latest_ci_status()
        if last_run:
            get_failed_job_logs(last_run["id"])
            # Try to get actual log text
            import urllib.request
            logs_url = f"https://api.github.com/repos/{REPO}/actions/runs/{last_run['id']}/logs"
            try:
                req = urllib.request.Request(logs_url,
                    headers={"Authorization": f"Bearer {GITHUB_TOKEN}", "Accept": "application/vnd.github+json"})
                with urllib.request.urlopen(req) as resp:
                    log_text = resp.read().decode("utf-8", errors="replace")
                    print(f"  Fetched {len(log_text)} chars of logs")
                    # Save to file for analysis
                    with open(WORKDIR / "ci_last_error.log", "w", encoding="utf-8") as f:
                        f.write(log_text[:50000])
            except Exception as e:
                print(f"  Could not fetch full logs: {e}")
                log_text = ""

        print("\n  Waiting for manual fix or dispatching next build...")
        # If we can't auto-fix, dispatch next build attempt
        if GITHUB_TOKEN:
            trigger_workflow_dispatch()

    print(f"\nExceeded max iterations ({MAX_LOOP}). Manual intervention needed.")
    return False

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--max", type=int, default=MAX_LOOP)
    args = parser.parse_args()
    MAX_LOOP = args.max
    success = auto_fix_loop()
    sys.exit(0 if success else 1)
