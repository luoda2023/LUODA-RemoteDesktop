#!/usr/bin/env python3
"""Fetch GitHub Actions job details and logs for a specific run."""
import json, urllib.request, sys, os

with open(os.path.expanduser("~/.hermes/github_token")) as f:
    TOKEN = f.read().strip()

run_id = sys.argv[1] if len(sys.argv) > 1 else "25961995024"
REPO = "luoda2023/LUODA-RemoteDesktop"

# Fetch jobs for this run
url = f"https://api.github.com/repos/{REPO}/actions/runs/{run_id}/jobs?per_page=30"
req = urllib.request.Request(url)
req.add_header("Authorization", f"Bearer {TOKEN}")
req.add_header("Accept", "application/vnd.github+json")
req.add_header("User-Agent", "Hermes-Agent")

with urllib.request.urlopen(req) as resp:
    data = json.loads(resp.read().decode())

jobs = data.get("jobs", [])
print(f"=== RUN {run_id}: {len(jobs)} jobs ===")
for j in jobs:
    print(f"Job: {j['name']} | Status: {j['status']} | Conclusion: {j['conclusion']}")
    print(f"  ID: {j['id']} | Started: {j.get('started_at')} | Completed: {j.get('completed_at')}")
    # Get the steps
    for step in j.get("steps", []):
        print(f"  Step: {step['name']} | Status: {step['status']} | Conclusion: {step.get('conclusion')}")

# Save for later
with open(f"/tmp/ci_jobs_{run_id}.json", "w") as f:
    json.dump(data, f)
