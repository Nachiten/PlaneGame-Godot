extends Node3D

## Generador de Terreno Procedural con Montañas
## Esculpe cordilleras y valles de escala alpina en tiempo de ejecución
## con triángulos pequeños estilizados (~6m) y colores vibrantes (valles verdes, roca y nieve).

@export_group("Dimensiones")
## Tamaño total del terreno en el mundo (X = ancho, Y = largo/profundidad)
@export var terrain_size: Vector2 = Vector2(2400.0, 3800.0)
## Desplazamiento del centro del terreno para cubrir la pista de aros
@export var center_offset: Vector3 = Vector3(250.0, 0.0, 1900.0)
## Resolución de la cuadrícula (X, Z). 380x580 genera triángulos de ~6 metros (más pequeños que el avión)
@export var grid_resolution: Vector2i = Vector2i(380, 580)
## Altura máxima de las cumbres montañosas (escala alpina monumental de casi 500m)
@export var max_height: float = 460.0

@export_group("Ruido Procedural")
## Frecuencia del ruido (0.0016 genera cadenas montañosas majestuosas y valles amplios)
@export var noise_frequency: float = 0.0016
## Octavas fractales para rugosidad y detalle en las faldas
@export var noise_octaves: int = 4
## Semilla aleatoria
@export var noise_seed: int = 1337

@export_group("Cañón de Vuelo y Aros")
## Radio protegido alrededor del punto de spawn inicial (0, 0)
@export var spawn_clear_radius: float = 200.0
## Si está activo, detecta automáticamente los aros y esculpe un cañón para que nunca queden enterrados
@export var clear_rings_path: bool = true
## Radio de despeje alrededor de cada aro
@export var ring_clear_radius: float = 85.0

@export_group("Visual y Física")
## Estilo Low-Poly con caras facetadas
@export var low_poly_shading: bool = true
## Generar colisión tridimensional para que el avión pueda colisionar con las montañas
@export var generate_collision: bool = true
## Material del terreno con shader de pasto, roca y nieve
@export var terrain_material: Material = preload("res://Assets/NACHITEN/shaders/mountain_terrain_material.tres")

var _noise: FastNoiseLite = null
var _mesh_instance: MeshInstance3D = null
var _static_body: StaticBody3D = null
var _collision_shape: CollisionShape3D = null
var _ring_positions: Array[Vector3] = []


func _ready() -> void:
	_setup_nodes()
	_init_noise()
	_collect_ring_positions()
	generate_terrain()


func _setup_nodes() -> void:
	_mesh_instance = find_child("TerrainMesh", false, false) as MeshInstance3D
	if not _mesh_instance:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "TerrainMesh"
		add_child(_mesh_instance)

	if generate_collision:
		_static_body = find_child("TerrainCollider", false, false) as StaticBody3D
		if not _static_body:
			_static_body = StaticBody3D.new()
			_static_body.name = "TerrainCollider"
			add_child(_static_body)

		_collision_shape = _static_body.find_child("CollisionShape3D", false, false) as CollisionShape3D
		if not _collision_shape:
			_collision_shape = CollisionShape3D.new()
			_collision_shape.name = "CollisionShape3D"
			_static_body.add_child(_collision_shape)


func _init_noise() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.seed = noise_seed
	_noise.frequency = noise_frequency
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = noise_octaves
	_noise.fractal_gain = 0.45


func _collect_ring_positions() -> void:
	_ring_positions.clear()
	var root := get_tree().current_scene if get_tree() else get_parent()
	if not root:
		return
	for child in root.get_children():
		if "Ring" in child.name and child is Node3D:
			_ring_positions.append(child.global_position)


## Genera la malla procedural de montañas y la colisión de alto rendimiento
func generate_terrain() -> void:
	var res_x: int = max(2, grid_resolution.x)
	var res_z: int = max(2, grid_resolution.y)

	var step_x: float = terrain_size.x / float(res_x - 1)
	var step_z: float = terrain_size.y / float(res_z - 1)

	var half_x: float = terrain_size.x * 0.5
	var half_z: float = terrain_size.y * 0.5

	# 1. Precalcular elevaciones en arrays contiguos para máximo rendimiento
	var heights: Array = []
	heights.resize(res_z)
	for j in range(res_z):
		var row := PackedFloat32Array()
		row.resize(res_x)
		var wz: float = center_offset.z - half_z + float(j) * step_z
		for i in range(res_x):
			var wx: float = center_offset.x - half_x + float(i) * step_x
			row[i] = get_height_at(wx, wz)
		heights[j] = row

	# 2. Construir geometría optimizada mediante ArrayMesh directo
	var quads_x: int = res_x - 1
	var quads_z: int = res_z - 1
	var num_vertices: int = quads_x * quads_z * 6

	var verts := PackedVector3Array()
	verts.resize(num_vertices)
	var normals := PackedVector3Array()
	normals.resize(num_vertices)

	var idx: int = 0
	for j in range(quads_z):
		var z0: float = center_offset.z - half_z + float(j) * step_z
		var z1: float = z0 + step_z
		var row0: PackedFloat32Array = heights[j]
		var row1: PackedFloat32Array = heights[j + 1]

		for i in range(quads_x):
			var x0: float = center_offset.x - half_x + float(i) * step_x
			var x1: float = x0 + step_x

			var p00 := Vector3(x0, row0[i], z0)
			var p10 := Vector3(x1, row0[i + 1], z0)
			var p01 := Vector3(x0, row1[i], z1)
			var p11 := Vector3(x1, row1[i + 1], z1)

			# Triángulo 1 (p00, p10, p11)
			var n1: Vector3 = (p10 - p00).cross(p11 - p00).normalized()
			verts[idx] = p00; normals[idx] = n1; idx += 1
			verts[idx] = p10; normals[idx] = n1; idx += 1
			verts[idx] = p11; normals[idx] = n1; idx += 1

			# Triángulo 2 (p00, p11, p01)
			var n2: Vector3 = (p11 - p00).cross(p01 - p00).normalized()
			verts[idx] = p00; normals[idx] = n2; idx += 1
			verts[idx] = p11; normals[idx] = n2; idx += 1
			verts[idx] = p01; normals[idx] = n2; idx += 1

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_instance.mesh = mesh

	if terrain_material:
		_mesh_instance.material_override = terrain_material

	# 3. Colisión física (LOD optimizado a paso 2 para construcción instantánea del BVH)
	if generate_collision and _collision_shape:
		var col_quads_x: int = int(ceil(float(quads_x) / 2.0))
		var col_quads_z: int = int(ceil(float(quads_z) / 2.0))
		var col_num_verts: int = col_quads_x * col_quads_z * 6
		var col_verts := PackedVector3Array()
		col_verts.resize(col_num_verts)

		var c_idx: int = 0
		var j: int = 0
		while j < quads_z:
			var next_j: int = min(j + 2, quads_z)
			var z0: float = center_offset.z - half_z + float(j) * step_z
			var z1: float = center_offset.z - half_z + float(next_j) * step_z

			var i: int = 0
			while i < quads_x:
				var next_i: int = min(i + 2, quads_x)
				var x0: float = center_offset.x - half_x + float(i) * step_x
				var x1: float = center_offset.x - half_x + float(next_i) * step_x

				var p00 := Vector3(x0, heights[j][i], z0)
				var p10 := Vector3(x1, heights[j][next_i], z0)
				var p01 := Vector3(x0, heights[next_j][i], z1)
				var p11 := Vector3(x1, heights[next_j][next_i], z1)

				col_verts[c_idx] = p00; c_idx += 1
				col_verts[c_idx] = p10; c_idx += 1
				col_verts[c_idx] = p11; c_idx += 1

				col_verts[c_idx] = p00; c_idx += 1
				col_verts[c_idx] = p11; c_idx += 1
				col_verts[c_idx] = p01; c_idx += 1

				i += 2
			j += 2

		col_verts.resize(c_idx)
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(col_verts)
		_collision_shape.shape = shape


## Retorna la elevación Y en cualquier coordenada del mundo (x, z)
func get_height_at(world_x: float, world_z: float) -> float:
	var n: float = _noise.get_noise_2d(world_x, world_z) # [-1.0, 1.0]
	var norm: float = (n + 1.0) * 0.5                   # [0.0, 1.0]
	var h: float = pow(norm, 1.4) * max_height

	# 1. Proteger zona de despegue (spawn del avión en 0, 0)
	var dist_spawn: float = Vector2(world_x, world_z).length()
	if dist_spawn < spawn_clear_radius:
		var spawn_factor: float = clampf(dist_spawn / spawn_clear_radius, 0.0, 1.0)
		spawn_factor = spawn_factor * spawn_factor * (3.0 - 2.0 * spawn_factor)
		h *= spawn_factor

	# 2. Cañón automático alrededor de los aros
	if clear_rings_path and _ring_positions.size() > 0:
		for ring_pos in _ring_positions:
			var d_ring: float = Vector2(world_x - ring_pos.x, world_z - ring_pos.z).length()
			if d_ring < ring_clear_radius:
				var ring_factor: float = clampf(d_ring / ring_clear_radius, 0.0, 1.0)
				ring_factor = ring_factor * ring_factor * (3.0 - 2.0 * ring_factor)
				# La altura máxima permitida bajo el aro es al menos 14m por debajo
				var max_allowed: float = maxf(0.0, ring_pos.y - 14.0)
				h = minf(h, lerpf(max_allowed, h, ring_factor))

	return h
