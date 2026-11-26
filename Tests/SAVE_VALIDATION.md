# Save Wallpaper validation — Mac 1.4.3 / Windows 1.0.4

November 26, 2026.

Save Project is now labelled Save Wallpaper on both platforms. Save and Apply previously generated independent UUIDs and therefore duplicate packages. Saving now compares image pixels, framing, appearance, group images and display layout, excluding the random UUID. Identical existing packages are reused, including packages saved by earlier versions. Changed content produces a separate version. Mac application state retains the reused package identity.

Mac automated checks passed for Save/Apply reuse, reopening an unchanged package, changed framing, changed source pixels with the same supplied UUID, and changed group pixels. Existing renderer, crop, library and startup restoration checks passed. The universal app and DMG built and signature/checksum verification passed.

The installed Mac 1.4.3 app was tested with the user's retained palm-tree package: Open in Editor → Save Wallpaper → Apply Wallpaper. The library remained at one entry and Current.json matched that entry's UUID. Public wallpaper API readback showed the saved per-display image on both attached displays. Open at Login and both restoration switches remained enabled. With user permission, the older byte-identical duplicate was moved to Trash; no other library content was removed.

Windows CI run [45878556528](https://github.com/grennilson/horizonspan/actions/runs/45878556528) passed 30 core checks, actual Windows renderer/editor checks and installer extraction checks. Added checks cover unchanged saves, reopening, legacy packages, changed framing, source pixels and group images. Startup schedule checks cover retry after an initial failure, cancellation and disabled restoration. The Windows suite uses temporary files and does not change the test machine's desktop wallpaper.

No complete Mac or Windows reboot was performed during this update. Windows 1.0.4 has not been installed on Gaming or Plex as part of this validation.
