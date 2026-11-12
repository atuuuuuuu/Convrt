#!/bin/bash
# Re-render the README images (assets/banner.png, wheels.png, social-preview.png)
# from the app's real RadialWheelView, using SwiftPM + ImageRenderer. No app launch needed.
set -euo pipefail
# Needs full Xcode (XCTest), not just the Command Line Tools.
source "$(dirname "$0")/xcode_env.sh"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG=/tmp/convrt-art-pkg
mkdir -p "$PKG/Sources/Convrt" "$PKG/Tests/Art"
rsync -a --delete --delete-excluded --exclude='ConvrtApp.swift' --include='*/' --include='*.swift' --exclude='*' "$ROOT/Convrt/" "$PKG/Sources/Convrt/"
cp "$ROOT/Scripts/readme-art/RenderReadmeArt.swift" "$PKG/Tests/Art/"
cat > "$PKG/Package.swift" <<'SWIFT'
// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "Convrt", platforms: [.macOS(.v13)], targets: [
    .target(name: "Convrt", path: "Sources/Convrt"),
    .testTarget(name: "Art", dependencies: ["Convrt"], path: "Tests/Art")])
SWIFT
cd "$PKG"
ART_OUT="$ROOT/assets" ART_LOGO="$ROOT/Branding/logo-white-transparent.png" \
  swift test --scratch-path /tmp/convrt-art-build 2>&1 | grep -E "error:|Case .*(passed|failed)"
echo "Wrote $ROOT/assets/{banner,wheels,social-preview}.png"
