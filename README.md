# Mesh Origin Editor

A Godot 4 editor plugin that lets you reposition the origin (pivot point) of a `MeshInstance3D` by baking a new offset directly into the mesh vertex data.

## Features

- **Center** — moves the origin to the geometric center of the mesh's bounding box.
- **Bottom Center** — moves the origin to the bottom-center of the bounding box (useful for characters and objects that sit on a surface).
- **Top Center** — moves the origin to the top-center of the bounding box.
- **Custom Offset** — type an exact X / Y / Z offset or drag the 3D gizmo handle in the viewport to place the origin anywhere in local mesh space.
- Non-destructive node position compensation — the node's world position is preserved after every bake.
- Full **undo / redo** support through Godot's built-in `UndoRedo` system.
- Works with both `ArrayMesh` and built-in `PrimitiveMesh` subclasses (`BoxMesh`, `SphereMesh`, `CapsuleMesh`, etc.).

## Installation

1. Copy the `addons/mesh-origin-editor` folder into your project's `addons/` directory.
2. Open **Project → Project Settings → Plugins** and enable **Mesh Origin Editor**.

## Usage

1. Select a `MeshInstance3D` node in the scene tree.
2. Open the **Mesh Origin Editor** dock (bottom-right by default).
3. Choose one of the preset buttons (**Center**, **Bottom Center**, **Top Center**) or enter a custom offset and click **Apply Custom**.
   - Alternatively, drag the yellow crosshair handle in the 3D viewport and click **Apply Custom** to bake that position.
4. The mesh vertices are rebaked and the node position is adjusted automatically so nothing moves in world space.

## Requirements

- Godot **4.x**

## License

MIT
