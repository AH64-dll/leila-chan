#!/usr/bin/env bash
# Collect and validate the evidence for one or more human playtest sessions.
#
#   tools/playtest/collect.sh <session-id> [<session-id> ...]
#   tools/playtest/collect.sh --all
#
# Per session it:
#   1. copies the pristine game transcripts from <bundle>/_userdata/ into <bundle>/raw/;
#   2. merges raw/ into <bundle>/telemetry.jsonl (deduplicated, so a tail that started
#      late or a rotated file loses nothing);
#   3. renders <bundle>/transcript.md — a readable chat log for the reviewer;
#   4. writes <bundle>/manifest.json (file sizes + sha256 + completeness);
#   5. validates the bundle and exits 2 with the exact missing fields if it is incomplete.
#
# It never invents data. Re-running it is safe: merge is idempotent, render and manifest
# are rewritten, and validation is read-only.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
PHASE="${LEILA_PLAYTEST_PHASE:-P2}"
HUMAN_DIR="$ROOT/production/playtests/P2/human"
SCORE="$HERE/score.py"
usage() {
    cat >&2 <<'EOF'
usage: tools/playtest/collect.sh [--sessions-dir DIR] [--no-seed] <session-id> [...]
       tools/playtest/collect.sh [--sessions-dir DIR] [--no-seed] --all

  --sessions-dir DIR  where the bundles live (default: production/playtests/P2/human)
  --no-seed           do not copy the survey/observer/log templates into a bundle that
                      is missing them (default: seed them so nothing is forgotten)
  --phase P2|P3      playtest phase (default: P2, or LEILA_PLAYTEST_PHASE)
  --all               collect every session bundle in the directory (skips _* dirs)
Exit: 0 every bundle complete; 2 at least one incomplete or missing.
EOF
    exit 2
}

SESSIONS_DIR="$HUMAN_DIR"
SEED=1
COLLECT_ALL=0
TARGETS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --sessions-dir) SESSIONS_DIR="${2:?--sessions-dir needs a value}"; shift 2 ;;
        --phase) PHASE="${2:?--phase needs a value}"; shift 2 ;;
        --all) COLLECT_ALL=1; shift ;;
        -h|--help) usage ;;
        -*) echo "collect.sh: unknown argument $1" >&2; usage ;;
        *) TARGETS+=("$1"); shift ;;
    esac
done
if [ "$PHASE" = "P3" ] || [ "$PHASE" = "3" ] || [[ "$SESSIONS_DIR" == *"/P3/"* ]]; then
    HUMAN_DIR="$ROOT/production/playtests/P3/human"
    SCORE="$HERE/score_p3.py"
    if [ "$SESSIONS_DIR" = "$ROOT/production/playtests/P2/human" ]; then
        SESSIONS_DIR="$HUMAN_DIR"
    fi
fi

if [ "$COLLECT_ALL" -eq 1 ]; then
    if [ ${#TARGETS[@]} -gt 0 ]; then
        echo "collect.sh: --all cannot be combined with explicit session ids" >&2
        exit 2
    fi
    while IFS= read -r entry; do
        TARGETS+=("$(basename "$entry")")
    done < <(find "$SESSIONS_DIR" -mindepth 1 -maxdepth 1 -type d ! -name '_*' | sort)
fi

if [ ${#TARGETS[@]} -eq 0 ]; then
    echo "collect.sh: no session id given and no bundle found under $SESSIONS_DIR" >&2
    usage
fi

seed_templates() {
    local bundle="$1"
    [ "$SEED" -eq 1 ] || return 0
    for name in survey.md obs_sheet.md; do
        if [ ! -e "$bundle/$name" ]; then
            cp "$HUMAN_DIR/$name" "$bundle/$name"
            echo "collect.sh: seeded $name from the template"
        fi
    done
    if [ ! -e "$bundle/session_log.md" ]; then
        cp "$HUMAN_DIR/session_log_template.md" "$bundle/session_log.md"
        echo "collect.sh: seeded session_log.md from the template"
    fi
}

copy_raw() {
    local bundle="$1"
    local debug_dir
    debug_dir="$(find "$bundle/_userdata" -type d -name debug -print -quit 2>/dev/null || true)"
    if [ -z "$debug_dir" ]; then
        echo "collect.sh: no _userdata debug directory (game never ran, or user:// was elsewhere)"
        return 0
    fi
    mkdir -p "$bundle/raw"
    local copied=0
    local file
    for file in "$debug_dir"/*.jsonl; do
        [ -e "$file" ] || continue
        if [ ! -e "$bundle/raw/$(basename "$file")" ]; then
            cp -p "$file" "$bundle/raw/"
            copied=$((copied + 1))
        fi
    done
    echo "collect.sh: raw transcripts: $copied new, $(find "$bundle/raw" -name '*.jsonl' | wc -l) total"
}

FAILED=0
REPORT=()
for session in "${TARGETS[@]}"; do
    bundle="$SESSIONS_DIR/$session"
    echo
    echo "== $session =="
    if [ ! -d "$bundle" ]; then
        echo "collect.sh: no bundle at $bundle" >&2
        FAILED=1
        continue
    fi
    if [ ! -f "$bundle/session.meta.json" ]; then
        echo "collect.sh: $bundle has no session.meta.json — not a session bundle" >&2
        FAILED=1
        continue
    fi

    seed_templates "$bundle"
    copy_raw "$bundle"
    python3 "$SCORE" --merge "$bundle"
    python3 "$SCORE" --render "$bundle"
    python3 "$SCORE" --manifest "$bundle"

    if python3 "$SCORE" --validate "$bundle"; then
        REPORT+=("OK    $session")
    else
        REPORT+=("FAIL  $session")
        FAILED=1
    fi
done

echo
echo "== summary =="
for line in "${REPORT[@]}"; do
    echo "$line"
done
if [ "$FAILED" -ne 0 ]; then
    echo
    echo "One or more bundles are incomplete: fix the fields above, then re-run collect.sh." >&2
    echo "The round is scored with: python3 tools/playtest/$(basename "$SCORE")" >&2
    exit 2
fi
echo
echo "All bundles complete. Next:"
echo "  python3 tools/playtest/$(basename "$SCORE") --dir \"$SESSIONS_DIR\""
echo "  (with the default dir that writes $SESSIONS_DIR/RESULT.md)"
