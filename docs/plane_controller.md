# Plane Controller & Arquitectura del Jugador

Este documento describe la arquitectura, controles y funcionamiento del sistema de control del avión ubicado en la escena principal [`plane_scene.tscn`](file:///c:/Repos%20Godot/PlaneGame/Assets/NACHITEN/scenes/plane_scene.tscn).

---

## 1. Arquitectura de Nodos en la Escena

Para respetar las mejores prácticas de Godot 4 y permitir detección de colisiones e interacción física, el avión del jugador está estructurado como un `CharacterBody3D`:

```text
Testing Scene (Node3D)
├── WorldEnvironment (Cielo procedural y entorno)
├── DirectionalLight3D
├── Floor (Piso procedural con shader de ajedrez)
├── SM_Prop_Plane_Ring_01 .. 06 (Aros de objetivo)
├── PlayerPlane (CharacterBody3D) [plane_controller.gd]
│   ├── CollisionShape3D (SphereShape3D r=2.5)
│   └── SM_Veh_Plane_Stunt_01 (Malla visual 3D del avión y sus partes)
│       └── SM_Veh_Plane_Stunt_01_Prop (Hélice)
└── Camera3D (Camera3D) [smooth_camera.gd]
```

### Cámara Suave del Jugador (`smooth_camera.gd`)
- **Independiente de la jerarquía**: La cámara es un nodo hermano de `PlayerPlane` (hija directa de `Testing Scene`). Esto desacopla el giro instantáneo del avión del punto de vista del jugador, eliminando por completo el mareo por movimiento.
- **Posición y Rotación de referencia sagrada**: Mantiene exactamente la posición `(0, 8.201576, -12.943382)` y orientación configurada por el usuario como punto de equilibrio relativo al avión.
- **Amortiguación suave**:
  - Posición: Damping exponencial con `follow_speed` (`6.0`).
  - Rotación: `Quaternion.slerp` amortiguado con `rotation_speed` (`4.5`).
  - Inicio sin saltos: En `_ready()` se alinea instantáneamente al avión para evitar tirones en el primer frame.

---

## 2. Sistema de Coordenadas y Orientación

El modelo original (`SM_Veh_Plane_Stunt_01`) tiene su nariz y hélice en $+Z$ y su cola en $-Z$:
- **Avance frontal (*Forward*)**: $+Z$ local (`global_transform.basis.z`).
- **Ala izquierda**: $+X$ local.
- **Ala derecha**: $-X$ local.
- **Arriba**: $+Y$ local.

El avance y los giros de pitch y yaw están calculados en base a esta orientación para garantizar que el avión se desplace directamente hacia los aros alineados en $+Z$.

---

## 3. Controles (Vuelo Casual)

El juego cuenta con un modelo de vuelo arcade/casual: el avión avanza constantemente hacia adelante y el jugador controla el cabeceo (*pitch*), viraje (*yaw*) y velocidad.

| Acción | Teclado Principal | Teclado Alternativo / Flechas | Efecto |
| :--- | :--- | :--- | :--- |
| **Pitch Down** (Bajar nariz) | `W` | `Flecha Arriba` | Inclina la nariz hacia abajo (descenso) |
| **Pitch Up** (Subir nariz) | `S` | `Flecha Abajo` | Inclina la nariz hacia arriba (ascenso) |
| **Yaw Left** (Virar izquierda) | `A` | `Flecha Izquierda` | Gira la dirección hacia la izquierda |
| **Yaw Right** (Virar derecha) | `D` | `Flecha Derecha` | Gira la dirección hacia la derecha |
| **Acelerar / Boost** | `Shift` | `Barra Espaciadora` | Aumenta la velocidad hasta `max_speed` |
| **Frenar** | `Ctrl` | — | Reduce la velocidad hasta `min_speed` |

> **Nota sobre InputMap:** El script [`plane_controller.gd`](file:///c:/Repos%20Godot/PlaneGame/Assets/NACHITEN/scripts/plane_controller.gd) auto-registra las acciones en `InputMap` en tiempo de ejecución si aún no fueron agregadas en los Project Settings de Godot, y además cuenta con fallback directo a teclas físicas.

---

## 4. Efectos Visuales y Pulido Arcade

1. **Banking Visual (Inclinación de alas)**:
   - Al virar con `A` o `D`, la malla visual (`SM_Veh_Plane_Stunt_01`) se inclina en su eje local hasta `28°`.
2. **Animación de la Hélice**:
   - Detecta automáticamente el nodo `SM_Veh_Plane_Stunt_01_Prop` y lo hace rotar continuamente a alta velocidad (`1800°/s`).
3. **Horizon Auto-Leveling (Estabilización de Horizonte)**:
   - Aplica el viraje (Yaw) sobre el eje vertical del mundo (`Vector3.UP` global) y reconstruye la matriz `Basis` ortonormal alineada al horizonte en cada frame.
   - Elimina por completo el "roll drift" (torsión parásita por holonomía de rotación), garantizando que el fuselaje físico mantenga $0.0^\circ$ de roll independientemente de cuánto se gire o cabecee.

---

## 5. Parámetros Exportados (`@export`)

En el inspector de Godot se pueden calibrar los siguientes valores:

| Variable | Tipo | Default | Descripción |
| :--- | :--- | :--- | :--- |
| `base_speed` | `float` | `35.0` | Velocidad crucero constante (unidades/s). |
| `max_speed` | `float` | `65.0` | Velocidad máxima al acelerar con Shift/Espacio. |
| `min_speed` | `float` | `15.0` | Velocidad mínima al frenar con Ctrl. |
| `speed_lerp` | `float` | `2.5` | Suavizado al acelerar o desacelerar. |
| `pitch_speed` | `float` | `60.0` | Sensibilidad de cabeceo (grados/s). |
| `yaw_speed` | `float` | `50.0` | Sensibilidad de viraje (grados/s). |
| `rotation_lerp` | `float` | `4.0` | Suavizado de la entrada de dirección. |
| `invert_pitch` | `bool` | `false` | Invertir cabeceo vertical (estilo simulador de vuelo). |
| `max_pitch_angle` | `float` | `80.0` | Límite máximo de cabeceo (grados arriba/abajo) para evitar volteretas verticales. |
| `max_bank_angle`| `float` | `28.0` | Ángulo máximo de inclinación visual de alas al girar. |
| `bank_lerp` | `float` | `5.0` | Velocidad con la que las alas vuelven a posición horizontal. |
| `propeller_spin_speed` | `float` | `1800.0` | Velocidad de rotación de la hélice (grados/s). |
| `explosion_speed` | `float` | `1.0` | Multiplicador de velocidad de la explosión (1.0 = normal, 0.2 = cámara lenta épica). |

---

## 6. Sistema de Impacto, Explosión y Desmembramiento Físico

Al colisionar contra el terreno montañoso o el suelo (`move_and_slide()` con colisiones activas), el avión ejecuta una secuencia arcade de destrucción modular:

1. **Pre-calentamiento de Shader y Formas de Colisión (Anti-Lag)**:
   - Para evitar el tirón/lagazo de compilación de shader la primera vez que choca, [`plane_destruction.gd`](file:///c:/Repos%20Godot/PlaneGame/Assets/NACHITEN/scripts/plane_destruction.gd) instancia un dummy microscópico en `_ready()` que obliga a la GPU a compilar el pipeline del shader durante la carga inicial.
   - Además, pre-calcula los convex hulls físicos de las 12 piezas en memoria al inicio, logrando un impacto fluido a 60+ FPS sin pausas.

2. **Shader de Explosión (`explosion.gdshader` / `explosion_vfx.tscn`)**:
   - Dispara una bola de fuego procedural mediante ruido 3D Simplex/FBM que deforma los vértices de una esfera hacia afuera en tiempo real.
   - Cuenta con transición térmica: núcleo incandescente amarillo/blanco $\to$ fuego naranja $\to$ humo oscuro disipándose con clumping/erosión de ruido.
   - Genera un destello de luz omnidireccional cálido (`OmniLight3D`), una onda de choque expansiva en el suelo y una ráfaga de chispas y partículas de humo.
   - El efecto se auto-libera (`queue_free()`) al terminar su ciclo animado vía Tween.

3. **Desmembramiento Físico (`plane_destruction.gd`)**:
   - Cada submalla del modelo (`SM_Veh_Plane_Stunt_01`: fuselaje, hélice, ruedas, alerones individuales, timón de cola, cúpula de cristal, palanca de cabina) se extrae y se convierte en un `RigidBody3D` independiente.
   - A cada parte se le asigna su colisión simplificada (`create_convex_shape()`), masa proporcional a su tamaño y material físico con fricción y rebote.
   - Se aplica un impulso explosivo radial hacia afuera con sesgo ascendente, sumado a la inercia del avance del avión y velocidades angulares aleatorias para que giren y reboten por las pendientes.
   - El avión original desactiva sus controles y colisiones para evitar interferencias.

4. **Cámara Cinemática de Choque & Reinicio**:
   - `smooth_camera.gd` detecta el impacto y enfoca de forma cinematográfica los restos del fuselaje sin rotaciones bruscas que mareen al jugador.
   - El HUD despliega el cartel de impacto permitiendo reiniciar el vuelo instantáneamente con la tecla `[ R ]`.

