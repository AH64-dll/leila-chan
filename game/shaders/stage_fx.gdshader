shader_type canvas_item;
// P2.15 — the stage FX stack in ONE screen pass (docs/02 §2.3).
//
// Why one pass: a Godot 4 2D screen texture is a single copy of the viewport
// per frame, so two full-screen sampling shaders in one frame cannot compose —
// the later one re-samples the pre-effect screen and erases the earlier effect
// (measured: a `flicker` frame at level 1.0 wiped the stage-3 desaturation).
// One pass, one sample, every effect composited in order. It also makes the
// whole vocabulary one blit, which is why the 60 fps budget holds with all six
// live at once.
//
// The pass sits above the UI (CanvasLayer 3): text_bleed needs the dialogue
// box in its sample, and docs/02 §2.3 calls glitch "on the whole screen".
// Effects are uniforms; timelines, envelopes, gates and cooldowns live in
// Character.gd (the look) and FX.gd (the rules). Colours are palette values.
//
// Photosensitive: nothing here strobes by itself — `flicker`'s uniform is
// stepped by the host and clamped to <= 3 Hz in photosensitive mode, the
// vignette pulse is a 1.4 Hz sine, glitch and bleed move pixels, never
// brightness.
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;

// --- stage baseline (docs/01 §3 onset, docs/03 §4 rate): background drain ---
uniform float desaturation : hint_range(0.0, 1.0) = 0.0;

// --- flicker + darken (docs/02 §2.3): two timelines, one luminance scale ---
uniform float flicker : hint_range(0.0, 1.0) = 1.0;
uniform float darken : hint_range(0.0, 1.0) = 1.0;

// --- vignette_red: red pulsing vignette, pulse capped under 3 Hz ---
uniform vec4 vignette_tint : source_color = vec4(0.847, 0.196, 0.227, 1.0); // palette fx[0] d8323a
uniform float vignette : hint_range(0.0, 1.0) = 0.0;
uniform float vignette_inner : hint_range(0.0, 1.5) = 0.25;
uniform float vignette_outer : hint_range(0.0, 1.5) = 0.85;
uniform float vignette_pulse_hz : hint_range(0.0, 2.0) = 1.4;
uniform float vignette_pulse_depth : hint_range(0.0, 1.0) = 0.35;

// --- glitch: scanline displacement + RGB split, whole screen ---
uniform float glitch : hint_range(0.0, 1.0) = 0.0;
uniform float glitch_seed : hint_range(0.0, 1.0) = 0.0;
// --- twitch: the P1.11 1-2 frame colour split, same sample, no displacement ---
uniform float split : hint_range(0.0, 2.0) = 0.0;

// --- text_bleed: the whole screen ---
uniform vec4 bleed_rect = vec4(0.02, 0.77, 0.98, 0.935); // uv min.xy, max.zw
uniform vec4 input_rect = vec4(0.0); // uv min.xy, max.zw of input box
uniform float bleed : hint_range(0.0, 1.0) = 0.0;
uniform float bleed_length : hint_range(0.0, 0.25) = 0.06;
uniform float bleed_seed : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float hash_drip(float n) {
	return fract(sin(n * 12.9898 + bleed_seed * 78.233) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;

	// glitch: 20 scanline bands jump sideways; the pattern re-rolls 24x/s and
	// a dead slice every ~12 bands tears further and holds for a few frames
	float band = floor(uv.y * 20.0);
	float tick = floor(TIME * 24.0) + glitch_seed * 17.0;
	uv.x += (hash(vec2(band, tick)) - 0.5) * 0.06 * glitch;
	float tear = step(0.92, hash(vec2(band * 3.0, floor(tick * 0.5))));
	uv.x += tear * (hash(vec2(band, tick * 2.3)) - 0.5) * 0.12 * glitch;

	// crimson / ice ghost split: the glitch's own split plus the twitch cue's
	// (palette fx[0] d8323a / fx[1] 7fd8e0 — the split channels carry them)
	float ghost = 0.004 * glitch + 0.008 * split;
	vec3 col = vec3(
		texture(screen_tex, uv + vec2(ghost, 0.0)).r,
		texture(screen_tex, uv).g,
		texture(screen_tex, uv - vec2(ghost, 0.0)).b
	);
	// scanlines: every other screen row one step down, only while glitching
	col *= 1.0 - 0.14 * glitch * (1.0 - step(0.5, fract(uv.y * 344.0)));

	// stage baseline: Rec.709 luma mix
	float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(col, vec3(luma), desaturation);

	// flicker / darken: one multiply each — what modulate does to a sprite
	col *= flicker * darken;

	// vignette: circular mask on the 384x688 screen, times the pulse envelope
	vec2 to_edge = (uv - vec2(0.5)) * vec2(2.0 * (384.0 / 688.0), 2.0);
	float mask = smoothstep(vignette_inner, vignette_outer, length(to_edge));
	float pulse = (
		1.0
		- vignette_pulse_depth
		+ vignette_pulse_depth * 0.5 * (1.0 + sin(TIME * TAU * vignette_pulse_hz))
	);
	col = mix(col, vignette_tint.rgb, mask * vignette * pulse);

	// text_bleed: the box's bottom rows stretched downward over the screen.
	// The per-column field is interpolated so streaks have soft edges; a third
	// of the columns never run, because the gaps are what read as drips.
	float below = SCREEN_UV.y - bleed_rect.w; // negative = inside the box border
	float colf = SCREEN_UV.x * 96.0;
	float h = mix(hash_drip(floor(colf)), hash_drip(floor(colf) + 1.0), fract(colf));
	float len = bleed_length * (0.35 + 0.65 * h);
	float in_box_x = step(bleed_rect.x, SCREEN_UV.x) * step(SCREEN_UV.x, bleed_rect.z);
	float in_input = step(input_rect.x, SCREEN_UV.x) * step(SCREEN_UV.x, input_rect.z)
		* step(input_rect.y, SCREEN_UV.y) * step(SCREEN_UV.y, input_rect.w)
		* step(0.0001, input_rect.z - input_rect.x);
	float band_mask = step(0.0, below) * step(below, len) * in_box_x * (1.0 - in_input);
	float t = clamp(below / max(len, 0.0001), 0.0, 1.0); // 0 edge, 1 tip
	float drift = (hash_drip(floor(colf) + 3.0) - 0.5) * 0.01 * t;
	vec3 ink = texture(
		screen_tex, vec2(SCREEN_UV.x + drift, bleed_rect.w - 0.002 - t * 0.03)
	).rgb;
	ink = mix(ink, vec3(0.847, 0.196, 0.227), 0.25 + 0.5 * t); // crimson spine
	float drip = bleed * band_mask * (1.0 - t) * (1.0 - t) * (0.3 + 0.5 * h);
	col = mix(col, ink, drip);

	COLOR = vec4(col, 1.0);
}
