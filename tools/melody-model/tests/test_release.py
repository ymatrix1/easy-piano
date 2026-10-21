import hashlib

import pytest

from melody_model import release


def man_for(tmp_path, data=b"weights"):
    (tmp_path / "w.onnx").write_bytes(data)
    return {"url": "unused/{file}", "files": {"w.onnx": {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}}}


def test_verify_ok_and_detects_tampering(tmp_path):
    man = man_for(tmp_path)
    assert release.verify(tmp_path, man) == []
    (tmp_path / "w.onnx").write_bytes(b"weightz")
    assert release.verify(tmp_path, man) == ["w.onnx: sha256 mismatch"]
    (tmp_path / "w.onnx").unlink()
    assert release.verify(tmp_path, man) == ["w.onnx: missing"]


def test_fetch_rejects_bad_download(tmp_path, monkeypatch):
    (tmp_path / "src").mkdir()
    man = man_for(tmp_path / "src", b"good")
    monkeypatch.setattr(release.urllib.request, "urlretrieve", lambda url, dest: open(dest, "wb").write(b"evil"))
    with pytest.raises(SystemExit, match="failed verification"):
        release.fetch(tmp_path / "out", man)
    assert not (tmp_path / "out" / "w.onnx").exists()


def test_committed_manifest_is_complete():
    man = release.manifest()
    assert {"decoder.int8.onnx", "heads.int8.onnx", "vocab.json", "meta.json"} <= set(man["files"])
    assert all(len(f["sha256"]) == 64 for f in man["files"].values())
    assert man["training"]["dataset_sha256"] == man["training"]["gate"]["dataset_sha256"]
