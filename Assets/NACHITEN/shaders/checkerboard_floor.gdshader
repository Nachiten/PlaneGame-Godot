shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Shader de piso procedural con patrón de ajedrez (checkerboard)
// y super-cuadrícula destacada cada 10 patrones (en ambas direcciones).

uniform vec4 color_a : source_color = vec4(0.24, 0.32, 0.24, 1.0); // Tono pasto oscuro
uniform vec4 color_b : source_color = vec4(0.34, 0.44, 0.34, 1.0); // Tono pasto claro
uniform vec4 minor_line_color : source_color = vec4(0.16, 0.22, 0.16, 1.0); // Líneas entre celdas
uniform vec4 major_line_color : source_color = vec4(1.0, 0.45, 0.05, 1.0); // Líneas destacadas cada 10 tiles (naranja)

uniform float cell_size : hint_range(5.0, 500.0) = 100.0; // 100m por celda (10x más grande)
uniform float minor_line_width : hint_range(0.0, 0.1) = 0.015; // Grosor de línea de cada celda

uniform float major_step : hint_range(2.0, 50.0) = 10.0; // Cada 10 celdas (1 km)
uniform float major_line_width : hint_range(0.0, 0.05) = 0.008; // Grosor de línea mayor (~8 metros)

uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float fade_distance : hint_range(1000.0, 25000.0) = 10000.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// UV normalizado por el tamaño de cada celda
	vec2 uv = world_pos.xz / cell_size;
	vec2 grid = floor(uv);
	
	// 1. Patrón de ajedrez básico
	float check = mod(grid.x + grid.y, 2.0);
	vec3 base_color = mix(color_a.rgb, color_b.rgb, check);
	
	// 2. Líneas menores (borde entre celdas individuales)
	vec2 cell_fract = fract(uv);
	vec2 minor_border = step(cell_fract, vec2(minor_line_width)) + step(vec2(1.0 - minor_line_width), cell_fract);
	float is_minor = clamp(minor_border.x + minor_border.y, 0.0, 1.0);
	vec3 pattern_color = mix(base_color, minor_line_color.rgb, is_minor * 0.6);
	
	// 3. Líneas mayores cada 10 patrones (en ambas direcciones X y Z)
	vec2 major_uv = uv / major_step;
	vec2 major_fract = fract(major_uv);
	vec2 major_border = step(major_fract, vec2(major_line_width)) + step(vec2(1.0 - major_line_width), major_fract);
	float is_major = clamp(major_border.x + major_border.y, 0.0, 1.0);
	pattern_color = mix(pattern_color, major_line_color.rgb, is_major);
	
	// 4. Desvanecimiento suave en la distancia (horizonte) para evitar moiré
	float dist = length(world_pos.xz - CAMERA_POSITION_WORLD.xz);
	float fade = clamp(dist / fade_distance, 0.0, 1.0);
	vec3 avg_color = (color_a.rgb + color_b.rgb) * 0.5;
	
	ALBEDO = mix(pattern_color, avg_color, fade * fade);
	ROUGHNESS = roughness;
}
