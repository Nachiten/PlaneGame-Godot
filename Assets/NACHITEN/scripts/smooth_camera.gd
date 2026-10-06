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


func _ready() -> void:
	# Si no se asignó en inspector, buscar PlayerPlane automáticamente
	if not target:
		target = get_tree().current_scene.find_child("PlayerPlane", true, false) as Node3D

	# Posicionar inmediatamente la cámara en el primer frame para evitar salto inicial
	if target:
		global_transform = target.global_transform * SACRED_RELATIVE_TRANSFORM


func _physics_process(delta: float) -> void:
	if not target:
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
