#!/bin/bash
set -euo pipefail

runtime=$1
arch=$(/usr/bin/uname -m)
if [[ "$arch" != arm64 ]]; then
    printf '%s\n' 'Local AI requires an Apple Silicon Mac.' >&2
    exit 1
fi

export UV_CACHE_DIR="$runtime/cache"
export UV_PYTHON_INSTALL_DIR="$runtime/python"
export UV_NO_PROGRESS=1
export UV_NO_CONFIG=1
mkdir -p "$runtime"
cd "$runtime"
uv="$runtime/uv"
if [[ ! -x "$uv" ]]; then
    temp=$(mktemp -d "$runtime/setup.XXXXXX")
    trap 'rm -rf -- "$temp"' EXIT
    printf '%s\n' 'Downloading the local AI runtime…'
    /usr/bin/curl --disable --fail --silent --show-error --location --retry 2 \
        https://github.com/astral-sh/uv/releases/download/0.13.8/uv-aarch64-apple-darwin.tar.gz \
        -o "$temp/uv.tar.gz"
    printf '%s  %s\n' '6b71028a6b904f2ae3340ef52e595512de807d06c0a20eaef2f692581b246558' "$temp/uv.tar.gz" \
        | /usr/bin/shasum -a 256 -c - >/dev/null
    /usr/bin/tar -xzf "$temp/uv.tar.gz" -C "$temp" uv-aarch64-apple-darwin/uv
    /bin/mv "$temp/uv-aarch64-apple-darwin/uv" "$uv"
fi

if [[ ! -f "$runtime/ready" || ! -x "$runtime/env/bin/python" ]]; then
    printf '%s\n' 'Setting up the local AI runtime…'
    "$uv" python install 3.12 --no-bin
    "$uv" venv --allow-existing --managed-python --python 3.12 "$runtime/env"
    "$uv" pip install --python "$runtime/env/bin/python" \
        'torch==2.10.0' 'torchvision==0.25.0' 'Pillow==12.1.1' 'spandrel==0.4.2' \
        'diffusers==0.37.0' 'transformers==4.57.6' 'accelerate==1.12.0' 'huggingface-hub==0.36.2'
    "$runtime/env/bin/python" -c 'import torch, spandrel; from diffusers import StableDiffusionInpaintPipeline'
    touch "$runtime/ready"
fi
