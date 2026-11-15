#!/bin/zsh
set -eu
cd -- "${0:A:h}"

version=$(plutil -extract CFBundleShortVersionString raw Info.plist)
output="${1:-$PWD/build/HorizonSpan-$version.dmg}"
output="${output:A}"
if [[ -e "$output" ]]; then
    print -u2 -r -- "Output already exists: $output"
    exit 1
fi

stage=$(mktemp -d)
trap 'rm -rf -- "$stage"' EXIT
mkdir -p "$stage/volume" "${output:h}"
zsh ./build.sh "$stage/volume/HorizonSpan.app"
ln -s /Applications "$stage/volume/Applications"
hdiutil create -volname HorizonSpan -srcfolder "$stage/volume" -format UDZO "$output"
hdiutil verify "$output"
