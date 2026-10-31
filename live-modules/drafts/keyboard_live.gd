extends SlopitectModule

# Slopitect live module: keyboard_live.
# Copies the keyboard's display line into the terminal's line as you type, so
# what you type shows on the terminal screen. Nothing is sent until Run (Send),
# as before. Only while the keyboard types into the terminal, and the terminal
# is in terminal mode (chat mode is left alone).

const CHECK_SECONDS := 0.1

var _since := 0.0
var _last := ""


func setup() -> String:
	return ""


func _run(request: Dictionary) -> Dictionary:
	return ctx["server"].run(request)


func _process(delta: float) -> void:
	_since += delta
	if _since < CHECK_SECONDS:
		return
	_since = 0.0
	var st := _run({"cmd": "keyboard_status"})
	if not st.get("ok", false):
		return
	var text: String = st.get("text", "")
	if text == _last:
		return
	_last = text
	if st.get("typing_into", "") != "terminal":
		return
	if _run({"cmd": "terminal_status"}).get("mode", "") != "terminal":
		return
	_run({"cmd": "terminal_key", "key": "clear"})
	if not text.is_empty():
		_run({"cmd": "terminal_type", "text": text})
