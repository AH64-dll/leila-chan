"""P3.06 — docs/01 §4's path sprite pools vs. the shipped casting table.

The acceptance criterion is "path sprite pools match docs/01 §4", so this test
reads the documents instead of a transcription: docs/01 §4.1–§4.6's own
`- **Sprites:**` line per path, and docs/03 §3.2's override rows. A silent edit to
either doc or to `data/casting.json` fails here before it reaches a build.
"""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOC_01 = (ROOT / "docs" / "01_GAME_DESIGN.md").read_text(encoding="utf-8")
CASTING = json.loads((ROOT / "data" / "casting.json").read_text(encoding="utf-8"))

# docs/01 §4's subsections, in doc order.
PATHS = ["YANDERE", "SPLIT", "TSUN", "HOLLOW", "AWAKE", "ANCHOR"]
SPRITE_ID = re.compile(r"\b\d{2}\b")

# docs/03 §3.2, transcribed: the faces each path's row names that docs/01 §4's pool
# omits. They ship (the resolver spec is explicit per feeling) but must stay counted,
# never silent — see the P3.06 handoff's DCR.
DOC_03_EXTRAS = {
    "YANDERE": {"22", "28"},  # joy→22, suspicious→28; §4.1 lists 01, 06, 24, 21, 30, 27
    "SPLIT": set(),  # 01/17 swap pair, 16 and 19 all sit in the §4.2 pool
    "TSUN": {"16", "18", "20"},  # disgusted→18; break afraid→20, crying→16
    "HOLLOW": set(),  # drift 23/10/12/14 is the §4.4 pool
    "AWAKE": {"26"},  # surprised→26; §4.5 lists 11 instead
    "ANCHOR": {"22"},  # relapse 26/22; §4.6 gives the spikes as 26 / 21
}


def _doc_section(text: str, heading_prefix: str) -> str:
    """One markdown section body, from its heading to the next heading."""
    start = text.index(heading_prefix)
    rest = text[start:]
    end = re.search(r"\n#{2,4} ", rest)
    return rest[: end.start()] if end else rest


def doc_pool(path: str) -> list[str]:
    """docs/01 §4.x's `- **Sprites:**` line, as sprite ids in doc order.

    The line is prose ("01 ↔ 17 rapid swaps, 19, 15, 16, 13", "…then sudden spikes of
    26 / 21 she recovers from"), so every two-digit token on it is a face.
    """
    section = _doc_section(DOC_01, f"### 4.{PATHS.index(path) + 1} ")
    line = next(line for line in section.splitlines() if line.startswith("- **Sprites:**"))
    return SPRITE_ID.findall(line)


def rule_faces(spec: dict) -> set[str]:
    """Every sprite id a path's rule tables can name (docs/03 §3.2 + docs/01 §4 pool)."""
    faces = set(spec["pool"])
    faces.update(spec.get("override", {}).values())
    faces.update(pair[0] for pair in spec.get("flagged", {}).values())
    faces.update(spec.get("break", {}).get("sprite", {}).values())
    faces.update(spec[key] for key in ("idealize", "devalue") if key in spec)
    faces.update(spec.get("drift", {}).values())
    relapse = spec.get("relapse", {})
    faces.update(relapse.get("spike", {}).values())
    if "crisis" in relapse:
        faces.add(relapse["crisis"]["sprite"])
    if "then" in relapse:
        faces.add(relapse["then"])
    return faces


def test_path_pools_are_docs_01_section_4() -> None:
    paths = CASTING["paths"]
    assert set(paths) == set(PATHS), "casting.paths is not docs/01 §4's six paths"
    for path in PATHS:
        assert paths[path]["pool"] == doc_pool(path), (
            f"{path}'s pool drifted from docs/01 §4.{PATHS.index(path) + 1}: "
            f"table {paths[path]['pool']} vs doc {doc_pool(path)}"
        )


def test_pool_faces_are_exported_sprites() -> None:
    sprites = set(CASTING["sprites"])
    for path in PATHS:
        pool = CASTING["paths"][path]["pool"]
        assert len(pool) == len(set(pool)), f"{path}'s pool repeats a face"
        missing = sorted(set(pool) - sprites)
        assert not missing, f"{path}'s pool names unexported sprites {missing}"


def test_docs_03_extras_are_exactly_the_documented_overrides() -> None:
    for path in PATHS:
        spec = CASTING["paths"][path]
        assert set(spec["docs_03_extras"]) == DOC_03_EXTRAS[path], (
            f"{path}'s docs/03 extras drifted from docs/03 §3.2's transcribed row"
        )
        # the field is load-bearing, not decoration: it is exactly the rule faces that
        # sit outside the path's docs/01 §4 pool
        outside = rule_faces(spec) - set(spec["pool"])
        assert outside == set(spec["docs_03_extras"]), (
            f"{path}'s rules name {sorted(outside)} outside its pool, "
            f"but docs_03_extras says {sorted(spec['docs_03_extras'])}"
        )
