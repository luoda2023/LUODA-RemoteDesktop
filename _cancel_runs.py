#!/usr/bin/env python3
"""Cancel stuck workflow runs."""
import json, urllib.request, os, sys

with open(os.path.expanduser("~/.hermes/github_token")) as f:
    TOKEN = f.read().strip()

REPO = "luoda2023/LUODA-RemoteDesktop"

# Get all in_progress runs
url = f"https://api.github.com/repos/{REPO}/actions/runs?status=in_progress&per_page=10"
req = urllib.request.Request(url)
req.add_header("Authorization", f"Bearer {TOKEN}")
req.add_header("Accept", "application/vnd.github+json")
req.add_header("User-Agent", "Hermes-Agent")

with urllib.request.urlopen(req) as resp:
    data = json.loads(resp.read().decode())

runs = data.get("workflow_runs", [])
print(f"Found {len(runs)} in_progress runs")

for r in runs:
    run_id = r['id']
    name = r['name']
    created = r['created_at']
    
    # Cancel the run
    cancel_url = f"https://api.github.com/repos/{REPO}/actions/runs/{run_id}/cancel"
    req2 = urllib.request.Request(cancel_url, method="POST")
    req2.add_header("Authorization", f"Bearer {TOKEN}")
    req2.add_header("Accept", "application/vnd.github+json")
    req2.add_header("User-Agent", "Hermes-Agent")
    
    try:
        with urllib.request.urlopen(req2) as resp2:
            print(f"Cancelled: {name} (ID: {run_id}, created: {created})")
    except urllib.error.HTTPError as e:
        print(f"Failed to cancel {name} (ID: {run_id}): {e.code} {e.reason}")
