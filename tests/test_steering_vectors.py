"""P2.03 — pin the shipped steering control vectors and their dose map.

docs/06 §2 says each path/malice vector ships inside the game pack (10–60 KB) and
that a vector is specific to the shipped GGUF; docs/06 §4 says the prototype
binds it with `--control-vector-scaled`. The GDScript suite
(game/tests/StageSteeringTest.gd) proves the mapping behaviour; this file guards
the artifact a reviewer reads without a Godot build: the files are real small GGUF
containers matching their recorded digest, the map only names dose keys the
schedule actually produces, the unbound keys explain themselves, and no brand
name leaks into a shipped asset name.
"""

import hashlib
import json
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
MAP = json.loads((ROOT / "game" / "data" / "steering" / "vectors.json").read_text(encoding="utf-8"))
DOSE = json.loads((ROOT / "game" / "data" / "steering" / "dose.json").read_text(encoding="utf-8"))
DESIGN = (ROOT / "docs" / "06_STEERING.md").read_text(encoding="utf-8")

# docs/06 §2: malice ~20 KB; the P3.03 path vectors ~111 KB (11 layers × 2560 f32).
DOC_MIN_BYTES = 10 * 1024
DOC_MAX_BYTES = 130 * 1024
GGUF_MAGIC = b"GGUF"
BRAND_TERMS = ["qwen", "alibaba", "evil"]


def shipped(res_path: str) -> Path:
    assert res_path.startswith("res://"), f"vector path must be res://packed, got {res_path!r}"
    return ROOT / "game" / res_path.removeprefix("res://")


def dose_keys() -> set[str]:
    """Every key the dose schedule can emit: stage-row keys plus the weight
    curves' vector names (P3.04 binds those to the locked path)."""
    keys: set[str] = set()
    for row in DOSE["stages"].values():
        keys.update(row)
    keys.update((DOSE.get("weight_curves") or {}).keys())
    return keys

def test_map_is_versioned_and_documented() -> None:
    assert MAP["version"] == 1
    assert "docs/06" in MAP["doc"]
    assert isinstance(MAP["vectors"], dict) and MAP["vectors"]


def test_malice_maps_to_the_shipped_malice_vector() -> None:
    row = MAP["vectors"]["malice"]
    assert row["file"] == "res://data/steering/malice.gguf"
    assert shipped(row["file"]).is_file()


def test_every_vector_key_is_a_dose_key() -> None:
    assert set(MAP["vectors"]) <= dose_keys()


def test_path_mix_is_declared_unbound_not_invented() -> None:
    # The interim weight binds no file (pre-assignment only, P3.04), so the map
    # must declare it unbound rather than silently bind some file.
    assert "path_mix" in MAP["unbound"]
    assert "path_mix" not in MAP["vectors"]
    assert "unassigned" in MAP["unbound"]["path_mix"]
    assert not (set(MAP["unbound"]) & set(MAP["vectors"]))


@pytest.mark.parametrize("name", sorted(MAP["vectors"]))
def test_shipped_vector_is_a_small_gguf_container(name: str) -> None:
    data = shipped(MAP["vectors"][name]["file"]).read_bytes()
    assert data[:4] == GGUF_MAGIC, f"{name} is not a GGUF container"
    assert DOC_MIN_BYTES <= len(data) <= DOC_MAX_BYTES, (
        f"{name} is {len(data)} bytes, outside docs/06 §2's 10–60 KB"
    )


@pytest.mark.parametrize("name", sorted(MAP["vectors"]))
def test_recorded_digest_matches_the_shipped_bytes(name: str) -> None:
    row = MAP["vectors"][name]
    digest = hashlib.sha256(shipped(row["file"]).read_bytes()).hexdigest()
    assert digest == row["sha256"], f"{name} was rebuilt without updating vectors.json"


@pytest.mark.parametrize("name", sorted(MAP["vectors"]))
def test_every_vector_records_its_provenance(name: str) -> None:
    row = MAP["vectors"][name]
    for field in ("built_by", "neurons", "model", "doc"):
        assert row.get(field), f"{name} is missing provenance field {field!r}"
    # The builder script is the documented way to rebuild it (docs/06 §5).
    script = row["built_by"].split()[0]
    assert (ROOT / script).is_file(), f"{name} names a builder that does not exist: {script}"
    assert str(row["model"]) in DESIGN or row["model"].endswith(".gguf")


@pytest.mark.parametrize("name", sorted(MAP["vectors"]))
def test_no_brand_name_in_a_shipped_asset_name(name: str) -> None:
    filename = Path(MAP["vectors"][name]["file"]).name.lower()
    for term in BRAND_TERMS:
        assert term not in filename, f"shipped vector name carries {term!r}: {filename}"


def test_local_experiment_copy_matches_when_present() -> None:
    # The experiment artifact is a local-only file (gitignored); when it exists,
    # the shipped copy must be the same bytes.
    source = ROOT / "experiments" / "steering" / "evil_qwen_unit.gguf"
    if not source.exists():
        pytest.skip("local experiment vector not present")
    shipped_bytes = shipped(MAP["vectors"]["malice"]["file"]).read_bytes()
    assert hashlib.sha256(source.read_bytes()).hexdigest() == hashlib.sha256(
        shipped_bytes
    ).hexdigest()


def test_vector_map_documents_that_the_dose_is_a_launch_flag() -> None:
    assert "--launch flag" in MAP["doc"] or "launch flag" in MAP["doc"]
    assert "docs/06 §4" in MAP["doc"]
