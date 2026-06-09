#!/usr/bin/env python3
"""Get full run list (all workflows, all statuses)."""
import json, urllib.request, os

with open(os.path.expanduser("~/.hermes/github_token")) as f:
    TOKEN = f.read().strip()

REPO = "luoda2023/LUODA-RemoteDesktop"

# Get all recent runs for all workflows
for wf_name in ["build-exe.yml", "build-apk.yml", "build-deb.yml", "build-msi.yml", "build-dmg.yml", "build-sciter.yml"]:
    url = f"https://api.github.com/repos/{REPO}/actions/workflows/{wf_name}/runs?per_page=3"
    req = urllib.request.Request(url)
    req.add_header("Authorization", f"Bearer {TOKEN}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("User-Agent", "Hermes-Agent")
    
    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode())
        runs = data.get("workflow_runs", [])
        for r in runs[:3]:
            print(f"{wf_name:20s} | ID:{r['id']} | {r['status']:12s} | {str(r['conclusion']):12s} | {r['created_at']} | sha:{r['head_sha'][:8]}")
    except Exception as e:
        print(f"{wf_name:20s} | ERROR: {e}")
