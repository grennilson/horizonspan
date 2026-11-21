"""Build the Windows multi-resolution ICO from AppIcon.png on macOS.

Uses Python's standard library and macOS sips; no image packages are required.
Run: python3 Tools/build_windows_icon.py
"""
from pathlib import Path
import struct
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
sizes = (16, 20, 24, 32, 40, 48, 64, 96, 128, 256)
frames = []
with tempfile.TemporaryDirectory(prefix="screenspan-icons-") as temporary:
    for size in sizes:
        path = Path(temporary) / f"icon-{size}.png"
        subprocess.run(["sips", "-z", str(size), str(size),
                        str(root / "AppIcon.png"), "--out", str(path)],
                       check=True, stdout=subprocess.DEVNULL)
        data = path.read_bytes()
        assert data[:8] == b"\x89PNG\r\n\x1a\n"
        assert struct.unpack(">II", data[16:24]) == (size, size)
        frames.append(data)
offset = 6 + 16 * len(frames)
directory = bytearray(struct.pack("<HHH", 0, 1, len(frames)))
for size, data in zip(sizes, frames):
    directory.extend(struct.pack("<BBBBHHII", size % 256, size % 256,
                                 0, 0, 1, 32, len(data), offset))
    offset += len(data)
target = root / "Windows/App/AppIcon.ico"
target.write_bytes(bytes(directory) + b"".join(frames))
print(f"Created {target} with {len(frames)} sizes (16–256 pixels).")
