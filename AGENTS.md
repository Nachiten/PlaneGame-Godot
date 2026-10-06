# Guía para Agentes de IA (AGENTS.md)

Este repositorio contiene un juego de vuelo casual desarrollado en **Godot 4.7.2**.

Antes de realizar tareas, modificaciones en escenas, scripts o selección de assets, **debes consultar y respetar la documentación ubicada en el directorio `/docs`**.

---

## Índice de Documentación (`/docs/`)

- [**Asset Guidelines**](/docs/asset_guidelines.md): Reglas estrictas sobre qué carpetas de assets usar y cuáles ignorar.
- [**Plane Controller**](/docs/plane_controller.md): Arquitectura, controles y parámetros del avión y su cámara.

---

## Reglas Críticas del Proyecto

1. **Uso de Assets**:
   - Solo usar y leer assets dentro de `Assets/NACHITEN/`.
   - Ignorar por completo la carpeta `Assets/Synty/` (son assets base importados del pack original), salvo instrucción explícita del usuario.
2. **Escena Principal**:
   - La escena principal configurada es `Assets/NACHITEN/scenes/plane_scene.tscn`.
3. **Cámara del Jugador**:
   - La posición y rotación relativa de la cámara respecto al avión `(0, 8.201576, -12.943382)` fue ajustada por el usuario y debe mantenerse como referencia sagrada.
4. **Convención de Ejes del Avión**:
   - El modelo del avión mira hacia **$+Z$** (hacia los aros). El avance hacia adelante es el eje $+Z$ (`global_transform.basis.z`).
