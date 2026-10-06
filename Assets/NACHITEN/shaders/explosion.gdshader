shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

// --- Parámetros de la Explosión ---
uniform float progress : hint_range(0.0, 1.0) = 0.0;

uniform vec4 color_core : source_color = vec4(1.0, 0.95, 0.6, 1.0);  // Núcleo blanco-amarillento incandescente
uniform vec4 color_fire : source_color = vec4(1.0, 0.35, 0.02, 1.0);  // Fuego naranja/rojo arcade
uniform vec4 color_smoke : source_color = vec4(0.12, 0.1, 0.11, 1.0); // Humo carbón oscuro

uniform float displacement_strength : hint_range(0.0, 4.0) = 1.4;
uniform float noise_scale : hint_range(0.5, 10.0) = 2.2;
uniform float emission_energy : hint_range(0.0, 25.0) = 8.0;

// Ruido 3D procedural autónomo (sin requerir texturas externas)
vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float value_noise3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float n000 = dot(hash33(i + vec3(0.0, 0.0, 0.0)) - 0.5, f - vec3(0.0, 0.0, 0.0));
	float n100 = dot(hash33(i + vec3(1.0, 0.0, 0.0)) - 0.5, f - vec3(1.0, 0.0, 0.0));
	float n010 = dot(hash33(i + vec3(0.0, 1.0, 0.0)) - 0.5, f - vec3(0.0, 1.0, 0.0));
	float n110 = dot(hash33(i + vec3(1.0, 1.0, 0.0)) - 0.5, f - vec3(1.0, 1.0, 0.0));
	float n001 = dot(hash33(i + vec3(0.0, 0.0, 1.0)) - 0.5, f - vec3(0.0, 0.0, 1.0));
	float n101 = dot(hash33(i + vec3(1.0, 0.0, 1.0)) - 0.5, f - vec3(1.0, 0.0, 1.0));
	float n011 = dot(hash33(i + vec3(0.0, 1.0, 1.0)) - 0.5, f - vec3(0.0, 1.0, 1.0));
	float n111 = dot(hash33(i + vec3(1.0, 1.0, 1.0)) - 0.5, f - vec3(1.0, 1.0, 1.0));

	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);

	float nxy0 = mix(nx00, nx10, f.y);
	float nxy1 = mix(nx01, nx11, f.y);

	return mix(nxy0, nxy1, f.z) + 0.5;
}

float fbm(vec3 p) {
	float total = 0.0;
	float amp = 0.5;
	float freq = 1.0;
	for (int i = 0; i < 3; i++) {
		total += value_noise3d(p * freq) * amp;
		freq *= 2.0;
		amp *= 0.5;
	}
	return total;
}

varying float v_noise;
varying float v_progress;

void vertex() {
	v_progress = progress;
	// Posición de muestreo que evoluciona con el progreso de la explosión
	vec3 sample_pos = VERTEX * noise_scale + vec3(0.0, progress * 1.5, 0.0);
	v_noise = fbm(sample_pos);

	// Deformación de vértices: se expande agresivamente en el pico y luego se estabiliza
	float expansion_curve = sin(clamp(progress, 0.0, 1.0) * PI);
	float displ = (v_noise - 0.35) * displacement_strength * (0.4 + 0.6 * expansion_curve);
	VERTEX += NORMAL * displ;
}

void fragment() {
	// Factor de calor: inicia alto (fuego) y disminuye dejando humo
	float heat = clamp(v_noise * 1.5 - v_progress * 1.3, 0.0, 1.0);

	// Gradiente de color: Humo -> Fuego Naranja -> Núcleo Amarillo/Blanco
	vec3 col;
	if (heat > 0.45) {
		float t = (heat - 0.45) / 0.55;
		col = mix(color_fire.rgb, color_core.rgb, t);
	} else {
		float t = heat / 0.45;
		col = mix(color_smoke.rgb, color_fire.rgb, t);
	}

	ALBEDO = col;
	ROUGHNESS = 0.85;

	// Emisión intensa en las zonas con fuego (disminuye conforme se vuelve humo)
	float fire_intensity = smoothstep(0.2, 0.7, heat) * (1.0 - v_progress * 0.8);
	EMISSION = col * emission_energy * fire_intensity;

	// Disolución del humo mediante corte de ruido al final de la explosión
	if (v_progress > 0.45) {
		float dissolve_threshold = (v_progress - 0.45) / 0.55;
		if (v_noise < dissolve_threshold) {
			discard;
		}
	}
}
