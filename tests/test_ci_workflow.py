"""Policy tests for .github/workflows/*.yml (P1.24, P0 gate C3).

The workflow files are parsed as YAML, not grepped: a missing key is what
these guards exist to catch. P0 gate C3 requires every job to carry an
explicit timeout-minutes so a stalled step (curl, godot --import) cannot
burn the 6-hour runner default.
"""

from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
WORKFLOWS = sorted((ROOT / ".github" / "workflows").glob("*.yml"))

# GitHub kills any job at 360 minutes anyway; a declared timeout above that
# bounds nothing. The floor exists only to reject a non-positive placeholder.
MAX_TIMEOUT_MINUTES = 360


def _workflow_docs() -> dict[str, dict]:
    docs = {}
    for path in WORKFLOWS:
        doc = yaml.safe_load(path.read_text(encoding="utf-8"))
        assert isinstance(doc, dict) and doc.get("jobs"), f"{path.name} has no jobs"
        docs[path.name] = doc
    assert docs, "no workflow files under .github/workflows/"
    return docs


def test_every_job_has_timeout_minutes() -> None:
    for name, doc in _workflow_docs().items():
        for job_id, job in doc["jobs"].items():
            timeout = job.get("timeout-minutes")
            assert timeout is not None, f"{name}: job {job_id!r} has no timeout-minutes"
            assert isinstance(timeout, int) and not isinstance(timeout, bool), (
                f"{name}: job {job_id!r} timeout-minutes {timeout!r} is not an int"
            )
            assert 0 < timeout <= MAX_TIMEOUT_MINUTES, (
                f"{name}: job {job_id!r} timeout-minutes {timeout} outside 1..{MAX_TIMEOUT_MINUTES}"
            )
