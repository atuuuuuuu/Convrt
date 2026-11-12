# Sourced by the other scripts. Points DEVELOPER_DIR at a full Xcode (XCTest needs it,
# the Command Line Tools are not enough) unless the caller already set it.
if [ -z "${DEVELOPER_DIR:-}" ]; then
  for x in "$(xcode-select -p 2>/dev/null | sed 's#/Contents/Developer$##')" /Applications/Xcode.app "$HOME/Downloads/Xcode.app"; do
    case "$x" in *.app) [ -d "$x/Contents/Developer" ] && export DEVELOPER_DIR="$x/Contents/Developer" && break ;; esac
  done
fi
