# Mac 1.4.2 startup restoration

November 26, 2026.

The reported failure showed different backgrounds on two displays after a reboot. Inspection found that ScreenSpan was not running and Open at Login was off. The saved panorama and source PNG were intact. A physical display also had a different temporary display number than the cached render from the preceding session.

Open at Login was enabled through the app. macOS reported the item as enabled and allowed. Starting ScreenSpan restored the saved panorama; public wallpaper API readback confirmed saved per-monitor files on both connected displays.

Changes:

- Physical monitor UUIDs determine render cache identity and filenames, independent of temporary display numbers and enumeration order.
- Startup retries force assignment over approximately 30 seconds. Display/Space changes receive shorter bounded retries. During initial startup, display events keep the longer retry schedule.
- Corrupt or missing cached images are regenerated from the saved source.
- Cancellation and disabled settings stop scheduled attempts.
- Settings explains the Open at Login requirement. A manual Apply can offer to enable it once.
- A bounded local WallpaperRestore.log records startup and restoration outcomes.

Automated checks passed for changed display numbers/order, unchanged panorama halves, independent monitor images, damaged cache recovery, delayed display discovery plus a later wallpaper overwrite, cancellation and disabled restoration. Existing layout, project, appearance, library, crop and update-version checks also passed.

The installed 1.4.2 app retained the enabled/allowed login registration after replacement. Its live diagnostic log recorded all five forced startup passes succeeding on two connected physical monitors. Public wallpaper API readback confirmed the physical-identity cache paths and 3840 × 2160 output on each display. The editor reopened the previously applied panorama without changing its saved selection.

Validation does not include restarting the user's computer or physical unplug/replug. App relaunch and current-display readback can verify the local setup, but a subsequent real reboot is still needed to confirm the complete login sequence on this hardware. Intel builds are produced; Intel runtime testing remains outstanding.
