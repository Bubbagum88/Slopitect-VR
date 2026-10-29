extends SlopitectModule

# View: a picture of the world, so the agent can see what it built.
# view_look renders the world once from the headset's eyes (or from any
# place you give it) with a camera of its own, and answers with a JPEG. The
# agent gets the picture itself; the same picture is also saved as
# views/last.jpg in the Slopitect folder, so you can see what it saw.
# Only the app's own world is in it: the Quest's cameras (your room) are
# never used.

const DEFAULT_WIDTH := 768
const MAX_WIDTH := 1280
const QUALITY := 0.75  # JPEG quality
const FOV := 75.0

var _viewport: SubViewport
var _camera: Camera3D
var _busy: SlopitectPending
var _folder := ""


func setup() -> String:
	_folder = ("/sdcard/Slopitect" if OS.get_name() == "Android" else OS.get_user_data_dir() + "/files_home") + "/views"
	_viewport = SubViewport.new()
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.world_3d = get_viewport().world_3d  # the same world, not a copy
	_camera = Camera3D.new()
	_camera.fov = FOV
	_camera.far = 500.0
	_viewport.add_child(_camera)
	add_child(_viewport)
	register("view_look", _look, "a picture of the world: from the person's eyes, or from position [x, y, z] looking at look_at [x, y, z]; optional width (up to %d, default %d), image (false: only save views/last.jpg)" % [MAX_WIDTH, DEFAULT_WIDTH])
	return ""


func _look(request: Dictionary) -> Dictionary:
	if _busy != null:
		return {"ok": false, "error": "a picture is already being taken"}
	var width = request.get("width", DEFAULT_WIDTH)
	if (typeof(width) != TYPE_INT and typeof(width) != TYPE_FLOAT) or int(width) < 64 or int(width) > MAX_WIDTH:
		return {"ok": false, "error": "\"width\" must be 64 to %d" % MAX_WIDTH}
	var send_image = request.get("image", true)
	if typeof(send_image) != TYPE_BOOL:
		return {"ok": false, "error": "\"image\" must be true or false"}

	var where := "the person's eyes"
	if request.has("position") or request.has("look_at"):
		var from := _vec(request.get("position"))
		var to := _vec(request.get("look_at"))
		if from.is_empty() or to.is_empty():
			return {"ok": false, "error": "give both \"position\" and \"look_at\" as [x, y, z], or neither (for the person's eyes)"}
		if from[0].distance_to(to[0]) < 0.01:
			return {"ok": false, "error": "\"position\" and \"look_at\" are the same place"}
		var up := Vector3.UP if absf((to[0] - from[0]).normalized().y) < 0.99 else Vector3.FORWARD
		_camera.global_transform = Transform3D.IDENTITY.translated(from[0]).looking_at(to[0], up)
		where = "%s looking at %s" % [request["position"], request["look_at"]]
	else:
		var eyes: Node3D = ctx["camera"]
		# Level and upright, the way a person would take a photo.
		var forward := -eyes.global_basis.z
		var up := Vector3.UP if absf(forward.y) < 0.99 else -eyes.global_basis.y
		_camera.global_transform = Transform3D.IDENTITY.translated(eyes.global_position).looking_at(eyes.global_position + forward, up)

	_viewport.size = Vector2i(int(width), int(width) * 9 / 16)
	_camera.current = true
	_busy = SlopitectPending.new()
	var pending := _busy
	_render(pending, send_image, where)
	return {"ok": true, "wait": pending}


# Renders on the next frame and reads it back the frame after, then answers.
func _render(pending: SlopitectPending, send_image: bool, where: String) -> void:
	var started := Time.get_ticks_msec()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	var image := _viewport.get_texture().get_image()
	_busy = null
	if pending.cancelled:
		return
	if image == null or image.is_empty():
		pending.finish({"ok": false, "error": "the picture came back empty"})
		return
	var jpeg := image.save_jpg_to_buffer(QUALITY)
	var reply := {"ok": true, "from": where, "width": image.get_width(), "height": image.get_height(), "kb": jpeg.size() / 1024}
	if DirAccess.make_dir_recursive_absolute(_folder) == OK:
		var out := FileAccess.open(_folder + "/last.jpg", FileAccess.WRITE)
		if out:
			out.store_buffer(jpeg)
			out.close()
			reply["saved"] = _folder + "/last.jpg"
	if send_image:
		# The agent takes this out of the reply and shows it to the model as a
		# picture instead of text.
		reply["image"] = {"media_type": "image/jpeg", "base64": Marshalls.raw_to_base64(jpeg)}
	print("Slopitect view: picture from %s, %dx%d, %d KB, %d ms" % [where, image.get_width(), image.get_height(), jpeg.size() / 1024, Time.get_ticks_msec() - started])
	pending.finish(reply)


func _vec(value) -> Array:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return []
	for v in value:
		if (typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT) or is_nan(float(v)) or absf(float(v)) > 10000.0:
			return []
	return [Vector3(value[0], value[1], value[2])]
