@tool
extends EditorPlugin

const DOCK_SCENE = preload("./origin_dock.tscn")
const GizmoPluginScript = preload("./origin_gizmo_plugin.gd")

var _dock: Control
var _selection: EditorSelection
var _gizmo_plugin: EditorNode3DGizmoPlugin

## Current handle transform (position + rotation) in the selected node's local mesh space.
## Shared between the dock spinboxes and the 3D gizmo.
var current_gizmo_transform := Transform3D.IDENTITY

## Stores original mesh data for revert functionality.
## Key: node instance_id, Value: {"mesh": Mesh, "transform": Transform3D}
var _original_meshes: Dictionary = {}

# Rotation drag state
var _dragging_ring := -1  # -1 = none, 0 = X, 1 = Y, 2 = Z
var _drag_start_basis := Basis.IDENTITY
var _drag_axis := Vector3.ZERO
var _drag_initial_vector := Vector3.ZERO
var _drag_origin := Vector3.ZERO


func _enter_tree() -> void:
	_dock = DOCK_SCENE.instantiate()
	_dock.plugin = self
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, _dock)

	_gizmo_plugin = GizmoPluginScript.new(self)
	add_node_3d_gizmo_plugin(_gizmo_plugin)

	_selection = get_editor_interface().get_selection()
	_selection.selection_changed.connect(_on_selection_changed)
	_on_selection_changed()


func _exit_tree() -> void:
	if _selection and _selection.selection_changed.is_connected(_on_selection_changed):
		_selection.selection_changed.disconnect(_on_selection_changed)
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
	if _gizmo_plugin:
		remove_node_3d_gizmo_plugin(_gizmo_plugin)
		_gizmo_plugin = null


func _on_selection_changed() -> void:
	if not _dock:
		return
	var mesh_instance := _get_selected_mesh_instance()
	# Reset gizmo handle to origin when switching to a new node.
	current_gizmo_transform = Transform3D.IDENTITY
	_dock.set_target(mesh_instance)
	if mesh_instance:
		_stash_original_if_needed(mesh_instance)
		mesh_instance.update_gizmos()


## Stores the original mesh and transform for later revert, if not already stashed.
func _stash_original_if_needed(node: MeshInstance3D) -> void:
	var id := node.get_instance_id()
	if not _original_meshes.has(id) and node.mesh:
		_original_meshes[id] = {
			"mesh": node.mesh.duplicate(true),
			"transform": node.transform
		}


## Returns true if the given node has a stashed original state.
func has_original(node: MeshInstance3D) -> bool:
	return _original_meshes.has(node.get_instance_id())


## Reverts the mesh and transform to the original stashed state.
func revert_to_original(node: MeshInstance3D) -> bool:
	var id := node.get_instance_id()
	if not _original_meshes.has(id):
		return false
	
	var original: Dictionary = _original_meshes[id]
	
	var undo := get_undo_redo()
	undo.create_action("Revert to Original Mesh")
	undo.add_do_property(node, "mesh", original["mesh"].duplicate(true))
	undo.add_undo_property(node, "mesh", node.mesh)
	undo.add_do_property(node, "transform", original["transform"])
	undo.add_undo_property(node, "transform", node.transform)
	undo.commit_action()
	
	return true


## Clears the stashed original for this node (call after user explicitly saves a new baseline).
func clear_original(node: MeshInstance3D) -> void:
	_original_meshes.erase(node.get_instance_id())


## Re-stashes the current mesh state as the new original.
func restash_original(node: MeshInstance3D) -> void:
	var id := node.get_instance_id()
	if node.mesh:
		_original_meshes[id] = {
			"mesh": node.mesh.duplicate(true),
			"transform": node.transform
		}


func _get_selected_mesh_instance() -> MeshInstance3D:
	var nodes := _selection.get_selected_nodes()
	if nodes.size() == 1 and nodes[0] is MeshInstance3D:
		return nodes[0] as MeshInstance3D
	return null


func _handles(object: Object) -> bool:
	return object is MeshInstance3D


func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	var mesh_instance := _get_selected_mesh_instance()
	if not mesh_instance:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				# Check if we clicked on a ring
				var ring := _test_ring_intersection(viewport_camera, mb.position, mesh_instance)
				if ring >= 0:
					_start_rotation_drag(ring, viewport_camera, mb.position, mesh_instance)
					return EditorPlugin.AFTER_GUI_INPUT_STOP
			else:
				if _dragging_ring >= 0:
					_dragging_ring = -1
					return EditorPlugin.AFTER_GUI_INPUT_STOP
	
	elif event is InputEventMouseMotion and _dragging_ring >= 0:
		var mm := event as InputEventMouseMotion
		_update_rotation_drag(viewport_camera, mm.position, mesh_instance)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _test_ring_intersection(camera: Camera3D, screen_pos: Vector2, node: MeshInstance3D) -> int:
	var gt := node.global_transform
	var ray_from := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	
	var offset: Vector3 = gt * current_gizmo_transform.origin
	var scale := gt.basis.get_scale().x
	var ring_radius := 0.3 * scale
	var ring_thickness := 0.08 * scale
	
	# Test against FIXED local axes (transformed to world space by node's transform only)
	var axes := [gt.basis.x.normalized(), gt.basis.y.normalized(), gt.basis.z.normalized()]
	var closest_distance := INF
	var closest_ring := -1
	
	for i in range(3):
		var axis: Vector3 = axes[i]
		var plane := Plane(axis, offset.dot(axis))
		var hit := plane.intersects_ray(ray_from, ray_dir)
		if hit != null:
			var hit_pos := hit as Vector3
			var distance_to_center := hit_pos.distance_to(offset)
			if abs(distance_to_center - ring_radius) < ring_thickness:
				var ray_distance := ray_from.distance_to(hit_pos)
				if ray_distance < closest_distance:
					closest_distance = ray_distance
					closest_ring = i
	
	return closest_ring


func _start_rotation_drag(ring: int, camera: Camera3D, screen_pos: Vector2, node: MeshInstance3D) -> void:
	_dragging_ring = ring
	_drag_start_basis = current_gizmo_transform.basis
	
	var gt := node.global_transform
	_drag_origin = gt * current_gizmo_transform.origin
	
	# Use FIXED local axes (not rotated by gizmo)
	match ring:
		0: _drag_axis = Vector3.RIGHT   # X
		1: _drag_axis = Vector3.UP      # Y
		2: _drag_axis = Vector3.BACK    # Z
	
	# Get initial click vector on the rotation plane
	var ray_from := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	var axis_world := (gt.basis * _drag_axis).normalized()
	var plane := Plane(axis_world, _drag_origin.dot(axis_world))
	var hit := plane.intersects_ray(ray_from, ray_dir)
	if hit != null:
		_drag_initial_vector = ((hit as Vector3) - _drag_origin).normalized()
	else:
		_drag_initial_vector = Vector3.ZERO


func _update_rotation_drag(camera: Camera3D, screen_pos: Vector2, node: MeshInstance3D) -> void:
	if _drag_initial_vector == Vector3.ZERO:
		return  # Can't rotate without initial vector
	
	var gt := node.global_transform
	var ray_from := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	var axis_world := (gt.basis * _drag_axis).normalized()
	var plane := Plane(axis_world, _drag_origin.dot(axis_world))
	
	var hit := plane.intersects_ray(ray_from, ray_dir)
	if hit != null:
		var current_vector: Vector3 = ((hit as Vector3) - _drag_origin).normalized()
		var angle := _drag_initial_vector.signed_angle_to(current_vector, axis_world)
		
		# Apply rotation around the FIXED local axis
		var rotation := Basis(_drag_axis, angle)
		current_gizmo_transform.basis = rotation * _drag_start_basis
		
		update_dock_spinboxes()
		node.update_gizmos()


## Called by the gizmo when the handle is dragged — keeps the dock spinboxes in sync.
func update_dock_spinboxes() -> void:
	if _dock:
		_dock.update_spinboxes_from_transform(current_gizmo_transform)


## Bakes a transform (position + rotation) into all surfaces of a mesh, returning a new ArrayMesh.
## The transform is in the mesh's LOCAL space (vertices are transformed by its inverse).
func bake_transform_into_mesh(source_mesh: Mesh, transform: Transform3D) -> ArrayMesh:
	var result := ArrayMesh.new()
	var inv_transform := transform.affine_inverse()
	
	for surf_idx in source_mesh.get_surface_count():
		var mdt := MeshDataTool.new()
		# PrimitiveMesh subclasses (BoxMesh, SphereMesh, etc.) don't expose
		# surface_get_primitive_type — they always produce PRIMITIVE_TRIANGLES.
		var prim_type: int = Mesh.PRIMITIVE_TRIANGLES
		if source_mesh is ArrayMesh:
			prim_type = (source_mesh as ArrayMesh).surface_get_primitive_type(surf_idx)
		# MeshDataTool requires a single-surface ArrayMesh
		var tmp := ArrayMesh.new()
		tmp.add_surface_from_arrays(
			prim_type,
			source_mesh.surface_get_arrays(surf_idx)
		)
		var err := mdt.create_from_surface(tmp, 0)
		if err != OK:
			push_error("MeshDataTool failed on surface %d: %s" % [surf_idx, error_string(err)])
			continue

		# Transform vertices and normals
		for v in mdt.get_vertex_count():
			# Transform vertex position
			mdt.set_vertex(v, inv_transform * mdt.get_vertex(v))
			# Transform normal (rotation only, no translation)
			mdt.set_vertex_normal(v, inv_transform.basis * mdt.get_vertex_normal(v))

		var out := ArrayMesh.new()
		mdt.commit_to_surface(out)
		var arrays := out.surface_get_arrays(0)
		result.add_surface_from_arrays(
			prim_type,
			arrays
		)
		# Copy material
		var mat := source_mesh.surface_get_material(surf_idx)
		if mat:
			result.surface_set_material(result.get_surface_count() - 1, mat)

	# Copy blend shapes (ArrayMesh only — PrimitiveMesh has none)
	if source_mesh is ArrayMesh:
		for i in (source_mesh as ArrayMesh).get_blend_shape_count():
			result.add_blend_shape((source_mesh as ArrayMesh).get_blend_shape_name(i))
		result.blend_shape_mode = (source_mesh as ArrayMesh).blend_shape_mode

	return result
