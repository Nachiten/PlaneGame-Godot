extends Node3D

## Controlador de Efecto de Explosión (VFX)
## Controla el shader de bola de fuego, la luz de destello, ondas de choque y partículas

## Multiplicador de velocidad de la animación (1.0 = normal, 0.2 = cámara lenta, 2.0 = rápida)
@export_range(0.05, 5.0, 0.05) var speed_scale: float = 1.0

## Duración base de la explosión en segundos
@export var duration: float = 1.3
@export var max_scale: float = 5.0
@export var flash_energy: float = 12.0

@onready var fireball: MeshInstance3D = $Fireball
@onready var flash_light: OmniLight3D = $FlashLight
@onready var shockwave: MeshInstance3D = $Shockwave
@onready var sparks: CPUParticles3D = $Sparks
@onready var smoke_debris: CPUParticles3D = $SmokeDebris


func _ready() -> void:
	# Duplicar el material para que cada explosión tenga su propio progreso independiente
	if fireball and fireball.get_surface_override_material(0):
		fireball.set_surface_override_material(0, fireball.get_surface_override_material(0).duplicate())

	var effective_speed: float = maxf(speed_scale, 0.01)
	var effective_duration: float = duration / effective_speed

	# Ajustar velocidad de partículas al multiplicador
	if sparks:
		sparks.speed_scale = effective_speed
		sparks.emitting = true
	if smoke_debris:
		smoke_debris.speed_scale = effective_speed
		smoke_debris.emitting = true

	# Configurar estado inicial
	if fireball:
		fireball.scale = Vector3(0.2, 0.2, 0.2)
		_set_shader_progress(0.0)

	if flash_light:
		flash_light.light_energy = flash_energy

	if shockwave:
		shockwave.scale = Vector3(0.1, 0.1, 0.1)

	# Iniciar animación vía Tween
	var tween := create_tween()
	tween.set_parallel(true)

	# 1. Progreso del shader de 0.0 a 1.0
	tween.tween_method(_set_shader_progress, 0.0, 1.0, effective_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 2. Expansión inicial de la bola de fuego
	if fireball:
		tween.tween_property(fireball, "scale", Vector3.ONE * max_scale, effective_duration * 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 3. Disipación de la luz del flash
	if flash_light:
		var flash_time: float = 0.35 / effective_speed
		tween.tween_property(flash_light, "light_energy", 0.0, flash_time).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	# 4. Expansión de onda de choque horizontal
	if shockwave:
		var shock_time: float = 0.6 / effective_speed
		tween.tween_property(shockwave, "scale", Vector3(12.0, 0.1, 12.0), shock_time).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
		tween.tween_property(shockwave, "transparency", 1.0, shock_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Auto-eliminarse al terminar
	tween.chain().tween_callback(queue_free)


func _set_shader_progress(val: float) -> void:
	if not fireball:
		return
	var mat := fireball.get_surface_override_material(0) as ShaderMaterial
	if mat:
		mat.set_shader_parameter("progress", val)
