# Shipping Convrt

Signing, notarization and a release checklist.

## 1. Project settings checklist (target Convrt)

**General tab**
- Display Name: Convrt
- Bundle Identifier: something you own, e.g. `com.yourname.Convrt` (write it down)
- Version 1.0, Build 1 (raise Build on every release)
- Minimum Deployments: macOS 13.0
- App Icons Source: AppIcon

**Signing & Capabilities tab**
- Automatically manage signing: ON, and pick your **Team** (a free personal team works for your own Mac).
  Never leave it on "None" or "Sign to Run Locally" (this is the #1 reason permissions get lost).
- Remove the **App Sandbox** capability if it is listed. Add **Hardened Runtime** (the "+ Capability" button) for Release.

**Info tab** (add these keys if missing)
- Application is agent (UIElement) = YES (Boolean). This hides the Dock icon.
- Application Category = Utilities
- Copyright (NSHumanReadableCopyright) = e.g. "© 2026 Your Name"

## 2. Works in Xcode (Cmd+R) but not when opened on its own

When Xcode launches the app, macOS treats Xcode as the responsible program, so the Accessibility and Input Monitoring
permission you gave Xcode also covers Convrt. When you open `Convrt.app` yourself, Convrt is on its own, and macOS
ties its permission to its code signature. Builds signed "to run locally" (ad hoc) get a brand-new signature on every
build, so the permission entry in System Settings keeps going stale: it still shows a switch that is ON, but it points
at an old build.

Fix, once:
1. Pick a Team in Signing & Capabilities (section 1) so the signature stays stable.
2. Build and install: `./Scripts/build_release.sh local` (copies the app to /Applications and opens it).
3. System Settings > Privacy & Security > **Accessibility** and **Input Monitoring**:
   remove every old Convrt entry with the **−** button, then let the new Convrt ask again (it prompts on first launch,
   or use the menu bar icon > Check Permissions…) and switch it on.
4. Click Restart when Convrt offers it.
5. Menu bar icon > **Diagnostics…** should now show "granted" twice, a real signing authority (not "ad-hoc") and
   "Events seen" going up when you drag a file.

Still stuck? Reset the stale entries from Terminal (use your bundle identifier from section 1), then repeat step 3:

    tccutil reset Accessibility com.yourname.Convrt
    tccutil reset ListenEvent com.yourname.Convrt

If something still fails, send me the Diagnostics text. The log is at `~/Library/Logs/Convrt.log`
(menu bar icon > Diagnostics… > Show Log in Finder). It holds counts and states only, never file names.

## 3. Install on your own Mac

    cd /path/to/folder/with/Convrt.xcodeproj
    ./Scripts/build_release.sh local

## 4. Share it with other people

Anyone else's Mac will block an app that isn't notarized, so this needs a paid Apple Developer account ($99/year).

One-time setup:
1. developer.apple.com > Certificates: create a **Developer ID Application** certificate (Xcode > Settings > Accounts >
   Manage Certificates > + > Developer ID Application also works).
2. appleid.apple.com > Sign-In and Security > **App-Specific Passwords**: create one named "convrt-notary".
3. Store the credentials in your keychain:

       xcrun notarytool store-credentials "convrt-notary" --apple-id "you@example.com" --team-id "YOURTEAMID" --password "xxxx-xxxx-xxxx-xxxx"

4. Edit TEAM_ID and SIGN_IDENTITY at the top of `Scripts/build_release.sh`.

Every release:

    ./Scripts/build_release.sh dmg

You get `build/Convrt.dmg`: signed, notarized and stapled. Send that file around. Users drag Convrt to Applications,
open it, and grant the two permissions once.

Note: the Mac App Store is not possible for this app. It needs global drag monitoring and access to files anywhere,
which the App Store sandbox forbids. Distribute the DMG directly instead.

## 5. Pre-release test checklist

- Fresh install in /Applications, launch from Finder (not Xcode): no Dock icon, logo in the menu bar.
- Permission prompts appear once; after granting and restarting, Diagnostics shows both granted.
- Shift-drag: PNG to JPG (transparent PNG gets a white background), HEIC to JPG, multi-page PDF to PNG, several images to PDF.
- Names never overwrite (`-1`, `-2`). The "Done" card appears with a working Reveal in Finder button.
- Settings: quality slider, chosen output folder, move-original-to-Trash, trigger key, launch at login.
- Zip or app dragged: "Can't convert this type".
- Quit and relaunch: settings are remembered.
