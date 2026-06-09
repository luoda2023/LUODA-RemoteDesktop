#!/usr/bin/env python3
"""Check artifacts for a workflow run."""
import json, urllib.request, os, sys

with open(os.path.expanduser("~/.hermes/github_token")) as f:
    TOKEN = f.read().strip()

REPO = "luoda2023/LUODA-RemoteDesktop"
run_id = sys.argv[1] if len(sys.argv) > 1 else "25963776173"

url = f"https://api.github.com/repos/{REPO}/actions/runs/{run_id}/artifacts"
req = urllib.request.Request(url)
req.add_header("Authorization", f"Bearer {TOKEN}")
req.add_header("Accept", "application/vnd.github+json")
req.add_header("User-Agent", "Hermes-Agent")

with urllib.request.urlopen(req) as resp:
    data = json.loads(resp.read().decode())

arts = data.get("artifacts", [])
print(f"=== Artifacts for run {run_id}: {len(arts)} ===")
for a in arts:
    size_mb = a.get('size_in_bytes', 0) / (1024*1024)
    print(f"  {a['name']:30s} | {size_mb:.1f} MB | {a.get('size_in_bytes', 0):,} bytes | expires: {a.get('expires_at', 'N/A')}")
