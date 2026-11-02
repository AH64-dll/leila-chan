"""Deliberately failing test — CI red-run demo for the P0.07 handoff.

This file lives only on the throwaway branch task/P0.07-ci-red and is never merged.
"""


def test_deliberate_failure() -> None:
    assert False, "deliberate failure to prove CI goes red"
