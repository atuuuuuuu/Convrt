#!/bin/bash
# Build or test Convrt with the Xcode in ~/Downloads (not the active developer dir).
# Builds go to /tmp/convrt-dd so unsigned test builds never pollute the signed app Xcode builds.
# `test` runs only the unit tests and retries when Xcode's test host hangs (it sometimes idles forever).
set -uo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Users/macbookpro2017/Downloads/Xcode.app/Contents/Developer}"
cd "$(dirname "$0")/.."
action="${1:?usage: xb.sh build|test}"; shift || true
LOG="${XB_LOG:-/tmp/xb-$action.log}"
common=(-derivedDataPath /tmp/convrt-dd -project Convrt.xcodeproj -scheme Convrt -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO)

if [ "$action" = "build" ]; then
  xcodebuild "${common[@]}" "$@" build > "$LOG" 2>&1; code=$?
  grep -E "error:|BUILD (SUCCEEDED|FAILED)" "$LOG" | head -20; exit $code
fi

limit="${XB_TEST_LIMIT:-300}"   # seconds before a run counts as hung
for attempt in 1 2 3; do
  pkill -f "/tmp/convrt-dd/Build/Products/Debug/Convrt.app" 2>/dev/null
  xcodebuild "${common[@]}" -only-testing:ConvrtTests "$@" test > "$LOG" 2>&1 &
  pid=$!
  waited=0
  while kill -0 $pid 2>/dev/null && [ $waited -lt "$limit" ]; do sleep 2; waited=$((waited+2)); done
  if kill -0 $pid 2>/dev/null; then
    echo "attempt $attempt: test run hung after ${limit}s; killing and retrying" >&2
    kill $pid 2>/dev/null; pkill -f "/tmp/convrt-dd/Build/Products/Debug/Convrt.app" 2>/dev/null; sleep 2
    continue
  fi
  wait $pid; code=$?
  grep -E "error:|Test Case .* failed|Executed [0-9]+ test|TEST (SUCCEEDED|FAILED)" "$LOG" | head -30
  exit $code
done
echo "test run hung 3 times" >&2; exit 124
