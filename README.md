# HorizonSpan

HorizonSpan is a native macOS app for spanning one still image across multiple displays. Preview the crops, zoom or drag the image to reposition it, then apply it to every connected display. It uses the arrangement from macOS Display Settings and renders a separate PNG at each display’s resolution.

## Install

1. Open the HorizonSpan disk image.
2. Drag **HorizonSpan.app** onto the **Applications** shortcut.
3. Eject the disk image and open HorizonSpan from Applications.
4. Choose a local image, adjust the preview, and click **Apply Wallpaper**.

The universal build targets Apple Silicon and Intel Macs running macOS 13 or later. It has been tested on Apple Silicon. The current disk image contains an ad hoc signed app. It has no Apple Developer ID signature or notarization, so macOS may block a downloaded copy on another Mac. See [Apple’s guide to opening downloaded apps](https://support.apple.com/en-us/102445).

## Build from source

Install the Apple Command Line Tools with `xcode-select --install` if you need them. No third-party packages are required.

```sh
zsh ./build.sh
open "build/HorizonSpan.app"
```

To package a disk image, run `zsh ./package.sh`. It creates a versioned DMG in `build/` by default. Pass an output path as the first argument to change the destination.

## Contribute

Fork the repository and open a pull request with a description of what you changed and how you checked it. `HorizonSpan.swift` contains the SwiftUI interface, the display layout and crop calculations, and the wallpaper assignment. `build.sh` creates the universal app bundle and packs the icon. `package.sh` creates the installation disk image.

For a change to rendering, try a numbered grid or a photo with recognizable landmarks across displays with different scaling or vertical positions. Check that the preview agrees with the desktop after you click **Apply Wallpaper**. For a layout bug, include your macOS version, display arrangement, and scaling settings.
