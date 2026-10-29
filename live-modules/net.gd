extends SlopitectModule

# Slopitect live module: net.
# The one way onto the internet for downloads: only https, and only the
# hosts you allowed from the PC (net_config). A redirect is followed only
# when it stays on an allowed host. Nothing about you is sent: no key, no
# cookies, only the User-Agent.
#
# net_fetch downloads a file into the Slopitect folder's downloads/HOST/,
# with a NAME.source.json beside it that says where it came from (and its
# licence, when you give one). A file is written as NAME.part and only
# renamed when it arrived whole, so a failed download leaves nothing.
# Other modules download through fetch(url, path, max_bytes), which keeps
# to the same hosts.
# The hosts change from the PC only (net_config) and are kept in the app's
# own storage (user://net.json).

const SETTINGS_PATH := "user://net.json"
const DEFAULT_HOSTS := ["api.polyhaven.com", "dl.polyhaven.org"]
const USER_AGENT := "Slopitect/0.1"
const MAX_BYTES := 50 * 1024 * 1024
const MAX_REDIRECTS := 5
const MAX_RUNNING := 3
const MAX_JOBS_KEPT := 30
const TIMEOUT := 120.0

var hosts: Array = DEFAULT_HOSTS.duplicate()
var _home := ""  # downloads/ in the Slopitect folder
var _jobs := {}  # id -> {id, url, file, state, bytes, error}
var _next_id := 1
var _running := 0


func setup() -> String:
	_load()
	_home = ("/sdcard/Slopitect" if OS.get_name() == "Android" else OS.get_user_data_dir() + "/files_home") + "/downloads"
	var made := DirAccess.make_dir_recursive_absolute(_home)
	if made != OK:
		return "net can't make its folder %s (error %d; does the app have storage permission? files_status shows it)" % [_home, made]
	register("net_fetch", _fetch_command, "download a file from an allowed host into downloads/HOST/: url (https), optional file (a name: letters, digits, . _ - and / for folders; default the URL's last part), licence (text kept with it); returns an id")
	register("net_status", _status, "the allowed hosts and the downloads: optional id for one")
	register("net_config", _config, "from the PC only: hosts [names], or add / remove (a host name)")
	return ""


# Whether a URL is on an allowed host (https, and the host followed by "/",
# so no other port, no login part and no look-alike longer name gets in).
func allowed(url: String) -> bool:
	for host in hosts:
		if url.begins_with("https://%s/" % host):
			return true
	return false


# Downloads url to path (a full path) through the allowed hosts. Returns ""
# or what went wrong; on failure nothing is left at path. Await it.
func fetch(url: String, path: String, max_bytes: int = MAX_BYTES) -> String:
	if not allowed(url):
		return "refused %s: only https from %s is allowed (net_config on the PC adds hosts)" % [url, ", ".join(hosts)]
	var http := HTTPRequest.new()
	http.use_threads = true
	http.timeout = TIMEOUT
	http.max_redirects = 0  # each redirect is checked here instead
	http.body_size_limit = max_bytes
	add_child(http)
	var part := path + ".part"
	http.download_file = part
	var problem := ""
	var at := url
	for hop in MAX_REDIRECTS + 1:
		var started := http.request(at, ["User-Agent: " + USER_AGENT])
		if started != OK:
			problem = "couldn't start the request to %s (error %d)" % [at, started]
			break
		var reply: Array = await http.request_completed
		var result: int = reply[0]
		var code: int = reply[1]
		if result == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			problem = "%s was bigger than the %d bytes allowed" % [at, max_bytes]
		elif result == HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED and code in [301, 302, 303, 307, 308]:
			# With max_redirects 0 the engine stops at each redirect and hands it here.
			var next := _location(reply[2], at)
			if next.is_empty():
				problem = "%s redirected without saying where" % at
			elif not allowed(next):
				problem = "%s redirected to %s, which isn't an allowed host" % [at, next]
			elif hop == MAX_REDIRECTS:
				problem = "%s redirected more than %d times" % [url, MAX_REDIRECTS]
			else:
				at = next
				continue
		elif result != HTTPRequest.RESULT_SUCCESS:
			problem = "%s failed (HTTPRequest result %d; 3 = no connection, 4 = TLS, 13 = timeout)" % [at, result]
		elif code != 200:
			problem = "%s answered HTTP %d" % [at, code]
		break
	http.queue_free()
	if problem.is_empty() and DirAccess.rename_absolute(part, path) != OK:
		problem = "couldn't move the download into place at %s" % path
	if not problem.is_empty() and FileAccess.file_exists(part):
		DirAccess.remove_absolute(part)
	return problem


func _location(headers: PackedStringArray, from: String) -> String:
	for header in headers:
		if header.to_lower().begins_with("location:"):
			var to := header.substr(9).strip_edges()
			if to.begins_with("/"):
				var host_end := from.find("/", 8)
				return from.left(host_end) + to
			return to
	return ""


# --- Commands -------------------------------------------------------------------------

func _fetch_command(request: Dictionary) -> Dictionary:
	var url = request.get("url")
	if typeof(url) != TYPE_STRING or url.length() > 2000:
		return {"ok": false, "error": "\"url\" must be an https address"}
	if not allowed(url):
		return {"ok": false, "error": "refused %s: only https from %s is allowed (net_config on the PC adds hosts)" % [url, ", ".join(hosts)]}
	var host: String = url.substr(8).get_slice("/", 0)
	var file = request.get("file", url.get_slice("?", 0).get_slice("#", 0).get_file())
	if not _good_file(file):
		return {"ok": false, "error": "\"file\" must be a name of letters, digits, . _ - and / for folders (no .. and not starting with /), up to 200 characters"}
	var licence = request.get("licence", "")
	if typeof(licence) != TYPE_STRING or licence.length() > 200:
		return {"ok": false, "error": "\"licence\" must be text of up to 200 characters"}
	if _running >= MAX_RUNNING:
		return {"ok": false, "error": "%d downloads are running already; wait for one (net_status)" % MAX_RUNNING}
	var path := "%s/%s/%s" % [_home, host, file]
	var made := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if made != OK:
		return {"ok": false, "error": "couldn't make the folder %s (error %d)" % [path.get_base_dir(), made]}
	var id := _next_id
	_next_id += 1
	_jobs[id] = {"id": id, "url": url, "file": path, "state": "downloading", "bytes": 0, "error": ""}
	while _jobs.size() > MAX_JOBS_KEPT:
		var oldest: int = _jobs.keys().min()
		if _jobs[oldest]["state"] == "downloading":
			break
		_jobs.erase(oldest)
	_run(id, licence)
	return {"ok": true, "id": id, "file": path}


func _run(id: int, licence: String) -> void:
	_running += 1
	var job: Dictionary = _jobs[id]
	var problem := await fetch(job["url"], job["file"])
	_running -= 1
	if problem.is_empty():
		job["state"] = "done"
		var done := FileAccess.open(job["file"], FileAccess.READ)
		job["bytes"] = done.get_length() if done else 0
		var source := {"url": job["url"], "downloaded": Time.get_datetime_string_from_system(true) + "Z", "licence": licence}
		var out := FileAccess.open(job["file"] + ".source.json", FileAccess.WRITE)
		if out:
			out.store_string(JSON.stringify(source, "\t"))
			out.close()
	else:
		job["state"] = "failed"
		job["error"] = problem
		push_error("Slopitect net: " + problem)


func _status(request: Dictionary) -> Dictionary:
	if request.has("id"):
		var id = request["id"]
		if typeof(id) not in [TYPE_INT, TYPE_FLOAT] or not _jobs.has(int(id)):
			return {"ok": false, "error": "no download with id %s" % JSON.stringify(id)}
		return {"ok": true, "download": _jobs[int(id)]}
	return {"ok": true, "hosts": hosts, "folder": _home, "running": _running, "downloads": _jobs.values()}


func _config(request: Dictionary) -> Dictionary:
	var changed := hosts.duplicate()
	if request.has("hosts"):
		if typeof(request["hosts"]) != TYPE_ARRAY or not request["hosts"].all(_good_host):
			return {"ok": false, "error": "\"hosts\" must be a list of host names like \"dl.polyhaven.org\""}
		changed = request["hosts"].duplicate()
	if request.has("add"):
		if not _good_host(request["add"]):
			return {"ok": false, "error": "\"add\" must be a host name like \"dl.polyhaven.org\""}
		if not request["add"] in changed:
			changed.append(request["add"])
	if request.has("remove"):
		if not request["remove"] in changed:
			return {"ok": false, "error": "%s isn't an allowed host" % JSON.stringify(request["remove"])}
		changed.erase(request["remove"])
	hosts = changed
	var out := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if out == null:
		push_error("Slopitect net: couldn't save %s (error %d)" % [SETTINGS_PATH, FileAccess.get_open_error()])
	else:
		out.store_string(JSON.stringify({"hosts": hosts}, "\t"))
		out.close()
	return {"ok": true, "hosts": hosts}


# A plain host name: lower-case letters, digits, - and dots, no port.
func _good_host(host) -> bool:
	if typeof(host) != TYPE_STRING or host.is_empty() or host.length() > 253 or host.begins_with(".") or host.ends_with(".") or host.contains(".."):
		return false
	for c in host:
		if not (c == "." or c == "-" or (c >= "a" and c <= "z") or (c >= "0" and c <= "9")):
			return false
	return true


func _good_file(file) -> bool:
	if typeof(file) != TYPE_STRING or file.is_empty() or file.length() > 200 or file.begins_with("/") or file.ends_with("/") \
			or file.contains("..") or file.ends_with(".part") or file.ends_with(".source.json"):
		return false
	for c in file:
		if not (c in "._-/" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9")):
			return false
	return true


func _load() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var saved = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if typeof(saved) != TYPE_DICTIONARY or typeof(saved.get("hosts")) != TYPE_ARRAY or not saved["hosts"].all(_good_host):
		push_error("Slopitect net: %s isn't readable; using the default hosts" % SETTINGS_PATH)
		return
	hosts = saved["hosts"].duplicate()
