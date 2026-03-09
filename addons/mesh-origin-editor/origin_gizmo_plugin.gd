@tool
extends EditorNode3DGizmoPlugin

# Untyped to avoid circular dependency — this is the plugin.gd EditorPlugin instance.
var plugin

func _init(p_plugin) -> void:
	plugin = p_plugin
	create_handle_material("handles")
	create_material("crosshair", Color(1.0, 0.8, 0.2))


func _get_gizmo_name() -> String:
	return "MeshOriginEditor"


func _has_gizmo(node: Node3D) -> bool:
	return node is MeshInstance3D and (node as MeshInstance3D).mesh != null


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var offset: Vector3 = plugin.current_gizmo_offset as Vector3

	# Crosshair at the target origin handle.
	var s := 0.15
	var lines := PackedVector3Array([
		offset + Vector3(-s, 0.0, 0.0), offset + Vector3(s, 0.0, 0.0),
		offset + Vector3(0.0, -s, 0.0), offset + Vector3(0.0, s, 0.0),
		offset + Vector3(0.0, 0.0, -s), offset + Vector3(0.0, 0.0, s),
	])
	gizmo.add_lines(lines, get_material("crosshair", gizmo), false)

	# Single draggable sphere handle.
	gizmo.add_handles(PackedVector3Array([offset]), get_material("handles", gizmo), [])


func _get_handle_name(_gizmo: EditorNode3DGizmo, _handle_id: int, _secondary: bool) -> String:
	return "Origin Point"


func _get_handle_value(_gizmo: EditorNode3DGizmo, _handle_id: int, _secondary: bool) -> Variant:
	# Return a copy so it isn't mutated during drag (used as restore value on cancel).
	return plugin.current_gizmo_offset


func _set_handle(gizmo: EditorNode3DGizmo, _handle_id: int, _secondary: bool,
		camera: Camera3D, screen_pos: Vector2) -> void:
	var node := gizmo.get_node_3d() as MeshInstance3D
	var gt := node.global_transform

	var ray_from := camera.project_ray_origin(screen_pos)
	var ray_dir  := camera.project_ray_normal(screen_pos)

	# Drag on a plane facing the camera that passes through the current handle world pos.
	var handle_world: Vector3 = gt * (plugin.current_gizmo_offset as Vector3)
	var cam_z := -camera.global_transform.basis.z.normalized()
	var plane := Plane(cam_z, handle_world.dot(cam_z))

	var hit: Variant = plane.intersects_ray(ray_from, ray_dir)
	if hit != null:
		plugin.current_gizmo_offset = gt.affine_inverse() * (hit as Vector3)
		plugin.update_dock_spinboxes()
		node.update_gizmos()


func _commit_handle(gizmo: EditorNode3DGizmo, _handle_id: int, _secondary: bool,
		restore: Variant, cancel: bool) -> void:
	if cancel:
		plugin.current_gizmo_offset = restore
		plugin.update_dock_spinboxes()
	gizmo.get_node_3d().update_gizmos()
