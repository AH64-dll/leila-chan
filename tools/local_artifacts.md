# Local artifacts

Large / machine-specific files that live only in the main tree `D:/lila` and are gitignored
(see README "Local artifacts"). Copied from the design machine's `E:` drive on 2026-11-02 (task P0.02);
the "Source on E:" paths below are relative to the project checkout there.
**E: is nearly full — read-only, never write to it.**

| Path in `D:/lila` | Size | SHA-256 | Source on E: |
|---|---|---|---|
| `models/Qwen3.5-4B-Q4_K_M.gguf` | 2,740,937,888 B (2.55 GiB) | `00fe7986ff5f6b463e62455821146049db6f9313603938a70800d1fb69ef11a4` | `models/Qwen3.5-4B-Q4_K_M.gguf` |
| `experiments/steering/evil_qwen_unit.gguf` | 20,736 B | `5a61adffca0c49aafea040be80d56c0356a6ad76db225ccde14cfd09a25cf9b5` | `experiments/steering/evil_qwen_unit.gguf` |
| `assets/audio/_raw/` | 372,520,560 B (355 MiB), 754 files | manifest `cbbbf468acdced6dfa10d692a6f2a27f9210546151f0e4b68676095ee5098b87` | `assets/audio/_raw/` |
| `art/_review/` | 1,088,610 B, 5 files | manifest `cc8529cb78a19f0d129f883da385c21909f5409291a6a80abfdc16731e2a1ff8` | `art/_review/` |
| `art/leila_legacy_1x/` | 6,993,128 B, 67 files | manifest `857afa86f338b939aafbaee35e776d41f553486f43a8c053546065293f58f9be` | `art/leila_legacy_1x/` |

For directories the hash is the SHA-256 of the sorted per-file `sha256sum` manifest
(`cd <dir> && find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum`). The manifest itself
is a text file of `<hash> *<relpath>` lines; diffing it against a manifest built the same way on the
source proves every file is byte-identical.

## Deliberately not copied

| Source on E: | Why |
|---|---|
| `tools/llama/llama-b12024/` | Linux ELF `.so` binaries — unusable on Windows. P0.03 fetches the Windows CUDA build of llama.cpp b12024 instead. |
| `models/.cache/` | 12 KB HuggingFace download cache (locks/metadata), not an artifact. |

## Re-verify (Git Bash, from `D:/lila`)

```bash
# point SRC at the project checkout on the design machine's E: drive
SRC="/e/<project-checkout>"
sha256sum "$SRC/models/Qwen3.5-4B-Q4_K_M.gguf" models/Qwen3.5-4B-Q4_K_M.gguf \
          "$SRC/experiments/steering/evil_qwen_unit.gguf" experiments/steering/evil_qwen_unit.gguf
for d in assets/audio/_raw art/_review art/leila_legacy_1x; do
  diff <(cd "$SRC/$d" && find . -type f -print0 | sort -z | xargs -0 sha256sum) \
       <(cd "$d"    && find . -type f -print0 | sort -z | xargs -0 sha256sum) \
    && echo "$d OK"
done
git check-ignore -v models/Qwen3.5-4B-Q4_K_M.gguf experiments/steering/evil_qwen_unit.gguf \
                    assets/audio/_raw art/_review art/leila_legacy_1x
```
