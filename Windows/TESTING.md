# Windows 1.0.0 validation

Validation performed on November 20, 2026.

## Completed

- Clean compilation with Microsoft's .NET 10 SDK, targeting x64 .NET Framework 4.8. Application and setup metadata use version 1.0.0.
- 27 platform-independent checks: two, three and four monitors; negative origins; portrait fit; crop bounds and ratio; pan clamping; Undo/Redo; design deep copies and validation; AI output planning; monitor-profile keys; Windows-only version checks.
- Windows 11 Pro on the Plex development machine: renderer colors, independent groups, dimming, format 1 import, format 2 save/reopen with group assets, exports and thumbnail, missing-asset rejection, horizontal/vertical combination, horizontal/vertical fading, favorites, rotation selection, profile persistence, render-cache reuse and monitor enumeration.
- The Windows suite executes the real editor's crop, Undo/Redo, compare and save/reopen commands against temporary pictures. It does not change the desktop wallpaper.
- Installer payload extraction, followed by running the complete application suite with the standalone EXE in a folder with no application DLL files.
- Actual Real-ESRGAN CPU inference on Plex Server: the pinned model was downloaded and loaded, and a 32 × 24 test image was enhanced to 64 × 48.
- Manual checks during development: image picker import, corner dragging, crop application, Undo/Redo, project save/reopen, small-screen window sizing and close-to-tray behavior.

## Release checks in progress

- Clean GitHub-hosted Windows build and packaging checks.
- Windows 10 Gaming installation, renderer and wallpaper assignment checks.
- NVIDIA edge-generation inference, if supported hardware is available on Gaming.

## Practical limits

Physical unplug/replug, monitor-input switching, different GPU drivers, multi-monitor hardware combinations beyond the available machines, and sign-in after a full reboot cannot be inferred from Remote Desktop results. Two-, three- and four-display layouts are covered by automated geometry/rendering cases; that is separate from testing those layouts on physical monitors.

AI outputs can contain seams or invented content. Passing a runtime/inference test does not guarantee pleasing results for every photograph. Intel/AMD graphics use CPU mode in this version; CPU edge generation requires at least 32 GB RAM. The Plex machine has Intel graphics and 16 GB RAM, so edge generation is not run there.

The GitHub build retains its test reports and SHA-256 checksums with its executable artifacts. The Windows executables are unsigned. The installer preserves Pictures/ScreenSpan Wallpaper and the application's local data when uninstalling.
