extends Node3D

# Slopitect, step 2: an empty VR room.
# Everything that could go wrong at start-up is logged in one go, so one run
# on the headset says what works and what doesn't. Read it with:
#   .\adb logcat -s godot

const STATS_EVERY_SECONDS := 5.0

var _xr: XRInterface
var _since_stats := 0.0
var _frames := 0


func _ready() -> void:
	$Sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	_log_system()
	_start_xr()


func _log_system() -> void:
	print("Slopitect: Godot ", Engine.get_version_info().string)
	print("Slopitect: OS ", OS.get_name(), " ", OS.get_version(), ", model ", OS.get_model_name())
	print("Slopitect: GPU ", RenderingServer.get_video_adapter_vendor(), " / ",
		RenderingServer.get_video_adapter_name(), ", API ",
		RenderingServer.get_video_adapter_api_version())
	print("Slopitect: renderer ", ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile"))


func _start_xr() -> void:
	_xr = XRServer.find_interface("OpenXR")
	if _xr == null:
		push_error("Slopitect: no OpenXR interface in this build (is OpenXR enabled in project settings?)")
		return
	if not _xr.is_initialized():
		push_error("Slopitect: OpenXR interface exists but did not start (no runtime found, or the runtime refused the session; see the OpenXR lines above)")
		return

	var info := _xr.get_system_info()
	print("Slopitect: OpenXR runtime '", info.get("XRRuntimeName", "?"), "' ",
		info.get("XRRuntimeVersion", "?"))
	print("Slopitect: views ", _xr.get_view_count(), ", render size per eye ",
		_xr.get_render_target_size(), ", refresh ", _xr.get_display_refresh_rate(), " Hz")

	_xr.session_begun.connect(func(): print("Slopitect: XR session begun"))
	_xr.session_visible.connect(func(): print("Slopitect: XR session visible"))
	_xr.session_focussed.connect(func(): print("Slopitect: XR session focused"))
	_xr.session_stopping.connect(func(): print("Slopitect: XR session stopping"))
	_xr.pose_recentered.connect(func(): print("Slopitect: recentered"))

	# The headset paces frames, so the window's vsync must be off.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	get_viewport().use_xr = true
	print("Slopitect: drawing to the headset")

	for hand in [$XROrigin3D/LeftHand, $XROrigin3D/RightHand]:
		hand.button_pressed.connect(func(button): print("Slopitect: ", hand.name, " pressed ", button))


func _process(delta: float) -> void:
	_frames += 1
	_since_stats += delta
	if _since_stats < STATS_EVERY_SECONDS:
		return
	var fps := _frames / _since_stats
	var mem_mb := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var video_mb := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	print("Slopitect: %.1f fps, CPU memory %.0f MB, video memory %.0f MB, draw calls %d, left hand tracked %s, right hand tracked %s" % [
		fps, mem_mb, video_mb,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		$XROrigin3D/LeftHand.get_has_tracking_data(),
		$XROrigin3D/RightHand.get_has_tracking_data()])
	_frames = 0
	_since_stats = 0.0
