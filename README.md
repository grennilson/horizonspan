# ScreenSpan Wallpaper

ScreenSpan Wallpaper creates desktop wallpapers across multiple displays, with native macOS and Windows applications. Preview crops, combine pictures, extend edges, organize saved wallpapers and render an image for each connected display.

## Downloads

- **Windows 10/11, 64-bit:** [Windows 1.0.2 release](https://github.com/grennilson/horizonspan/releases/tag/windows-v1.0.2). Choose the setup EXE to install, or the standalone EXE to run without installation. See the [Windows guide](Windows/README.md), [validation results](Windows/TESTING.md) and [third-party notices](Windows/THIRD-PARTY-NOTICES.md).
- **macOS 13 or newer:** [Mac 1.4.0 release](https://github.com/grennilson/horizonspan/releases/tag/v1.4.0). Download the DMG. The Mac version supports Apple Silicon and Intel.

Windows code and its build script live in `Windows/`. The Swift files and build scripts at the repository root are the Mac application. Windows and Mac have separate version tags and downloads; a Windows release does not replace the Mac latest-release link.

The following sections describe the Mac application. The Windows guide explains its installer, tray menu, local AI requirements and saved-project portability.

## Install on macOS

These instructions cover ScreenSpan Wallpaper 1.4.0.

1. Download the disk image from [the latest GitHub release](https://github.com/grennilson/horizonspan/releases/latest) and open it.
2. Drag **ScreenSpan Wallpaper.app** onto the **Applications** shortcut.
3. Eject the disk image and open ScreenSpan Wallpaper from Applications.
4. Choose a local image or drag one from Finder into the preview box. Adjust the preview and click **Apply Wallpaper**.

New images open with **Fit Entire Photo**, which preserves the full framing and leaves space around the image where needed. Choose **Fill & Crop** to cover the entire display layout and drag to adjust which part is visible. Open **Extend Edges** to fill the available space.

If you’re upgrading from HorizonSpan, quit it and move the old app out of Applications before installing ScreenSpan Wallpaper. Your saved wallpaper and settings carry over.

## Wallpaper library and monitor setups

Click **Library** to browse saved projects with thumbnails. Select a project to rename it, mark it as a favorite, open it in the editor, or apply it directly. Applying from the library leaves your current editor draft available.

To remember a wallpaper for the monitors connected now, select a project, enter a monitor setup name, and click **Use for This Monitor Setup**. This enables automatic setup matching. The app matches display identities, resolutions, and their arrangement when displays change or the app starts. **Forget This Setup** removes that association. Settings includes a switch to disable automatic matching.

## Display groups, alignment, and appearance

Click **Displays & Appearance** in the editor. Monitors in the same wallpaper group share one spanning image. **Span All Displays** puts all monitors in the main panorama. **Separate Images** creates one group per monitor. You can also put two monitors in one group and leave another in a separate group. Choose an image for each numbered group, or use the main image.

Horizontal and vertical offsets adjust where each monitor samples the panorama. Positive vertical offsets move that sampling area upward. **Relative screen size** helps compensate for different physical screen sizes and scaling. These controls adjust the wallpaper preview and render, while macOS retains control of display configuration.

The Appearance tab provides brightness, saturation, dimming, and a background color for uncovered areas. Click **Done**, then save or apply the wallpaper. Groups, their images, alignment, and appearance are included in new version 2 .ssw projects. Version 1 projects continue to open.

## Rotation and updates

Favorite projects in the library, then enable **Rotate favorite wallpapers** in Settings and choose an interval. Rotation runs while the app is open and waits while you are cropping, choosing an image, or using a dialog. **Next Wallpaper** in the menu bar advances through favorites, or all saved projects if none are favorites.

**Check for Updates** in Settings checks the latest public GitHub release and offers its release page when a newer version is available.

## Crop in the preview

Click **Crop Image** beside Framing to select a crop matching the combined display layout. Drag inside the rectangle to move it, or drag any of its four corner handles to resize it. The ratio stays locked to the connected displays. Scroll up to zoom into the image and scroll down to zoom out. The darkened area falls outside the crop.

Click **Apply Crop** to commit the selection, or **Cancel Crop** to return to the previous preview. **Undo** and **Redo** restore the image and framing before or after the crop. **Save Project** saves the cropped image and its wallpaper settings.

## Combine multiple images

Select multiple images in **Choose Image** or drop several image files into the preview. **Combine Images** shows their order and a preview. Use the arrows to change the order, and choose **Side by Side** or **Stacked**. Click **Combine Images** to edit the result as one wallpaper.

Images are initially sorted by filename using natural number order. Each image keeps its proportions and is scaled to the smallest shared height (side by side) or width (stacked). Combined images are limited to 64 megapixels. Matching 1,920 × 1,080 halves form a 3,840 × 1,080 image. **Save Project** stores the combined image and framing in a .ssw project.

## Saved wallpaper projects

**Apply Wallpaper** automatically saves a new project in **Pictures/ScreenSpan Wallpaper**. Use **Save Project** (Command–S) to save your current edit without changing the desktop. Each save creates a separate file.

A project has the extension `.ssw` and contains `Image.png` (the imported or AI-edited image), `Wallpaper.png` (the finished wallpaper with the chosen framing), `Displays/` (one PNG per monitor), and `Settings.json` (format version, framing, zoom, position, and display layout). The finished combined wallpaper is limited to 64 megapixels. The per-monitor PNGs retain each monitor’s output resolution.

Double-click a project, choose it with **Choose Image**, or drag it into the editor to reopen its image and settings. Applying it uses the currently connected displays. To retrieve the PNG files, Control-click the project in Finder and choose **Show Package Contents**. **Wallpaper Library** in the File or menu bar menu opens the visual library. Its **Open Folder** button opens the library folder in Finder.

The project contains the current edited image, framing, and display design. Undo history is available for the current editing session.

Version 2 projects include a thumbnail and a separate PNG for each group with its own image. Library names, favorites, and monitor setup associations are kept in the library folder’s metadata file.

## Keep your wallpaper across display changes

Click **Apply Wallpaper** to save a local copy of the image and its framing. ScreenSpan Wallpaper restores that wallpaper when you change displays, switch macOS Spaces, or wake the displays while the app is running. It recalculates the crops for the connected displays. You can close the editor window and keep ScreenSpan Wallpaper running in the menu bar.

Click the two-display icon at the right of the menu bar to open the editor, choose **New Wallpaper**, reapply the saved wallpaper, or open **Settings**. **New Wallpaper** opens the image picker. The current desktop wallpaper stays visible until you click **Apply Wallpaper**. Use **Quit ScreenSpan Wallpaper** to stop the app.

Open **ScreenSpan Wallpaper → Settings** or press **Command–Comma** to show or hide the menu bar icon, manage **Open at Login**, and control automatic restoration separately for macOS desktops and display changes. After upgrading from 1.3.2 or earlier, apply your preferred wallpaper once to save it for restoration.

The universal build targets Apple Silicon and Intel Macs running macOS 13 or later. It has been tested on Apple Silicon. The current disk image contains an ad hoc signed app. It has no Apple Developer ID signature or notarization, so macOS may block a downloaded copy on another Mac. See [Apple’s guide to opening downloaded apps](https://support.apple.com/en-us/102445).

## Extend edges and enhance detail

- **Extend Edges → Fade to Black** continues a narrow strip of edge texture into black. Drag the photo to where you want it before opening **Extend Edges**. The fade fills the space around your photo at that position. It works offline on both Intel and Apple Silicon Macs.
- **Extend Edges → Generate with AI** uses SDXL on Apple Silicon to add scenery one edge at a time. You can describe what should continue at the edges before generating. The preview can show seams or invented details.
- **Enhance Detail** upscales a low-resolution source on Apple Silicon by up to four times per side, within a 64-megapixel output limit. You can use it after extending the image.
- **Undo** (Command–Z) and **Redo** (Shift–Command–Z) step through the five most recent image edits in the current draft. **Show Original** lets you compare the original and edited previews. **Revert to Original** restores the original photo and its framing.

The first use of an AI tool downloads a local Python runtime and model files. The edge model is about 7 GB and the detail model is about 67 MB. Internet access is needed for setup and downloads. After setup, processing runs on your Mac without an account, API key, or per-image fee.

Edge extension uses the [SDXL inpainting model](https://huggingface.co/diffusers/stable-diffusion-xl-1.0-inpainting-0.1). Detail enhancement uses [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN). Their model files are downloaded separately from the app.

## Build from source

Install the Apple Command Line Tools with `xcode-select --install` if you need them. No third-party packages are required.

```sh
zsh ./build.sh
open "build/ScreenSpan Wallpaper.app"
```

To package a disk image, run `zsh ./package.sh`. It creates a versioned DMG in `build/` by default. Pass an output path as the first argument to change the destination.

## Contribute

Fork the repository and open a pull request with a description of what you changed and how you checked it. `HorizonSpan.swift` contains the SwiftUI interface, display layout, crop calculations, and wallpaper assignment. `WallpaperProject.swift` reads and writes portable .ssw projects. `SavedWallpaper.swift` stores the last applied wallpaper and renders it for each display layout. `LocalImageAI.swift` handles the fade and runs the AI tools in `LocalAI/`. `build.sh` creates the universal app bundle and packs the icon. `package.sh` creates the installation disk image.

For a change to rendering, try a numbered grid or a photo with recognizable landmarks across displays with different scaling or vertical positions. Check that the preview agrees with the desktop after you click **Apply Wallpaper**. For a layout bug, include your macOS version, display arrangement, and scaling settings.

`CropPreview.swift` implements crop handles and scroll zoom. `CombineImages.swift` handles image ordering and combining. `WallpaperDesign.swift` renders display groups, alignment, and appearance. `WallpaperLibrary.swift` stores names, favorites, and monitor setup associations. `WallpaperFeatures.swift` contains their interfaces, rotation, and update checking.

## Run regression checks

Run `zsh Tests/run.sh`. The checks use temporary projects and simulated displays to verify spanning, separate sources, mixed resolutions, display groups, appearance, older project compatibility, library metadata, monitor setup associations, version comparison, and crop undo/redo.

The 1.4.0 release was also checked through the app interface on Apple Silicon, including library renaming and favorites, independent monitor images, saved appearance settings, the update checker, and timed rotation. Physical monitor reconnection and an Intel runtime still need testing.
