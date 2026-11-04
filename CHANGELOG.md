# Changelog

All notable changes to Convrt are listed here.

## [Unreleased]

### Added
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
