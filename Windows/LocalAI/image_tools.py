"""On-device wallpaper outpainting and upscaling for ScreenSpan Wallpaper."""

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
from io import BytesIO
from pathlib import Path
import secrets
import subprocess
import tempfile
import os
import time
import urllib.request

MODEL = "diffusers/stable-diffusion-xl-1.0-inpainting-0.1"
REVISION = "115134f363124c53c7d878647567d04daf26e41e"
MODEL_FILES = (
    "model_index.json",
    "scheduler/scheduler_config.json",
    "tokenizer/merges.txt",
    "tokenizer/special_tokens_map.json",
    "tokenizer/tokenizer_config.json",
    "tokenizer/vocab.json",
    "tokenizer_2/merges.txt",
    "tokenizer_2/special_tokens_map.json",
    "tokenizer_2/tokenizer_config.json",
    "tokenizer_2/vocab.json",
    "text_encoder/config.json",
    "text_encoder/model.fp16.safetensors",
    "text_encoder_2/config.json",
    "text_encoder_2/model.fp16.safetensors",
    "unet/config.json",
    "unet/diffusion_pytorch_model.fp16.safetensors",
    "vae/config.json",
    "vae/diffusion_pytorch_model.fp16.safetensors",
)
MODEL_DIGESTS = {
    "text_encoder/model.fp16.safetensors": "fc83cf401d930147807e7c44021c164bcc5508c9d4cc0ff35f4e354685ca9cd0",
    "text_encoder_2/model.fp16.safetensors": "a8622bd41f8d359df484fdf9de091edb9337a2fd747f0a5c9c320a62e24d1fd3",
    "unet/diffusion_pytorch_model.fp16.safetensors": "6470840731e98cc16713ddf3ac7ee458c9fdbcb881a98c6727cd4a938f227d3f",
    "vae/diffusion_pytorch_model.fp16.safetensors": "4ad62825e5c8b31eefb77355ba6693785619bf7d669d9b1a6fd9f19dec6d65b3",
}
ESRGAN_URL = (
    "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth"
)
ESRGAN_SHA256 = "4fa0d38905f75ac06eb49a7951b426670021be3018265fd191d2125df9d682f1"
MAX_PIXELS = 64_000_000


def progress(message):
    print(message, flush=True)


def download(url, path, digest=None):
    def valid(file):
        if not file.is_file() or not file.stat().st_size:
            return False
        if digest is None:
            return True
        with file.open("rb") as stream:
            return hashlib.file_digest(stream, "sha256").hexdigest() == digest

    if valid(path):
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, suffix=".part", delete=False) as temporary:
        partial = Path(temporary.name)
    try:
        for attempt in range(3):
            try:
                request = urllib.request.Request(url, headers={"User-Agent": "ScreenSpanWallpaper/1.0"})
                with urllib.request.urlopen(request, timeout=90) as response, partial.open("wb") as stream:
                    while chunk := response.read(4 * 1024 * 1024):
                        stream.write(chunk)
                break
            except Exception:
                if attempt == 2:
                    raise
                time.sleep(2)
        if not valid(partial):
            raise RuntimeError("The model download failed its integrity check.")
        partial.replace(path)
    finally:
        partial.unlink(missing_ok=True)


def prepare_outpaint(models):
    directory = models / f"sdxl-inpaint-{REVISION[:7]}"
    if not all((directory / name).is_file() for name in MODEL_FILES):
        progress("Downloading the edge-extension model (about 7 GB)…")
    base = f"https://huggingface.co/{MODEL}/resolve/{REVISION}"
    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(lambda name: download(f"{base}/{name}", directory / name, MODEL_DIGESTS.get(name)),
                      MODEL_FILES))
    return directory


def device():
    import torch

    if os.environ.get("SCREENSPAN_AI_DEVICE") == "cpu":
        torch.set_num_threads(max(1, min(4, (os.cpu_count() or 2) // 2)))
        return "cpu"
    if torch.cuda.is_available():
        return "cuda"
    torch.set_num_threads(max(1, min(4, (os.cpu_count() or 2) // 2)))
    return "cpu"


def enhance(image, width, height, models):
    import numpy as np
    from PIL import Image
    from spandrel import ModelLoader
    import torch

    weights = models / "RealESRGAN_x4plus.pth"
    if not weights.exists():
        progress("Downloading the detail-enhancement model (67 MB)…")
    download(ESRGAN_URL, weights, ESRGAN_SHA256)
    progress("Enhancing image detail…")
    model = ModelLoader().load_from_state_dict(torch.load(weights, map_location="cpu", weights_only=True))
    gpu = device()
    model = model.eval().to(gpu)
    # Keep independent tiles small and include neighboring pixels around each tile.
    # Downsample tiles to the requested size before assembling the output.
    source_width, source_height = image.size
    output = Image.new("RGB", (width, height))
    tile, padding, magnification = 224, 24, model.scale
    for y in range(0, source_height, tile):
        for x in range(0, source_width, tile):
            right, bottom = min(x + tile, source_width), min(y + tile, source_height)
            left_pad, top_pad = max(0, x - padding), max(0, y - padding)
            box = (left_pad, top_pad, min(right + padding, source_width),
                   min(bottom + padding, source_height))
            pixels = np.asarray(image.crop(box).convert("RGB"))
            tensor = torch.from_numpy(pixels.copy()).to(gpu, dtype=torch.float32)
            tensor = tensor.permute(2, 0, 1).unsqueeze(0) / 255
            with torch.inference_mode():
                enhanced = model(tensor)[0].permute(1, 2, 0)
                enhanced = enhanced.clamp(0, 1).mul(255).round().to(torch.uint8).cpu().numpy()
            dx = round(x * width / source_width)
            dy = round(y * height / source_height)
            dw = round(right * width / source_width) - dx
            dh = round(bottom * height / source_height) - dy
            sample = tuple(value * magnification for value in
                           (x - left_pad, y - top_pad, right - left_pad, bottom - top_pad))
            output.paste(Image.fromarray(enhanced).resize((dw, dh), Image.Resampling.LANCZOS, box=sample), (dx, dy))
    if "A" in image.getbands():
        output.putalpha(image.getchannel("A").resize((width, height), Image.Resampling.LANCZOS))
    return output


def extend(image, width, height, models, prompt=None, seed=None, leading_extension=None, steps=26):
    from PIL import Image, ImageCms
    import torch
    from diffusers import StableDiffusionXLInpaintPipeline

    horizontal = width > image.width and height == image.height
    vertical = height > image.height and width == image.width
    if not (horizontal or vertical):
        raise ValueError("Extend Edges needs to add room along one axis.")

    added = width - image.width if horizontal else height - image.height
    before = added // 2 if leading_extension is None else leading_extension
    if not 0 <= before <= added:
        raise ValueError("The original image must stay inside the extended canvas.")

    gpu = device()
    if gpu == "cpu" and os.name == "nt":
        import ctypes
        class Memory(ctypes.Structure):
            _fields_ = [("length", ctypes.c_ulong), ("load", ctypes.c_ulong)] + [(name, ctypes.c_ulonglong) for name in ("total", "available", "page_total", "page_available", "virtual_total", "virtual_available", "extended")]
        memory = Memory()
        memory.length = ctypes.sizeof(memory)
        ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(memory))
        if memory.total < 30 * 1024 ** 3:
            raise RuntimeError("CPU edge generation needs at least 32 GB RAM. Use an NVIDIA CUDA GPU, or choose Fade Edges to Black on this PC.")
    progress(f"Using {gpu.upper()} for edge generation…")
    directory = prepare_outpaint(models)
    progress("Loading the SDXL edge-extension model…")
    pipe = StableDiffusionXLInpaintPipeline.from_pretrained(
        directory, local_files_only=True, use_safetensors=True, variant="fp16",
        torch_dtype=torch.float16 if gpu == "cuda" else torch.float32,
    )
    if gpu == "cuda":
        pipe.enable_model_cpu_offload()
    else:
        pipe = pipe.to("cpu")
    pipe.enable_vae_tiling()
    pipe.set_progress_bar_config(disable=True)

    # Keep model input in sRGB and the output in the original color space.
    # Only generated pixels are transformed back. The source is copied as-is.
    embedded = image.info.get("icc_profile")
    profile = ImageCms.ImageCmsProfile(BytesIO(embedded)) if embedded else None
    srgb = ImageCms.createProfile("sRGB")
    original_rgb = image.convert("RGB")
    working = (ImageCms.profileToProfile(original_rgb, profile, srgb, outputMode="RGB")
               if profile else original_rgb)
    result = Image.new(image.mode, (width, height))
    cross = image.height if horizontal else image.width
    result.paste(image, (before, 0) if horizontal else (0, before))
    max_step = max(1, int(cross * 0.94))
    seed = secrets.randbits(32) if seed is None else seed
    negative = (
        "new people, duplicate subject, person, face, crowd, body, indoor room, second photograph, collage, "
        "text, fake lettering, watermark, frame, obvious border, mismatched perspective, distorted geometry"
    )
    description = (prompt.strip() if prompt else "") or (
        "Seamlessly continue the existing background, matching the perspective, shapes, lighting, "
        "and colors. Keep the new area free of people and lettering."
    )
    work_size = (1152, 704) if horizontal else (704, 1152)

    for side, remaining, start in (
        (("left" if horizontal else "top"), before, before),
        (("right" if horizontal else "bottom"), added - before, before + (image.width if horizontal else image.height)),
    ):
        leading = side in ("left", "top")
        context_image = working
        while remaining:
            amount = min(remaining, max_step)
            progress(f"Extending the {side} edge…")
            band = generate_band(pipe, context_image, side, amount, work_size, description, negative, seed, steps)
            seed += 1
            # Make this band available as context when the layout needs another pass.
            if horizontal:
                merged = Image.new("RGB", (amount + context_image.width, cross))
                merged.paste(context_image, (amount if leading else 0, 0))
                merged.paste(band, (0 if leading else context_image.width, 0))
            else:
                merged = Image.new("RGB", (cross, amount + context_image.height))
                merged.paste(context_image, (0, amount if leading else 0))
                merged.paste(band, (0, 0 if leading else context_image.height))
            context_image = merged
            if profile:
                band = ImageCms.profileToProfile(band, srgb, profile, outputMode="RGB")
            if leading:
                start -= amount
            result.paste(band.convert(image.mode), (start, 0) if horizontal else (0, start))
            if not leading:
                start += amount
            remaining -= amount
    return result


def generate_band(pipe, source, side, amount, work_size, description, negative, seed, steps=26):
    import numpy as np
    from PIL import Image, ImageDraw
    import torch

    horizontal = side in ("left", "right")
    leading = side in ("left", "top")
    axis = 1 if horizontal else 0
    cross = source.height if horizontal else source.width
    source_span = source.width if horizontal else source.height
    work_cross = work_size[1 if horizontal else 0]
    work_span = work_size[0 if horizontal else 1]
    pad = min(work_span - 1, max(1, round(amount * work_cross / cross)))
    context_span = work_span - pad
    selected = min(source_span, max(1, round(context_span * cross / work_cross)))
    context_pixels = min(context_span, max(1, round(selected * work_cross / cross)))
    low = 0 if leading else source_span - selected
    crop = (low, 0, low + selected, cross) if horizontal else (0, low, cross, low + selected)
    context_size = (context_pixels, work_cross) if horizontal else (work_cross, context_pixels)
    context = source.crop(crop).resize(context_size, Image.Resampling.LANCZOS)
    padding = [(0, 0)] * 3
    missing_context = context_span - context_pixels
    padding[axis] = (pad, missing_context) if leading else (missing_context, pad)
    canvas = Image.fromarray(np.pad(np.asarray(context), padding, mode="edge"))
    mask = Image.new("L", work_size)
    draw = ImageDraw.Draw(mask)
    split = pad if leading else context_span
    overlap = min(8, max(0, (context_pixels - 1) // 2))
    start, stop = (0, split + overlap) if leading else (split - overlap, work_span)
    box = (start, 0, stop - 1, work_cross - 1) if horizontal else (0, start, work_cross - 1, stop - 1)
    draw.rectangle(box, fill=255)

    generated = pipe(
        prompt=f"Natural continuation of the same scene at the {side} edge. {description}",
        negative_prompt=negative,
        image=canvas, mask_image=mask, width=work_size[0], height=work_size[1],
        num_inference_steps=steps, strength=0.99, guidance_scale=7.0,
        original_size=work_size[::-1], target_size=work_size[::-1],
        generator=torch.Generator(device="cpu").manual_seed(seed),
    ).images[0]
    start, stop = (0, split) if leading else (split, work_span)
    crop = (start, 0, stop, work_cross) if horizontal else (0, start, work_cross, stop)
    size = (amount, cross) if horizontal else (cross, amount)
    band = generated.crop(crop).resize(size, Image.Resampling.LANCZOS)
    match_join(band, source, horizontal, leading)
    return band


def match_join(band, source, horizontal, leading):
    import numpy as np
    from PIL import Image

    # Match the boundary color and taper the correction into the generated pixels.
    cross = band.height if horizontal else band.width
    length = band.width if horizontal else band.height
    source_length = source.width if horizontal else source.height
    depth = min(length, 68)
    start, stop = (length - depth, length) if leading else (0, depth)
    box = (start, 0, stop, cross) if horizontal else (0, start, cross, stop)
    index = 0 if leading else source_length - 1
    edge = (index, 0, index + 1, cross) if horizontal else (0, index, cross, index + 1)
    strip = np.asarray(band.crop(box), dtype=np.float32)
    guide = np.asarray(source.crop(edge), dtype=np.float32)
    boundary = np.take(strip, [-1 if leading else 0], axis=1 if horizontal else 0)
    weights = np.linspace(1, 0, depth, endpoint=False, dtype=np.float32) ** 2
    if leading:
        weights = weights[::-1]
    weights = weights.reshape((1, depth, 1) if horizontal else (depth, 1, 1))
    corrected = np.clip(np.rint(strip + (guide - boundary) * weights), 0, 255).astype(np.uint8)
    band.paste(Image.fromarray(corrected), box[:2])


def main():
    from PIL import Image

    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["enhance", "extend"])
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("models", type=Path)
    parser.add_argument("width", type=int)
    parser.add_argument("height", type=int)
    parser.add_argument("--steps", type=int, default=26, choices=range(1, 51))
    parser.add_argument("--cpu", action="store_true")
    parser.add_argument("--prompt")
    parser.add_argument("--seed", type=int)
    parser.add_argument("--leading-extension", type=int)
    args = parser.parse_args()
    if args.cpu:
        os.environ["SCREENSPAN_AI_DEVICE"] = "cpu"
    if args.width <= 0 or args.height <= 0 or args.width * args.height > MAX_PIXELS:
        parser.error("The requested image exceeds the 64-megapixel local AI limit.")
    with Image.open(args.input) as source:
        mode = "RGBA" if "A" in source.getbands() else "RGB"
        image = source.convert(mode)
        profile = image.info.get("icc_profile")
    if args.action == "enhance":
        result = enhance(image, args.width, args.height, args.models)
    else:
        result = extend(image, args.width, args.height, args.models, args.prompt, args.seed, args.leading_extension, args.steps)
    result.save(args.output, format="PNG", icc_profile=profile)


if __name__ == "__main__":
    main()
