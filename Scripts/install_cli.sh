#!/bin/bash
# Build the `convrt` command-line tool and copy it to ~/.local/bin (no sudo needed).
# Add ~/.local/bin to your PATH if `convrt --version` says "command not found".
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Users/macbookpro2017/Downloads/Xcode.app/Contents/Developer}"
cd "$(dirname "$0")/../CLI"
swift build -c release --scratch-path /tmp/convrt-cli-build
mkdir -p "$HOME/.local/bin"
cp /tmp/convrt-cli-build/release/convrt "$HOME/.local/bin/convrt"
echo "Installed: $HOME/.local/bin/convrt"
"$HOME/.local/bin/convrt" --version
