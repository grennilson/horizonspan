# Windows 1.0.2 validation

Validation performed on November 20, 2026.

## Completed

- Clean compilation with Microsoft's .NET 10 SDK, targeting x64 .NET Framework 4.8. Application and setup metadata use version 1.0.2.
- 27 platform-independent checks: two, three and four monitors; negative origins; portrait fit; crop bounds and ratio; pan clamping; Undo/Redo; design deep copies and validation; AI output planning; monitor-profile keys; Windows-only version checks.
- Windows 11 Pro on the Plex development machine: renderer colors, independent groups, dimming, format 1 import, format 2 save/reopen with group assets, exports and thumbnail, missing-asset rejection, horizontal/vertical combination, horizontal/vertical fading, favorites, rotation selection, profile persistence, render-cache reuse and monitor enumeration.
- The Windows suite executes the real editor's crop, Undo/Redo, compare and save/reopen commands against temporary pictures. It does not change the desktop wallpaper.
- Installer payload extraction, followed by running the complete application suite with the standalone EXE in a folder with no application DLL files.
- Actual Real-ESRGAN CPU inference on Plex Server: the pinned model was downloaded and loaded, and a 32 × 24 test image was enhanced to 64 × 48.
- Manual checks during development: image picker import, corner dragging, crop application, Undo/Redo, project save/reopen, small-screen window sizing and close-to-tray behavior.
- Clean GitHub-hosted Windows compilation, rendering/editor checks, installer payload checks and artifact packaging.
- Windows 10 Pro (build 19045) on Gaming: installation, complete rendering/project suite, and actual desktop wallpaper assignment/readback followed by restoration of the previous wallpaper.
- Windows 11 Pro (build 26300) on Plex: installation and manual library thumbnails, Settings and Displays & Appearance checks. Group controls and labels were corrected and rechecked.
- Model downloader checks without network access: pinned revision, anonymous download, reuse of validated weights, repair of corrupted cached weights and rejection of an incorrect SHA-256 digest.
- Version 1.0.2 fixes clipped wrapped controls found when installing the release on Gaming. Toolbar rows now grow with their contents. A new Windows regression check exercises narrow windows, enlarged text and both crop states; it passed on Gaming, and the corrected window was also checked visually.

- Actual SDXL CPU inference on Gaming (AMD Radeon RX 580, 32 GB RAM): downloaded and hash-verified the pinned model, loaded the pipeline and extended a 128 × 128 image to 256 × 128 using two inference steps per band. Output dimensions and unchanged original pixels passed. Normal editor generation uses 26 steps; this diagnostic is a runtime check, not a visual-quality evaluation.
- Rechecked Real-ESRGAN CPU inference and the complete Windows editor/project suite on Plex after updating the AI runtime. Both passed.
- Fixed a stalled large-model transfer during integration testing. Downloads now use the resumable Hugging Face client and explicit Windows Xet transport. The full SDXL download and inference then completed successfully.

## Practical limits

Physical unplug/replug, monitor-input switching, different GPU drivers, multi-monitor hardware combinations beyond the available machines, and sign-in after a full reboot cannot be inferred from Remote Desktop results. Two-, three- and four-display layouts are covered by automated geometry/rendering cases; that is separate from testing those layouts on physical monitors.

AI outputs can contain seams or invented content. Passing a runtime/inference test does not guarantee pleasing results for every photograph. Intel/AMD graphics use CPU mode in this version; CPU edge generation requires at least 32 GB RAM. The Plex machine has Intel graphics and 16 GB RAM, so edge generation is not run there.

Neither available PC has NVIDIA graphics. CUDA inference has not been tested on hardware.

## Window activation regression

Version 1.0.2 adds foreground-permission transfer from a new launcher to the existing instance, explicit minimized-window restoration, maximized-state preservation and activation of owned modal dialogs. A single notification-icon click opens the editor. The Windows suite now checks minimize/restore, close-to-background and reopening. Manual Gaming checks of 1.0.1 did not reproduce every reported failure: its title-bar minimize, taskbar restore, close and Desktop shortcut reopening responded during inspection. Updated-build validation is recorded in its attached Windows report; manual checks are performed before release.

The GitHub build retains its test reports and SHA-256 checksums with its executable artifacts. The Windows executables are unsigned. The installer preserves Pictures/ScreenSpan Wallpaper and the application's local data when uninstalling.
