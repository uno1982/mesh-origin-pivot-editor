@tool
extends EditorPlugin

const DOCK_SCENE = preload("./origin_dock.tscn")
const GizmoPluginScript = preload("./origin_gizmo_plugin.gd")

var _dock: Control
var _selection: EditorSelection
var _gizmo_plugin: EditorNode3DGizmoPlugin

## Current handle offset in the selected node's local mesh space.
## Shared between the dock spinboxes and the 3D gizmo.
var current_gizmo_offset := Vector3.ZERO


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
	current_gizmo_offset = Vector3.ZERO
	_dock.set_target(mesh_instance)
	if mesh_instance:
		mesh_instance.update_gizmos()


func _get_selected_mesh_instance() -> MeshInstance3D:
	var nodes := _selection.get_selected_nodes()
	if nodes.size() == 1 and nodes[0] is MeshInstance3D:
		return nodes[0] as MeshInstance3D
	return null


## Called by the gizmo when the handle is dragged — keeps the dock spinboxes in sync.
func update_dock_spinboxes() -> void:
	if _dock:
		_dock.update_spinboxes_from_offset(current_gizmo_offset)


## Bakes an offset into all surfaces of a mesh, returning a new ArrayMesh.
## The offset is in the mesh's LOCAL space (subtract from every vertex).
func bake_offset_into_mesh(source_mesh: Mesh, offset: Vector3) -> ArrayMesh:
	var result := ArrayMesh.new()
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

		for v in mdt.get_vertex_count():
			mdt.set_vertex(v, mdt.get_vertex(v) - offset)

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
