// Pixel-art nebula background.
// Adapted from Deep-Fold's Pixel Space Background Generator (MIT licence):
//   https://github.com/Deep-Fold/PixelSpace  (Godot 4 port: github.com/Muneeb1195/PixelSpace)
// Changes: scrolls with the camera instead of being a fixed image, and blends
// between a "calm" and a "danger" colour scheme (space_background.gd sets `danger`).
shader_type canvas_item;
render_mode unshaded;

uniform float size = 6.0;             // how big the cloud shapes are (smaller = bigger clouds)
uniform int OCTAVES : hint_range(1, 8) = 5;  // detail layers of noise
uniform float seed : hint_range(1.0, 10.0) = 3.7;
uniform float pixels = 180.0;         // pixel-art resolution across the screen's height
uniform float cover = 0.3;            // how much of the sky the nebula covers (0..1)
uniform vec2 offset = vec2(0.0);      // scroll position, set from the camera by space_background.gd
uniform float aspect = 1.777;         // screen width / height, so pixels stay square

uniform sampler2D colors_calm;        // gradient used near the station
uniform sampler2D colors_danger;      // gradient used far away
uniform float danger : hint_range(0.0, 1.0) = 0.0;  // 0 = home, 1 = deep space
uniform vec4 background_calm : source_color = vec4(0.02, 0.02, 0.06, 1.0);
uniform vec4 background_danger : source_color = vec4(0.06, 0.01, 0.02, 1.0);

// Pseudo-random number from a 2D coordinate.
float rand(vec2 coord) {
	return fract(sin(dot(coord, vec2(12.9898, 78.233))) * (15.5453 + seed));
}

// Smooth "value noise": random values on a grid, blended between grid points.
float noise(vec2 coord) {
	vec2 i = floor(coord);
	vec2 f = fract(coord);
	float a = rand(i);
	float b = rand(i + vec2(1.0, 0.0));
	float c = rand(i + vec2(0.0, 1.0));
	float d = rand(i + vec2(1.0, 1.0));
	vec2 cubic = f * f * (3.0 - 2.0 * f);
	return mix(a, b, cubic.x) + (c - a) * cubic.y * (1.0 - cubic.x) + (d - b) * cubic.x * cubic.y;
}

// Fractal noise: several layers of noise, each twice as detailed and half as strong.
float fbm(vec2 coord) {
	float value = 0.0;
	float scale = 0.5;
	for (int i = 0; i < OCTAVES; i++) {
		value += noise(coord) * scale;
		coord *= 2.0;
		scale *= 0.5;
	}
	return value;
}

// Random circles; used to make the clouds lumpy and turbulent.
float circle_noise(vec2 uv) {
	float uv_y = floor(uv.y);
	uv.x += uv_y * 0.31;
	vec2 f = fract(uv);
	float h = rand(vec2(floor(uv.x), floor(uv_y)));
	float m = length(f - 0.25 - (h * 0.5));
	float r = h * 0.25;
	return smoothstep(0.0, r, m * 0.75);
}

float cloud_alpha(vec2 uv) {
	float c_noise = 0.0;
	for (int i = 0; i < 2; i++) {
		c_noise += circle_noise(uv * 0.5 + float(i + 1) + vec2(-0.3, 0.0));
	}
	return fbm(uv + c_noise);
}

// Checkerboard pattern that gives the pixel-art "dithered" look.
bool dither(vec2 pixel_uv, vec2 raw_uv) {
	return mod(pixel_uv.y + raw_uv.x, 2.0 / pixels) <= 1.0 / pixels;
}

void fragment() {
	// Square pixels, scrolled by the camera, snapped to a chunky pixel grid.
	vec2 raw_uv = UV * vec2(aspect, 1.0) + offset;
	vec2 uv = floor(raw_uv * pixels) / pixels;
	bool dith = dither(uv, raw_uv);

	// Noise for the inside of the nebula and the dust in it.
	float n = cloud_alpha(uv * size);
	float n2 = fbm(uv * size + vec2(1.0, 1.0));
	float n_lerp = n2 * n;
	float n_dust_lerp = cloud_alpha(uv * size) * n_lerp;
	if (dith) {
		n_dust_lerp *= 0.95;
	}

	// Two slightly different thresholds make a thin bright band around each cloud.
	float a = step(n2, cover);
	float a2 = step(n2, cover + 0.015);
	float col_value = (a2 > a) ? floor(n_dust_lerp * 35.0) / 7.0 : floor(n_dust_lerp * 14.0) / 7.0;

	// Pick the colour from both gradients and blend by how far out the player is.
	vec3 calm = texture(colors_calm, vec2(col_value, 0.0)).rgb;
	vec3 scary = texture(colors_danger, vec2(col_value, 0.0)).rgb;
	vec3 col = mix(calm, scary, danger);
	vec3 bg = mix(background_calm.rgb, background_danger.rgb, danger);
	if (col_value < 0.1 || a2 < 0.5) {
		col = bg;  // outside the nebula: plain background
	}
	COLOR = vec4(col, 1.0);
}
