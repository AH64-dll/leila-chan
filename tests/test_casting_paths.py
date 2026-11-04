"""P3.06 — docs/01 §4's path sprite pools vs. the shipped casting table.

The acceptance criterion is "path sprite pools match docs/01 §4", so this test
reads the documents instead of a transcription: docs/01 §4.1–§4.6's own
`- **Sprites:**` line per path, and the faces each docs/03 §3.2 row names. A
silent edit to either doc or to `data/casting.json` fails here before it reaches
a build.
"""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOC_01 = (ROOT / "docs" / "01_GAME_DESIGN.md").read_text(encoding="utf-8")
DOC_03 = (ROOT / "docs" / "03_EMOTIONS.md").read_text(encoding="utf-8")
CASTING = json.loads((ROOT / "data" / "casting.json").read_text(encoding="utf-8"))

# docs/01 §4's subsections, in doc order. These are the casting keys; docs/03 §3.2
# labels the TSUN path "TSUN-BREAK", so its row is looked up through DOC_03_ROWS.
PATHS = ["YANDERE", "SPLIT", "TSUN", "HOLLOW", "AWAKE", "ANCHOR"]
DOC_03_ROWS = {"TSUN": "TSUN-BREAK"}
SPRITE_ID = re.compile(r"\b\d{2}\b")


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


def doc_03_row(path: str) -> str:
    """docs/03 §3.2's table row for one path, as raw markdown."""
    section = _doc_section(DOC_03, "### 3.2 ")
    label = DOC_03_ROWS.get(path, path)
    return next(line for line in section.splitlines() if line.startswith(f"| {label} "))


def doc_03_faces(path: str) -> set[str]:
    """Every face docs/03 §3.2's row for `path` names ("love→24", "26/22", "then 02")."""
    return set(SPRITE_ID.findall(doc_03_row(path)))


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


def test_docs_03_extras_are_the_documented_overrides() -> None:
    for path in PATHS:
        spec = CASTING["paths"][path]
        documented = doc_03_faces(path)
        assert documented, f"docs/03 §3.2 names no face for {path}: {doc_03_row(path)!r}"
        # docs_03_extras is the docs/03 §3.2 row minus the path's own §4 pool, limited
        # to the faces the rule tables actually act on. The intersection is what keeps
        # DCR 2 visible: docs/03 §3.2's broader SPLIT wording (02/24 and 18/07) is
        # documented but not forced, so it is neither an extra nor an error here.
        documented_rule_faces = (documented & rule_faces(spec)) - set(spec["pool"])
        assert set(spec["docs_03_extras"]) == documented_rule_faces, (
            f"{path}'s docs_03_extras is not docs/03 §3.2's row minus its pool: "
            f"table {sorted(spec['docs_03_extras'])} vs doc {sorted(documented_rule_faces)}"
        )
        # the field is load-bearing, not decoration: it is exactly the rule faces that
        # sit outside the path's docs/01 §4 pool
        outside = rule_faces(spec) - set(spec["pool"])
        assert outside == set(spec["docs_03_extras"]), (
            f"{path}'s rules name {sorted(outside)} outside its pool, "
            f"but docs_03_extras says {sorted(spec['docs_03_extras'])}"
        )
