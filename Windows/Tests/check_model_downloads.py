"""Check model download integrity without installing AI packages or fetching weights."""
import hashlib
import importlib.util
from pathlib import Path
import sys
import tempfile
import types

spec = importlib.util.spec_from_file_location(
    "worker", Path(__file__).resolve().parents[1] / "LocalAI/image_tools.py")
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)
worker.MODEL_FILES = ("unet/weights",)
weights = b"verified weights"
worker.MODEL_DIGESTS = {"unet/weights": hashlib.sha256(weights).hexdigest()}
calls = []


def fetch(**kwargs):
    calls.append(kwargs)
    path = Path(kwargs["local_dir"]) / kwargs["filename"]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(weights)
    return str(path)


sys.modules["huggingface_hub"] = types.SimpleNamespace(hf_hub_download=fetch)
with tempfile.TemporaryDirectory() as root:
    directory = worker.prepare_outpaint(Path(root))
    assert len(calls) == 1
    assert calls[-1]["revision"] == worker.REVISION
    assert calls[-1]["token"] is False
    worker.prepare_outpaint(Path(root))
    assert len(calls) == 1, "Valid cached weights should not be downloaded again"
    (directory / worker.MODEL_FILES[0]).write_bytes(b"corrupted")
    worker.prepare_outpaint(Path(root))
    assert len(calls) == 2 and calls[-1]["force_download"] is True
    worker.MODEL_DIGESTS["unet/weights"] = "0" * 64
    try:
        worker.prepare_outpaint(Path(root))
        raise AssertionError("Corrupt model accepted")
    except RuntimeError as error:
        assert "Integrity" in str(error)
print("Passed model download checks: pinned revision, anonymous download, cache reuse, corruption repair, digest rejection.")
