extends SlopitectModule

# Downloads files from the web (http/https) into /sdcard/Slopitect/assets/.
# web_fetch starts a download and returns an id; web_status reports progress.

const HOME := "/sdcard/Slopitect/assets/"
const MAX_BYTES := 52428800  # 50 MB
var jobs := {}
var next_id := 1


func setup() -> String:
	DirAccess.make_dir_recursive_absolute(HOME)
	register("web_fetch", _fetch, "download a URL into assets/: url (http/https), file (name, letters digits . _ - and / for subfolders)")
	register("web_status", _status, "downloads: optional id; state, bytes, error")
	return ""


func _fetch(request: Dictionary) -> Dictionary:
	var url := str(request.get("url", ""))
	var file := str(request.get("file", ""))
	if not (url.begins_with("http://") or url.begins_with("https://")):
		return {"ok": false, "error": "url must start with http:// or https://"}
	if file == "" or file.contains("..") or file.begins_with("/"):
		return {"ok": false, "error": "file must be a relative name inside assets/, no .."}
	var re := RegEx.new()
	re.compile("^[A-Za-z0-9._/-]+$")
	if re.search(file) == null:
		return {"ok": false, "error": "file may only use letters, digits, . _ - /"}
	var path := HOME + file
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var http := HTTPRequest.new()
	http.download_file = path
	http.body_size_limit = MAX_BYTES
	http.timeout = 120.0
	add_child(http)
	var id := next_id
	next_id += 1
	jobs[id] = {"id": id, "url": url, "path": path, "state": "downloading", "error": "", "http": http}
	http.request_completed.connect(_done.bind(id))
	var err := http.request(url)
	if err != OK:
		http.queue_free()
		jobs[id]["state"] = "failed"
		jobs[id]["error"] = "request failed to start: %d" % err
		jobs[id]["http"] = null
		return {"ok": false, "error": jobs[id]["error"]}
	return {"ok": true, "id": id, "path": path}


func _done(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray, id: int) -> void:
	var job: Dictionary = jobs[id]
	if result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300:
		job["state"] = "done"
	else:
		job["state"] = "failed"
		job["error"] = "result %d, http %d" % [result, code]
		if FileAccess.file_exists(job["path"]):
			DirAccess.remove_absolute(job["path"])
	job["bytes"] = job["http"].get_downloaded_bytes()
	job["http"].queue_free()
	job["http"] = null


func _info(job: Dictionary) -> Dictionary:
	var bytes = job.get("bytes", 0)
	if job["http"] != null:
		bytes = job["http"].get_downloaded_bytes()
	return {"id": job["id"], "url": job["url"], "path": job["path"], "state": job["state"], "bytes": bytes, "error": job["error"]}


func _status(request: Dictionary) -> Dictionary:
	if request.has("id"):
		var id := int(request["id"])
		if not jobs.has(id):
			return {"ok": false, "error": "no download with id %d" % id}
		return {"ok": true, "download": _info(jobs[id])}
	var list := []
	for j in jobs.values():
		list.append(_info(j))
	return {"ok": true, "downloads": list}
