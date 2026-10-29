extends SlopitectModule

# Pairing: only programs you said Yes to can use the command port.
# Any app on the headset can connect to port 7777, so a connection must
# first show a pairing key. A program gets one with the "pair" command,
# which asks you in the headset; on Yes it gets a new random key, which it
# keeps (slopi.ps1 keeps it in slopi-key.txt next to itself) and sends as
# "pair_key" on its commands. Only the key's SHA-256 is kept here, in the
# app's own storage, and keys never reach the log ("..._key" fields are
# hidden there). The agent and the in-headset buttons don't go through the
# port, so they don't need a key.

const SETTINGS_PATH := "user://pairing.json"
const MAX_PAIRED := 8
const AFTER_NO_SECONDS := 20.0  # no new "pair" question this soon after a No

var _paired: Array = []  # [{"name", "sha256", "since"}]
var _confirm: SlopitectModule
var _asking := false
var _refused_at := -1000.0


func setup() -> String:
	_confirm = ctx["modules"].module("confirm")
	if _confirm == null:
		return "pairing needs the confirm module (for your Yes); list \"confirm\" before \"pairing\" in modules.json"
	_load()
	register("pair", _pair, "pair a program on the PC with Slopitect: name (of the PC or program); asks the person in the headset, and on Yes answers with its pair_key")
	register("pair_config", _config, "from the PC only: list the paired programs, or remove (a name) to unpair one")
	ctx["server"].client_guard = _check
	print("Slopitect pairing: %d paired program(s)" % _paired.size())
	return ""


func _exit_tree() -> void:
	if ctx["server"].client_guard == Callable(self, "_check"):
		ctx["server"].client_guard = Callable()


# "" when the request's pair_key is one you said Yes to, else why not.
func _check(request: Dictionary) -> String:
	var key = request.get("pair_key")
	if typeof(key) == TYPE_STRING and key.length() >= 32:
		var sha256: String = key.sha256_text()
		for entry in _paired:
			if entry["sha256"] == sha256:
				return ""
	print("Slopitect pairing: refused a connection without a known pair_key")
	return "this program isn't paired with Slopitect: on the PC, run .\\slopi.ps1 -Pair and say Yes in the headset"


func _pair(request: Dictionary) -> Dictionary:
	var who = request.get("name", "")
	if typeof(who) != TYPE_STRING or who.strip_edges().is_empty() or who.length() > 40:
		return {"ok": false, "error": "\"name\" must be the PC's or program's name, 1 to 40 characters"}
	who = who.strip_edges()
	if _asking:
		return {"ok": false, "error": "a pairing question is already open in the headset"}
	if Time.get_ticks_msec() / 1000.0 - _refused_at < AFTER_NO_SECONDS:
		return {"ok": false, "error": "the last pairing was refused; wait %d seconds before asking again" % AFTER_NO_SECONDS}
	if _paired.size() >= MAX_PAIRED:
		return {"ok": false, "error": "%d programs are paired already; remove one with pair_config first" % MAX_PAIRED}
	var asked: Dictionary = _confirm.ask("Let \"%s\" control Slopitect?" % who,
		"A program on the command port wants to pair. Say Yes only if you just started it on your PC (slopi.ps1 -Pair).",
		func(): return _add(who))
	if not asked.get("ok", false):
		return asked
	_asking = true
	var pending: SlopitectPending = asked["wait"]
	return {"ok": true, "wait": pending.then(func(reply: Dictionary):
		_asking = false
		if not reply.get("ok", false):
			_refused_at = Time.get_ticks_msec() / 1000.0
		return reply)}


func _add(who: String) -> Dictionary:
	var key := Crypto.new().generate_random_bytes(32).hex_encode()
	# A program paired again under the same name replaces its old key.
	_paired = _paired.filter(func(e): return e["name"] != who)
	_paired.append({"name": who, "sha256": key.sha256_text(), "since": Time.get_datetime_string_from_system(true)})
	var problem := _save()
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	print("Slopitect pairing: paired \"%s\"" % who)
	return {"ok": true, "paired": who, "pair_key": key}


func _config(request: Dictionary) -> Dictionary:
	if request.has("remove"):
		var who = request["remove"]
		var kept := _paired.filter(func(e): return e["name"] != who)
		if kept.size() == _paired.size():
			return {"ok": false, "error": "no paired program named %s" % JSON.stringify(who)}
		_paired = kept
		var problem := _save()
		if not problem.is_empty():
			return {"ok": false, "error": problem}
		print("Slopitect pairing: unpaired %s" % JSON.stringify(who))
	var listed := []
	for entry in _paired:
		listed.append({"name": entry["name"], "since": entry["since"]})
	return {"ok": true, "paired": listed}


func _load() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("paired")) != TYPE_ARRAY:
		push_error("Slopitect pairing: %s isn't readable; no program is paired until one pairs again" % SETTINGS_PATH)
		return
	for entry in parsed["paired"]:
		if typeof(entry) == TYPE_DICTIONARY and typeof(entry.get("name")) == TYPE_STRING and typeof(entry.get("sha256")) == TYPE_STRING:
			_paired.append({"name": entry["name"], "sha256": entry["sha256"], "since": str(entry.get("since", ""))})


func _save() -> String:
	var out := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if out == null:
		return "couldn't save %s (error %d)" % [SETTINGS_PATH, FileAccess.get_open_error()]
	out.store_string(JSON.stringify({"paired": _paired}, "\t"))
	out.close()
	return ""
