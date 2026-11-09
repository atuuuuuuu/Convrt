#!/bin/bash
# Convrt release helper.
# Run it from the folder that contains Convrt.xcodeproj:
#
#   ./Scripts/build_release.sh local   Build Release and install to /Applications (for your own Mac)
#   ./Scripts/build_release.sh dmg     Build, sign, notarize and staple Convrt.dmg to share with others
#                                      (needs a paid Apple Developer account, see SHIPPING.md)
set -euo pipefail

PROJECT="Convrt.xcodeproj"
SCHEME="Convrt"
APP="Convrt"
BUILD_DIR="$(pwd)/build"

# ----- Fill these in for "dmg" mode only -----------------------------------
TEAM_ID="YOURTEAMID"                                              # 10 characters, from developer.apple.com > Membership
SIGN_IDENTITY="Developer ID Application: Your Name (YOURTEAMID)"  # exact name from Keychain Access
NOTARY_PROFILE="convrt-notary"                                    # created once, see SHIPPING.md
# ---------------------------------------------------------------------------

mode="${1:-local}"

case "$mode" in
  local)
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
      -derivedDataPath "$BUILD_DIR" clean build

    BUILT="$BUILD_DIR/Build/Products/Release/$APP.app"
    pkill -x "$APP" 2>/dev/null || true
    rm -rf "/Applications/$APP.app"
    ditto "$BUILT" "/Applications/$APP.app"

    echo
    echo "Installed: /Applications/$APP.app"
    codesign -dv --verbose=2 "/Applications/$APP.app" 2>&1 | grep -E "Authority|Signature|flags" || true
    echo
    echo "If it says Signature=adhoc, pick a Team in Xcode > Signing & Capabilities and run this again,"
    echo "otherwise macOS forgets the Accessibility / Input Monitoring permission after every rebuild."
    open "/Applications/$APP.app"
    ;;

  dmg)
    if [[ "$TEAM_ID" == "YOURTEAMID" ]]; then
      echo "Edit TEAM_ID, SIGN_IDENTITY and NOTARY_PROFILE at the top of this script first."
      exit 1
    fi

    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"

    echo "==> Archiving"
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
      -archivePath "$BUILD_DIR/$APP.xcarchive" \
      DEVELOPMENT_TEAM="$TEAM_ID" ENABLE_HARDENED_RUNTIME=YES \
      -allowProvisioningUpdates archive

    echo "==> Exporting with Developer ID"
    cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST
    xcodebuild -exportArchive -archivePath "$BUILD_DIR/$APP.xcarchive" \
      -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
      -exportPath "$BUILD_DIR/export" -allowProvisioningUpdates

    echo "==> Building the DMG"
    STAGING="$BUILD_DIR/dmg-staging"
    mkdir -p "$STAGING"
    ditto "$BUILD_DIR/export/$APP.app" "$STAGING/$APP.app"
    ln -s /Applications "$STAGING/Applications"
    hdiutil create -volname "$APP" -srcfolder "$STAGING" -ov -format UDZO "$BUILD_DIR/$APP.dmg"
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "$BUILD_DIR/$APP.dmg"

    echo "==> Notarizing (this takes a few minutes)"
    xcrun notarytool submit "$BUILD_DIR/$APP.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$BUILD_DIR/$APP.dmg"

    echo "==> Checking"
    spctl --assess --type open --context context:primary-signature -v "$BUILD_DIR/$APP.dmg" || true
    echo
    echo "Done: $BUILD_DIR/$APP.dmg"
    ;;

  *)
    echo "Usage: $0 local | dmg"
    exit 1
    ;;
esac
