extends CharacterBody3D

## Casual Flight Controller
## Controles:
##   W / Flecha Arriba  → Inclinar hacia abajo (Pitch down / picar)
##   S / Flecha Abajo   → Inclinar hacia arriba (Pitch up / subir)
##   A / Flecha Izq     → Girar a la izquierda (Yaw left)
##   D / Flecha Der     → Girar a la derecha (Yaw right)
##   Shift / Espacio    → Acelerar (Boost)
##   Ctrl               → Frenar (Brake)

# -- Velocidades --
## Velocidad crucero normal (unidades/seg)
@export var base_speed: float = 35.0
## Velocidad máxima acelerando
@export var max_speed: float = 65.0
## Velocidad mínima frenando
@export var min_speed: float = 15.0
## Suavizado de aceleración/frenado
@export var speed_lerp: float = 2.5

# -- Maniobrabilidad --
## Velocidad de cabeceo (grados/seg)
@export var pitch_speed: float = 60.0
## Velocidad de viraje (grados/seg)
@export var yaw_speed: float = 50.0
## Suavizado de entrada de rotación
@export var rotation_lerp: float = 4.0
## Invertir controles verticales (Pitch)
@export var invert_pitch: bool = false
## Ángulo máximo de cabeceo (grados arriba/abajo) para evitar volteretas
@export var max_pitch_angle: float = 80.0

# -- Visuales --
## Ángulo máximo de inclinación al girar (Roll / Banking en grados)
@export var max_bank_angle: float = 28.0
## Suavizado de inclinación de alas
@export var bank_lerp: float = 5.0
## Velocidad de giro de la hélice (grados/seg)
@export var propeller_spin_speed: float = 1800.0

# -- Debug --
## Mostrar texto de telemetría / debug en pantalla
@export var show_debug_hud: bool = true

# -- Referencias internas --
var _visual_mesh: Node3D = null
var _propeller: Node3D = null
var _debug_label: Label = null
var _debug_hud_layer: CanvasLayer = null

# Estado interno
var _current_speed: float = 0.0
var _smooth_pitch: float = 0.0
var _smooth_yaw: float = 0.0
var _current_bank: float = 0.0


func _ready() -> void:
	_current_speed = base_speed
	_setup_input_actions()
	_setup_debug_hud()

	# Buscar nodo visual y hélice
	_visual_mesh = find_child("SM_Veh_Plane_Stunt_01", true, false) as Node3D
	_propeller = find_child("SM_Veh_Plane_Stunt_01_Prop", true, false) as Node3D

	# Desactivar colisión interna del modelo para evitar que el avión choque contra sí mismo
	var internal_collider := find_child("MeshCollider", true, false) as CollisionObject3D
	if internal_collider:
		internal_collider.collision_layer = 0
		internal_collider.collision_mask = 0


func _physics_process(delta: float) -> void:
	_process_speed(delta)
	_process_steering(delta)
	_process_movement(delta)
	_process_visuals(delta)
	_update_debug_hud()


func _setup_input_actions() -> void:
	_ensure_action("pitch_down", KEY_W, KEY_UP)
	_ensure_action("pitch_up", KEY_S, KEY_DOWN)
	_ensure_action("yaw_left", KEY_A, KEY_LEFT)
	_ensure_action("yaw_right", KEY_D, KEY_RIGHT)
	_ensure_action("accelerate", KEY_SHIFT, KEY_SPACE)
	_ensure_action("brake", KEY_CTRL)


func _ensure_action(action_name: String, key1: Key, key2: Key = KEY_NONE) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
		var ev1 := InputEventKey.new()
		ev1.physical_keycode = key1
		InputMap.action_add_event(action_name, ev1)
		if key2 != KEY_NONE:
			var ev2 := InputEventKey.new()
			ev2.physical_keycode = key2
			InputMap.action_add_event(action_name, ev2)


func _process_speed(delta: float) -> void:
	var target_speed: float = base_speed

	var is_accel: bool = Input.is_action_pressed("accelerate") or Input.is_physical_key_pressed(KEY_SHIFT) or Input.is_physical_key_pressed(KEY_SPACE)
	var is_brake: bool = Input.is_action_pressed("brake") or Input.is_physical_key_pressed(KEY_CTRL)

	if is_accel and not is_brake:
		target_speed = max_speed
	elif is_brake and not is_accel:
		target_speed = min_speed

	_current_speed = lerp(_current_speed, target_speed, speed_lerp * delta)


func _process_steering(delta: float) -> void:
	# Pitch: W/Arriba = +1 (bajar nariz), S/Abajo = -1 (subir nariz)
	var target_pitch: float = 0.0
	if Input.is_action_pressed("pitch_down") or Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		target_pitch += 1.0
	if Input.is_action_pressed("pitch_up") or Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		target_pitch -= 1.0

	if invert_pitch:
		target_pitch = -target_pitch

	# Yaw: D/Der = +1 (girar derecha), A/Izq = -1 (girar izquierda)
	var target_yaw: float = 0.0
	if Input.is_action_pressed("yaw_right") or Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		target_yaw += 1.0
	if Input.is_action_pressed("yaw_left") or Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		target_yaw -= 1.0

	# Suavizado de controles
	_smooth_pitch = lerp(_smooth_pitch, target_pitch, rotation_lerp * delta)
	_smooth_yaw = lerp(_smooth_yaw, target_yaw, rotation_lerp * delta)

	# 1. Cabeceo local (Pitch)
	var pitch_amount: float = _smooth_pitch * deg_to_rad(pitch_speed) * delta
	rotate_object_local(Vector3.RIGHT, pitch_amount)

	# Limitar cabeceo máximo para evitar que el avión se invierta verticalmente
	if max_pitch_angle > 0.0 and max_pitch_angle < 90.0:
		var max_y: float = sin(deg_to_rad(max_pitch_angle))
		var fwd: Vector3 = global_transform.basis.z
		if absf(fwd.y) > max_y:
			fwd.y = clampf(fwd.y, -max_y, max_y)
			var horiz_len: float = sqrt(maxf(0.0, 1.0 - fwd.y * fwd.y))
			var horiz_dir: Vector2 = Vector2(fwd.x, fwd.z).normalized() * horiz_len
			fwd.x = horiz_dir.x
			fwd.z = horiz_dir.y
			global_transform.basis.z = fwd.normalized()

	# 2. Viraje sobre el eje vertical del mundo (evita inducir roll por inclinación de cabeceo)
	var yaw_amount: float = -_smooth_yaw * deg_to_rad(yaw_speed) * delta
	rotate_y(yaw_amount)

	# 3. Auto-leveling de horizonte: mantiene las alas del fuselaje perfectamente horizontales con el mundo (Roll = 0°)
	var forward: Vector3 = global_transform.basis.z.normalized()
	if absf(forward.y) < 0.999:
		var left: Vector3 = Vector3.UP.cross(forward).normalized()
		var up: Vector3 = forward.cross(left).normalized()
		global_transform.basis = Basis(left, up, forward)


func _process_movement(_delta: float) -> void:
	# El modelo del avión mira hacia +Z (hélice en +Z, cola en -Z)
	var forward_direction: Vector3 = global_transform.basis.z.normalized()
	velocity = forward_direction * _current_speed
	move_and_slide()


func _process_visuals(delta: float) -> void:
	# Giro de la hélice
	if _propeller:
		_propeller.rotate_z(deg_to_rad(propeller_spin_speed * delta))

	# Inclinación visual de las alas (banking) al virar
	if _visual_mesh:
		var target_bank: float = _smooth_yaw * deg_to_rad(max_bank_angle)
		_current_bank = lerp(_current_bank, target_bank, bank_lerp * delta)
		_visual_mesh.rotation.z = _current_bank


func _setup_debug_hud() -> void:
	if not show_debug_hud:
		return

	_debug_hud_layer = CanvasLayer.new()
	_debug_hud_layer.name = "PlaneDebugHUD"
	add_child(_debug_hud_layer)

	# Fondo semitransparente para legibilidad
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.04, 0.06, 0.08, 0.6)
	bg.position = Vector2(12, 12)
	bg.size = Vector2(330, 72)
	_debug_hud_layer.add_child(bg)

	_debug_label = Label.new()
	_debug_label.name = "TelemetryText"
	_debug_label.position = Vector2(18, 16)
	_debug_label.add_theme_font_size_override("font_size", 12)
	_debug_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0, 1.0))
	_debug_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_debug_label.add_theme_constant_override("outline_size", 3)
	_debug_hud_layer.add_child(_debug_label)


func _update_debug_hud() -> void:
	if not _debug_label:
		return

	var pos: Vector3 = global_position
	var rot: Vector3 = global_rotation_degrees
	_debug_label.text = "WORLD POS:  X: %7.1f | Y: %6.1f | Z: %7.1f\nROTATION:   Pitch: %5.1f° | Yaw: %5.1f° | Roll: %5.1f°\nSPEED:      %4.1f u/s" % [
		pos.x, pos.y, pos.z,
		rot.x, rot.y, rot.z,
		_current_speed
	]
