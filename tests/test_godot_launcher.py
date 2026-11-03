"""Regression test for the Windows Godot launcher (P1.30).

Windows PowerShell 5.1 turns a native process's stderr into an ErrorRecord.
tools/godot.ps1 set ErrorActionPreference=Stop during the native invocation, so
an expected Godot WARNING aborted a passing run with NativeCommandError. The
PowerShell probe runs both resolution branches (LEILA_GODOT and the pinned
binary) with a compiled stub that writes to stderr and exits 0 or 7.
"""

import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
PROBE = ROOT / "tests" / "launcher" / "godot_launcher_probe.ps1"
LAUNCHER = ROOT / "tools" / "godot.ps1"

pytestmark = pytest.mark.skipif(
    sys.platform != "win32",
    reason="PowerShell 5.1 native-stderr behavior is Windows-only",
)


def test_launcher_survives_native_stderr_and_preserves_exit_code() -> None:
    powershell = shutil.which("powershell")
    assert powershell, "Windows PowerShell (powershell.exe) is required"

    result = subprocess.run(
        [
            powershell,
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(PROBE),
            "-Launcher",
            str(LAUNCHER),
        ],
        capture_output=True,
        text=True,
        timeout=120,
    )
    output = result.stdout + result.stderr
    assert result.returncode == 0, output
    for case in (
        "LEILA_GODOT warning + exit 0",
        "LEILA_GODOT stderr + exit 7",
        "resolved binary warning + exit 0",
        "resolved binary stderr + exit 7",
        "missing resolved binary fails closed",
        "missing LEILA_GODOT fails closed",
    ):
        assert f"PASS  {case}" in output, output
    assert "PROBE: OK" in output, output
