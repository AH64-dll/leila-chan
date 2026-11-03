"""Regression tests for the --control-vector-scaled FNAME:SCALE path contract (P1.23, P0 gate C1).

llama.cpp parses the flag by splitting on ':' and ',' and requiring exactly two
fields, so a FNAME containing ':' (every 'X:/...' Windows absolute path) or ','
can never reach it. tools/llm/cvec_path.py is the single normalizer both
launchers (serve.sh / serve.ps1) shell out to; these tests cover Windows path
forms (emulated via ntpath), POSIX behaviour, scale validation, the CLI both
scripts call, and serve.sh's real argv in --dry-run mode.
"""

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools" / "llm"))
import cvec_path  # noqa: E402

CVEC_PY = ROOT / "tools" / "llm" / "cvec_path.py"
SERVE_SH = ROOT / "tools" / "llm" / "serve.sh"
SERVE_PS1 = ROOT / "tools" / "llm" / "serve.ps1"
LLAMA_DIR = Path(os.environ.get("LEILA_LLAMA_BIN",
                                ROOT / "tools" / "llama" / "llama-b12024"))

CWD = "D:\\proj"  # pretend the server runs from D:\proj

needs_bash = pytest.mark.skipif(not shutil.which("bash"), reason="bash not on PATH")


def flag(path, scale="4", cwd=CWD, platform="windows"):
    return cvec_path.flag_arg(path, scale, cwd=cwd, platform=platform)


# ---------------------------------------------------------------- norm_path


def test_windows_abs_same_drive_becomes_relative():
    assert flag("D:\\proj\\vecs\\v.gguf") == "vecs/v.gguf:4"
    assert flag("D:\\v.gguf") == "../v.gguf:4"  # drive root is one level up from D:\proj


def test_windows_abs_other_dir_walks_up():
    assert flag("D:\\data\\v.gguf", cwd="D:\\proj") == "../data/v.gguf:4"


def test_windows_drive_letter_case_insensitive():
    assert flag("d:\\PROJ\\v.gguf", cwd="D:\\proj") == "v.gguf:4"


def test_windows_relative_and_unc_normalise_slashes():
    assert flag("steering\\v.gguf") == "steering/v.gguf:4"
    assert flag("./steering/v.gguf") == "steering/v.gguf:4"
    assert flag("\\\\server\\share\\v.gguf") == "//server/share/v.gguf:4"


def test_windows_ambiguous_drive_relative_rejected():
    with pytest.raises(cvec_path.PathError, match="ambiguous drive-relative"):
        flag("D:vecs\\v.gguf")


def test_windows_cross_drive_rejected():
    with pytest.raises(cvec_path.PathError, match="different drive"):
        flag("E:\\vecs\\v.gguf", cwd="D:\\proj")


def test_windows_filename_with_colon_rejected():
    # ADS-style or otherwise literal ':' inside the filename: no flag-safe form.
    with pytest.raises(cvec_path.PathError, match="contains ':' or ','"):
        flag("D:\\proj\\a:b.gguf")


def test_windows_filename_with_comma_rejected():
    # ',' separates FNAME:SCALE pairs — silently mis-parses, so it is fatal.
    with pytest.raises(cvec_path.PathError, match="contains ':' or ','"):
        flag("vecs\\a,b.gguf")


def test_posix_relative_and_absolute_pass_through():
    assert flag("steering/v.gguf", platform="posix") == "steering/v.gguf:4"
    assert flag("/home/u/vecs/v.gguf", platform="posix") == "/home/u/vecs/v.gguf:4"


def test_posix_colon_or_comma_rejected():
    with pytest.raises(cvec_path.PathError):
        flag("we:ird.gguf", platform="posix")
    with pytest.raises(cvec_path.PathError):
        flag("a,b.gguf", platform="posix")
    with pytest.raises(cvec_path.PathError):
        flag("D:\\v.gguf", platform="posix")  # drive path on Linux is just a ':' name


def test_windows_space_in_path_ok():
    assert flag("D:\\proj\\my vecs\\v.gguf") == "my vecs/v.gguf:4"


# -------------------------------------------------------------------- scale


@pytest.mark.parametrize("scale", ["0", "1", "4", "-2", "1.5", "4.0", "2e-1"])
def test_valid_scales(scale):
    assert flag("D:\\proj\\v.gguf", scale=scale) == f"v.gguf:{scale}"


@pytest.mark.parametrize("scale", ["foo", "", "nan", "inf", "-inf", "4,5"])
def test_invalid_scales_rejected(scale):
    with pytest.raises(cvec_path.PathError, match="scale"):
        flag("D:\\proj\\v.gguf", scale=scale)


# ---------------------------------------------------------------------- CLI


def run_cli(*args):
    return subprocess.run(
        [sys.executable, str(CVEC_PY), *args],
        capture_output=True, text=True, timeout=15, cwd=ROOT)


def test_cli_windows_drive_path():
    p = run_cli("--platform", "windows", "--cwd", "D:\\proj",
                "--scale", "4", "--", "D:\\proj\\vecs\\v.gguf")
    assert p.returncode == 0, p.stderr
    lines = p.stdout.strip().splitlines()
    assert lines[0] == "vecs/v.gguf"
    assert lines[1] == "vecs/v.gguf:4"


def test_cli_ambiguous_drive_relative_exits_2():
    p = run_cli("--platform", "windows", "--cwd", "D:\\proj", "--", "D:v.gguf")
    assert p.returncode == 2
    assert "ambiguous drive-relative" in p.stderr


def test_cli_bad_scale_exits_2():
    p = run_cli("--platform", "windows", "--scale", "abc", "--", "v.gguf")
    assert p.returncode == 2
    assert "scale" in p.stderr


# -------------------------------------------------------------- serve.sh (POSIX)


def fake_bin_and_model(tmp_path):
    """Executable stub llama-server + empty model under tmp_path."""
    bindir = tmp_path / "llama"
    bindir.mkdir()
    exe = bindir / "llama-server"
    exe.write_text('#!/bin/sh\necho "version: fake (build 0)"\n')
    exe.chmod(0o755)
    (bindir / "llama-server.exe").write_text("stub\n")  # in case OS=Windows_NT leaks
    model = tmp_path / "model.gguf"
    model.write_bytes(b"GGUF")
    return bindir, model


def serve_sh(tmp, *extra, vec=None):
    env = {k: v for k, v in os.environ.items() if k != "OS"}  # force the POSIX leg
    env["LEILA_MODEL"] = str(tmp / "model.gguf")
    env["LEILA_LLAMA_BIN"] = str(tmp / "llama")
    cmd = ["bash", str(SERVE_SH), "--dry-run", *extra]
    if vec is not None:
        cmd += ["--vector", str(vec)]
    return subprocess.run(cmd, capture_output=True, text=True, timeout=20,
                          cwd=tmp, env=env)


def args_line(proc):
    for line in proc.stdout.splitlines():
        if "args:" in line:
            return line
    raise AssertionError(f"no args line in output:\n{proc.stdout}{proc.stderr}")


@needs_bash
def test_serve_sh_relative_and_absolute_vector(tmp_path):
    fake_bin_and_model(tmp_path)
    (tmp_path / "vec.gguf").write_bytes(b"V")
    p = serve_sh(tmp_path, "--scale", "4", vec=tmp_path / "vec.gguf")
    assert p.returncode == 0, p.stderr
    assert "--control-vector-scaled" in args_line(p)
    assert f"{tmp_path}/vec.gguf:4" in args_line(p)


@needs_bash
def test_serve_sh_default_scale_is_1(tmp_path):
    fake_bin_and_model(tmp_path)
    (tmp_path / "vec.gguf").write_bytes(b"V")
    p = serve_sh(tmp_path, vec="vec.gguf")
    assert p.returncode == 0, p.stderr
    assert "vec.gguf:1" in args_line(p)


@needs_bash
def test_serve_sh_colon_filename_rejected(tmp_path):
    fake_bin_and_model(tmp_path)
    try:
        (tmp_path / "a:b.gguf").write_bytes(b"V")
    except OSError:
        pytest.skip("FS refuses ':' filenames")
    p = serve_sh(tmp_path, vec="a:b.gguf")
    assert p.returncode == 1
    assert "control vector rejected" in p.stderr
    assert "':' or ','" in p.stderr


@needs_bash
def test_serve_sh_invalid_scale_rejected(tmp_path):
    fake_bin_and_model(tmp_path)
    (tmp_path / "vec.gguf").write_bytes(b"V")
    p = serve_sh(tmp_path, "--scale", "abc", vec="vec.gguf")
    assert p.returncode == 1
    assert "control vector rejected" in p.stderr


@needs_bash
def test_serve_sh_missing_vector_file(tmp_path):
    fake_bin_and_model(tmp_path)
    p = serve_sh(tmp_path, vec="nope.gguf")
    assert p.returncode == 1
    assert "control vector not found" in p.stderr


@needs_bash
def test_serve_sh_dry_run_does_not_exec(tmp_path):
    fake_bin_and_model(tmp_path)
    p = serve_sh(tmp_path)
    assert p.returncode == 0
    assert "--control-vector-scaled" not in args_line(p)
    assert "dry-run" in p.stdout


# ------------------------------------------------------------ serve.ps1 parity


def test_serve_ps1_uses_shared_normalizer():
    """serve.ps1 must delegate to cvec_path.py (not inline FNAME:SCALE string math)."""
    src = SERVE_PS1.read_text(encoding="utf-8")
    assert "cvec_path.py" in src
    assert '"--platform", "windows"' in src
    assert "DryRun" in src
    # The naive `path:scale` interpolation that broke D: paths must be gone.
    assert '$($Vector):$($VectorScale)' not in src


# ------------------------------------------------- live parser ground truth


def test_llama_server_rejects_colon_fname():
    """The pinned binary itself refuses a FNAME containing ':' — the bug C1 gates on."""
    exe = LLAMA_DIR / ("llama-server.exe" if os.name == "nt" else "llama-server")
    if not exe.is_file():
        pytest.skip("llama.cpp binaries not fetched (local artifact)")
    env = dict(os.environ, LD_LIBRARY_PATH=str(LLAMA_DIR))
    p = subprocess.run(
        [str(exe), "--control-vector-scaled", "a:b:c", "-m", "none.gguf",
         "--port", "0"],
        capture_output=True, text=True, timeout=30, env=env)
    out = p.stdout + p.stderr
    assert "FNAME:SCALE" in out, out
