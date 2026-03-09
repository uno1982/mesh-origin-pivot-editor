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
@onready var _apply_custom_btn: Button = $CustomContainer/ApplyCustomBtn


func _ready() -> void:
	_center_btn.pressed.connect(_on_center_pressed)
	_bottom_btn.pressed.connect(_on_bottom_pressed)
	_top_btn.pressed.connect(_on_top_pressed)
	_apply_custom_btn.pressed.connect(_on_apply_custom_pressed)
	# Keep plugin offset in sync when user types in the spinboxes.
	_offset_x.value_changed.connect(_on_spinbox_changed)
	_offset_y.value_changed.connect(_on_spinbox_changed)
	_offset_z.value_changed.connect(_on_spinbox_changed)
	set_target(null)


## Called by the gizmo when the handle is dragged.
func update_spinboxes_from_offset(offset: Vector3) -> void:
	# Block value_changed emissions while we update programmatically.
	_offset_x.set_block_signals(true)
	_offset_y.set_block_signals(true)
	_offset_z.set_block_signals(true)
	_offset_x.value = offset.x
	_offset_y.value = offset.y
	_offset_z.value = offset.z
	_offset_x.set_block_signals(false)
	_offset_y.set_block_signals(false)
	_offset_z.set_block_signals(false)


func _on_spinbox_changed(_v: float) -> void:
	if not plugin:
		return
	plugin.current_gizmo_offset = Vector3(_offset_x.value, _offset_y.value, _offset_z.value)
	if _target:
		_target.update_gizmos()


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


func _apply_offset(offset: Vector3) -> void:
	if not _target or not _target.mesh:
		return

	var new_mesh: ArrayMesh = plugin.bake_offset_into_mesh(_target.mesh, offset)

	var undo := plugin.get_undo_redo()
	undo.create_action("Set Mesh Origin")
	undo.add_do_property(_target, "mesh", new_mesh)
	undo.add_undo_property(_target, "mesh", _target.mesh)
	# Compensate node transform so world position stays the same
	var old_pos := _target.position
	var new_pos := old_pos + _target.basis * offset
	undo.add_do_property(_target, "position", new_pos)
	undo.add_undo_property(_target, "position", old_pos)
	undo.commit_action()


func _on_center_pressed() -> void:
	if not _target or not _target.mesh:
		return
	var aabb := _target.mesh.get_aabb()
	var offset := aabb.get_center()
	_apply_offset(offset)
	_reset_offset()


func _on_bottom_pressed() -> void:
	if not _target or not _target.mesh:
		return
	var aabb := _target.mesh.get_aabb()
	var offset := Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z)
	_apply_offset(offset)
	_reset_offset()


func _on_top_pressed() -> void:
	if not _target or not _target.mesh:
		return
	var aabb := _target.mesh.get_aabb()
	var offset := Vector3(aabb.get_center().x, aabb.end.y, aabb.get_center().z)
	_apply_offset(offset)
	_reset_offset()


func _reset_offset() -> void:
	plugin.current_gizmo_offset = Vector3.ZERO
	update_spinboxes_from_offset(Vector3.ZERO)
	# Defer the gizmo redraw so the node transform from commit_action() has
	# fully propagated before the handle position is recalculated.
	if _target:
		_target.update_gizmos.call_deferred()


func _on_apply_custom_pressed() -> void:
	_apply_offset(plugin.current_gizmo_offset)
	_reset_offset()
