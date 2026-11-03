"""Policy tests for .github/workflows/*.{yml,yaml} (P1.24 C3, P1.25 C4).

The workflow files are parsed as YAML, not grepped: a missing key is what
these guards exist to catch.
- P0 gate C3 (P1.24): every job carries an explicit timeout-minutes so a
  stalled step (curl, godot --import) cannot burn the 6-hour runner default.
- P0 gate C4 (P1.25): every actions/checkout step sets persist-credentials: false
  so the token is not persisted in .git/config when repo scripts run.
- P1.24 CODE-1: both .yml and .yaml workflow extensions are discovered.
"""

from pathlib import Path
import re

import pytest
import yaml
ROOT = Path(__file__).resolve().parent.parent
WORKFLOW_DIR = ROOT / ".github" / "workflows"

# GitHub kills any job at 360 minutes anyway; a declared timeout above that
# bounds nothing. The floor exists only to reject a non-positive placeholder.
MAX_TIMEOUT_MINUTES = 360


def discover_workflow_paths(workflow_dir: Path = WORKFLOW_DIR) -> list[Path]:
    """Return sorted unique .yml and .yaml workflow paths under workflow_dir."""
    return sorted({*workflow_dir.glob("*.yml"), *workflow_dir.glob("*.yaml")})


WORKFLOWS = discover_workflow_paths()


def _workflow_docs(workflow_dir: Path = WORKFLOW_DIR) -> dict[str, dict]:
    docs = {}
    for path in discover_workflow_paths(workflow_dir):
        doc = yaml.safe_load(path.read_text(encoding="utf-8"))
        assert isinstance(doc, dict) and doc.get("jobs"), f"{path.name} has no jobs"
        docs[path.name] = doc
    assert docs, "no workflow files under .github/workflows/"
    return docs


def _validate_job_timeouts(docs: dict[str, dict]) -> None:
    for name, doc in docs.items():
        for job_id, job in doc["jobs"].items():
            timeout = job.get("timeout-minutes")
            assert timeout is not None, f"{name}: job {job_id!r} has no timeout-minutes"
            assert isinstance(timeout, int) and not isinstance(timeout, bool), (
                f"{name}: job {job_id!r} timeout-minutes {timeout!r} is not an int"
            )
            assert 0 < timeout <= MAX_TIMEOUT_MINUTES, (
                f"{name}: job {job_id!r} timeout-minutes {timeout} outside 1..{MAX_TIMEOUT_MINUTES}"
            )


def _is_checkout_uses(uses: object) -> bool:
    if not isinstance(uses, str):
        return False
    action = uses.strip().split("@", 1)[0]
    return action == "actions/checkout" or action.startswith("actions/checkout/")


def _validate_checkout_persist_credentials(docs: dict[str, dict]) -> int:
    checkout_steps = 0
    for name, doc in docs.items():
        for job_id, job in doc["jobs"].items():
            steps = job.get("steps")
            assert isinstance(steps, list) and steps, f"{name}: job {job_id!r} has no steps"
            for idx, step in enumerate(steps):
                assert isinstance(step, dict), f"{name}: job {job_id!r} step {idx} is not a mapping"
                uses = step.get("uses")
                if not _is_checkout_uses(uses):
                    continue
                checkout_steps += 1
                step_label = step.get("name") or f"step[{idx}]"
                with_block = step.get("with")
                assert isinstance(with_block, dict), (
                    f"{name}: job {job_id!r} checkout step {step_label!r} ({uses}) "
                    "is missing a 'with:' mapping for persist-credentials: false"
                )
                assert "persist-credentials" in with_block, (
                    f"{name}: job {job_id!r} checkout step {step_label!r} ({uses}) "
                    "does not set persist-credentials"
                )
                persist = with_block["persist-credentials"]
                assert persist is False, (
                    f"{name}: job {job_id!r} checkout step {step_label!r} ({uses}) "
                    f"must set boolean persist-credentials: false (got {persist!r})"
                )
    assert checkout_steps > 0, "expected at least one actions/checkout step across workflows"
    return checkout_steps


def test_every_job_has_timeout_minutes() -> None:
    _validate_job_timeouts(_workflow_docs())


def test_every_checkout_disables_persisted_credentials() -> None:
    _validate_checkout_persist_credentials(_workflow_docs())


def test_discover_workflow_paths_includes_yml_and_yaml(tmp_path: Path) -> None:
    (tmp_path / "a.yml").write_text(
        "jobs:\n  build:\n    timeout-minutes: 10\n    steps:\n"
        "      - uses: actions/checkout@v7\n        with:\n          persist-credentials: false\n",
        encoding="utf-8",
    )
    (tmp_path / "b.yaml").write_text(
        "jobs:\n  lint:\n    timeout-minutes: 5\n    steps:\n"
        "      - uses: actions/checkout@v7\n        with:\n          persist-credentials: false\n",
        encoding="utf-8",
    )
    (tmp_path / "ignored.txt").write_text("not a workflow\n", encoding="utf-8")

    paths = discover_workflow_paths(tmp_path)
    assert [p.name for p in paths] == ["a.yml", "b.yaml"]
    docs = _workflow_docs(tmp_path)
    assert set(docs.keys()) == {"a.yml", "b.yaml"}
    _validate_job_timeouts(docs)
    assert _validate_checkout_persist_credentials(docs) == 2


@pytest.mark.parametrize(
    ("step_yaml", "expected_msg"),
    [
        (
            "- name: Checkout\n  uses: actions/checkout@v7\n",
            "missing a 'with:' mapping",
        ),
        (
            "- name: Checkout\n  uses: actions/checkout@v7\n  with:\n    fetch-depth: 1\n",
            "does not set persist-credentials",
        ),
        (
            "- name: Checkout\n  uses: actions/checkout@v7\n  with:\n    persist-credentials: true\n",
            "must set boolean persist-credentials: false (got True)",
        ),
        (
            "- name: Checkout\n  uses: actions/checkout@v7\n  with:\n    persist-credentials: 'false'\n",
            "must set boolean persist-credentials: false (got 'false')",
        ),
        (
            "- name: Checkout\n  uses: actions/checkout@v7\n  with:\n    persist-credentials: 0\n",
            "must set boolean persist-credentials: false (got 0)",
        ),
    ],
)
def test_checkout_policy_rejects_missing_or_non_false_persist_credentials(
    step_yaml: str, expected_msg: str
) -> None:
    doc = yaml.safe_load(
        f"jobs:\n  checks:\n    timeout-minutes: 15\n    steps:\n      {step_yaml.replace(chr(10), chr(10) + '      ')}\n"
    )
    with pytest.raises(AssertionError, match=re.escape(expected_msg)):
        _validate_checkout_persist_credentials({"ci.yaml": doc})
