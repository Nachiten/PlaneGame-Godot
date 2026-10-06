# Flujo de Importación Blender -> Godot 4 (Workflow 3D)

Esta guía documenta el flujo de trabajo para modelar/modificar assets en **Blender** e importarlos en **Godot 4.x**, con foco en el modelo del avión (`SM_Veh_Plane_Stunt_01`) y el sistema de corte de piezas para desmembramiento físico (`plane_destruction.gd`).

---

## 1. Cómo funciona la importación 3D en Godot 4

Cuando colocas un archivo 3D en el proyecto (`.blend`, `.glb` o `.fbx`), Godot **no lo utiliza directamente en tiempo de ejecución**. En su lugar:

1. **Compilación a escena interna (`.scn`)**:
   - Godot procesa el archivo fuente y genera una escena binaria optimizada dentro del directorio oculto:
     ```
     res://.godot/imported/<archivo>-<hash>.scn
     ```
   - **Regla de oro**: **Nunca** se deben editar, mover ni reemplazar manualmente los archivos dentro de `.godot/imported/`. Son archivos temporales de caché administrados 100% por el motor.

2. **Archivo de metadatos (`.import`)**:
   - Cada modelo tiene su archivo `.import` asociado (ej. `SM_Veh_Plane_Stunt_01.blend.import`).
   - Contiene la configuración de importación (escala, si extrae mallas, si importa animaciones, LODs, etc.) y apunta al `.scn` generado en caché.

---

## 2. Comparativa de Formatos: ¿Qué conviene más?

| Formato | ¿Cómo lo procesa Godot? | Ventajas | Desventajas | Recomendación |
| :--- | :--- | :--- | :--- | :--- |
| **`.blend`** | Llama a Blender en segundo plano por CLI (`blender.exe --background`) y exporta un glTF temporal que Godot lee. | • **Iteración instantánea**: Guardas en Blender (`Ctrl+S`) y se actualiza solo en Godot sin exportar a mano. | • Requiere configurar la ruta de Blender en Godot.<br>• Genera archivos `.blend1` (backups).<br>• Más lento si el archivo es pesado. | **Ideal para modelar y cortar piezas activamente en tu máquina.** |
| **`.glb` / `.gltf`** | Importador nativo ultra rápido en C++ dentro de Godot. Formato abierto estándar (Khronos). | • **Estándar de la industria para Godot**.<br>• Carga instantánea.<br>• Ejes y escalas predecibles.<br>• No depende de tener Blender instalado. | • Requiere un paso manual: en Blender hacer *File -> Export -> glTF 2.0*. | **Ideal para versión final limpia o proyectos en equipo.** |
| **`.fbx`** | Usa convertidor `ufbx` o herramienta externa `FBX2glTF`. | • Formato común en packs comerciales (Synty). | • Formato cerrado y propietario de Autodesk.<br>• Frecuentes problemas de escala (100x cm vs 1m) y rotaciones de ejes.<br>• Más pesado. | **Evitar para nuevos modelos. Solo usar cuando el asset original ya venga en FBX.** |

> [!TIP]
> **Veredicto para este proyecto**: 
> Puedes trabajar directamente con el archivo **`.blend`** en `Assets/NACHITEN/` mientras estás cortando y testeando las partes de la explosión. Cuando las mallas estén definitivas, puedes exportar un **`.glb`** limpio si deseas máxima portabilidad.

---

## 3. Reglas de Organización y Assets

Siguiendo las pautas del proyecto ([asset_guidelines.md](file:///c:/Repos%20Godot/PlaneGame/docs/asset_guidelines.md)):

1. **No tocar ni pisar `Assets/Synty/`**:
   - Los assets originales de Synty son recursos base. No hace falta modificar ni pisar `Assets/Synty/.../SM_Veh_Plane_Stunt_01.fbx`.
2. **Ubicación de assets modificados**:
   - Todo modelo editado o cortado debe residir en `Assets/NACHITEN/` (por ejemplo, en `Assets/NACHITEN/models/` o `Assets/NACHITEN/FBX/`).
3. **Escena visual del avión**:
   - La escena principal `plane_scene.tscn` instancia a:
     ```
     res://Assets/NACHITEN/scenes/SM_Veh_Plane_Stunt_01.tscn
     ```
   - Esta es la escena que debemos actualizar con las nuevas piezas cortadas.

---

## 4. Flujo Paso a Paso para Cortar y Actualizar el Avión

### Paso 1: Preparación en Blender
1. **Separar las partes en objetos independientes**:
   - En Modo Edición (`Edit Mode`), selecciona los vértices/caras que formarán una pieza de escombros (ej. mitad del ala izquierda, punta de la cola, trozo de cabina).
   - Presiona `P` -> **Selection** para separarlo en un nuevo objeto (`Object`).
2. **Nombrar cada objeto con claridad**:
   - Asigna nombres semánticos en el Outliner:
     * `SM_Veh_Plane_Stunt_01_Wing_Left_ChunkA`
     * `SM_Veh_Plane_Stunt_01_Tail_Chunk`
     * `SM_Veh_Plane_Stunt_01_Fuselage_Front`
   - *Nota para `plane_destruction.gd`*: El script busca automáticamente todos los `MeshInstance3D` hijos. Cuanto más descriptivo sea el nombre, mejor se comportará el cálculo de masa y colisión.
3. **Ajustar el origen de pivote de cada pieza**:
   - Selecciona los objetos cortados -> Click derecho -> **Set Origin** -> **Origin to Geometry** (o al punto de corte). Esto asegura que al explotar giren naturalmente sobre su centro de masa.
4. **Verificar orientación de avance**:
   - En la convención de este proyecto, el avión mira hacia **$+Z$**.

---

### Paso 2: Guardar o Exportar
- **Opción `.blend`**:
  - Guarda el archivo directamente dentro de tu proyecto Godot:
    `Assets/NACHITEN/models/SM_Veh_Plane_Stunt_01.blend`
- **Opción `.glb`**:
  - *File -> Export -> glTF 2.0 (.glb)*.
  - Activar: *Transform -> +Y Up*, *Geometry -> Apply Modifiers*.
  - Guardar en `Assets/NACHITEN/models/SM_Veh_Plane_Stunt_01.glb`.

---

### Paso 3: Configurar Blender en Godot (Solo si usas `.blend`)
Si Godot no importa automáticamente el archivo `.blend`:
1. Ve a **Editor -> Editor Settings** en la barra superior de Godot.
2. En el buscador escribe `blender`.
3. Ve a **FileSystem -> Import -> Blender**.
4. En el campo **Blender 3 RPC Path** (o **Blender Path**), selecciona la ruta a tu ejecutable de Blender:
   *(Normalmente `C:/Program Files/Blender Foundation/Blender 4.x/blender.exe`)*.

---

### Paso 4: Crear la Escena en Godot (Heredada / Inherited Scene)

En vez de extraer mallas `.res` a mano una por una, el método moderno de Godot 4 es usar **Escenas Heredadas**:

1. En el dock *FileSystem* de Godot, haz **click derecho** sobre `SM_Veh_Plane_Stunt_01.blend` (o `.glb`).
2. Elige **"New Inherited Scene"** (Nueva escena heredada).
3. Verás la jerarquía con todas las piezas cortadas que definiste en Blender.
4. Asigna los materiales correspondientes a las piezas:
   - Material de pintura: `res://Assets/Synty/PolygonStarter/Materials/Plane/PolygonStarter_Mat_Plane_01_mat.tres`
   - Material de cristal: `res://Assets/Synty/PolygonStarter/Materials/Misc/PolygonStarter_Mat_01_Glass_mat.tres`
5. Guarda esta escena como:
   ```
   res://Assets/NACHITEN/scenes/SM_Veh_Plane_Stunt_01.tscn
   ```
   *(Pisa o actualiza la escena existente que ya está conectada al jugador)*.

---

### Paso 5: Cómo lo aprovecha el Sistema de Destrucción

El script [plane_destruction.gd](file:///c:/Repos%20Godot/PlaneGame/Assets/NACHITEN/scripts/plane_destruction.gd):
1. Al chocar el avión, recorre recursivamente todos los nodos `MeshInstance3D` hijos de `SM_Veh_Plane_Stunt_01`.
2. Oculta el avión original.
3. Instancia un `RigidBody3D` para **cada una de las piezas cortadas** con:
   - Su respectiva colisión convexa generada a partir de la malla.
   - Masa calculada por componente.
   - Vector de impulso explosivo outward + inercia de impacto + rotación angular aleatoria.

Con este flujo, **cualquier pieza nueva que cortes en Blender aparecerá automáticamente volando en la explosión** sin tener que modificar una sola línea de código en GDScript.

---

## 5. Limpieza y Buenas Prácticas en Git

Blender genera automáticamente archivos de respaldo `.blend1`. Para evitar subirlos a GitHub, es recomendable incluir en [.gitignore](file:///c:/Repos%20Godot/PlaneGame/.gitignore):

```gitignore
# Blender autosave & backups
*.blend1
*.blend2
```
