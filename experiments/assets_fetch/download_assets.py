"""Download the CC0 audio candidates into assets/audio/_raw/<source>/ and write a license manifest.
Usage: python3 download_assets.py <project_root>
"""
import json, os, sys, time, urllib.request, urllib.parse, zipfile

UA = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) Firefox/140.0"}
ROOT = os.path.abspath(sys.argv[1])
RAW = os.path.join(ROOT, "assets/audio/_raw")
OGA = "https://opengameart.org/sites/default/files/"
MAX_BYTES = 60_000_000

KENNEY = []  # kenney.nl blocks scripted downloads (noai); Kenney's own OpenGameArt uploads are used below

# (folder, page slug, [files]) — every page verified CC0 on 2026-11-01
OGA_ITEMS = [
    ("kenney_interface_sounds", "interface-sounds", ["kenney_interfaceSounds.zip"]),
    ("kenney_ui_sfx", "51-ui-sound-effects-buttons-switches-and-clicks", ["UI_SFX_Set.zip"]),
    ("kenney_digital_sfx", "63-digital-sound-effects-lasers-phasers-space-etc", ["Digital_SFX_Set.zip"]),
    ("kenney_jingles", "85-short-music-jingles", ["jingleSounds_Kenney.zip"]),
    ("sfx_keyboard", "keyboard-soundpack-1-typing-and-single-keystrokes", ["unicae_games_keyboard_soundpack_1_0.zip"]),
    ("sfx_typewriter", "typewriter-sounds", [f"typewriter{i}.wav" for i in range(1, 9)]),
    ("sfx_clock", "ticking-clock", ["ticking_clock.wav"]),
    ("sfx_clock_tick", "clock-tick-0", ["Timetick.ogg"]),
    ("sfx_ringtone", "modern-ringtone-chirptone", ["chirptone.wav"]),
    ("sfx_horror_hits", "horror-hit-soundpack-1", ["horror_hit_soundpack_1.zip"]),
    ("sfx_heartbeat", "heartbeat-sounds", ["heartbeat_fast_0.wav", "heartbeat_fast_reverb.wav", "heartbeat_slow_0.wav", "heartbeat_slow_reverb.wav"]),
    ("sfx_heartbeat_single", "heartbeat-single-sound", ["heartbeat.mp3_.flac"]),
    ("sfx_static_noise", "static", ["ScatterNoise1.mp3"]),
    ("sfx_static_freq", "frequency-static-sound-effects", [f"static{i}.wav" for i in range(1, 4)]),
    ("sfx_giggling", "group-giggling", ["group_giggling.ogg"]),
    ("sfx_vocal_samples", "dialog-vocal-samples", ["vocal_samples.zip"]),
    ("sfx_creatures", "80-cc0-creature-sfx", ["80-CC0-creature-SFX_0.zip"]),
    ("sfx_breaking", "75-cc0-breaking-falling-hit-sfx", ["sfx_breaking_and_falling.zip"]),
    ("sfx_glass", "glass-break", ["glass_breaking.wav"]),
    ("sfx_100", "100-cc0-sfx", ["100-CC0-SFX_0.zip"]),
    ("sfx_breathing", "horror-breathing", ["horrorbreathing.zip"]),
    ("sfx_ghost_breath", "ghost-breath", ["ghostbreath.flac"]),
    ("sfx_jumpscare", "jumpscare-sound", ["jumpscare.wav"]),
    ("sfx_scream", "horror-scream1", ["scream_horror1_0.mp3"]),
    ("music_music_box", "4-music-box-tracks", ["4_music_box_tracks_ogg.zip"]),
    ("music_creepy_ambient_loop", "creepy-ambient-loop", ["creepyloop-v2_0.ogg", "creepyloop.ogg"]),
    ("music_horror_atmosphere", "horror-atmosphere", ["Juhani Junkala - Post Apocalyptic Wastelands [Loop Ready].ogg"]),
    ("music_ice_cream_date", "ice-cream-date", ["ice_cream_date.zip"]),
    ("music_daisy", "daisy", ["daisy_0.ogg"]),
    ("music_calm_synthwave", "calm-relax-1-synthwave-421k", ["007_Synthwave_421k.mp3"]),
    ("music_chill_lofi", "chill-lofi-inspired", ["ChillLofi.ogg"]),
    ("music_snowfall", "snowfall", ["Snowfall (Looped ver.)_0.ogg"]),
    ("music_happy_lullaby", "happy-lullaby-song17", ["song17.mp3"]),
    ("music_moonlit_lullaby", "moonlit-lullaby-for-the-lost", ["moonlit_lullaby_for_the_lost_loop.flac"]),
    ("music_goodbye_lullaby", "goodbye-lullaby-day-4", ["goodbye_lullaby.wav"]),
    ("music_insistent", "insistent-background-loop", ["Insistent.ogg"]),
    ("music_creep", "creepy", ["CrEEP.ogg"]),
    ("music_glitch_stairs", "glitch-stairs", ["glitchstairs_6.ogg"]),
    ("music_sirens_in_darkness", "sirens-in-darkness", ["012_Sirens_in_Darkness_0.mp3"]),
    ("amb_rain_night", "rain-and-thunders", ["Dark_Rainy_Night(ambience).ogg"]),
    ("music_flowerbed_fields", "flowerbed-fields-loop", ["flowerbed_fields.ogg"]),
    ("music_apple_cider", "apple-cider", ["apple_cider.ogg"]),
    ("music_talking_cute", "talking-cute-chiptune", ["TalkingCuteChiptune_0.mp3"]),
    ("music_baby_song", "lullaby-0", ["Baby Song.wav"]),
]


def fetch(url, dest):
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        return True
    for attempt in range(4):
        try:
            time.sleep(1.5)
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120) as r:
                size = int(r.headers.get("Content-Length") or 0)
                if size > MAX_BYTES:  # disk is tight; huge uncompressed files are skipped and noted
                    print(f"   SKIP too large ({size // 1_000_000} MB): {url}", file=sys.stderr)
                    return False
                with open(dest, "wb") as f:
                    f.write(r.read())
            return True
        except Exception as e:
            print("   retry", attempt, url, e, file=sys.stderr)
            time.sleep(6)
    return False


def unzip(path):
    if path.endswith(".zip") and os.path.exists(path):
        with zipfile.ZipFile(path) as z:
            z.extractall(os.path.splitext(path)[0])
        os.remove(path)


manifest = []
for pack in KENNEY:
    d = os.path.join(RAW, f"kenney_{pack.replace('-', '_')}")
    os.makedirs(d, exist_ok=True)
    try:
        link = json.load(urllib.request.urlopen(urllib.request.Request(
            "https://kenney.nl/download-link/" + ("assets/" + pack).encode().hex(), headers=UA), timeout=30))["url"]
        ok = fetch(link, os.path.join(d, pack + ".zip"))
        unzip(os.path.join(d, pack + ".zip"))
    except Exception as e:
        ok = False; print("kenney fail", pack, e, file=sys.stderr)
    manifest.append({"folder": os.path.basename(d), "source": f"https://kenney.nl/assets/{pack}", "author": "Kenney (kenney.nl)", "license": "CC0", "ok": ok})
    print(("OK  " if ok else "FAIL"), pack)

for folder, slug, files in OGA_ITEMS:
    d = os.path.join(RAW, folder)
    os.makedirs(d, exist_ok=True)
    ok = all(fetch(OGA + urllib.parse.quote(f), os.path.join(d, f)) for f in files)
    for f in files:
        unzip(os.path.join(d, f))
    manifest.append({"folder": folder, "source": f"https://opengameart.org/content/{slug}", "license": "CC0", "ok": ok})
    print(("OK  " if ok else "FAIL"), folder)

json.dump(manifest, open(os.path.join(ROOT, "assets/audio/SOURCES.json"), "w"), indent=1)
