shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

// Shader procedural para terreno de montañas estilizado Low-Poly
// Colores vibrantes: pasto verde en valles, faldas boscosas, roca en laderas y nieve en cumbres altas

// Paleta de colores vibrante (estilo Low-Poly estilizado)
uniform vec4 valley_color : source_color = vec4(0.35, 0.72, 0.25, 1.0);   // Pasto verde brillante visible
uniform vec4 foothill_color : source_color = vec4(0.22, 0.50, 0.20, 1.0); // Bosque / faldas de montaña
uniform vec4 rock_color : source_color = vec4(0.48, 0.44, 0.40, 1.0);     // Roca cálida de montaña
uniform vec4 snow_color : source_color = vec4(0.96, 0.98, 1.0, 1.0);     // Nieve blanca resplandeciente

// Umbrales de Elevación (calibrados para montañas de hasta ~480m)
uniform float grass_max_height : hint_range(0.0, 300.0) = 140.0;
uniform float foothill_blend : hint_range(5.0, 100.0) = 40.0;
uniform float rock_start_height : hint_range(50.0, 400.0) = 220.0;
uniform float rock_blend : hint_range(10.0, 100.0) = 50.0;
uniform float snow_start_height : hint_range(150.0, 500.0) = 310.0;
uniform float snow_blend : hint_range(10.0, 100.0) = 40.0;

// Umbral de acantilado: solo paredes verticales muestran roca en cotas bajas
uniform float cliff_slope_threshold : hint_range(0.0, 1.0) = 0.30;

varying float v_world_y;
varying vec3 v_world_normal;

void vertex() {
	v_world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float flatness = clamp(v_world_normal.y, 0.0, 1.0);
	
	// 1. Capa verde de pasto a bosque/faldas
	float foothill_factor = smoothstep(grass_max_height - foothill_blend, grass_max_height + foothill_blend, v_world_y);
	vec3 green_layer = mix(valley_color.rgb, foothill_color.rgb, foothill_factor);
	
	// 2. Transición a roca por altura
	float rock_by_height = smoothstep(rock_start_height, rock_start_height + rock_blend, v_world_y);
	
	// Acantilados casi verticales muestran roca
	float cliff_factor = 1.0 - smoothstep(cliff_slope_threshold - 0.15, cliff_slope_threshold + 0.10, flatness);
	
	float to_rock = clamp(max(rock_by_height, cliff_factor * 0.85), 0.0, 1.0);
	vec3 terrain_base = mix(green_layer, rock_color.rgb, to_rock);
	
	// 3. Nieve en las cimas altas
	float snow_by_height = smoothstep(snow_start_height, snow_start_height + snow_blend, v_world_y);
	float snow_adhesion = smoothstep(0.15, 0.45, flatness);
	float to_snow = clamp(snow_by_height * snow_adhesion, 0.0, 1.0);
	
	vec3 final_color = mix(terrain_base, snow_color.rgb, to_snow);
	
	ALBEDO = final_color;
	ROUGHNESS = mix(0.9, 0.5, to_snow);
	SPECULAR = 0.15;
}
