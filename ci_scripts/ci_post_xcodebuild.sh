#!/bin/zsh
set -euo pipefail

TESTFLIGHT_DIR_PATH=../TestFlight
mkdir -p $TESTFLIGHT_DIR_PATH
git fetch --deepen 5
git log -5 --pretty=format:"%s" >! $TESTFLIGHT_DIR_PATH/WhatToTest.en-US.txtfi   