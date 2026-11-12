#!/bin/bash
# Run Convrt's unit tests with Swift Package Manager (no app launch, no Xcode test host,
# so it needs neither Developer Mode nor any permission prompt).
# Copies the app sources (minus the @main file) and the tests into /tmp/convrt-pkg and runs `swift test`.
set -euo pipefail
source "$(dirname "$0")/xcode_env.sh"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG=/tmp/convrt-pkg
mkdir -p "$PKG/Sources/Convrt" "$PKG/Tests/ConvrtTests"
rsync -a --delete --delete-excluded --exclude='ConvrtApp.swift' --include='*/' --include='*.swift' --exclude='*' "$ROOT/Convrt/" "$PKG/Sources/Convrt/"
rsync -a --delete --include='*/' --include='*.swift' --exclude='*' "$ROOT/ConvrtTests/" "$PKG/Tests/ConvrtTests/"
cat > "$PKG/Package.swift" <<'SWIFT'
// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "Convrt",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "Convrt", path: "Sources/Convrt"),
        .testTarget(name: "ConvrtTests", dependencies: ["Convrt"], path: "Tests/ConvrtTests")
    ]
)
SWIFT
cd "$PKG"
code=0
swift test --scratch-path /tmp/convrt-pkg-build "$@" > /tmp/convrt-test.log 2>&1 || code=$?
grep -E "error:|warning: unre|Test Case .* failed|XCTAssert|Executed [0-9]+ test" /tmp/convrt-test.log | sort -u | head -40
[ $code -eq 0 ] && echo "TESTS PASSED" || echo "TESTS FAILED (exit $code; see /tmp/convrt-test.log)"
exit $code
