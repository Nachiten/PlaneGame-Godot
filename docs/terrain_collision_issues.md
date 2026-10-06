# Diagnóstico de Problemáticas: Colisión del Avión contra el Terreno

Este documento describe en detalle las causas técnicas y el comportamiento observado de los tres problemas reportados al colisionar el avión contra el terreno procedural:

1. **El avión (y sus fragmentos) sale disparado muy lejos y con fuerza excesiva.**
2. **La cámara no queda apuntando correctamente al avión / restos.**
3. **El avión atraviesa el terreno (Tunneling y traspaso de mallas).**

---

## 1. Problemática 1: El avión sale disparado muy lejos, con mucha fuerza

### Síntoma
Al tocar tierra o una montaña, las partes del avión o el fuselaje salen despedidos a velocidades desproporcionadas, alejándose cientos de metros de la zona del choque.

### Análisis y Causa Raíz

1. **Suma acumulativa de velocidades en la dispersión (`plane_destruction.gd`):**
   - En la función `_create_debris_part()`, la velocidad lineal inicial de cada pieza se calcula como:
     $$\text{linear\_velocity} = (\text{impact\_velocity} \times [0.2 \dots 0.4]) + (\text{outward\_dir} \times \text{force\_mag})$$
   - El avión viaja entre **$35\text{ m/s}$ y $65\text{ m/s}$**. A esto se le suma una fuerza radial de explosión `force_mag` de entre **$8\text{ m/s}$ y $18\text{ m/s}$**, más un sesgo vertical aleatorio (`upward_bias`).
   - La velocidad resultante puede superar fácilmente los $40\text{--}50\text{ m/s}$, equivalente a más de $150\text{ km/h}$.

2. **Fuerza de despenetración violenta (*Physics Depenetration Pop*):**
   - Cuando el avión impacta, su modelo ya se encuentra solapado o parcialmente incrustado en la superficie del terreno.
   - En ese mismo instante exacto, `plane_destruction.gd` reemplaza el modelo instanciando de golpe múltiples nodos `RigidBody3D` con colisionadores convexos (`Shape3D`).
   - Al nacer dentro de la geometría sólida del terreno (`ConcavePolygonShape3D`), el motor de física de Godot detecta una superposición severa y aplica un impulso de separación masivo (*depenetration push*) en el siguiente tick de física, catapultando los cuerpos hacia el cielo o en direcciones imprevistas.

3. **Propiedades de amortiguación física bajas:**
   - En `_create_debris_part()`:
     - `pmat.bounce = 0.35`: Coeficiente de restitución alto para un choque destructivo de metal contra tierra.
     - `linear_damp = 0.5`: Amortiguamiento aerodinámico muy bajo, lo que permite que los objetos conserven su inercia durante segundos en el aire sin frenarse.

---

## 2. Problemática 2: La cámara no queda apuntando bien al avión

### Síntoma
Inmediatamente tras el impacto, la cámara queda orientada hacia zonas vacías, perdiendo de vista el fuselaje o rotando con lentitud y desorientación.

### Análisis y Causa Raíz

1. **Desfasaje cinemático entre objetivo veloz y suavizado lento (`smooth_camera.gd`):**
   - Al chocar, el método `on_target_destroyed(fuselage_debris)` redirige la cámara al `RigidBody3D` del fuselaje principal.
   - Sin embargo, en `_process_crash_camera()`, la posición focal se actualiza con un `lerp` amortiguado:
     ```gdscript
     _last_focus_pos = _last_focus_pos.lerp(target_pos, 1.0 - exp(-2.5 * delta))
     ```
   - Si el escombro sale disparado a gran velocidad (como se describió en el punto 1), `_last_focus_pos` se queda muy atrás respecto a la posición real del objeto, provocando que la cámara enfoque el espacio vacío que el escombro ya abandonó.

2. **Dirección de retroceso estática y congelada:**
   - La dirección de zoom (`_crash_away_dir`) se calcula una única vez al momento exacto del impacto basándose en la posición inicial:
     ```gdscript
     var away := (global_position - _last_focus_pos)
     _crash_away_dir = away.normalized()
     ```
   - Si los escombros rebotan o se desplazan hacia una dirección distinta a la que la cámara calculó originalmente, la cámara no recalcula su ángulo de observación, pudiendo quedar delante de la trayectoria de los restos o apuntando en un vector ciego.

3. **Inercia rotacional y retardo en `Basis.looking_at`:**
   - La rotación de la cámara utiliza un `slerp` sobre cuaterniones con un factor de suavizado moderado (`rot_factor` con tasa $3.5$).
   - Durante los primeros $0.5\text{--}1.0$ segundos posteriores al choque, la cámara no alcanza a alinearse con la nueva trayectoria del objetivo.

4. **Falta de evasión de oclusión por relieve (Montañas):**
   - La cámara cinemática de choque no cuenta con un sistema de verificación de línea de visión (*SpringArm3D* o raycasts contra el terreno). Si el avión choca contra la ladera de una montaña y cae al otro lado, la cámara se coloca detrás de la roca, quedando tapada por el terreno.

---

## 3. Problemática 3: El avión muchas veces atraviesa el terreno

### Síntoma
En maniobras de descenso rápido o choques directos, el avión no colisiona con la ladera visible, sino que se hunde en el terreno, atraviesa la montaña o cae al vacío infinito por debajo del mapa.

### Análisis y Causa Raíz

1. **Efecto de "Túnel" (*Tunneling*) por velocidad vs. frecuencia física:**
   - A velocidad máxima ($65\text{ m/s}$), el avión recorre más de **$1.08\text{ metros}$ en un solo frame de física** ($60\text{ Hz}$).
   - `PlayerPlane` es un `CharacterBody3D` que utiliza `move_and_slide()`. Los `CharacterBody3D` en Godot no poseen detección continua de colisiones (*Continuous Collision Detection / CCD*) bidireccional automática contra mallas cóncavas estáticas.
   - Si en el tick $N$ el avión está a $0.5\text{ m}$ por delante de la cara del triángulo, en el tick $N+1$ ya ha avanzado $1.08\text{ m}$, quedando a $0.58\text{ m}$ por detrás de la superficie.

2. **Naturaleza unilateral y grosor cero de `ConcavePolygonShape3D`:**
   - El terreno genera su física mediante `ConcavePolygonShape3D` (`procedural_terrain.gd:207`).
   - Las formas cóncavas son mallas de triángulos con grosor cero e infinitamente delgadas (*one-sided*). Solo tienen normal de colisión hacia el frente exterior.
   - Una vez que el centro del colisionador cruza el plano del triángulo en un frame rápido, el motor de físicas considera que el avión está "fuera" o por detrás del plano, por lo que **no detecta ninguna colisión adicional**, permitiendo que continúe cayendo libremente debajo de la montaña.

3. **Discrepancia geométrica entre la malla visual y la colisión física (LOD a paso 2):**
   - En `procedural_terrain.gd`, la malla visual se genera con la resolución completa (`step = 1`, quads de aprox. $6\text{ metros}$):
     ```gdscript
     // Malla visual: recorre todos los índices i, j uno a uno
     ```
   - Sin embargo, para la física se utiliza una optimización con paso 2 (`procedural_terrain.gd:171`):
     ```gdscript
     var col_quads_x: int = int(ceil(float(quads_x) / 2.0))
     // ...
     while j < quads_z:
         j += 2
     ```
   - Esto significa que la colisión física tiene la mitad de resolución espacial (triángulos de $\approx 12\text{--}13\text{ metros}$). En picos puntiagudos, bordes afilados o cañones escarpados, el triángulo de colisión corta en línea recta ("corta esquinas") respecto a la superficie visual.
   - El jugador ve la roca visual varios metros por delante o por encima del collider físico real, dando la ilusión visual de que el avión se incrusta profundamente o desaparece dentro de la roca antes de que el motor de físicas registre algún contacto.

4. **Falta de detección continua en los restos (`RigidBody3D`):**
   - Los fragmentos generados por `plane_destruction.gd` se instancian con `continuous_cd = false` (por defecto en Godot). Al salir disparados a altas velocidades contra triángulos cóncavos sin espesor, los escombros también experimentan tunneling y traspasan el suelo hacia abajo.

---

## 4. Matriz de Componentes Involucrados

| Problemática | Archivos Involucrados | Componente / Parámetro Clave | Mecanismo |
|---|---|---|---|
| **1. Dispersión violenta** | `Assets/NACHITEN/scripts/plane_destruction.gd` | `explosion_force_max`, `pmat.bounce`, `linear_damp` | Velocidades sumadas muy altas + impulso de despenetración por solapamiento de mallas. |
| **2. Pérdida de foco de cámara** | `Assets/NACHITEN/scripts/smooth_camera.gd` | `_last_focus_pos.lerp`, `_crash_away_dir`, `Basis.looking_at` | El objetivo se aleja más rápido que el lerp de seguimiento; dirección de zoom estática. |
| **3. Traspaso de terreno** | `Assets/NACHITEN/scripts/procedural_terrain.gd`<br>`Assets/NACHITEN/scripts/plane_controller.gd` | `ConcavePolygonShape3D` (LOD paso 2), ausencia de CCD en `CharacterBody3D` | Tunneling a alta velocidad + discrepancia entre malla visual (paso 1) y colisión (paso 2). |

---

## 5. Posibles Vías de Abordaje Futuro (Sin Modificar Código)

Para cuando se decida implementar la solución técnica, las líneas de acción recomendadas a evaluar son:

1. **Para la dispersión excesiva:**
   - Reducir la fuerza explosiva radial y elevar significativamente la amortiguación (`linear_damp` y `angular_damp`).
   - Reducir el rebote (`bounce`) para que las piezas absorban impacto en lugar de rebotar como goma.
   - Limitar la velocidad máxima de los escombros mediante un `clamp` de velocidad lineal.

2. **Para la cámara de choque:**
   - Hacer que la dirección y distancia de la cámara acompañen dinámicamente el centro de masa de los escombros o se anclen a un punto de vista estático sobre el punto de impacto original.
   - Ajustar el tiempo de respuesta de rotación para que mantenga al objetivo centrado en el encuadre.
   - Incorporar control de altura o raycast para evitar que la cámara quede bajo tierra o detrás de una montaña.

3. **Para el traspaso del terreno:**
   - Sincronizar la resolución de la colisión del terreno con la malla visual o emplear `HeightMapShape3D` (el cual posee volumen sólido hacia abajo y previene atravesar el suelo por debajo).
   - Implementar un raycast predictivo hacia adelante (*Shapecast* o *Raycast*) en el avión para detectar colisiones inminentes antes de que ocurra el tunneling por frame.
   - Activar Continuous Collision Detection (CCD) en los escombros `RigidBody3D`.
