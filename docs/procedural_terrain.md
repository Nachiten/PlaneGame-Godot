# Terreno Procedural de Montañas

Este documento describe la arquitectura, parámetros y funcionamiento del sistema de terreno procedural ubicado en la escena principal [`plane_scene.tscn`](file:///c:/Repos%20Godot/PlaneGame/Assets/NACHITEN/scenes/plane_scene.tscn).

---

## 1. Arquitectura y Funcionamiento

El terreno es generado proceduralmente en tiempo de ejecución por el script [`procedural_terrain.gd`](file:///c:/Repos%20Godot/PlaneGame/Assets/NACHITEN/scripts/procedural_terrain.gd) sin depender de modelos 3D externos.

- **Generación Visual (`SurfaceTool` + `ArrayMesh`):**
  - Construye una malla poligonal con estilo *low-poly* facetado (normales calculadas por cara triangular), consistente con la estética de los modelos de aviones y accesorios.
- **Función de Ruido (`FastNoiseLite`):**
  - Muestreo fractal simplex (FBM) para modelar cordilleras, valles y cumbres escarpadas.
- **Cañón de Vuelo Inteligente (Protección de Aros):**
  - Detecta automáticamente los nodos de aros (`Ring`) en la escena y suaviza/atenúa la elevación a su alrededor para que nunca queden enterrados bajo una montaña.
  - Mantiene el área de despegue/spawn `(0, 0)` plana y despejada.
- **Colisión Física:**
  - Crea un `StaticBody3D` con `ConcavePolygonShape3D` (`mesh.create_trimesh_shape()`) correspondiente a la geometría visual exacta para permitir choques del avión.
- **Shader Estilizado ([`mountain_terrain.gdshader`](file:///c:/Repos%20Godot/PlaneGame/Assets/NACHITEN/shaders/mountain_terrain.gdshader)):**
  - Pinta dinámicamente según la altura del mundo y la pendiente:
    - **Valle/Pasto:** Tierras bajas y llanuras.
    - **Roca:** Laderas empinadas y cotas medias.
    - **Nieve:** Cumbres altas y mesetas elevadas.

---

## 2. Parámetros Exportados (`@export`)

En el inspector de Godot, seleccionando el nodo `ProceduralTerrain`, se pueden calibrar los siguientes valores:

| Variable | Tipo | Default | Descripción |
| :--- | :--- | :--- | :--- |
| `terrain_size` | `Vector2` | `(2400, 3800)` | Dimensiones en el mundo (ancho X, largo Z). |
| `center_offset` | `Vector3` | `(250, 0, 1900)` | Desplazamiento del centro para abarcar la pista de aros. |
| `grid_resolution` | `Vector2i` | `(380, 580)` | Subdivisión de vértices (triángulos pequeños de ~6m). |
| `max_height` | `float` | `460.0` | Altura máxima de las cumbres (escala alpina monumental). |
| `noise_frequency` | `float` | `0.0016` | Escala de las cordilleras (cordilleras amplias y valles majestuosos). |
| `noise_octaves` | `int` | `4` | Detalle fino fractal. |
| `noise_seed` | `int` | `1337` | Semilla procedural (cambiarla genera otro mapa). |
| `spawn_clear_radius` | `float` | `200.0` | Radio despejado alrededor de la pista inicial `(0, 0)`. |
| `clear_rings_path` | `bool` | `true` | Esculpe cañones automáticamente alrededor de los aros. |
| `ring_clear_radius` | `float` | `85.0` | Distancia de despeje alrededor de cada aro. |
| `low_poly_shading` | `bool` | `true` | Caras planas facetadas (*flat shading* estilo low-poly). |
| `generate_collision` | `bool` | `true` | Generar colisionador tridimensional optimizado. |
