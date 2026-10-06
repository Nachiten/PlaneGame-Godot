class_name PlaneDestruction
extends Node

## Sistema de Destrucción y Desmembramiento Físico del Avión
## Separa cada parte del modelo (fuselaje, flaps, hélice, ruedas, cristal, etc.)
## convirtiéndolas en RigidBody3D individuales con impulsos explosivos y giro realista.

signal plane_destroyed(debris_root: Node3D, fuselage_rb: RigidBody3D)

## Velocidad de reproducción de la explosión (1.0 = normal, 0.2 = cámara lenta épica, 3.0 = rápida)
@export_range(0.05, 5.0, 0.05) var explosion_speed: float = 1.0

@export var explosion_force_min: float = 14.0
@export var explosion_force_max: float = 32.0
@export var angular_speed_max: float = 22.0
@export var upward_bias: float = 0.5
@export var debris_lifetime: float = 15.0

var _is_destroyed: bool = false
var _cached_shapes: Dictionary = {}
var _explosion_vfx_scene: PackedScene = preload("res://Assets/NACHITEN/scenes/explosion_vfx.tscn")
var _explosion_material: ShaderMaterial = preload("res://Assets/NACHITEN/shaders/explosion_material.tres")


func _ready() -> void:
	# 1. Pre-calentar el shader en la GPU para eliminar el lagazo en el momento del impacto
	_prewarm_gpu_shader()

	# 2. Pre-calcular las formas de colisión de las piezas durante la carga para evitar tirones de CPU
	call_deferred("_precalculate_collision_shapes")


## Crea una malla microscópica invisible en pantalla para obligar al driver de GPU
## a compilar el shader de explosión en el arranque en vez de congelar el juego al chocar
func _prewarm_gpu_shader() -> void:
	if not _explosion_material:
		return
	var dummy := MeshInstance3D.new()
	dummy.name = "ShaderPrewarmDummy"
	var sphere := SphereMesh.new()
	sphere.radius = 0.001
	sphere.height = 0.002
	dummy.mesh = sphere
	dummy.material_override = _explosion_material
	dummy.extra_cull_margin = 1000.0
	dummy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dummy)


## Pre-calcula los convex shapes de cada pieza del avión en memoria
func _precalculate_collision_shapes() -> void:
	var plane_body := get_parent() as Node3D
	if not plane_body:
		return
	var model_root := plane_body.find_child("SM_Veh_Plane_Stunt_01", true, false) as Node3D
	if not model_root:
		return

	var all_meshes: Array[MeshInstance3D] = []
	if model_root is MeshInstance3D and (model_root as MeshInstance3D).mesh != null:
		all_meshes.append(model_root as MeshInstance3D)
	for child in model_root.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			all_meshes.append(child as MeshInstance3D)

	for mesh_node in all_meshes:
		if mesh_node.mesh and not _cached_shapes.has(mesh_node.name):
			var shape: Shape3D = mesh_node.mesh.create_convex_shape(true, true)
			if not shape:
				var box := BoxShape3D.new()
				var aabb: AABB = mesh_node.mesh.get_aabb()
				box.size = aabb.size.max(Vector3(0.25, 0.25, 0.25))
				shape = box
			_cached_shapes[mesh_node.name] = shape


## Dispara el desmembramiento y la explosión
func explode(plane_body: CharacterBody3D, impact_velocity: Vector3, contact_point: Vector3 = Vector3.ZERO) -> RigidBody3D:
	if _is_destroyed:
		return null
	_is_destroyed = true

	var world_root: Node = plane_body.get_parent()
	if not world_root:
		world_root = plane_body.get_tree().current_scene

	if contact_point == Vector3.ZERO:
		contact_point = plane_body.global_position

	# 1. Instanciar el efecto de explosión aplicando la velocidad configurada
	if _explosion_vfx_scene:
		var vfx: Node3D = _explosion_vfx_scene.instantiate() as Node3D
		if "speed_scale" in vfx:
			vfx.speed_scale = explosion_speed
		world_root.add_child(vfx)
		vfx.global_position = contact_point

	# 2. Contenedor de escombros en el mundo
	var debris_container := Node3D.new()
	debris_container.name = "PlaneCrashDebris"
	world_root.add_child(debris_container)

	# 3. Buscar el modelo visual del avión
	var model_root := plane_body.find_child("SM_Veh_Plane_Stunt_01", true, false) as Node3D
	if not model_root:
		push_warning("PlaneDestruction: No se encontró SM_Veh_Plane_Stunt_01 en el avión")
		return null

	# Recopilar todos los MeshInstance3D (el nodo raíz y todos sus hijos)
	var mesh_nodes: Array[MeshInstance3D] = []
	if model_root is MeshInstance3D and (model_root as MeshInstance3D).mesh != null:
		mesh_nodes.append(model_root as MeshInstance3D)

	for child in model_root.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			mesh_nodes.append(child as MeshInstance3D)

	var main_fuselage_rb: RigidBody3D = null

	# 4. Convertir cada pieza en un RigidBody3D independiente
	for mesh_node in mesh_nodes:
		var rb := _create_debris_part(mesh_node, contact_point, impact_velocity)
		if rb:
			debris_container.add_child(rb)
			if "SM_Veh_Plane_Stunt_01" == mesh_node.name:
				main_fuselage_rb = rb

	# 5. Ocultar el modelo original y desactivar la física del avión padre
	model_root.visible = false
	plane_body.collision_layer = 0
	plane_body.collision_mask = 0
	plane_body.velocity = Vector3.ZERO

	var main_col := plane_body.find_child("CollisionShape3D", false, false) as CollisionShape3D
	if main_col:
		main_col.set_deferred("disabled", true)

	# 6. Limpieza diferida de los escombros tras unos segundos
	if debris_lifetime > 0.0:
		var tree := plane_body.get_tree()
		if tree:
			var timer := tree.create_timer(debris_lifetime)
			timer.timeout.connect(func():
				if is_instance_valid(debris_container):
					# Desvanecer suavemente antes de borrar
					var tween := debris_container.create_tween()
					for child in debris_container.get_children():
						if child is RigidBody3D:
							tween.tween_property(child, "scale", Vector3.ZERO, 1.2).set_trans(Tween.TRANS_QUAD)
					tween.chain().tween_callback(debris_container.queue_free)
			)

	plane_destroyed.emit(debris_container, main_fuselage_rb)
	return main_fuselage_rb


## Construye un RigidBody3D con colisión, masa y momentum explosivo para una pieza específica
func _create_debris_part(mesh_node: MeshInstance3D, explosion_origin: Vector3, impact_velocity: Vector3) -> RigidBody3D:
	var mesh: Mesh = mesh_node.mesh
	if not mesh:
		return null

	var rb := RigidBody3D.new()
	rb.name = "Debris_" + mesh_node.name
	rb.global_transform = mesh_node.global_transform

	# Capa de colisión estándar para interactuar con suelo y terreno
	rb.collision_layer = 1
	rb.collision_mask = 1

	# Material físico con rebote y fricción elástica
	var pmat := PhysicsMaterial.new()
	pmat.bounce = 0.35
	pmat.friction = 0.65
	rb.physics_material_override = pmat
	rb.linear_damp = 0.4
	rb.angular_damp = 0.8

	# Asignar masa según el tipo de componente
	var part_name := mesh_node.name.to_lower()
	if part_name == "sm_veh_plane_stunt_01":
		rb.mass = 30.0 # Fuselaje principal
	elif "wheel" in part_name or "prop" in part_name:
		rb.mass = 6.0  # Hélice y tren de aterrizaje
	elif "flap" in part_name:
		rb.mass = 3.5  # Alerones y timón
	elif "glass" in part_name:
		rb.mass = 2.0  # Cúpula de cristal
	else:
		rb.mass = 2.5  # Palanca, accesorios

	# Crear MeshInstance3D visual clonado
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	visual.mesh = mesh
	visual.cast_shadow = mesh_node.cast_shadow
	# Copiar materiales de superficie
	for s in range(mesh_node.get_surface_override_material_count()):
		var mat := mesh_node.get_surface_override_material(s)
		if mat:
			visual.set_surface_override_material(s, mat)
	rb.add_child(visual)

	# Crear CollisionShape3D utilizando la forma pre-calculada en la carga
	var col_shape := CollisionShape3D.new()
	col_shape.name = "Collider"
	var shape: Shape3D = _cached_shapes.get(mesh_node.name, null)

	if not shape:
		shape = mesh.create_convex_shape(true, true)
		if not shape:
			var box := BoxShape3D.new()
			var aabb: AABB = mesh.get_aabb()
			box.size = aabb.size.max(Vector3(0.25, 0.25, 0.25))
			shape = box
			col_shape.position = aabb.get_center()

	col_shape.shape = shape
	rb.add_child(col_shape)

	# --- Vector de Impulso Explosivo ---
	var part_pos: Vector3 = mesh_node.global_position
	var outward_dir: Vector3 = (part_pos - explosion_origin)
	if outward_dir.length_squared() < 0.05:
		outward_dir = Vector3(randf_range(-1.0, 1.0), randf_range(0.2, 1.0), randf_range(-1.0, 1.0))
	outward_dir = outward_dir.normalized()

	# Sesgo hacia arriba para que las piezas salgan volando por el aire
	outward_dir.y = maxf(outward_dir.y, 0.2) + randf_range(0.3, upward_bias + 0.3)
	outward_dir = (outward_dir + Vector3(randf_range(-0.35, 0.35), randf_range(0.0, 0.3), randf_range(-0.35, 0.35))).normalized()

	var force_mag: float = randf_range(explosion_force_min, explosion_force_max)

	# Heredar parte de la inercia del avance del avión
	var forward_momentum: Vector3 = impact_velocity * randf_range(0.3, 0.55)
	rb.linear_velocity = forward_momentum + outward_dir * force_mag

	# Giro angular aleatorio (volteretas)
	rb.angular_velocity = Vector3(
		randf_range(-angular_speed_max, angular_speed_max),
		randf_range(-angular_speed_max, angular_speed_max),
		randf_range(-angular_speed_max, angular_speed_max)
	)

	return rb
