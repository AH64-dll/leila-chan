#!/usr/bin/env python3
"""Plot the P2.01 meters simulation (CSV -> SVG, plus PNG when ImageMagick exists).

The CSV is produced by game/tools/meters_sim.gd through tools/meters/sim.sh; this
script only draws it. Stdlib only, so a reviewer needs no pip install: the SVG is
plain text and diffable, and the PNG is a convenience render of the same file.

    python3 tools/meters/plot.py production/handoffs/media/P2.01/meters_curve.csv \
        production/handoffs/media/P2.01/meters_curve.svg

Axis meanings: the x axis is turns; the Instability panel's y axis is the meter
value. The docs/01 §3 stage bands are instability ranges, so they shade that
panel's y axis (a horizontal stripe per band, labelled with its range), and the
strip above it is the stage the CSV is actually in on each turn. Stage
crossings are marked with their turn and in-game day, read from the CSV.

Panel 1: Instability with the docs/01 §2 ratchet floor (peak - 15) and the peak.
Panel 2: Affection, Trust (mapped from its -50..+50 range), Fixation and
Lucidity.
"""

from __future__ import annotations

import csv
import shutil
import subprocess
import sys
from pathlib import Path

WIDTH = 1100
HEIGHT = 760
LEFT = 70
RIGHT = WIDTH - 30
STRIP_TOP = 104
STRIP_HEIGHT = 30
TOP1 = 142
HEIGHT1 = 238
TOP2 = 424
HEIGHT2 = 200

BG = "#fbfaf7"
INK = "#2b2b2b"
GRID = "#d9d5cc"

## docs/01 §3, verbatim: (lo, hi, name, fill). The numbers are Instability
## values, never turns — the Instability panel's y axis carries them.
STAGES = [
    (0, 14, "S0 Honeymoon", "#eaf6ef"),
    (15, 29, "S1 Hairline Cracks", "#f3f7e6"),
    (30, 49, "S2 Leaks", "#fbf3dd"),
    (50, 69, "S3 Fracture", "#fbe7dc"),
    (70, 89, "S4 Collapse", "#f8dcdc"),
    (90, 100, "S5 Terminal", "#efd0e2"),
]


def read_rows(path: Path) -> list[dict[str, float | str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    if not rows:
        raise SystemExit(f"plot: {path} has no data rows")
    return rows


def num(row: dict[str, float | str], key: str) -> float:
    return float(row[key])


class Svg:
    def __init__(self) -> None:
        self.parts: list[str] = []

    def add(self, markup: str) -> None:
        self.parts.append(markup)

    def rect(self, x: float, y: float, w: float, h: float, fill: str, extra: str = "") -> None:
        self.add(
            f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" '
            f'fill="{fill}" {extra}/>'
        )

    def line(self, x1: float, y1: float, x2: float, y2: float, stroke: str, width: float,
             dash: str = "") -> None:
        dash_attr = f' stroke-dasharray="{dash}"' if dash else ""
        self.add(
            f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" '
            f'stroke="{stroke}" stroke-width="{width}"{dash_attr}/>'
        )

    def polyline(self, points: list[tuple[float, float]], stroke: str, width: float,
                 dash: str = "") -> None:
        if len(points) < 2:
            return
        dash_attr = f' stroke-dasharray="{dash}"' if dash else ""
        path = " ".join(f"{x:.1f},{y:.1f}" for x, y in points)
        self.add(
            f'<polyline points="{path}" fill="none" stroke="{stroke}" '
            f'stroke-width="{width}" stroke-linejoin="round" stroke-linecap="round"{dash_attr}/>'
        )

    def text(self, x: float, y: float, value: str, size: float = 13, anchor: str = "start",
             fill: str = INK, weight: str = "normal") -> None:
        self.add(
            f'<text x="{x:.1f}" y="{y:.1f}" font-family="DejaVu Sans, Helvetica, Arial, '
            f'sans-serif" font-size="{size}" font-weight="{weight}" fill="{fill}" '
            f'text-anchor="{anchor}">{value}</text>'
        )

    def render(self) -> str:
        body = "\n  ".join(self.parts)
        return (
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" '
            f'viewBox="0 0 {WIDTH} {HEIGHT}">\n  '
            f'<rect width="{WIDTH}" height="{HEIGHT}" fill="{BG}"/>\n  {body}\n</svg>\n'
        )


def x_for(turn: float, first: float, last: float) -> float:
    span = max(last - first, 1.0)
    return LEFT + (turn - first) / span * (RIGHT - LEFT)


def y_for(value: float, top: float, height: float, lo: float = 0.0, hi: float = 100.0) -> float:
    return top + height - (value - lo) / (hi - lo) * height


def draw_stage_bands(svg: Svg, top: float, height: float) -> None:
    """docs/01 §3 bands shade the Instability axis: one horizontal stripe per range.

    The band edges are meter values, so each stripe spans the full turn width and
    the curve crossing a stripe edge is exactly the stage change the CSV records.
    """
    for index, (lo, hi, label, fill) in enumerate(STAGES):
        # The doc table's bands are integer ranges (0-14, 15-29, ...), so the
        # next band's floor is this band's ceiling on the continuous axis.
        ceiling = STAGES[index + 1][0] if index + 1 < len(STAGES) else hi
        y_hi = y_for(ceiling, top, height)
        y_lo = y_for(lo, top, height)
        svg.rect(LEFT, y_hi, RIGHT - LEFT, y_lo - y_hi, fill)
        if lo > 0:
            svg.line(LEFT, y_lo, RIGHT, y_lo, "#d5cdbe", 0.9)
        svg.text(
            RIGHT - 8, (y_hi + y_lo) / 2 + 4, f"{label} ({lo}-{hi})", 10, "end", "#9a9186"
        )


def stage_runs(rows: list[dict]) -> list[tuple[int, int, int]]:
    """Contiguous (first_turn, last_turn, stage) runs, read from the CSV's stage column."""
    runs: list[tuple[int, int, int]] = []
    for row in rows:
        turn, stage = int(num(row, "turn")), int(num(row, "stage"))
        if runs and runs[-1][2] == stage:
            runs[-1] = (runs[-1][0], turn, stage)
        else:
            runs.append((turn, turn, stage))
    return runs


def stage_crossings(rows: list[dict]) -> list[tuple[int, int, int]]:
    """Turns where the CSV stage changes: (turn, day, new_stage)."""
    crossings: list[tuple[int, int, int]] = []
    previous = int(num(rows[0], "stage"))
    for row in rows[1:]:
        stage = int(num(row, "stage"))
        if stage != previous:
            crossings.append((int(num(row, "turn")), int(num(row, "day")), stage))
            previous = stage
    return crossings


def draw_stage_strip(svg: Svg, rows: list[dict], x) -> None:
    """The stage the run is actually in per turn, so the strip answers "when".

    Each segment is one contiguous run of the CSV's `stage` column, labelled with
    the docs/01 §3 name; the in-game day ticks under it are turn-based too.
    """
    for start, end, stage in stage_runs(rows):
        xs = max(LEFT, x(start - 0.5))
        xe = min(RIGHT, x(end + 0.5))
        if xe <= xs:
            continue
        _lo, _hi, label, fill = STAGES[stage]
        svg.rect(xs, STRIP_TOP, xe - xs, STRIP_HEIGHT, fill)
        svg.line(xs, STRIP_TOP, xs, STRIP_TOP + STRIP_HEIGHT, "#b8b1a4", 0.8)
        if xe - xs >= 84:
            svg.text((xs + xe) / 2, STRIP_TOP + 14, label, 9, "middle", "#5d564b")
        elif xe - xs >= 34:
            svg.text((xs + xe) / 2, STRIP_TOP + 14, f"S{stage}", 9, "middle", "#5d564b")
    svg.line(RIGHT, STRIP_TOP, RIGHT, STRIP_TOP + STRIP_HEIGHT, "#b8b1a4", 0.8)
    seen: set[int] = set()
    for row in rows:
        day = int(num(row, "day"))
        if day in seen:
            continue
        seen.add(day)
        px = x(num(row, "turn"))
        svg.line(px, STRIP_TOP + 18, px, STRIP_TOP + STRIP_HEIGHT, "#c9c3b6", 0.8)
        svg.text(px + 3, STRIP_TOP + 28, f"D{day}", 9, "start", "#8a8377")


def draw_day_lines(svg: Svg, rows: list[dict], x, top: float, bottom: float) -> None:
    seen: set[int] = set()
    for row in rows:
        day = int(num(row, "day"))
        if day in seen:
            continue
        seen.add(day)
        px = x(num(row, "turn"))
        svg.line(px, top, px, bottom, "#e3ded4", 0.7, "2 4")


def draw_axes(svg: Svg, rows: list[dict], x, top: float, height: float, lo: float, hi: float,
              ticks: list[float]) -> None:
    svg.line(LEFT, top, LEFT, top + height, "#b8b1a4", 1.0)
    svg.line(LEFT, top + height, RIGHT, top + height, "#b8b1a4", 1.0)
    for value in ticks:
        py = y_for(value, top, height, lo, hi)
        svg.line(LEFT, py, RIGHT, py, GRID, 0.8)
        svg.text(LEFT - 8, py + 4, f"{value:g}", 11, "end", "#6f675b")


def legend(svg: Svg, items: list[tuple[str, str, str]], x0: float, y: float) -> None:
    cursor = x0
    for label, color, dash in items:
        svg.line(cursor, y - 4, cursor + 26, y - 4, color, 3, dash)
        svg.text(cursor + 32, y, label, 12)
        cursor += 32 + 8 * len(label) + 26


def plot(rows: list[dict], out: Path) -> None:
    svg = Svg()
    turns = [num(r, "turn") for r in rows]
    first, last = min(turns), max(turns)

    def x(turn: float) -> float:
        return x_for(turn, first, last)

    svg.text(LEFT, 34, "Leila-chan - 100-turn meters simulation (P2.01)", 20, "start", INK, "bold")
    svg.text(
        LEFT, 56,
        "Slow burn +0.35 +0.15*Fixation/100 - 0.2*Lucidity/100 per turn, +3 per day; "
        "ratchet floor = peak - 15 (docs/01 section 2).",
        12, "start", "#6f675b",
    )
    svg.text(
        LEFT, 74,
        "Seeded player model (game/tools/meters_sim.gd, seed 20261104): 14 days, "
        "warm -> provocative -> cold reads.  Bands + strip: docs/01 section 3.",
        12, "start", "#6f675b",
    )
    draw_stage_bands(svg, TOP1, HEIGHT1)
    draw_stage_strip(svg, rows, x)
    draw_day_lines(svg, rows, x, TOP1, TOP2 + HEIGHT2)
    draw_axes(svg, rows, x, TOP1, HEIGHT1, 0, 100, [0, 20, 40, 60, 80, 100])

    crossings = stage_crossings(rows)
    for turn, _day, stage in crossings:
        px = x(turn)
        svg.line(px, TOP1, px, TOP1 + HEIGHT1, "#b09a5f", 0.9, "3 3")
        svg.text(px + 3, TOP1 + HEIGHT1 - 6, f"S{stage}", 9, "start", "#8a7434")

    for key, color, width, dash in (
        ("instability", "#c21f3a", 2.6, ""),
        ("instability_floor", "#8a8a8a", 1.4, "6 4"),
        ("instability_peak", "#7a1b2c", 1.4, "2 3"),
    ):
        points = [(x(num(r, "turn")), y_for(num(r, key), TOP1, HEIGHT1)) for r in rows]
        svg.polyline(points, color, width, dash)

    svg.text(LEFT, 96, "Instability", 14, "start", INK, "bold")
    legend(
        svg,
        [
            ("instability", "#c21f3a", ""),
            ("ratchet floor", "#8a8a8a", "6 4"),
            ("peak", "#7a1b2c", "2 3"),
        ],
        LEFT + 110,
        96,
    )

    svg.text(LEFT, TOP2 - 24, "Other meters", 14, "start", INK, "bold")
    legend(
        svg,
        [
            ("affection", "#d6538a", ""),
            ("trust (-50..50 shifted)", "#3d6fc4", ""),
            ("fixation", "#7b4fa8", ""),
            ("lucidity", "#2f9e6f", ""),
        ],
        LEFT + 110,
        TOP2 - 20,
    )
    draw_axes(svg, rows, x, TOP2, HEIGHT2, 0, 100, [0, 25, 50, 75, 100])
    series = (
        ("affection", "#d6538a"),
        ("trust", "#3d6fc4"),
        ("fixation", "#7b4fa8"),
        ("lucidity", "#2f9e6f"),
    )
    for key, color in series:
        points = []
        for row in rows:
            value = num(row, key)
            if key == "trust":
                value += 50.0  # -50..50 -> 0..100 so the shared axis is honest
            points.append((x(num(row, "turn")), y_for(value, TOP2, HEIGHT2)))
        svg.polyline(points, color, 2.0)

    step = 10 if last - first >= 50 else 5
    tick = int(first)
    while tick <= last:
        px = x(tick)
        svg.line(px, TOP2 + HEIGHT2, px, TOP2 + HEIGHT2 + 5, "#b8b1a4", 1.0)
        svg.text(px, TOP2 + HEIGHT2 + 20, str(tick), 11, "middle", "#6f675b")
        tick += step
    svg.text((LEFT + RIGHT) / 2, TOP2 + HEIGHT2 + 42, "turn (100 turns / 14 in-game days)",
             12, "middle", "#6f675b")

    if crossings:
        svg.text(
            LEFT, HEIGHT - 36,
            "stage crossings (instability -> stage): "
            + " - ".join(f"S{stage} turn {turn}/day {day}" for turn, day, stage in crossings),
            11, "start", "#6f675b",
        )

    last_row = rows[-1]
    svg.text(
        LEFT, HEIGHT - 12,
        f"final: instability {num(last_row, 'instability'):.1f} (stage {int(num(last_row, 'stage'))}) "
        f"- peak {num(last_row, 'instability_peak'):.1f} - floor "
        f"{num(last_row, 'instability_floor'):.1f} - affection "
        f"{num(last_row, 'affection'):.0f} - trust {num(last_row, 'trust'):.0f}",
        12, "start", "#6f675b",
    )
    out.write_text(svg.render(), encoding="utf-8")


def to_png(svg_path: Path) -> None:
    png_path = svg_path.with_suffix(".png")
    tool = shutil.which("magick") or shutil.which("convert")
    if tool is None:
        print("plot: ImageMagick not found - SVG written, PNG skipped")
        return
    result = subprocess.run(
        [tool, str(svg_path), str(png_path)], capture_output=True, text=True, check=False
    )
    if result.returncode != 0:
        print(f"plot: PNG conversion failed: {result.stderr.strip()}")
        return
    print(f"plot: wrote {png_path}")


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__)
        return 2
    source, target = Path(argv[1]), Path(argv[2])
    rows = read_rows(source)
    turns = [num(r, "turn") for r in rows]
    if turns != list(range(1, len(rows) + 1)):
        raise SystemExit("plot: turns must be 1..N with no gaps")
    for row in rows:
        if num(row, "instability") < num(row, "instability_floor") - 1e-6:
            raise SystemExit(f"plot: ratchet violated at turn {row['turn']}")
        if not 0 <= int(num(row, "stage")) < len(STAGES):
            raise SystemExit(f"plot: stage out of range at turn {row['turn']}")
    plot(rows, target)
    print(f"plot: wrote {target} ({len(rows)} turns)")
    to_png(target)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
