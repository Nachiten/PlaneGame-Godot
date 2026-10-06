extends Camera3D

## Smooth Chase Camera (Cámara suave en tercera persona)
## Sigue al avión con amortiguación suave para evitar mareos durante maniobras bruscas,
## manteniendo la distancia y rotación de referencia calibradas por el usuario.

## Nodo objetivo a seguir (por defecto busca 'PlayerPlane' si no se asigna)
@export var target: Node3D = null

## Suavizado de seguimiento de posición (mayor = más ceñido, menor = más elástico)
@export var follow_speed: float = 6.0

## Suavizado de seguimiento de rotación (slerp de orientación)
@export var rotation_speed: float = 4.5

## Transform relativo de referencia calibrado por el usuario
## Posición: (0, 8.201576, -12.943382)
const SACRED_RELATIVE_TRANSFORM := Transform3D(
	Basis(
		Vector3(-1.0, 6.25373e-08, -1.3743659e-07),
		Vector3(-1.0658142e-14, 0.91020143, 0.41416594),
		Vector3(1.5099579e-07, 0.41416594, -0.91020143)
	),
	Vector3(0.0, 8.201576, -12.943382)
)

@export_group("Crash Camera Zoom")
## Distancia horizontal de zoom-out hacia atrás tras el choque para tener visión panorámica
@export var crash_zoom_distance: float = 24.0

## Altura de la cámara por encima del punto de impacto durante el choque
@export var crash_zoom_height: float = 9.0

## Suavizado de transición de alejamiento (zoom-out) al chocar
@export var crash_zoom_speed: float = 2.5


var _is_crash_cam: bool = false
var _last_focus_pos: Vector3 = Vector3.ZERO
var _crash_away_dir: Vector3 = Vector3.BACK
## Posición del impacto en el mundo, usada como ancla de cámara panoramica
var _crash_impact_pos: Vector3 = Vector3.ZERO


func _ready() -> void:
	# Si no se asignó en inspector, buscar PlayerPlane automáticamente
	if not target:
		target = get_tree().current_scene.find_child("PlayerPlane", true, false) as Node3D

	# Posicionar inmediatamente la cámara en el primer frame para evitar salto inicial
	if target:
		global_transform = target.global_transform * SACRED_RELATIVE_TRANSFORM


func _physics_process(delta: float) -> void:
	if _is_crash_cam:
		_process_crash_camera(delta)
		return

	if not target or not is_instance_valid(target):
		return

	# Transform objetivo ideal en el mundo
	var target_tf: Transform3D = target.global_transform * SACRED_RELATIVE_TRANSFORM

	# 1. Amortiguación suave de posición (decay exponencial independiente de framerate)
	var pos_factor: float = 1.0 - exp(-follow_speed * delta)
	global_position = global_position.lerp(target_tf.origin, pos_factor)

	# 2. Amortiguación suave de rotación con Quaternion slerp
	var rot_factor: float = 1.0 - exp(-rotation_speed * delta)
	var cur_quat: Quaternion = global_transform.basis.get_rotation_quaternion()
	var target_quat: Quaternion = target_tf.basis.get_rotation_quaternion()
	var blended_quat: Quaternion = cur_quat.slerp(target_quat, rot_factor)
	global_transform.basis = Basis(blended_quat)


## Activa el modo de cámara cinemática de impacto al estrellarse el avión
func on_target_destroyed(new_target: Node3D) -> void:
	_is_crash_cam = true
	if is_instance_valid(new_target):
		target = new_target
		_last_focus_pos = new_target.global_position
	elif is_instance_valid(target):
		_last_focus_pos = target.global_position
	# Guardar el punto exacto de impacto como ancla de la cámara panoramica
	_crash_impact_pos = _last_focus_pos

	# Calcular la dirección horizontal de alejamiento basada en la posición actual de la cámara
	var away := (global_position - _last_focus_pos)
	away.y = 0.0
	if away.length_squared() < 0.1:
		away = -global_transform.basis.z
		away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3(0.0, 0.0, -1.0)
	_crash_away_dir = away.normalized()


func _process_crash_camera(delta: float) -> void:
	if is_instance_valid(target):
		# Seguimiento rápido del escombro para no quedarse atrás cuando sale disparado
		var target_pos: Vector3 = target.global_position
		_last_focus_pos = _last_focus_pos.lerp(target_pos, 1.0 - exp(-8.0 * delta))
		# Actualizar dinámicamente la dirección de alejamiento basada en el movimiento real
		var drift := target_pos - _crash_impact_pos
		drift.y = 0.0
		if drift.length_squared() > 1.0:
			_crash_away_dir = drift.normalized()

	# La cámara se posiciona sobre el punto de impacto original para una vista panoramica estable
	var cam_anchor: Vector3 = _crash_impact_pos
	var desired_cam_pos: Vector3 = cam_anchor + (_crash_away_dir * crash_zoom_distance) + (Vector3.UP * crash_zoom_height)
	var pos_factor: float = 1.0 - exp(-crash_zoom_speed * delta)
	global_position = global_position.lerp(desired_cam_pos, pos_factor)

	# Orientación cinemática mirando hacia el centro de los restos
	var look_target: Vector3 = _last_focus_pos + Vector3.UP * 0.8
	var look_dir: Vector3 = (look_target - global_position).normalized()
	if look_dir.length_squared() > 0.01 and absf(look_dir.dot(Vector3.UP)) < 0.99:
		var target_basis := Basis.looking_at(look_dir, Vector3.UP)
		var cur_quat: Quaternion = global_transform.basis.get_rotation_quaternion()
		var target_quat: Quaternion = target_basis.get_rotation_quaternion()
		# Rotación rápida para mantenerse alineada con el objetivo en movimiento
		var rot_factor: float = 1.0 - exp(-8.0 * delta)
		global_transform.basis = Basis(cur_quat.slerp(target_quat, rot_factor))


