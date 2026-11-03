#!/usr/bin/env python3
"""Normalize a control-vector path for llama.cpp's --control-vector-scaled flag.

The flag's grammar is `FNAME:SCALE[,FNAME:SCALE,...]`: llama.cpp splits on ':'
and ',' and requires each pair to have exactly two fields (b12024 rejects
`D:/x.gguf:4` with "control-vector-scaled format: FNAME:SCALE"). A FNAME that
itself contains ':' or ',' can therefore never be passed. The fix is to express
the vector as a *same-drive relative path* — llama-server resolves it against
its working directory, and a relative path needs no drive colon (the trick
experiments/steer_sweep.py already used; P0 gate C1 makes it the documented
contract for every launcher).

Used by tools/llm/serve.sh and tools/llm/serve.ps1 so the rule lives in one
tested place. CLI: `python cvec_path.py --platform windows --cwd 'D:\\proj' --scale 4 -- 'D:\\v.gguf'`
prints the normalized path and the final flag argument.
"""
import argparse
import ntpath
import os
import sys



class PathError(ValueError):
    """User-facing error: the vector path cannot be made flag-safe."""


def _is_drive_rooted(path):
    """True for `X:\\foo` / `X:/foo` (drive letter + separator)."""
    return len(path) >= 3 and path[0].isalpha() and path[1] == ":" and path[2] in "\\/"


def _is_drive_relative(path):
    """True for `X:foo` (drive letter, colon, no separator) — ambiguous."""
    return len(path) >= 3 and path[0].isalpha() and path[1] == ":" and path[2] not in "\\/"


def parse_scale(text):
    """Validate the dose string; return it canonicalized ('4' stays '4', '4.0' -> '4.0')."""
    try:
        val = float(text)
    except ValueError:
        raise PathError(f"invalid --control-vector scale {text!r}: must be a number (e.g. 0, 1.5, 4)")
    if val != val or val in (float("inf"), float("-inf")):
        raise PathError(f"invalid --control-vector scale {text!r}: NaN/infinity is not a dose")
    return text


def norm_path(path, cwd=None, platform=None):
    """Return a FNAME-safe path (no ':' or ',') or raise PathError.

    - POSIX: any ':' is fatal (filenames cannot be made flag-safe); all other
      paths pass through unchanged.
    - Windows: `X:/abs/path` becomes a forward-slash path relative to `cwd`
      (must be the same drive); `X:rel` is rejected as ambiguous; UNC
      `\\\\srv\\share` and plain relative paths pass through with '\\' -> '/';
      a path whose *filename* literally contains ':' or ',' is fatal.
    """
    platform = platform or ("windows" if os.name == "nt" else "posix")
    if platform == "posix":
        if ":" in path or "," in path:
            raise PathError(
                f"control vector path {path!r} contains ':' or ',' — the "
                "--control-vector-scaled FNAME:SCALE parser cannot accept it; "
                "rename the file or pass a path without ':'/','")
        return path

    if platform != "windows":
        raise PathError(f"unknown platform {platform!r} (windows|posix)")

    np = path.replace("\\", "/")
    if _is_drive_relative(np):
        raise PathError(
            f"ambiguous drive-relative path {path!r}: 'X:file' means 'file on "
            "drive X's saved directory', not a path. Pass the full 'X:/...' "
            "absolute path instead.")
    if _is_drive_rooted(np):
        cwd = cwd or os.getcwd()
        cnp = cwd.replace("\\", "/")
        if not (_is_drive_rooted(cnp) or cnp.startswith("//")):
            raise PathError(
                f"cannot compute drive for cwd {cwd!r}; pass --cwd with a "
                "Windows path")
        # Same drive? ntpath.relpath raises ValueError across drives.
        try:
            rel = ntpath.relpath(ntpath.normpath(np), ntpath.normpath(cnp))
        except ValueError:
            raise PathError(
                f"control vector {path!r} is on a different drive than the "
                f"server working directory {cwd!r}; llama.cpp cannot take an "
                "absolute drive path here. Pass a same-drive relative path, or "
                "launch serve.sh/serve.ps1 from the vector's drive.")
        rel = rel.replace("\\", "/")
        if ":" in rel or "," in rel:
            # The filename itself (e.g. an ADS suffix 'v.gguf:stream') carries
            # a ':' — no spelling of it is flag-safe.
            raise PathError(
                f"control vector path {path!r} contains ':' or ',' — the "
                "--control-vector-scaled FNAME:SCALE parser cannot accept it; "
                "rename the file or pass a path without ':'/','")
        return rel
    # UNC or relative path — normalize slashes and '..' segments for display.
    out = ntpath.normpath(np).replace("\\", "/")
    if ":" in out or "," in out:
        raise PathError(
            f"control vector path {path!r} contains ':' or ',' — the "
            "--control-vector-scaled FNAME:SCALE parser cannot accept it; "
            "rename the file or pass a path without ':'/','")
    return out


def flag_arg(path, scale, cwd=None, platform=None):
    """Return the full `--control-vector-scaled` argument 'FNAME:SCALE'."""
    return f"{norm_path(path, cwd, platform)}:{parse_scale(scale)}"


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Normalize a control-vector path for --control-vector-scaled (P1.23).",
        epilog="Exit 0 prints NORMALIZED + FLAG lines; exit 2 prints the reason to stderr.")
    ap.add_argument("path", help="control vector .gguf path (relative or absolute)")
    ap.add_argument("--scale", default="1", help="dose appended after ':' (default 1)")
    ap.add_argument("--platform", choices=["windows", "posix"],
                    default="windows" if os.name == "nt" else "posix",
                    help="path flavor of --path/--cwd (auto-detected)")
    ap.add_argument("--cwd", help="working dir the server resolves relative "
                                  "paths against (default: process cwd)")
    opt = ap.parse_args(argv)
    try:
        norm = norm_path(opt.path, opt.cwd, opt.platform)
        flag = f"{norm}:{parse_scale(opt.scale)}"
    except PathError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2
    print(norm)
    print(flag)
    return 0


if __name__ == "__main__":
    sys.exit(main())
