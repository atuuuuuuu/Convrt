# Changelog

All notable changes to Convrt are listed here.

## [Unreleased]

### Added
- Three wheels: **Convert**, **Tools** and **Actions**. Option cycles them, Command/Control jump, scroll/Tab/arrows step, Esc closes.
- Audio conversion (WAV, MP3, M4A, FLAC, AIFF; MP3 output via `lame`), video conversion (MOV, MP4), PDF and ZIP tools.
- Image tools including an interactive cropper, background removal, resize, compress, strip metadata, rotate, flip.
- Video tools (mute, trim, snapshot, extract audio), AirDrop, floating shelf, Drop Zone window.
- Watch Folders, Recent Conversions with Undo, and a `convrt` command-line tool.
- Blue theme; stable signing so permissions survive rebuilds; unit tests run with `Scripts/test.sh`.
- Menu bar app with no Dock icon, Launch at Login, About and Diagnostics.
- Shift-drag radial wheel with real drop targets and a fade/scale animation.
- Image conversion: PNG, JPG, HEIC, TIFF, BMP, GIF and PDF (WEBP and AVIF when macOS can write them).
- PDF to images (one folder for multi-page files) and several images to one combined PDF.
- Color profile, orientation and EXIF/GPS data are kept; transparency becomes white for JPG and BMP.
- Results are saved next to the original and never overwrite (`-1`, `-2`, …).
- Settings window: trigger key, output folder, move originals to the Trash, quality, sound, launch at login.
- "Converting… / Done" card with Reveal in Finder.
- Permission guidance with a one-click restart, a Diagnostics report and a local log.
- Release script for a local install or a signed, notarized DMG.
