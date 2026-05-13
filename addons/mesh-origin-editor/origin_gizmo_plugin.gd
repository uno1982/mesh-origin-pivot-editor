@tool
extends EditorNode3DGizmoPlugin

# Untyped to avoid circular dependency — this is the plugin.gd EditorPlugin instance.
var plugin


func _init(p_plugin) -> void:
	plugin = p_plugin
	create_handle_material("handles")
	create_material("crosshair", Color(1.0, 0.8, 0.2))
	create_material("rotation_x", Color(1.0, 0.3, 0.3), false, true)
	create_material("rotation_y", Color(0.3, 1.0, 0.3), false, true)
	create_material("rotation_z", Color(0.3, 0.3, 1.0), false, true)


func _get_gizmo_name() -> String:
	return "MeshOriginEditor"


func _has_gizmo(node: Node3D) -> bool:
	return node is MeshInstance3D and (node as MeshInstance3D).mesh != null


## Helper function to generate points for a circle as line segments
func _generate_circle_points(radius: float, segments: int, axis: Vector3, center: Vector3) -> PackedVector3Array:
	var points := PackedVector3Array()
	var angle_step := TAU / segments
	
	# Find two perpendicular vectors to the axis
	var tangent: Vector3
	if abs(axis.dot(Vector3.UP)) < 0.99:
		tangent = axis.cross(Vector3.UP).normalized()
	else:
		tangent = axis.cross(Vector3.RIGHT).normalized()
	var bitangent := axis.cross(tangent).normalized()
	
	# Generate line segments (each segment needs 2 points: start and end)
	for i in segments:
		var angle1 := i * angle_step
		var angle2 := (i + 1) * angle_step
		
		var point1 := center + (tangent * cos(angle1) + bitangent * sin(angle1)) * radius
		var point2 := center + (tangent * cos(angle2) + bitangent * sin(angle2)) * radius
		
		points.push_back(point1)
		points.push_back(point2)
	
	return points


## Create a thick ring mesh (like Godot's rotation gizmo)
func _create_ring_mesh(radius: float, thickness: float, segments: int, axis: Vector3, center: Vector3, material: Material) -> ArrayMesh:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Find two vectors perpendicular to axis
	var tangent: Vector3
	if abs(axis.dot(Vector3.UP)) < 0.99:
		tangent = axis.cross(Vector3.UP).normalized()
	else:
		tangent = axis.cross(Vector3.RIGHT).normalized()
	var bitangent := axis.cross(tangent).normalized()
	
	var step := TAU / segments
	var thickness_segments := 3
	
	# Create vertices for the tube
	for i in range(segments):
		var angle := i * step
		var circle_pos := (tangent * cos(angle) + bitangent * sin(angle)) * radius
		
		for k in range(thickness_segments):
			var thickness_angle := k * TAU / thickness_segments
			var radial_dir := tangent * cos(angle) + bitangent * sin(angle)
			var normal := radial_dir * cos(thickness_angle) + axis * sin(thickness_angle)
			surface_tool.set_normal(normal.normalized())
			surface_tool.add_vertex(center + circle_pos + normal.normalized() * thickness)
	
	# Create triangles
	for i in range(segments):
		for k in range(thickness_segments):
			var current := i * thickness_segments + k
			var next_ring := ((i + 1) % segments) * thickness_segments + k
			var current_next := i * thickness_segments + ((k + 1) % thickness_segments)
			var next_ring_next := ((i + 1) % segments) * thickness_segments + ((k + 1) % thickness_segments)
			
			surface_tool.add_index(current_next)
			surface_tool.add_index(current)
			surface_tool.add_index(next_ring)
			
			surface_tool.add_index(next_ring)
			surface_tool.add_index(next_ring_next)
			surface_tool.add_index(current_next)
	
	surface_tool.set_material(material)
	return surface_tool.commit()


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var transform: Transform3D = plugin.current_gizmo_transform as Transform3D
	var offset := transform.origin
	var basis := transform.basis

	# Crosshair at the target origin handle.
	var s := 0.15
	var lines := PackedVector3Array([
		offset + Vector3(-s, 0.0, 0.0), offset + Vector3(s, 0.0, 0.0),
		offset + Vector3(0.0, -s, 0.0), offset + Vector3(0.0, s, 0.0),
		offset + Vector3(0.0, 0.0, -s), offset + Vector3(0.0, 0.0, s),
	])
	gizmo.add_lines(lines, get_material("crosshair", gizmo), false)
	
	# Draw rotation rings at FIXED local axes (not rotated)
	var ring_radius := 0.3
	var ring_segments := 64
	var ring_thickness := 0.02
	
	# X-axis rotation ring (perpendicular to X) - Red - FIXED at local X
	var x_mesh := _create_ring_mesh(ring_radius, ring_thickness, ring_segments, Vector3.RIGHT, offset, get_material("rotation_x", gizmo))
	gizmo.add_mesh(x_mesh)
	
	# Y-axis rotation ring (perpendicular to Y) - Green - FIXED at local Y
	var y_mesh := _create_ring_mesh(ring_radius, ring_thickness, ring_segments, Vector3.UP, offset, get_material("rotation_y", gizmo))
	gizmo.add_mesh(y_mesh)
	
	# Z-axis rotation ring (perpendicular to Z) - Blue - FIXED at local Z
	var z_mesh := _create_ring_mesh(ring_radius, ring_thickness, ring_segments, Vector3.BACK, offset, get_material("rotation_z", gizmo))
	gizmo.add_mesh(z_mesh)

	# Draw arrows pointing along each rotation axis
	var arrow_length := 0.5
	var arrow_head_size := 0.1
	
	# X-axis arrow (Red) - points along X
	var x_arrow_lines := PackedVector3Array([
		offset, offset + basis.x * arrow_length,
		offset + basis.x * arrow_length, offset + basis.x * (arrow_length - arrow_head_size) + basis.y * arrow_head_size,
		offset + basis.x * arrow_length, offset + basis.x * (arrow_length - arrow_head_size) - basis.y * arrow_head_size
	])
	gizmo.add_lines(x_arrow_lines, get_material("rotation_x", gizmo), false)
	
	# Y-axis arrow (Green) - points along Y
	var y_arrow_lines := PackedVector3Array([
		offset, offset + basis.y * arrow_length,
		offset + basis.y * arrow_length, offset + basis.y * (arrow_length - arrow_head_size) + basis.x * arrow_head_size,
		offset + basis.y * arrow_length, offset + basis.y * (arrow_length - arrow_head_size) - basis.x * arrow_head_size
	])
	gizmo.add_lines(y_arrow_lines, get_material("rotation_y", gizmo), false)
	
	# Z-axis arrow (Blue) - points along Z
	var z_arrow_lines := PackedVector3Array([
		offset, offset + basis.z * arrow_length,
		offset + basis.z * arrow_length, offset + basis.z * (arrow_length - arrow_head_size) + basis.x * arrow_head_size,
		offset + basis.z * arrow_length, offset + basis.z * (arrow_length - arrow_head_size) - basis.x * arrow_head_size
	])
	gizmo.add_lines(z_arrow_lines, get_material("rotation_z", gizmo), false)

	# Position handle at center only
	var handle_material := get_material("handles")
	gizmo.add_handles(PackedVector3Array([offset]), handle_material, PackedInt32Array([0]))


func _get_handle_name(_gizmo: EditorNode3DGizmo, _handle_id: int, _secondary: bool) -> String:
	return "Origin Point"


func _get_handle_value(_gizmo: EditorNode3DGizmo, _handle_id: int, _secondary: bool) -> Variant:
	return plugin.current_gizmo_transform


func _set_handle(gizmo: EditorNode3DGizmo, _handle_id: int, _secondary: bool,
		camera: Camera3D, screen_pos: Vector2) -> void:
	var node := gizmo.get_node_3d() as MeshInstance3D
	var gt := node.global_transform

	var ray_from := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)

	# Position handle - drag on a plane facing the camera
	var handle_world: Vector3 = gt * plugin.current_gizmo_transform.origin
	var cam_z := -camera.global_transform.basis.z.normalized()
	var plane := Plane(cam_z, handle_world.dot(cam_z))

	var hit: Variant = plane.intersects_ray(ray_from, ray_dir)
	if hit != null:
		plugin.current_gizmo_transform.origin = gt.affine_inverse() * (hit as Vector3)
		plugin.update_dock_spinboxes()
		node.update_gizmos()


func _commit_handle(gizmo: EditorNode3DGizmo, _handle_id: int, _secondary: bool,
		restore: Variant, cancel: bool) -> void:
	if cancel:
		plugin.current_gizmo_transform = restore
		plugin.update_dock_spinboxes()
	gizmo.get_node_3d().update_gizmos()
