#!/bin/zsh
set -euo pipefail

TESTFLIGHT_DIR_PATH=../TestFlight
mkdir -p "$TESTFLIGHT_DIR_PATH"

# Xcode Cloud may check out the source without a .git directory.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git fetch --deepen 5 || true
    git log -5 --pretty=format:"%s" >! "$TESTFLIGHT_DIR_PATH/WhatToTest.en-US.txt"
else
    echo "Not a git repository; skipping WhatToTest generation."
fi
