#!/usr/bin/env python3
"""Fetch logs for a specific job."""
import json, urllib.request, sys, os, gzip, io

with open(os.path.expanduser("~/.hermes/github_token")) as f:
    TOKEN = f.read().strip()

job_id = sys.argv[1]  # e.g. 76318817499
REPO = "luoda2023/LUODA-RemoteDesktop"

url = f"https://api.github.com/repos/{REPO}/actions/jobs/{job_id}/logs"
req = urllib.request.Request(url)
req.add_header("Authorization", f"Bearer {TOKEN}")
req.add_header("Accept", "application/vnd.github+json")
req.add_header("User-Agent", "Hermes-Agent")

try:
    with urllib.request.urlopen(req) as resp:
        raw = resp.read()
    
    # Try decompressing
    try:
        text = gzip.decompress(raw).decode('utf-8', errors='replace')
    except:
        text = raw.decode('utf-8', errors='replace')
    
    # Show last 200 lines
    lines = text.split('\n')
    print(f"=== LOG for job {job_id}: {len(lines)} lines ===")
    for line in lines[-200:]:
        print(line)
    
    with open(f"/tmp/ci_log_{job_id}.txt", "w") as f:
        f.write(text)
except Exception as e:
    print(f"ERROR: {e}")
