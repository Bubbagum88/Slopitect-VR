extends SlopitectModule

# Slopitect: questions only you can answer.
# Some things wait for your Yes in the headset first: the agent reading or
# changing files outside the Slopitect folder, new code being loaded. Other
# modules call ask(); a yellow-edged window then opens in front of you, and
# only pointing at Yes or No and pulling the right trigger answers it.
# No command can answer it, and while it's open the pointer works on nothing
# else, so a panel can't cover it or be pressed instead. It draws over
# everything. Unanswered, it says No after a minute.

const CONFIRM_LAYER := 1 << 20  # physics layer 21, used only by this window
const TIMEOUT_SECONDS := 60.0
const ARM_SECONDS := 0.6  # a trigger already held, or pulled at once, doesn't count
const MAX_WAITING := 5
const WIDTH := 0.42
const HEIGHT := 0.26
const LASER_LENGTH := 3.0

var _queue: Array = []  # [{question, details, on_yes, pending}], the first is shown
var _shown_for := 0.0
var _dialog: Node3D
var _question: Label3D
var _details: Label3D
var _clock: Label3D
var _yes: StaticBody3D
var _no: StaticBody3D
var _ray: RayCast3D
var _laser: MeshInstance3D
var _hovered: StaticBody3D


func setup() -> String:
	_dialog = Node3D.new()
	_dialog.name = "Question"
	_dialog.visible = false
	add_child(_dialog)
	_dialog.add_child(_quad(Vector2(WIDTH + 0.012, HEIGHT + 0.012), Vector3(0, 0, -0.002), Color(1.0, 0.8, 0.1), 0))
	_dialog.add_child(_quad(Vector2(WIDTH, HEIGHT), Vector3(0, 0, -0.001), Color(0.07, 0.07, 0.06), 1))
	_dialog.add_child(_label("Slopitect asks", Vector3(0, HEIGHT / 2 - 0.015, 0), 30, Color(1.0, 0.8, 0.1)))
	_question = _label("", Vector3(0, HEIGHT / 2 - 0.05, 0), 34, Color.WHITE)
	_dialog.add_child(_question)
	_details = _label("", Vector3(0, HEIGHT / 2 - 0.115, 0), 24, Color(0.75, 0.75, 0.75))
	_dialog.add_child(_details)
	_clock = _label("", Vector3(0, -HEIGHT / 2 + 0.015, 0), 20, Color(0.6, 0.6, 0.6))
	_dialog.add_child(_clock)
	_yes = _button("Yes", Vector3(-0.09, -0.07, 0), Color(0.15, 0.5, 0.2))
	_no = _button("No", Vector3(0.09, -0.07, 0), Color(0.55, 0.15, 0.15))

	var right: XRController3D = ctx["right"]
	_ray = RayCast3D.new()
	_ray.target_position = Vector3(0, 0, -LASER_LENGTH)
	_ray.collision_mask = CONFIRM_LAYER
	_ray.enabled = false
	right.add_child(_ray)
	_laser = MeshInstance3D.new()
	var laser_mesh := BoxMesh.new()
	laser_mesh.size = Vector3(0.002, 0.002, 1.0)
	_laser.mesh = laser_mesh
	_laser.material_override = _material(Color(1.0, 0.8, 0.1), 0)
	_laser.visible = false
	right.add_child(_laser)
	right.button_pressed.connect(_on_right_pressed)

	register("confirm_status", _status, "the questions waiting for the person's answer in the headset (nothing can answer them but the person)")
	return ""


func _exit_tree() -> void:
	for node in [_ray, _laser]:
		if node and is_instance_valid(node):
			node.queue_free()


# Asks the person `question` (with `details`, like the file path) and returns
# {"ok": true, "wait": pending} at once. On Yes, `on_yes` runs and its reply
# is the answer; on No, Stop or no answer, nothing runs.
func ask(question: String, details: String, on_yes: Callable) -> Dictionary:
	if _queue.size() >= MAX_WAITING:
		return {"ok": false, "error": "%d questions are already waiting for the person; wait for answers first" % MAX_WAITING}
	var entry := {"question": question.left(200), "details": details.left(300), "on_yes": on_yes, "pending": SlopitectPending.new()}
	_queue.append(entry)
	# However it ends (an answer, Stop, the minute running out), it leaves the queue.
	entry["pending"].done.connect(func(_reply): _finished(entry), CONNECT_ONE_SHOT)
	print("Slopitect confirm: asking \"%s\" (%s)" % [entry["question"], entry["details"]])
	if _queue.size() == 1:
		_open()
	return {"ok": true, "wait": entry["pending"]}


func _status(_request: Dictionary) -> Dictionary:
	var waiting := []
	for entry in _queue:
		waiting.append({"question": entry["question"], "details": entry["details"]})
	return {"ok": true, "waiting": waiting}


func _process(delta: float) -> void:
	if _queue.is_empty() or _queue[0].get("answered", false):
		return
	_shown_for += delta
	_clock.text = "No in %d s" % ceili(TIMEOUT_SECONDS - _shown_for)
	if _shown_for >= TIMEOUT_SECONDS:
		print("Slopitect confirm: no answer to \"%s\" in %d s; counted as No" % [_queue[0]["question"], TIMEOUT_SECONDS])
		_queue[0]["pending"].finish({"ok": false, "error": "the person didn't answer within %d seconds; ask again if it's still needed" % TIMEOUT_SECONDS})


func _physics_process(_delta: float) -> void:
	if not _dialog.visible:
		return
	var hit: StaticBody3D = _ray.get_collider() as StaticBody3D if _ray.is_colliding() else null
	if hit != _hovered:
		_hover(_hovered, false)
		_hovered = hit
		_hover(_hovered, true)
	var length := LASER_LENGTH
	if _hovered:
		length = (ctx["right"] as XRController3D).global_position.distance_to(_ray.get_collision_point())
	_laser.scale = Vector3(1, 1, length)
	_laser.position = Vector3(0, 0, -length / 2.0)


func _on_right_pressed(button: String) -> void:
	if button != "trigger_click" or _queue.is_empty() or not _hovered or _shown_for < ARM_SECONDS:
		return
	var entry: Dictionary = _queue[0]
	if entry.get("answered", false):
		return
	entry["answered"] = true
	var pending: SlopitectPending = entry["pending"]
	if _hovered == _yes:
		print("Slopitect confirm: Yes to \"%s\"" % entry["question"])
		# The reply is worked out before finishing, so the next question can't
		# open (and be answered by this same pull) in between.
		var reply = entry["on_yes"].call()
		if typeof(reply) != TYPE_DICTIONARY:
			reply = {"ok": false, "error": "the approved action gave no proper reply"}
		if reply.get("wait") is SlopitectPending:
			# A long job (a big copy): answer when it's done.
			var job: SlopitectPending = reply["wait"]
			_close()
			if not job.finished:
				await job.done
			pending.finish(job.result)
		else:
			pending.finish(reply)
	else:
		print("Slopitect confirm: No to \"%s\"" % entry["question"])
		pending.finish({"ok": false, "error": "the person said No"})


func _finished(entry: Dictionary) -> void:
	var was_shown: bool = not _queue.is_empty() and _queue[0] == entry
	_queue.erase(entry)
	if was_shown:
		_close()
		if not _queue.is_empty():
			_open()


func _open() -> void:
	var entry: Dictionary = _queue[0]
	_question.text = entry["question"]
	_details.text = entry["details"]
	_shown_for = 0.0
	var head: Transform3D = ctx["camera"].global_transform
	var forward := -head.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	_dialog.global_position = head.origin + forward * 0.45 + Vector3(0, -0.1, 0)
	_dialog.look_at(head.origin, Vector3.UP, true)
	_dialog.visible = true
	_ray.enabled = true
	_laser.visible = true
	_set_ui_blocked(true)


func _close() -> void:
	_dialog.visible = false
	_ray.enabled = false
	_laser.visible = false
	_hover(_hovered, false)
	_hovered = null
	_set_ui_blocked(false)


func _set_ui_blocked(on: bool) -> void:
	var ui: SlopitectModule = ctx["modules"].module("ui")
	if ui:
		ui.pointer_blocked = on


func _hover(body: StaticBody3D, on: bool) -> void:
	if body == null or not is_instance_valid(body):
		return
	var color: Color = body.get_meta("color")
	(body.get_node("Face").material_override as StandardMaterial3D).albedo_color = color.lightened(0.35) if on else color


func _button(text: String, at: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = CONFIRM_LAYER
	body.collision_mask = 0
	body.set_meta("color", color)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.14, 0.06, 0.004)
	shape.shape = box
	body.add_child(shape)
	var face := _quad(Vector2(0.14, 0.06), Vector3.ZERO, color, 2)
	face.name = "Face"
	body.add_child(face)
	var label := _label(text, Vector3(0, 0.012, 0.001), 44, Color.WHITE)
	body.add_child(label)
	_dialog.add_child(body)
	return body


# Drawn over everything else, so nothing in the world can hide it. Without
# depth, the order is set by priority: frame, background, buttons, text.
func _material(color: Color, layer: int) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = true
	material.render_priority = 100 + layer
	return material


func _quad(size: Vector2, at: Vector3, color: Color, layer: int) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	mesh.mesh = quad
	mesh.position = at
	mesh.material_override = _material(color, layer)
	return mesh


func _label(text: String, at: Vector3, font_size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.pixel_size = 0.0006
	label.font_size = font_size
	label.outline_size = 0
	label.modulate = color
	label.width = (WIDTH - 0.03) / label.pixel_size
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.no_depth_test = true
	label.render_priority = 110
	return label
