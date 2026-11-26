#!/bin/zsh
set -eu
cd -- "${0:A:h}/.."
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
xcrun swiftc -D SCREENSPAN_TESTING -parse-as-library \
    HorizonSpan.swift LocalImageAI.swift SavedWallpaper.swift WallpaperRestoration.swift WallpaperProject.swift \
    CombineImages.swift CropPreview.swift WallpaperDesign.swift WallpaperLibrary.swift WallpaperFeatures.swift \
    Tests/RegressionChecks.swift -o "$scratch/checks"
"$scratch/checks"
