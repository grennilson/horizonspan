# ScreenSpan Wallpaper

ScreenSpan Wallpaper is a native macOS app for spanning one still image across multiple displays. Preview the crops, zoom or drag the image to reposition it, then apply it to every connected display. It uses the arrangement from macOS Display Settings and renders a separate PNG at each display’s resolution.

## Install

These instructions cover ScreenSpan Wallpaper 1.3.5.

1. Open the ScreenSpan Wallpaper disk image.
2. Drag **ScreenSpan Wallpaper.app** onto the **Applications** shortcut.
3. Eject the disk image and open ScreenSpan Wallpaper from Applications.
4. Choose a local image or drag one from Finder into the preview box. Adjust the preview and click **Apply Wallpaper**.

New images open with **Fit Entire Photo**, which preserves the full framing and leaves space around the image where needed. Choose **Fill & Crop** to cover the entire display layout and drag to adjust which part is visible. Open **Extend Edges** to fill the available space.

If you’re upgrading from HorizonSpan, quit it and move the old app out of Applications before installing ScreenSpan Wallpaper. Your saved wallpaper and settings carry over.

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

Fork the repository and open a pull request with a description of what you changed and how you checked it. `HorizonSpan.swift` contains the SwiftUI interface, display layout, crop calculations, and wallpaper assignment. `SavedWallpaper.swift` stores the last applied wallpaper and renders it for each display layout. `LocalImageAI.swift` handles the fade and runs the AI tools in `LocalAI/`. `build.sh` creates the universal app bundle and packs the icon. `package.sh` creates the installation disk image.

For a change to rendering, try a numbered grid or a photo with recognizable landmarks across displays with different scaling or vertical positions. Check that the preview agrees with the desktop after you click **Apply Wallpaper**. For a layout bug, include your macOS version, display arrangement, and scaling settings.
