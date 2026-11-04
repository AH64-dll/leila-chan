"""Tests for tools/audio/import_audio.py (P1.12).

Pure-Python coverage of the selection/sanitisation contract; the GDScript
side of the same sanitisation is asserted in the gdUnit4 suite
(game/tests/AudioDirectorTest.gd) via _resolve_src. The --check half runs
against the committed game/assets/audio files — no raw pool needed.
"""

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools" / "audio"))

import import_audio  # noqa: E402


def test_sanitise_relpath() -> None:
    cases = {
        "sfx_heartbeat/heartbeat_slow_0.wav": "sfx_heartbeat/heartbeat_slow_0.ogg",
        "music_snowfall/Snowfall (Looped ver.)_0.ogg":
        "music_snowfall/snowfall_looped_ver._0.ogg",
        "sfx_heartbeat_single/heartbeat.mp3_.flac":
        "sfx_heartbeat_single/heartbeat.mp3_.ogg",
        "music_ice_cream_date/ice_cream_date/Ice Cream Date/icd_repeating.mp3":
        "music_ice_cream_date/ice_cream_date/ice_cream_date/icd_repeating.ogg",
        "sfx_creatures/80-CC0-creature-SFX_0/cute_01.ogg":
        "sfx_creatures/80-cc0-creature-sfx_0/cute_01.ogg",
    }
    for src, want in cases.items():
        assert import_audio.sanitise_relpath(src) == want


def test_band_span() -> None:
    assert import_audio.band_span("0-1") == (0, 1)
    assert import_audio.band_span("any") == (0, 5)
    assert import_audio.band_span("4-5") == (4, 5)
    assert import_audio.band_span("note") is None


def test_stage0_selection_is_exactly_the_v1_scope() -> None:
    """Golden plan: 8 stage-0 cues (5 real + 3 gap) + stage 0-1 music +
    voice_blip.stage0_2 = the 24 committed files."""
    cue_map, rules = import_audio.load_tables()
    sel = import_audio.build_selection(
        cue_map, rules, max_stage=0, extra_cues=[], extra_music=[],
        system_keys=["voice_blip.stage0_2"],
    )
    rows = import_audio.plan_rows(sel)
    assert len(rows) == 24
    assert len([r for r in rows if r[0] == "music"]) == 10
    assert len([r for r in rows if r[0] == "sfx"]) == 3
    assert len([r for r in rows if r[0] == "vocal"]) == 11
    # Gap cues hum/sniffle produce no rows but stay legal requests.
    assert all("gap" not in dst for _, _, dst in rows)
    for _, src, dst in rows:
        assert not src.startswith("/") and ".." not in Path(dst).parts
        assert Path(dst).suffix == ".ogg"


def test_stage1_selection_adds_gate1_cues() -> None:
    cue_map, rules = import_audio.load_tables()
    sel = import_audio.build_selection(
        cue_map, rules, max_stage=1, extra_cues=[], extra_music=[],
        system_keys=[],
    )
    cue_srcs = {s for pairs in (sel["sfx"], sel["vocal"]) for s, _ in pairs}
    assert any("musicbox" in s for s in cue_srcs)  # music_box_note gate 1
    assert any("ticking_clock" in s or "Timetick" in s for s in cue_srcs)


def test_check_mode_verifies_committed_outputs() -> None:
    proc = subprocess.run(
        [sys.executable, str(ROOT / "tools" / "audio" / "import_audio.py"),
         "--max-stage", "0", "--system", "voice_blip.stage0_2", "--check"],
        capture_output=True, text=True, cwd=ROOT,
    )
    assert proc.returncode == 0, proc.stderr
    assert "24 imported file(s)" in proc.stdout


BLIP_KEYS = [
    "voice_blip.stage0_2", "voice_blip.stage3", "voice_blip.stage4",
    "voice_blip.stage5", "voice_blip.awake",
]


def test_music_stage_scope_opens_every_layer_without_high_stage_cues() -> None:
    """P2.16: --music-stage 5 imports every music band (and every voice blip
    pool) while --max-stage 0 keeps the cue scope at the P1.12 set."""
    cue_map, rules = import_audio.load_tables()
    sel = import_audio.build_selection(
        cue_map, rules, max_stage=0, extra_cues=[], extra_music=[],
        system_keys=BLIP_KEYS, music_max_stage=5,
    )
    rows = import_audio.plan_rows(sel)
    assert len(rows) == 53
    music = [r for r in rows if r[0] == "music"]
    assert len(music) == 23
    srcs = {src for _cat, src, _dst in music}
    # The stage 2-5 layers for every state in docs/04 §8.3.
    for state_src in (
        "music_glitch_stairs/glitchstairs_6.ogg",
        "music_insistent/Insistent.ogg",
        "music_music_box/4_music_box_tracks_ogg/musicbox1_spooky_waltz.ogg",
        "music_music_box/4_music_box_tracks_ogg/musicbox2_cute_tune.ogg",
        "music_music_box/4_music_box_tracks_ogg/musicbox3_sad_tune.ogg",
        "music_music_box/4_music_box_tracks_ogg/musicbox4_happy_polka.ogg",
        "music_creep/CrEEP.ogg",
        "music_creepy_ambient_loop/creepyloop.ogg",
        "music_horror_atmosphere/"
        "Juhani Junkala - Post Apocalyptic Wastelands [Loop Ready].ogg",
        "music_sirens_in_darkness/012_Sirens_in_Darkness_0.mp3",
        "music_baby_song/Baby Song.wav",
        "music_happy_lullaby/song17.mp3",
    ):
        assert state_src in srcs, state_src
    # Voice blip pools for stages 3/4/5 + AWAKE are selected too.
    vocal_srcs = {src for cat, src, _dst in rows if cat == "vocal"}
    for pool in ("female_standard_1.ogg", "whisper_1.ogg",
                 "demon_1.ogg", "robot_1.ogg"):
        assert any(src.endswith(pool) for src in vocal_srcs), pool
    # No high-stage cue assets leak in with the music scope: sfx rows stay in
    # the stage-0 set (static slices, music_box_note etc. are P5.10 work).
    sfx_srcs = {src for cat, src, _dst in rows if cat == "sfx"}
    assert not any("static_freq" in src for src in sfx_srcs)
    assert not any(src.startswith("music_") for src in sfx_srcs)


def test_check_mode_covers_the_stage_layer_scope() -> None:
    """The committed stage 2-5 music and stage 3-5/AWAKE blips exist."""
    cmd = [sys.executable, str(ROOT / "tools" / "audio" / "import_audio.py"),
           "--max-stage", "0", "--music-stage", "5"]
    for key in BLIP_KEYS:
        cmd += ["--system", key]
    proc = subprocess.run(cmd + ["--check"], capture_output=True, text=True, cwd=ROOT)
    assert proc.returncode == 0, proc.stderr
    assert "53 imported file(s)" in proc.stdout
