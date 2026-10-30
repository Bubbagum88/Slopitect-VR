extends SlopitectModule

# Slopitect live module: tool_front.
# Each tool's own menu (panel tools_t_ID) comes up in front of you whenever
# it opens, not where the Tools window was. A menu whose title bar's Pin is
# on (keep_place) stays where you put it. Made by the headset agent; it
# hears vrui's panel_shown, so it does nothing between openings.

const PREFIX := "tools_t_"  # tools.gd's TOOL_PANEL_PREFIX

var _lib: SlopitectModule


func setup() -> String:
	set_process(false)
	return ""


func lib_ready(lib) -> void:
	_lib = lib
	if lib:
		lib.follow(self, "vrui", "panel_shown", _shown)


func _shown(id_panel: String, on: bool) -> void:
	if on and id_panel.begins_with(PREFIX):
		_front.call_deferred(id_panel)  # after vrui has finished opening it


# Showing an unpinned window again puts it in front of you (vrui's own rule).
func _front(id_panel: String) -> void:
	var got: Dictionary = ctx["server"].run({"cmd": "ui_get", "id_panel": id_panel})
	var panel: Dictionary = got.get("panel", {})
	if panel.get("visible", false) and not panel.get("keep_place", false):
		ctx["server"].run({"cmd": "ui_show", "id_panel": id_panel, "visible": true})
