"""P3.03 — pin the shipped path vectors, their manifest and the tooling.

The model-dependent artefacts (the 200-pair residual means) are regenerable and
gitignored; what ships is six small control-vector .gguf files plus
`paths.json`. These tests check the shipped bytes without a model: the GGUF
layout the llama.cpp loader expects, unit norms per layer, the layer range, the
scale convention, the provenance hashes and the blind-read keep/fallback rule.
They also exercise the builder and the TSV preparer on synthetic data.
"""

import hashlib
import json
import subprocess
import sys
from pathlib import Path

import gguf
import numpy as np
import pytest

ROOT = Path(__file__).resolve().parent.parent
STEERING = ROOT / "game" / "data" / "steering"
MANIFEST = STEERING / "paths.json"
TRAITS = ["possessive", "unstable", "contempt", "hollow", "aware", "lucid"]
LAYER_LO, LAYER_HI = 10, 20
N_EMBD = 2560
KEEP_THRESHOLD = 0.70


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _manifest() -> dict:
    assert MANIFEST.is_file(), "P3.03 manifest game/data/steering/paths.json is missing"
    return json.loads(MANIFEST.read_text(encoding="utf-8"))


def test_manifest_ships_six_vectors() -> None:
    manifest = _manifest()
    assert manifest["task"] == "P3.03"
    assert "docs/06" in manifest["doc"]
    assert manifest["layers"] == f"{LAYER_LO}-{LAYER_HI}"
    assert list(manifest["vectors"]) == TRAITS
    for trait in TRAITS:
        row = manifest["vectors"][trait]
        assert row["file"] == f"res://data/steering/{trait}.gguf"
        assert row["layers"] == f"{LAYER_LO}-{LAYER_HI}"
        assert row["n_embd"] == N_EMBD
        assert row["pairs"] == 200
        assert row["mean_diff_norm"] and len(row["mean_diff_norm"]) == LAYER_HI - LAYER_LO + 1
        assert row["pair_source"] == f"tools/steering/pairs/{trait}.jsonl"


def test_each_vector_is_the_unit_direction_per_layer() -> None:
    manifest = _manifest()
    for trait in TRAITS:
        path = STEERING / f"{trait}.gguf"
        assert path.is_file(), f"{path} missing"
        reader = gguf.GGUFReader(str(path))
        assert int(reader.fields["controlvector.layer_count"].contents()) == 32
        assert str(reader.fields["controlvector.model_hint"].contents()) == "qwen35"
        names = [tensor.name for tensor in reader.tensors]
        assert names == [f"direction.{layer}" for layer in range(LAYER_LO, LAYER_HI + 1)]
        for tensor in reader.tensors:
            vector = tensor.data
            assert vector.shape == (N_EMBD,), tensor.name
            assert vector.dtype == np.float32
            assert np.isfinite(vector).all(), tensor.name
            norm = float(np.linalg.norm(vector))
            assert abs(norm - 1.0) < 1e-5, f"{trait} {tensor.name} norm {norm}"
        assert _sha256(path) == manifest["vectors"][trait]["sha256"], trait


def test_scale_convention_and_anchor_are_documented() -> None:
    manifest = _manifest()
    convention = manifest["scale_convention"]
    assert "unit" in convention.lower() and "scale" in convention.lower()
    assert manifest["blind_read_scale"] > 0
    assert "lucid" in manifest["anchors"]
    assert "negative scale" in manifest["anchors"]["lucid"].lower()
    # lucid's extracted positive side is the ANCHOR side (docs/06 §2)
    assert "ANCHOR" in manifest["vectors"]["lucid"]["positive_side"]


def test_blind_read_decisions_follow_the_threshold() -> None:
    manifest = _manifest()
    blind = manifest["blind_read"]
    assert blind is not None, "the blind-read separation test has not been run"
    assert blind["threshold"] == pytest.approx(KEEP_THRESHOLD)
    assert manifest["decision"] == {
        trait: blind["conditions"][trait]["decision"] for trait in TRAITS
    }
    for trait in TRAITS:
        row = blind["conditions"][trait]
        assert row["n"] > 0
        expected = "keep" if row["accuracy"] >= KEEP_THRESHOLD else "fallback"
        assert row["decision"] == expected, trait
    assert blind["conditions"]["none"]["decision"] == "baseline"


def test_prepare_pairs_writes_aligned_tsv(tmp_path: Path) -> None:
    out = tmp_path / "tsv"
    subprocess.run(
        [sys.executable, str(ROOT / "tools" / "steering" / "prepare_pairs.py"), "--out-dir", str(out)],
        check=True,
        capture_output=True,
    )
    for trait in TRAITS:
        rows = [
            json.loads(line)
            for line in (ROOT / "tools" / "steering" / "pairs" / f"{trait}.jsonl")
            .read_text(encoding="utf-8").splitlines()
            if line
        ]
        for side, field in (("pos", "positive"), ("neg", "negative")):
            lines = (out / f"{trait}.{side}.tsv").read_text(encoding="utf-8").splitlines()
            assert len(lines) == 200
            for row, line in zip(rows, lines):
                context, reply = line.split("\t")
                assert context == row["context"]
                assert reply == row[field]


def test_builder_normalises_per_layer(tmp_path: Path) -> None:
    means = tmp_path / "means"
    means.mkdir()
    rng = np.random.default_rng(7)
    dim, layers = 16, 3
    planted = np.zeros(dim, dtype=np.float32)
    planted[0] = 1.0
    for trait in TRAITS:
        neg = rng.normal(scale=0.05, size=(200, layers, dim)).astype(np.float32)
        pos = neg + 2.0 * planted
        np.save(means / f"{trait}.pos.npy", pos)
        np.save(means / f"{trait}.neg.npy", neg)

    out = tmp_path / "out"
    subprocess.run(
        [
            sys.executable, str(ROOT / "tools" / "steering" / "build_path_vectors.py"),
            "--means-dir", str(means), "--out-dir", str(out),
            "--manifest", str(out / "paths.json"), "--record", str(tmp_path / "record.json"),
            "--layers", "10-12", "--n-layer", "32",
        ],
        check=True,
        capture_output=True,
    )
    manifest = json.loads((out / "paths.json").read_text(encoding="utf-8"))
    for trait in TRAITS:
        reader = gguf.GGUFReader(str(out / f"{trait}.gguf"))
        assert [tensor.name for tensor in reader.tensors] == [
            f"direction.{layer}" for layer in range(10, 13)
        ]
        for tensor in reader.tensors:
            assert tensor.data.shape == (dim,)
            assert abs(float(np.linalg.norm(tensor.data)) - 1.0) < 1e-5
            assert tensor.data[0] > 0.99, "the planted direction was not recovered"
        assert manifest["vectors"][trait]["pc1_cos_mean"] >= 0.0
