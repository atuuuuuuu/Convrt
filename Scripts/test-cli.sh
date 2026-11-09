#!/bin/bash
# Run the command-line tool's tests (it shares the app's engine files).
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Users/macbookpro2017/Downloads/Xcode.app/Contents/Developer}"
cd "$(dirname "$0")/../CLI"
swift test --scratch-path /tmp/convrt-cli-build 2>&1 | grep -E "error:|failed|Executed [0-9]+ tests" | sort -u | tail -8
