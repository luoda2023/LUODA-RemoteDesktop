#!/bin/bash
# Script to push changes and trigger CI builds
# Run this from the repo root: cd LUODA-RemoteDesktop && bash push-changes.sh
# Requires: git with access to github.com

set -e

REPO="luoda2023/LUODA-RemoteDesktop"

echo "=== Current branch: branding-ci-v2 ==="
echo "The following commits will be pushed:"
git log origin/branding-ci-v2..HEAD --oneline

echo ""
echo "=== Pushing branding-ci-v2 (will auto-trigger CI) ==="
echo "CI will run: build-exe.yml + build-msi.yml"
echo ""

read -p "Push now? (Y/n): " push_choice
if [ "$push_choice" = "n" ] || [ "$push_choice" = "N" ]; then
  echo "Push cancelled."
  exit 0
fi

git push origin branding-ci-v2 2>&1

echo ""
echo "=== Also merge to master for stable release? ==="
read -p "Merge branding-ci-v2 into master? (y/N): " master_choice
if [ "$master_choice" = "y" ] || [ "$master_choice" = "Y" ]; then
  git checkout master
  git merge branding-ci-v2
  git push origin master
  git checkout branding-ci-v2
fi

echo ""
echo "=== Done ==="
echo "Check CI status at: https://github.com/$REPO/actions"
