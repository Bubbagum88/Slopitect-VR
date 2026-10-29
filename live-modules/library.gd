extends SlopitectModule

# Slopitect live module: library.
# The Library window: three tabs of pictures to pick from.
# - Textures: Poly Haven's textures (all CC0). Pick a shape with the
#   Inspect tool, then press a texture: it's downloaded (once) and put on
#   that shape by textures.gd.
# - Assets: Poly Haven's 3D models, lightest first for the Quest 1. Press
#   one: assets.gd downloads it (once) and it's placed in front of you.
# - Prefabs: the sets of shapes and models saved with prefabs_save
#   (prefabs.gd). Press one to place a copy in front of you.
# Each tab is a grid of 12 with Prev / Next and a category button. The
# pictures are Poly Haven's own small thumbnails (128 px, renders of each
# model), and for a prefab a picture drawn here once from what it holds;
# both are kept in the Slopitect folder's library/ and only the tab you're
# on is drawn, so a page costs a dozen small pictures on the Quest 1.
#
# It keeps nothing but those pictures and Poly Haven's lists (fetched once a
# day): downloading is net.gd's (only the hosts allowed on the PC; the
# thumbnails need cdn.polyhaven.com added there), placing and texturing are
# assets.gd's, textures.gd's and prefabs.gd's. A tab whose module isn't
# loaded says so.
#
# The hand menu gets a button for each tab (hand_info()); a button opens the
# window on its tab, and closes it when it's already showing that tab.

const PANEL := "library"
const PAGES := ["Textures", "Assets", "Prefabs"]
const KEYS := {"Textures": "t", "Assets": "a", "Prefabs": "p"}
const COLUMNS := 4
const PER_PAGE := 12
const TILE := [0.11, 0.115]
const NAV_BUTTON := [0.1, 0.05]
const INFO_WIDTH := 0.14
const LIST_URL := "https://api.polyhaven.com/assets?t=%s"
const FILES_URL := "https://api.polyhaven.com/files/%s"
const THUMB_URL := "https://cdn.polyhaven.com/asset_img/thumbs/%s.png?width=128&height=128"
const MAX_LIST_BYTES := 8 * 1024 * 1024
const MAX_TEXTURE_BYTES := 16 * 1024 * 1024
const LIST_KEEP_SECONDS := 24 * 3600
const TEXTURE_RES := "1k"  # kind to the Quest 1
const MAX_CATEGORIES := 10  # the biggest, for the category button
const THUMBS_AT_ONCE := 2
const PREFAB_PX := 160
const CHECK_SECONDS := 0.5
const PLACE_DISTANCE := 1.5  # metres in front of you

var _home := ""  # the Slopitect folder
var _lists := {"textures": {}, "models": {}}  # Poly Haven's lists, id -> info
var _loading := {}  # "textures" / "models" -> true while its list is fetched
var _sorted := {}  # tab -> [ids] in the order shown, for the category picked
var _page := {"Textures": 0, "Assets": 0, "Prefabs": 0}
var _category := {"Textures": "", "Assets": "", "Prefabs": ""}
var _status := ""
var _thumb_queue: Array = []  # [url, path] waiting
var _thumbs_running := 0
var _thumb_failed := {}  # path -> true, not tried again this session
var _textures_busy := {}  # id -> true while downloading
var _place_when_done := {}  # model id -> true: place it when assets.gd has it
var _prefab_queue: Array = []  # prefab names waiting for their picture
var _drawing_prefab := false
var _shown_page := ""  # the tab the window showed at the last check
var _since_check := 0.0


func setup() -> String:
	_home = "/sdcard/Slopitect" if OS.get_name() == "Android" else OS.get_user_data_dir() + "/files_home"
	var made := DirAccess.make_dir_recursive_absolute(_home + "/library/thumbs")
	if made != OK:
		return "library can't make its folder %s/library (error %d)" % [_home, made]
	register("library_do", _do, "the Library window (textures, assets, prefabs): act = toggle (optional tab), show (optional tab), hide, page (tab, page: next, prev or a number), category (tab, optional category; none cycles), pick (tab, id), refresh")
	register("library_status", _status_command, "what the Library window shows: each tab's page, category and items, and the last thing it did")
	return ""


func _exit_tree() -> void:
	if ctx["modules"].module(name) != null:
		return  # the app is closing, not unloading this: the window stays for next time
	ctx["server"].run({"cmd": "ui_remove", "id_panel": PANEL})


func menu_info() -> Dictionary:
	return {"id": "library", "label": "Library", "order": 30, "action": {"cmd": "library_do", "act": "toggle"}}


# A button on the hand menu for each tab.
func hand_info() -> Array:
	var out := []
	for i in PAGES.size():
		out.append({"id": "library_" + KEYS[PAGES[i]], "label": PAGES[i], "order": 50 + i,
			"action": {"cmd": "library_do", "act": "toggle", "tab": PAGES[i]}})
	return out


func _process(delta: float) -> void:
	_since_check += delta
	if _since_check < CHECK_SECONDS:
		return
	_since_check = 0.0
	var panel := _panel()
	if not panel.get("visible", false):
		return
	# A tab pressed in the window: fill it (its list may not be fetched yet).
	if panel.get("page", "") != _shown_page:
		_shown_page = panel.get("page", "")
		_build()
	_finish_placing()


func _run(request: Dictionary) -> Dictionary:
	return ctx["server"].run(request)


func _has(module_name: String) -> bool:
	return ctx["modules"].module(module_name) != null


func _ui() -> SlopitectModule:
	var ui: SlopitectModule = ctx["modules"].module("vrui")
	return ui if ui != null else ctx["modules"].module("ui")


func _panel() -> Dictionary:
	return _run({"cmd": "ui_get", "id_panel": PANEL}).get("panel", {})


func _say(text: String) -> void:
	_status = text
	var ui := _ui()
	if ui != null and ui.has_method("set_text"):
		ui.call("set_text", PANEL, "status", text)


# --- Commands ------------------------------------------------------------------------

func _do(request: Dictionary) -> Dictionary:
	var tab = request.get("tab", "")
	if typeof(tab) != TYPE_STRING or not (tab.is_empty() or tab in PAGES):
		return {"ok": false, "error": "\"tab\" must be one of %s" % [PAGES]}
	match request.get("act"):
		"toggle":
			var panel := _panel()
			if panel.get("visible", false) and (tab.is_empty() or panel.get("page") == tab):
				return _run({"cmd": "ui_show", "id_panel": PANEL, "visible": false})
			return _open(tab)
		"show":
			return _open(tab)
		"hide":
			return _run({"cmd": "ui_show", "id_panel": PANEL, "visible": false})
		"refresh":
			_lists = {"textures": {}, "models": {}}
			_sorted.clear()
			for list in ["textures", "models"]:
				DirAccess.remove_absolute(_list_path(list))
			return _built()
		"page":
			if tab.is_empty():
				return {"ok": false, "error": "\"page\" needs a tab"}
			var to = request.get("page")
			var pages := _page_count(tab)
			if to == "next":
				_page[tab] = (_page[tab] + 1) % pages
			elif to == "prev":
				_page[tab] = (_page[tab] - 1 + pages) % pages
			elif typeof(to) in [TYPE_INT, TYPE_FLOAT] and to >= 1 and to <= pages:
				_page[tab] = int(to) - 1
			else:
				return {"ok": false, "error": "\"page\" must be next, prev or 1 to %d" % pages}
			return _built()
		"category":
			if tab.is_empty():
				return {"ok": false, "error": "\"category\" needs a tab"}
			var categories := _categories(tab)
			var category = request.get("category", null)
			if category == null:
				var at := categories.find(_category[tab])
				category = categories[(at + 1) % categories.size()]
			if not category in categories:
				return {"ok": false, "error": "\"category\" must be one of %s" % [categories]}
			_category[tab] = category
			_page[tab] = 0
			_sorted.erase(tab)
			return _built()
		"pick":
			var id = request.get("id")
			if typeof(id) != TYPE_STRING or not _good_id(id):
				return {"ok": false, "error": "\"id\" must be an item's id (library_status lists them)"}
			match tab:
				"Textures":
					return _pick_texture(id)
				"Assets":
					return _pick_model(id)
				"Prefabs":
					return _pick_prefab(id)
			return {"ok": false, "error": "\"pick\" needs a tab"}
	return {"ok": false, "error": "\"act\" must be toggle, show, hide, page, category, pick or refresh"}


func _open(tab: String) -> Dictionary:
	var problem := _build(tab)
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	return _run({"cmd": "ui_show", "id_panel": PANEL, "visible": true})


func _built() -> Dictionary:
	var problem := _build()
	return {"ok": true} if problem.is_empty() else {"ok": false, "error": problem}


func _status_command(_request: Dictionary) -> Dictionary:
	var tabs := {}
	for tab in PAGES:
		var items := []
		for item in _items(tab):
			items.append(item["id"])
		tabs[tab] = {"page": _page[tab] + 1, "pages": _page_count(tab), "category": _category[tab], "items": items}
	return {"ok": true, "tabs": tabs, "status": _status, "thumbnails_waiting": _thumb_queue.size() + _thumbs_running}


# --- What each tab holds -----------------------------------------------------------------

# Every id in a tab, for its category, in the order shown.
func _ids(tab: String) -> Array:
	if _sorted.has(tab):
		return _sorted[tab]
	var ids := []
	if tab == "Prefabs":
		for prefab in (_run({"cmd": "prefabs_list"}).get("prefabs", []) if _has("prefabs") else []):
			if typeof(prefab) == TYPE_DICTIONARY and _good_id(prefab.get("name")):
				ids.append(prefab["name"])
		ids.sort()
		return ids  # not kept: prefabs come and go
	var list: Dictionary = _lists[_list_name(tab)]
	for id in list:
		var info = list[id]
		if typeof(info) != TYPE_DICTIONARY or not _good_id(id):
			continue
		if _category[tab].is_empty() or _category[tab] in info.get("categories", []):
			ids.append(id)
	if tab == "Assets":
		ids.sort_custom(func(a, b): return int(list[a].get("polycount", 0)) < int(list[b].get("polycount", 0)))
	else:
		ids.sort_custom(func(a, b): return int(list[a].get("download_count", 0)) > int(list[b].get("download_count", 0)))
	_sorted[tab] = ids
	return ids


func _page_count(tab: String) -> int:
	return maxi(1, ceili(_ids(tab).size() / float(PER_PAGE)))


# The page shown: [{id, label, image}].
func _items(tab: String) -> Array:
	var ids := _ids(tab)
	_page[tab] = clampi(_page[tab], 0, _page_count(tab) - 1)
	var out := []
	for i in range(_page[tab] * PER_PAGE, mini(ids.size(), (_page[tab] + 1) * PER_PAGE)):
		var id: String = ids[i]
		var label := id
		if tab != "Prefabs":
			label = str(_lists[_list_name(tab)][id].get("name", id))
		out.append({"id": id, "label": label.left(40), "image": _thumb_path(tab, id)})
	return out


# "" (all) and the biggest categories.
func _categories(tab: String) -> Array:
	if tab == "Prefabs":
		return [""]
	var counts := {}
	var list: Dictionary = _lists[_list_name(tab)]
	for id in list:
		for category in (list[id].get("categories", []) if typeof(list[id]) == TYPE_DICTIONARY else []):
			if typeof(category) == TYPE_STRING and category.length() <= 30:
				counts[category] = counts.get(category, 0) + 1
	var names := counts.keys()
	names.sort_custom(func(a, b): return counts[a] > counts[b])
	return [""] + names.slice(0, MAX_CATEGORIES)


func _list_name(tab: String) -> String:
	return "textures" if tab == "Textures" else "models"


func _list_path(list: String) -> String:
	return "%s/library/polyhaven_%s.json" % [_home, list]


func _thumb_path(tab: String, id: String) -> String:
	return "%s/library/thumbs/%s_%s.png" % [_home, KEYS[tab], id]


func _good_id(id) -> bool:
	if typeof(id) != TYPE_STRING or id.is_empty() or id.length() > 80:
		return false
	for c in id:
		if not (c == "_" or c == "-" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9")):
			return false
	return true


# --- The window ---------------------------------------------------------------------------

# Fills the window: every tab's top line and grid (only the tab shown is
# drawn), and the line saying what happened. Returns "" or what went wrong.
func _build(open_tab := "") -> String:
	if _ui() == null:
		return "the Library window needs vrui.gd"
	var panel := _panel()
	var tab: String = open_tab if not open_tab.is_empty() else panel.get("page", PAGES[0])
	_shown_page = tab
	if tab != "Prefabs" and _lists[_list_name(tab)].is_empty():
		_load_list(_list_name(tab))
	var elements := []
	for each in PAGES:
		elements.append_array(_tab_elements(each))
	elements.append({"type": "text", "id": "status", "text": _status, "width": COLUMNS * TILE[0] + (COLUMNS - 1) * 0.01, "font_size": 24, "color": "muted"})
	var reply: Dictionary
	if panel.is_empty():
		reply = _run({"cmd": "ui_add", "id_panel": PANEL, "title": "Library", "place": "front", "chrome": true,
			"pages": PAGES, "page": tab, "layout": "column", "elements": elements})
	else:
		var change := {"cmd": "ui_update", "id_panel": PANEL, "elements": elements}
		if not open_tab.is_empty():
			change["page"] = open_tab
		reply = _run(change)
	if not reply.get("ok", false):
		return "the Library window could not be built: %s" % reply.get("error", "?")
	_fetch_thumbs(tab)
	return ""


func _tab_elements(tab: String) -> Array:
	var key: String = KEYS[tab]
	var missing := _missing(tab)
	if not missing.is_empty():
		return [{"type": "text", "id": key + "_missing", "page": tab, "text": missing, "width": COLUMNS * TILE[0], "font_size": 28, "color": "muted"}]
	var info := "Page %d of %d" % [_page[tab] + 1, _page_count(tab)]
	if _loading.get(_list_name(tab), false) and tab != "Prefabs":
		info = "Fetching the list..."
	var top := [
		{"type": "button", "id": key + "_prev", "label": "< Prev", "size": NAV_BUTTON, "action": {"cmd": "library_do", "act": "page", "tab": tab, "page": "prev"}},
		{"type": "text", "id": key + "_info", "text": info, "width": INFO_WIDTH, "font_size": 26, "align": "center", "color": "muted"},
		{"type": "button", "id": key + "_next", "label": "Next >", "size": NAV_BUTTON, "action": {"cmd": "library_do", "act": "page", "tab": tab, "page": "next"}},
	]
	if tab != "Prefabs":
		var category: String = _category[tab]
		top.append({"type": "button", "id": key + "_cat", "label": "All" if category.is_empty() else category.capitalize(), "size": NAV_BUTTON,
			"color": "accent", "action": {"cmd": "library_do", "act": "category", "tab": tab}})
	var tiles := []
	var items := _items(tab)
	for i in items.size():
		var item: Dictionary = items[i]
		var tile := {"type": "button", "id": "%s_i%d" % [key, i], "label": item["label"], "size": TILE, "image": item["image"],
			"action": {"cmd": "library_do", "act": "pick", "tab": tab, "id": item["id"]}}
		if _have(tab, item["id"]):
			tile["color"] = "ok"  # already on the headset
		tiles.append(tile)
	var out := [{"type": "row", "id": key + "_top", "page": tab, "children": top}]
	if tiles.is_empty():
		out.append({"type": "text", "id": key + "_empty", "page": tab, "width": COLUMNS * TILE[0], "font_size": 26, "color": "muted",
			"text": "No prefabs yet: ask the agent to save some with prefabs_save." if tab == "Prefabs" else "Nothing here yet."})
	else:
		out.append({"type": "grid", "id": key + "_grid", "page": tab, "columns": COLUMNS, "children": tiles})
	return out


# Why a tab can't work, or "".
func _missing(tab: String) -> String:
	match tab:
		"Textures":
			if not _has("net"):
				return "Load net.gd to fetch Poly Haven's textures."
			if not _has("textures"):
				return "Load textures.gd to put textures on shapes."
		"Assets":
			if not _has("net"):
				return "Load net.gd to fetch Poly Haven's models."
			if not _has("assets"):
				return "Load assets.gd to download and place models."
		"Prefabs":
			if not _has("prefabs"):
				return "Load prefabs.gd for prefabs."
	return ""


func _have(tab: String, id: String) -> bool:
	match tab:
		"Textures":
			return FileAccess.file_exists(_texture_file(id))
		"Assets":
			return FileAccess.file_exists("%s/assets/polyhaven/%s/1k/%s.gltf" % [_home, id, id])
	return false


# --- Downloads -------------------------------------------------------------------------------

func _load_list(list: String) -> void:
	var path := _list_path(list)
	if FileAccess.file_exists(path) and Time.get_unix_time_from_system() - FileAccess.get_modified_time(path) < LIST_KEEP_SECONDS:
		_read_list(list)
		if not _lists[list].is_empty():
			return
	if _loading.get(list, false) or not _has("net"):
		return
	_loading[list] = true
	var problem: String = await ctx["modules"].module("net").fetch(LIST_URL % list, path, MAX_LIST_BYTES)
	_loading.erase(list)
	if not problem.is_empty():
		_say("Couldn't fetch the list: " + problem)
	else:
		_read_list(list)
	_sorted.clear()
	if _panel().get("visible", false):
		_build()


func _read_list(list: String) -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(_list_path(list)))
	if typeof(parsed) == TYPE_DICTIONARY:
		_lists[list] = parsed
	else:
		_say("Poly Haven's %s list wasn't the JSON expected" % list)


# The pictures for the page shown that aren't on the headset yet: Poly
# Haven's thumbnails through net.gd, a prefab's drawn here.
func _fetch_thumbs(tab: String) -> void:
	for item in _items(tab):
		var path: String = item["image"]
		if _thumb_failed.has(path):
			continue
		if tab == "Prefabs":
			var saved := FileAccess.get_modified_time("%s/prefabs/%s.json" % [_home, item["id"]])
			if FileAccess.file_exists(path) and FileAccess.get_modified_time(path) >= saved:
				continue
			if not item["id"] in _prefab_queue:
				_prefab_queue.append(item["id"])
			continue
		if FileAccess.file_exists(path):
			continue
		var url := THUMB_URL % item["id"]
		if not ctx["modules"].module("net").allowed(url):
			_say("Pictures need cdn.polyhaven.com allowed: on the PC, net_config add cdn.polyhaven.com")
			return
		if not _thumb_queue.any(func(q): return q[1] == path):
			_thumb_queue.append([url, path])
	if _status.begins_with("Pictures need"):
		_say("")  # cdn.polyhaven.com is allowed now
	_next_thumbs()
	_next_prefab_picture()


func _next_thumbs() -> void:
	while _thumbs_running < THUMBS_AT_ONCE and not _thumb_queue.is_empty() and _has("net"):
		var job: Array = _thumb_queue.pop_front()
		_fetch_thumb(job[0], job[1])


func _fetch_thumb(url: String, path: String) -> void:
	_thumbs_running += 1
	var problem: String = await ctx["modules"].module("net").fetch(url, path, 512 * 1024)
	_thumbs_running -= 1
	if problem.is_empty():
		_picture_ready(path)
	else:
		_thumb_failed[path] = true
		push_error("Slopitect library: " + problem)
	_next_thumbs()


func _picture_ready(path: String) -> void:
	var ui := _ui()
	if ui != null and ui.has_method("reload_image"):
		ui.call("reload_image", path)


func _texture_file(id: String) -> String:
	return "%s/downloads/polyhaven/textures/%s_%s.jpg" % [_home, id, TEXTURE_RES]


# --- Picking -----------------------------------------------------------------------------------

# A texture goes on the shape picked with the Inspect tool.
func _pick_texture(id: String) -> Dictionary:
	var missing := _missing("Textures")
	if not missing.is_empty():
		return {"ok": false, "error": missing}
	var selected := str(_run({"cmd": "inspect_status"}).get("selected", "")) if _has("inspect") else ""
	if selected.is_empty():
		_say("Pick a shape with the Inspect tool first, then press a texture.")
		return {"ok": false, "error": "no shape picked: choose one with the Inspect tool (or inspect_select) first"}
	if FileAccess.file_exists(_texture_file(id)):
		return _apply_texture(id, selected)
	if _textures_busy.has(id):
		return {"ok": true, "downloading": id}
	_download_texture(id, selected)
	_say("Downloading %s..." % id)
	return {"ok": true, "downloading": id, "for": selected}


func _download_texture(id: String, for_shape: String) -> void:
	_textures_busy[id] = true
	var problem := await _texture_download(id)
	_textures_busy.erase(id)
	if not problem.is_empty():
		_say("Couldn't get %s: %s" % [id, problem])
		return
	_apply_texture(id, for_shape)
	if _panel().get("visible", false):
		_build()


# Poly Haven's colour map at TEXTURE_RES, checked against the size and MD5
# it lists. Returns "" or what went wrong; a failed download leaves nothing.
func _texture_download(id: String) -> String:
	var net: SlopitectModule = ctx["modules"].module("net")
	var listing := "%s/library/files_%s.json" % [_home, id]
	var problem: String = await net.fetch(FILES_URL % id, listing, 1024 * 1024)
	if not problem.is_empty():
		return problem
	var files = JSON.parse_string(FileAccess.get_file_as_string(listing))
	DirAccess.remove_absolute(listing)
	if typeof(files) != TYPE_DICTIONARY:
		return "its file list wasn't the JSON expected"
	var entry = null
	for key in files:
		if key.to_lower() in ["diffuse", "diff", "color", "albedo"] and typeof(files[key]) == TYPE_DICTIONARY:
			var at_res = files[key].get(TEXTURE_RES)
			if typeof(at_res) == TYPE_DICTIONARY and typeof(at_res.get("jpg")) == TYPE_DICTIONARY:
				entry = at_res["jpg"]
				break
	if entry == null or typeof(entry.get("url")) != TYPE_STRING or typeof(entry.get("md5")) != TYPE_STRING \
			or typeof(entry.get("size")) not in [TYPE_INT, TYPE_FLOAT]:
		return "it has no %s colour map as a jpg" % TEXTURE_RES
	if int(entry["size"]) > MAX_TEXTURE_BYTES:
		return "its colour map is %d MB, over the %d MB allowed" % [int(entry["size"]) / 1048576, MAX_TEXTURE_BYTES / 1048576]
	var path := _texture_file(id)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	problem = await net.fetch(entry["url"], path, int(entry["size"]) + 1024)
	if not problem.is_empty():
		return problem
	var size := FileAccess.open(path, FileAccess.READ).get_length()
	if size != int(entry["size"]) or FileAccess.get_md5(path) != entry["md5"]:
		DirAccess.remove_absolute(path)
		return "the file didn't match the size and MD5 Poly Haven lists; nothing was kept"
	return ""


func _apply_texture(id: String, shape: String) -> Dictionary:
	var reply := _run({"cmd": "textures_apply", "names": [shape], "texture": "polyhaven/textures/%s_%s.jpg" % [id, TEXTURE_RES]})
	if reply.get("ok", false):
		_say("%s is on %s." % [id, shape])
	else:
		_say("Couldn't put %s on %s: %s" % [id, shape, reply.get("error", "?")])
	return reply


# A model is downloaded by assets.gd (once), then placed in front of you.
func _pick_model(id: String) -> Dictionary:
	var missing := _missing("Assets")
	if not missing.is_empty():
		return {"ok": false, "error": missing}
	if _have("Assets", id):
		return _place_model(id)
	var reply := _run({"cmd": "assets_get", "id": id})
	if reply.get("ok", false):
		_place_when_done[id] = true
		_say("Downloading %s; it appears in front of you when it's done." % id)
	else:
		_say("Couldn't download %s: %s" % [id, reply.get("error", "?")])
	return reply


func _finish_placing() -> void:
	for id in _place_when_done.keys():
		if _have("Assets", id):
			_place_when_done.erase(id)
			_place_model(id)
			_build()
		elif not _has("assets") or str(_run({"cmd": "assets_status"}).get("last_error", "")).contains(id):
			_place_when_done.erase(id)
			_say("Couldn't download %s (assets_status says why)." % id)


func _place_model(id: String) -> Dictionary:
	var reply := _run({"cmd": "assets_place", "id": id, "position": _in_front()})
	_say(("Placed %s." % reply["placed"]["name"]) if reply.get("ok", false) else "Couldn't place %s: %s" % [id, reply.get("error", "?")])
	return reply


func _pick_prefab(id: String) -> Dictionary:
	var missing := _missing("Prefabs")
	if not missing.is_empty():
		return {"ok": false, "error": missing}
	var reply := _run({"cmd": "prefabs_place", "name": id, "position": _in_front()})
	_say(("Placed %s (%d things)." % [id, reply.get("placed", 0)]) if reply.get("ok", false) else "Couldn't place %s: %s" % [id, reply.get("error", "?")])
	return reply


# On the floor, PLACE_DISTANCE in front of where you look.
func _in_front() -> Array:
	var head: Transform3D = (ctx["camera"] as Node3D).global_transform
	var ahead := -head.basis.z
	ahead.y = 0.0
	ahead = ahead.normalized() if ahead.length() > 0.01 else Vector3.FORWARD
	var at := head.origin + ahead * PLACE_DISTANCE
	return [snappedf(at.x, 0.01), 0.0, snappedf(at.z, 0.01)]


# --- Prefab pictures ---------------------------------------------------------------------------
# Drawn once, the first time a prefab is shown, in a small 3D view of its
# own: its shapes as they are saved (shape, colour, place) and its models
# when they're on the headset, seen from above and to the front. Kept as
# library/thumbs/p_NAME.png and drawn again only when the prefab is saved
# again (its file is newer).

func _next_prefab_picture() -> void:
	if _drawing_prefab or _prefab_queue.is_empty():
		return
	_drawing_prefab = true
	var id: String = _prefab_queue.pop_front()
	var path := _thumb_path("Prefabs", id)
	var problem := await _draw_prefab(id, path)
	if problem.is_empty():
		_picture_ready(path)
	else:
		_thumb_failed[path] = true
		push_error("Slopitect library: prefab %s's picture: %s" % [id, problem])
	_drawing_prefab = false
	_next_prefab_picture()


func _draw_prefab(id: String, path: String) -> String:
	var data = JSON.parse_string(FileAccess.get_file_as_string("%s/prefabs/%s.json" % [_home, id]))
	if typeof(data) != TYPE_DICTIONARY:
		return "prefabs/%s.json isn't readable" % id
	var view := SubViewport.new()
	view.size = Vector2i(PREFAB_PX, PREFAB_PX)
	view.own_world_3d = true
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(view)
	var things := Node3D.new()
	view.add_child(things)
	for shape in data.get("shapes", []):
		if typeof(shape) == TYPE_DICTIONARY:
			things.add_child(_shape_node(shape))
	for model in data.get("models", []):
		if typeof(model) == TYPE_DICTIONARY:
			var node := _model_node(model)
			if node != null:
				things.add_child(node)
	var box := AABB()
	var first := true
	for mesh: MeshInstance3D in things.find_children("*", "MeshInstance3D", true, false):
		var world_box := _transform_in(mesh, things) * mesh.get_aabb()
		box = world_box if first else box.merge(world_box)
		first = false
	if first:
		view.queue_free()
		return "it has nothing to draw"
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	view.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.55, 0.58, 0.65)
	view.add_child(environment)
	var camera := Camera3D.new()
	camera.fov = 40.0
	var centre := box.get_center()
	var radius := maxf(box.size.length() / 2.0, 0.05)
	var distance := radius / sin(deg_to_rad(camera.fov / 2.0)) * 1.05
	view.add_child(camera)
	camera.look_at_from_position(centre + Vector3(0.6, 0.55, 1.0).normalized() * distance, centre)
	camera.current = true
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	view.queue_free()
	if image == null or image.is_empty():
		return "nothing came out of the drawing (no renderer, as when headless?)"
	var saved := image.save_png(path)
	return "" if saved == OK else "couldn't save %s (error %d)" % [path, saved]


func _shape_node(shape: Dictionary) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	match shape.get("shape"):
		"sphere":
			node.mesh = SphereMesh.new()
		"cylinder":
			node.mesh = CylinderMesh.new()
		"capsule":
			node.mesh = CapsuleMesh.new()
		_:
			node.mesh = BoxMesh.new()
	var material := StandardMaterial3D.new()
	var color = shape.get("color")
	material.albedo_color = Color.from_string(color if typeof(color) == TYPE_STRING else "", Color.WHITE)
	node.material_override = material
	_place(node, shape)
	return node


# A prefab's model, if assets.gd has downloaded it.
func _model_node(model: Dictionary) -> Node3D:
	var id = model.get("id")
	var res = model.get("resolution", "1k")
	if not _good_id(id) or not _good_id(res):
		return null
	var path := "%s/assets/polyhaven/%s/%s/%s.gltf" % [_home, id, res, id]
	if not FileAccess.file_exists(path):
		return null
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(path, state) != OK:
		return null
	var scene := document.generate_scene(state) as Node3D
	if scene != null:
		_place(scene, model)
	return scene


func _place(node: Node3D, data: Dictionary) -> void:
	for key in ["position", "rotation", "scale"]:
		var v = data.get(key)
		if typeof(v) != TYPE_ARRAY or v.size() != 3:
			continue
		var vector := Vector3(float(v[0]), float(v[1]), float(v[2]))
		match key:
			"position":
				node.position = vector
			"rotation":
				node.rotation_degrees = vector
			"scale":
				node.scale = vector


# A node's transform relative to `root`, before either is in a tree.
func _transform_in(node: Node3D, root: Node3D) -> Transform3D:
	var out := Transform3D.IDENTITY
	var at: Node = node
	while at != null and at != root:
		if at is Node3D:
			out = (at as Node3D).transform * out
		at = at.get_parent()
	return out
