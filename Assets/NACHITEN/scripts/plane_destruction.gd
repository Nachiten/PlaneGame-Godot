class_name PlaneDestruction
extends Node

## Sistema de Destrucción y Desmembramiento Físico del Avión
## Separa cada parte del modelo (fuselaje, flaps, hélice, ruedas, cristal, etc.)
## convirtiéndolas en RigidBody3D individuales con impulsos explosivos y giro realista.

signal plane_destroyed(debris_root: Node3D, fuselage_rb: RigidBody3D)

## Velocidad de reproducción de la explosión (1.0 = normal, 0.2 = cámara lenta épica, 3.0 = rápida)
@export_range(0.05, 5.0, 0.05) var explosion_speed: float = 1.0

@export var explosion_force_min: float = 3.0
@export var explosion_force_max: float = 7.0
## Velocidad lineal máxima permitida para los escombros (m/s) para evitar dispersión excesiva
@export var debris_max_linear_speed: float = 20.0
@export var angular_speed_max: float = 12.0
@export var upward_bias: float = 0.3
@export var debris_lifetime: float = 15.0

## Tiempo (en segundos) durante el cual los escombros NO colisionan entre sí al explotar.
## Esto evita el empuje violento por superposición de piezas contiguas recién cortadas.
## Tras este tiempo, la colisión mutua se activa para que rueden y se apilen con normalidad.
@export var debris_mutual_collision_delay: float = 1.0

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


## Recorre recursivamente un árbol de nodos para extraer todos los MeshInstance3D
func _collect_mesh_instances(node: Node, list: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		list.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_mesh_instances(child, list)


## Pre-calcula los convex shapes de cada pieza del avión en memoria
func _precalculate_collision_shapes() -> void:
	var plane_body := get_parent() as Node3D
	if not plane_body:
		return
	var model_root := plane_body.find_child("SM_Veh_Plane_Stunt_01", true, false) as Node3D
	if not model_root:
		return

	var all_meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(model_root, all_meshes)

	for mesh_node in all_meshes:
		if mesh_node.mesh and not _cached_shapes.has(mesh_node.name):
			# Usamos BoxShape3D. Los cascos convexos de mallas cortadas pueden ser "planos" (2D)
			# o degenerados, lo cual congela el motor de físicas de Godot instantáneamente al chocar.
			var box := BoxShape3D.new()
			var aabb: AABB = mesh_node.mesh.get_aabb()
			box.size = aabb.size.max(Vector3(0.2, 0.2, 0.2)) # Evitar que sea 0 en algún eje
			_cached_shapes[mesh_node.name] = box


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

	# Recopilar todos los MeshInstance3D (recursivo para soportar jerarquías de Blender)
	var mesh_nodes: Array[MeshInstance3D] = []
	_collect_mesh_instances(model_root, mesh_nodes)

	var main_fuselage_rb: RigidBody3D = null
	var spawned_rbs: Array[RigidBody3D] = []

	# 4. Convertir cada pieza en un RigidBody3D independiente
	for mesh_node in mesh_nodes:
		var rb := _create_debris_part(mesh_node, contact_point, impact_velocity)
		if rb:
			debris_container.add_child(rb)
			spawned_rbs.append(rb)
			if "sm_veh_plane_stunt_01" in mesh_node.name.to_lower() or "fuselage" in mesh_node.name.to_lower() or main_fuselage_rb == null:
				main_fuselage_rb = rb

	# (Eliminado: Activación diferida de colisión mutua)
	# Decidimos que los escombros nunca colisionarán entre sí. Si activamos la capa 2 (entre escombros) 
	# cuando están todos apilados en el suelo, el motor de físicas colapsa intentando separar
	# 50 cascos convexos superpuestos, lo que traba el juego y catapulta las piezas.

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

	# Capa de colisión: el escombro reside en la Capa 2 (Escombros)
	# Inicialmente solo detecta la Capa 1 (suelo y terreno) para no repelerse violentamente con piezas contiguas
	rb.collision_layer = 2
	rb.collision_mask = 1
	if debris_mutual_collision_delay <= 0.0:
		rb.set_collision_mask_value(2, true)

	# Material físico con rebote y fricción realista (metal contra tierra)
	var pmat := PhysicsMaterial.new()
	pmat.bounce = 0.08
	pmat.friction = 0.80
	rb.physics_material_override = pmat
	rb.linear_damp = 2.5
	rb.angular_damp = 2.5
	# CCD desactivado: al usar HeightMapShape3D en el terreno (que tiene volumen sólido),
	# el tunneling se mitiga naturalmente. Activar CCD en decenas de piezas causaba un lagazo masivo.
	rb.continuous_cd = false

	# Asignar masa según el tipo de componente (más balanceado para piezas cortadas)
	var part_name := mesh_node.name.to_lower()
	if "fuselage" in part_name or "body" in part_name or part_name == "sm_veh_plane_stunt_01":
		rb.mass = 12.0 # Trozos de fuselaje
	elif "wing" in part_name:
		rb.mass = 7.0  # Alas
	elif "tail" in part_name:
		rb.mass = 5.0  # Cola
	elif "wheel" in part_name or "prop" in part_name:
		rb.mass = 4.5  # Hélice y tren de aterrizaje
	elif "flap" in part_name:
		rb.mass = 3.0  # Alerones y timón
	elif "glass" in part_name:
		rb.mass = 2.0  # Cúpula de cristal
	else:
		rb.mass = 4.0  # Accesorios / piezas cortadas genéricas

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

	# Crear CollisionShape3D y ajustar su posición según la geometría
	var col_shape := CollisionShape3D.new()
	col_shape.name = "Collider"
	var shape: Shape3D = _cached_shapes.get(mesh_node.name, null)

	if shape is BoxShape3D:
		col_shape.position = mesh.get_aabb().get_center()
		
		# A prueba de balas: Sobrescribir el centro de masa de Godot
		# Si en Blender el Origin estaba lejos de la geometría, esto obliga a Godot 
		# a balancear el peso exactamente en el centro de la pieza visual.
		rb.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		rb.center_of_mass = col_shape.position

	col_shape.shape = shape
	rb.add_child(col_shape)

	# --- Vector de Impulso Explosivo ---
	var part_pos: Vector3 = mesh_node.global_position
	var outward_dir: Vector3 = (part_pos - explosion_origin)
	if outward_dir.length_squared() < 0.05:
		outward_dir = Vector3(randf_range(-1.0, 1.0), randf_range(0.2, 1.0), randf_range(-1.0, 1.0))
	outward_dir = outward_dir.normalized()

	# Sesgo hacia arriba controlado
	outward_dir.y = maxf(outward_dir.y, 0.15) + randf_range(0.2, upward_bias + 0.2)
	outward_dir = (outward_dir + Vector3(randf_range(-0.3, 0.3), randf_range(0.0, 0.25), randf_range(-0.3, 0.3))).normalized()

	var force_mag: float = randf_range(explosion_force_min, explosion_force_max)

	# Inercia hacia adelante proporcional a la velocidad del choque (reducida al 15%)
	var forward_momentum: Vector3 = impact_velocity * randf_range(0.05, 0.15)
	var raw_velocity: Vector3 = forward_momentum + outward_dir * force_mag
	# Clampear la velocidad máxima para evitar catapultado violento por depenetración
	if raw_velocity.length() > debris_max_linear_speed:
		raw_velocity = raw_velocity.normalized() * debris_max_linear_speed
	rb.linear_velocity = raw_velocity

	# Giro angular controlado
	rb.angular_velocity = Vector3(
		randf_range(-angular_speed_max, angular_speed_max),
		randf_range(-angular_speed_max, angular_speed_max),
		randf_range(-angular_speed_max, angular_speed_max)
	)

	return rb

