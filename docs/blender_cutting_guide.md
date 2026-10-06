# Guía Rápida: Cortar, Cerrar y Triangular Mallas en Blender

Esta guía explica el flujo de trabajo ultra-rápido usando atajos de teclado para separar un pedazo de un modelo (ej. romper el ala de un avión), rellenar el agujero que queda, y prepararlo para exportar a Godot.

---

## 📌 Resumen y Glosario

**Modos Principales:**
- **Object Mode** (Modo Objeto): Para seleccionar piezas enteras.
- **Edit Mode** (Modo Edición): Para modificar vértices, bordes y caras de una pieza.

**Glosario de Hotkeys (Atajos de Teclado):**
- `Tab`: Alternar entre *Object Mode* y *Edit Mode*.
- `1`, `2`, `3` (Arriba de las letras): Cambiar modo de selección a Vértices (`1`), Bordes (`2`) o Caras (`3`).
- `Z` (mantener y arrastrar mouse): Cambiar vista (Wireframe, Solid).
- `C` / `B` / `L`: Selección de brocha circular (`C`), caja (`B`), o toda la pieza conectada (`L`).
- `P`: Separar la selección en un nuevo objeto independiente (Separate).
- `F`: Rellenar caras huecas o crear cara nueva (Fill).
- `Alt + Click Izquierdo`: Seleccionar un bucle cerrado de bordes (*Edge Loop*).
- `Ctrl + T`: Triangular las caras seleccionadas.
- `Alt + P`: Desvincular un objeto de su padre (Clear Parent).

---

## 🔪 Tutorial Paso a Paso

### Paso 1: Seleccionar lo que quieres cortar
1. Selecciona el avión principal y presiona **`Tab`** para entrar a **Edit Mode**.
2. Presiona **`3`** para activar la selección de caras (Faces).
3. Selecciona la parte del modelo que quieres separar. 
   *(Tip: Puedes presionar `Z` -> ir a `Wireframe` y usar la letra `B` para crear una caja de selección perfecta que atrape todos los polígonos de un ala, o usar `C` para pintar la selección).*

### Paso 2: Separar la pieza (El Corte)
1. Con las caras de tu nueva pieza ya seleccionadas, presiona **`P`**.
2. En el menú que aparece, elige **Selection**.
3. Presiona **`Tab`** para salir a **Object Mode**. ¡Listo! Ahora tienes dos objetos distintos.

### Paso 3: Rellenar los agujeros huecos (Cerrar la Malla)
Al realizar el corte, ambas piezas (el avión y el trozo cortado) quedarán huecas por dentro. Para que Godot calcule el volumen físico correctamente, la malla debe estar cerrada (*manifold*).

1. Selecciona el nuevo trozo cortado y presiona **`Tab`** para entrar a su **Edit Mode**.
2. Presiona **`2`** para cambiar al modo de selección de Bordes (Edges).
3. Mantén la tecla **`Alt`** presionada y haz **Click Izquierdo** sobre cualquiera de los bordes del agujero. Esto seleccionará mágicamente todo el contorno (Edge Loop).
4. Presiona **`F`**. Se creará una cara plana que cerrará completamente el agujero.
5. *(Recuerda volver a Object Mode, seleccionar el avión original y repetir este proceso para tapar el hueco que quedó en el fuselaje).*

### Paso 4: Triangular la nueva cara
Esa cara gigante que creaste con la `F` es probablemente un *N-Gon* (un polígono de más de 4 lados). Los motores de videojuegos (Godot) necesitan que toda la geometría sean triángulos.

1. Mientras aún tienes esa nueva cara seleccionada en Edit Mode, presiona **`Ctrl + T`**.
2. Blender conectará los vértices automáticamente creando una red de triángulos perfecta.

### Paso 5: Arreglar el Centro de Masa y Jerarquía (Crítico para Físicas)
Para que los escombros no salgan volando por un error físico en Godot, debes hacer esto por cada pieza cortada:

1. Presiona **`Tab`** para salir a **Object Mode**.
2. Selecciona la pieza cortada.
3. Haz **Click Derecho -> Set Origin -> Origin to Geometry**. *(Esto pone el pivote en el centro de la pieza, vital para el Centro de Masa de Godot).*
4. Mueve el cursor a la ventana 3D y presiona **`Alt + P`**.
5. Elige **Clear and Keep Transformation**. *(Esto asegura que la pieza sea independiente y no hija del avión original, manteniéndola en su lugar exacto).*
6. Dale un nombre claro en el Outliner (ej: `Fuselage_Chunk_01`).

¡Guarda el `.blend` (`Ctrl + S`) y Godot se encargará del resto!
