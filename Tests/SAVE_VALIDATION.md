# Save Wallpaper validation — Mac 1.4.3 / Windows 1.0.4

November 26, 2026.

Save Project is now labelled Save Wallpaper on both platforms. Save and Apply previously generated independent UUIDs and therefore duplicate packages. Saving now compares image pixels, framing, appearance, group images and display layout, excluding the random UUID. Identical existing packages are reused, including packages saved by earlier versions. Changed content produces a separate version. Mac application state retains the reused package identity.

Mac automated checks passed for Save/Apply reuse, reopening an unchanged package, changed framing, changed source pixels with the same supplied UUID, and changed group pixels. Existing renderer, crop, library and startup restoration checks passed. The universal app and DMG built and signature/checksum verification passed.

The installed Mac 1.4.3 app was tested with the user's retained palm-tree package: Open in Editor → Save Wallpaper → Apply Wallpaper. The library remained at one entry and Current.json matched that entry's UUID. Public wallpaper API readback showed the saved per-display image on both attached displays. Open at Login and both restoration switches remained enabled. With user permission, the older byte-identical duplicate was moved to Trash; no other library content was removed.

Windows CI run [45878556528](https://github.com/grennilson/horizonspan/actions/runs/45878556528) passed 30 core checks, actual Windows renderer/editor checks and installer extraction checks. Added checks cover unchanged saves, reopening, legacy packages, changed framing, source pixels and group images. Startup schedule checks cover retry after an initial failure, cancellation and disabled restoration. The Windows suite uses temporary files and does not change the test machine's desktop wallpaper.

No complete Mac or Windows reboot was performed during this update. Windows 1.0.4 has not been installed on Gaming or Plex as part of this validation.

## November 27 — Mac 1.4.4 / Windows 1.0.5

The reported same-name entries were distinct crops (3,054 × 859 and 3,056 × 859), not exact duplicates. Both unchanged packages were resaved in an isolated temporary library without creating another package. No original user files were changed by that investigation.

Save Wallpaper and Apply now update the package open in the editor. First save binds an imported draft to its saved package. Importing another image or combining new images starts a new draft. Save as New Wallpaper deliberately creates a separate ID and distinct title, even when pixels/settings are unchanged. The Mac save dropdown and File menu expose it; Command–Shift–S is its Mac shortcut. Windows offers a separate button. Existing same-name entries get distinct visible labels without deleting or merging files. Favorites and monitor setup references retain their IDs on update.

Mac checks passed for stable path/ID on changed settings, explicit copies, distinct titles, saving an identical copy without merging another item, failed saves leaving the existing package intact, and cache revision changes rendering new pixels. Existing renderer, project, crop, restore and library checks passed. Package replacement is staged; no existing package is replaced until rendering/export succeeds.

Mac 1.4.4 was installed and checked through the UI. The two existing crop versions showed distinct names, the save dropdown offered both commands, and saving the selected wallpaper kept the library at five entries. Existing crop files were retained. No desktop wallpaper change or machine reboot was requested during this validation.

Windows CI [46033364952](https://github.com/grennilson/horizonspan/actions/runs/46033364952) passed actual Windows rendering/editor, update-in-place, stable ID, explicit new-copy/name, failed-update preservation, layout and installer extraction checks. Downloaded EXE/ZIP SHA-256 values were verified. Windows 1.0.5 was not installed on Gaming or Plex during this update.
