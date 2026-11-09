#!/bin/bash
# Copy the project tree to ~/Desktop/Convrt-checkpoints/NAME (no git in this folder).
set -euo pipefail
name="${1:?usage: checkpoint.sh NAME}"
root="$(cd "$(dirname "$0")/.." && pwd)"
dest="$HOME/Desktop/Convrt-checkpoints/$name"
mkdir -p "$dest"
rsync -a --delete --exclude 'build/' --exclude '.DS_Store' --exclude 'xcuserdata/' "$root/" "$dest/"
echo "checkpoint saved: $dest"
