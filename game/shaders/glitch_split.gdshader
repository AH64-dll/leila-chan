shader_type canvas_item;
// P1.11: 1-2 frame chromatic split fired by Character.twitch_fired — the
// cheap end of the glitch vocabulary (full glitch shader is P2.15).
// A colour-only offset; no flash, so the < 3 Hz photosensitive rule is met
// even while twitch fires it.
uniform float offset_uv = 0.008;
uniform float strength = 1.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;

void fragment() {
	vec2 uv = SCREEN_UV;
	float r = texture(screen_tex, uv + vec2(offset_uv, 0.0)).r;
	vec2 gb = texture(screen_tex, uv).gb;
	float b = texture(screen_tex, uv - vec2(offset_uv, 0.0)).b;
	COLOR = vec4(r, gb.x, b, 1.0) * strength;
}
