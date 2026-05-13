@tool
extends VBoxContainer

var plugin: EditorPlugin = null
var _target: MeshInstance3D = null

@onready var _status_label: Label = $StatusLabel
@onready var _center_btn: Button = $CenterBtn
@onready var _bottom_btn: Button = $BottomBtn
@onready var _top_btn: Button = $TopBtn
@onready var _custom_container: VBoxContainer = $CustomContainer
@onready var _offset_x: SpinBox = $CustomContainer/HBox/OffsetX
@onready var _offset_y: SpinBox = $CustomContainer/HBox/OffsetY
@onready var _offset_z: SpinBox = $CustomContainer/HBox/OffsetZ
@onready var _reset_offset_btn: Button = $CustomContainer/HBox/ResetOffsetBtn
@onready var _apply_custom_btn: Button = $CustomContainer/ApplyCustomBtn
@onready var _rotation_x: SpinBox = $RotationContainer/RotHBox/RotationX
@onready var _rotation_y: SpinBox = $RotationContainer/RotHBox/RotationY
@onready var _rotation_z: SpinBox = $RotationContainer/RotHBox/RotationZ
@onready var _reset_rotation_btn: Button = $RotationContainer/RotHBox/ResetRotationBtn
@onready var _revert_btn: Button = $RevertContainer/RevertHBox/RevertBtn
@onready var _set_baseline_btn: Button = $RevertContainer/RevertHBox/SetBaselineBtn


func _ready() -> void:
	_center_btn.pressed.connect(_on_center_pressed)
	_bottom_btn.pressed.connect(_on_bottom_pressed)
	_top_btn.pressed.connect(_on_top_pressed)
	_apply_custom_btn.pressed.connect(_on_apply_custom_pressed)
	# Keep plugin offset in sync when user types in the spinboxes.
	_offset_x.value_changed.connect(_on_spinbox_changed)
	_offset_y.value_changed.connect(_on_spinbox_changed)
	_offset_z.value_changed.connect(_on_spinbox_changed)
	_reset_offset_btn.pressed.connect(_on_reset_offset_pressed)
	# Keep plugin rotation in sync when user types in the rotation spinboxes.
	_rotation_x.value_changed.connect(_on_rotation_spinbox_changed)
	_rotation_y.value_changed.connect(_on_rotation_spinbox_changed)
	_rotation_z.value_changed.connect(_on_rotation_spinbox_changed)
	_reset_rotation_btn.pressed.connect(_on_reset_rotation_pressed)
	_revert_btn.pressed.connect(_on_revert_pressed)
	_set_baseline_btn.pressed.connect(_on_set_baseline_pressed)
	set_target(null)


## Called by the gizmo when the handle is dragged.
func update_spinboxes_from_transform(transform: Transform3D) -> void:
	# Block value_changed emissions while we update programmatically.
	_offset_x.set_block_signals(true)
	_offset_y.set_block_signals(true)
	_offset_z.set_block_signals(true)
	_rotation_x.set_block_signals(true)
	_rotation_y.set_block_signals(true)
	_rotation_z.set_block_signals(true)
	
	_offset_x.value = transform.origin.x
	_offset_y.value = transform.origin.y
	_offset_z.value = transform.origin.z
	
	# Convert basis to Euler angles (in degrees)
	var euler := transform.basis.get_euler()
	_rotation_x.value = rad_to_deg(euler.x)
	_rotation_y.value = rad_to_deg(euler.y)
	_rotation_z.value = rad_to_deg(euler.z)
	
	_offset_x.set_block_signals(false)
	_offset_y.set_block_signals(false)
	_offset_z.set_block_signals(false)
	_rotation_x.set_block_signals(false)
	_rotation_y.set_block_signals(false)
	_rotation_z.set_block_signals(false)


func _on_spinbox_changed(_v: float) -> void:
	if not plugin:
		return
	# Update position, keep existing rotation
	plugin.current_gizmo_transform.origin = Vector3(_offset_x.value, _offset_y.value, _offset_z.value)
	if _target:
		_target.update_gizmos()


func _on_reset_offset_pressed() -> void:
	if not plugin:
		return
	plugin.current_gizmo_transform.origin = Vector3.ZERO
	_offset_x.value = 0.0
	_offset_y.value = 0.0
	_offset_z.value = 0.0
	if _target:
		_target.update_gizmos()


func _on_rotation_spinbox_changed(_v: float) -> void:
	if not plugin:
		return
	# Update rotation from Euler angles (degrees to radians)
	var euler := Vector3(
		deg_to_rad(_rotation_x.value),
		deg_to_rad(_rotation_y.value),
		deg_to_rad(_rotation_z.value)
	)
	plugin.current_gizmo_transform.basis = Basis.from_euler(euler)
	if _target:
		_target.update_gizmos()


func _on_reset_rotation_pressed() -> void:
	if not plugin:
		return
	plugin.current_gizmo_transform.basis = Basis.IDENTITY
	_rotation_x.value = 0.0
	_rotation_y.value = 0.0
	_rotation_z.value = 0.0
	if _target:
		_target.update_gizmos()


func _on_revert_pressed() -> void:
	if not plugin or not _target:
		return
	if plugin.revert_to_original(_target):
		_reset_transform()


func _on_set_baseline_pressed() -> void:
	if not plugin or not _target:
		return
	plugin.restash_original(_target)


func set_target(mesh_instance: MeshInstance3D) -> void:
	_target = mesh_instance
	var has_target := _target != null and _target.mesh != null
	_status_label.text = (
		"Selected: %s" % _target.name if has_target else "Select a MeshInstance3D"
	)
	_center_btn.disabled = not has_target
	_bottom_btn.disabled = not has_target
	_top_btn.disabled = not has_target
	_apply_custom_btn.disabled = not has_target
	_revert_btn.disabled = not (has_target and plugin and plugin.has_original(_target))
	_set_baseline_btn.disabled = not has_target


func _apply_transform(transform: Transform3D) -> void:
	if not _target or not _target.mesh:
		return

	var new_mesh: ArrayMesh = plugin.bake_transform_into_mesh(_target.mesh, transform)

	var undo := plugin.get_undo_redo()
	undo.create_action("Set Mesh Origin")
	undo.add_do_property(_target, "mesh", new_mesh)
	undo.add_undo_property(_target, "mesh", _target.mesh)
	
	# Compensate node transform so world position/rotation stays the same
	var node_transform := _target.transform
	# Apply the mesh transform change to the node's transform
	var new_node_transform := node_transform * transform
	
	undo.add_do_property(_target, "transform", new_node_transform)
	undo.add_undo_property(_target, "transform", node_transform)
	undo.commit_action()


func _on_center_pressed() -> void:
	if not _target or not _target.mesh:
		return
	var aabb := _target.mesh.get_aabb()
	var transform := Transform3D()
	transform.origin = aabb.get_center()
	_apply_transform(transform)
	_reset_transform()


func _on_bottom_pressed() -> void:
	if not _target or not _target.mesh:
		return
	var aabb := _target.mesh.get_aabb()
	var transform := Transform3D()
	transform.origin = Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z)
	_apply_transform(transform)
	_reset_transform()


func _on_top_pressed() -> void:
	if not _target or not _target.mesh:
		return
	var aabb := _target.mesh.get_aabb()
	var transform := Transform3D()
	transform.origin = Vector3(aabb.get_center().x, aabb.end.y, aabb.get_center().z)
	_apply_transform(transform)
	_reset_transform()


func _reset_transform() -> void:
	plugin.current_gizmo_transform = Transform3D.IDENTITY
	update_spinboxes_from_transform(Transform3D.IDENTITY)
	# Defer the gizmo redraw so the node transform from commit_action() has
	# fully propagated before the handle position is recalculated.
	if _target:
		_target.update_gizmos.call_deferred()


func _on_apply_custom_pressed() -> void:
	_apply_transform(plugin.current_gizmo_transform)
	_reset_transform()
