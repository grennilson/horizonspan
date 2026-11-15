#!/bin/zsh
set -eu
cd -- "${0:A:h}"

output="${1:-$PWD/build/HorizonSpan.app}"
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
app="$scratch/HorizonSpan.app"
iconset="$scratch/AppIcon.iconset"
mkdir -p "$iconset" "$app/Contents/MacOS" "$app/Contents/Resources"

for arch in arm64 x86_64; do
    xcrun swiftc -parse-as-library -O -target "$arch-apple-macosx13.0" \
        HorizonSpan.swift -o "$scratch/HorizonSpan-$arch"
done
lipo -create "$scratch/HorizonSpan-arm64" "$scratch/HorizonSpan-x86_64" \
    -output "$app/Contents/MacOS/HorizonSpan"

for size in 16 32 128 256 512; do
    sips -z "$size" "$size" AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    sips -z "$retina_size" "$retina_size" AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
cp Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
mkdir -p "${output:h}"
ditto --noextattr --norsrc "$app" "$output"
if xattr -p com.apple.FinderInfo "$output" >/dev/null 2>&1; then
    xattr -d com.apple.FinderInfo "$output"
fi
codesign --verify --strict "$output"
print -r -- "$output"
