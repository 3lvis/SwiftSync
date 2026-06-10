#!/bin/sh
# One-time local setup for a fresh clone. Safe to re-run.
set -e

repo_root=$(git rev-parse --show-toplevel)
git -C "$repo_root" config core.hooksPath .githooks
echo "setup: core.hooksPath -> .githooks (swift-format pre-commit hook enabled)"
