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
#
# net_search searches the web through DuckDuckGo (no key, no cost) and
# net_read gives a page's text. net_read only reads a page that a search
# found or one on an allowed host, so nothing can be sent off in a made-up
# address. The agent uses these instead of Claude's own web search when the
# Settings window's "Search through the net module" is on.

const SETTINGS_PATH := "user://net.json"
const DEFAULT_HOSTS := ["api.polyhaven.com", "dl.polyhaven.org"]
const USER_AGENT := "Slopitect/0.1"
const MAX_BYTES := 50 * 1024 * 1024
const MAX_REDIRECTS := 5
const MAX_RUNNING := 3
const MAX_JOBS_KEPT := 30
const TIMEOUT := 120.0
const SEARCH_URL := "https://html.duckduckgo.com/html/?q="
const SEARCH_BYTES := 1024 * 1024
const READ_BYTES := 2 * 1024 * 1024
const READ_CHARS := 6000  # what net_read gives by default, and SEARCH_RESULTS
const MAX_READ_CHARS := 20000
const SEARCH_RESULTS := 8
const FOUND_KEPT := 100  # the newest search results net_read may open

var hosts: Array = DEFAULT_HOSTS.duplicate()
var _home := ""  # downloads/ in the Slopitect folder
var _jobs := {}  # id -> {id, url, file, state, bytes, error}
var _next_id := 1
var _running := 0
var _found: Array = []  # addresses from the newest searches, oldest first


func setup() -> String:
	_load()
	_home = ("/sdcard/Slopitect" if OS.get_name() == "Android" else OS.get_user_data_dir() + "/files_home") + "/downloads"
	var made := DirAccess.make_dir_recursive_absolute(_home)
	if made != OK:
		return "net can't make its folder %s (error %d; does the app have storage permission? files_status shows it)" % [_home, made]
	register("net_fetch", _fetch_command, "download a file from an allowed host into downloads/HOST/: url (https), optional file (a name: letters, digits, . _ - and / for folders; default the URL's last part), licence (text kept with it); returns an id")
	register("net_search", _search_command, "search the web (DuckDuckGo): query (text), optional count (1-%d); returns title, url and snippet for each result" % SEARCH_RESULTS)
	register("net_read", _read_command, "the text of a web page that net_search found (or one on an allowed host): url, optional offset and max_chars (default %d, at most %d)" % [READ_CHARS, MAX_READ_CHARS])
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
	var problem: String = (await _follow(http, url, max_bytes, allowed))[0]
	http.queue_free()
	if problem.is_empty() and DirAccess.rename_absolute(part, path) != OK:
		problem = "couldn't move the download into place at %s" % path
	if not problem.is_empty() and FileAccess.file_exists(part):
		DirAccess.remove_absolute(part)
	return problem


# Requests url with http, following a redirect only to where may_go(url)
# says yes. Returns [problem ("" if it worked), the address it ended at, the
# reply's headers, its body].
func _follow(http: HTTPRequest, url: String, max_bytes: int, may_go: Callable) -> Array:
	var at := url
	for hop in MAX_REDIRECTS + 1:
		var started := http.request(at, ["User-Agent: " + USER_AGENT])
		if started != OK:
			return ["couldn't start the request to %s (error %d)" % [at, started], at, PackedStringArray(), PackedByteArray()]
		var reply: Array = await http.request_completed
		var result: int = reply[0]
		var code: int = reply[1]
		var problem := ""
		if result == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			problem = "%s was bigger than the %d bytes allowed" % [at, max_bytes]
		elif result == HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED and code in [301, 302, 303, 307, 308]:
			# With max_redirects 0 the engine stops at each redirect and hands it here.
			var next := _location(reply[2], at)
			if next.is_empty():
				problem = "%s redirected without saying where" % at
			elif not may_go.call(next):
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
		return [problem, at, reply[2], reply[3]]
	return ["%s redirected more than %d times" % [url, MAX_REDIRECTS], at, PackedStringArray(), PackedByteArray()]


# Gets url into memory (for search and read). Returns [problem, address it
# ended at, headers, body].
func _download_text(url: String, max_bytes: int, may_go: Callable) -> Array:
	var http := HTTPRequest.new()
	http.use_threads = true
	http.timeout = TIMEOUT
	http.max_redirects = 0
	http.body_size_limit = max_bytes
	add_child(http)
	var got: Array = await _follow(http, url, max_bytes, may_go)
	http.queue_free()
	return got


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


# --- Search and read --------------------------------------------------------------

# Searches DuckDuckGo's plain page. Returns [problem, [{title, url, snippet}]].
func search(query: String, count: int = SEARCH_RESULTS) -> Array:
	var got: Array = await _download_text(SEARCH_URL + query.uri_encode(), SEARCH_BYTES, func(next: String): return next.begins_with("https://html.duckduckgo.com/"))
	if not got[0].is_empty():
		return [got[0], []]
	var found := parse_results((got[3] as PackedByteArray).get_string_from_utf8())
	if found.is_empty() and "anomaly" in (got[3] as PackedByteArray).get_string_from_utf8():
		return ["DuckDuckGo asked to check that a person is searching (it does this to apps now and then); try again in a while, or switch to Claude's search in Settings", []]
	found = found.slice(0, count)
	for result in found:
		_found.erase(result["url"])
		_found.append(result["url"])
	while _found.size() > FOUND_KEPT:
		_found.pop_front()
	return ["", found]


# The results on a DuckDuckGo results page: each one's link (class
# result__a, through DuckDuckGo's /l/?uddg= redirect) and snippet. Adverts
# (links to duckduckgo.com/y.js) are left out.
static func parse_results(page: String) -> Array:
	var links := RegEx.create_from_string("(?s)<a\\s[^>]*class=\"result__a\"[^>]*>(.*?)</a>")
	var snippets := RegEx.create_from_string("(?s)class=\"result__snippet\"[^>]*>(.*?)</(?:a|div|td)>")
	var href := RegEx.create_from_string("href=\"([^\"]+)\"")
	var found := []
	# Each result's snippet comes after its link and before the next link.
	for link in links.search_all(page):
		var tag := link.get_string(0)
		var target := href.search(tag)
		if target == null:
			continue
		var url := _real_url(_unescape(target.get_string(1)))
		var next_link := page.find("class=\"result__a\"", link.get_end())
		var snippet := snippets.search(page, link.get_end(), next_link if next_link != -1 else -1)
		if not url.begins_with("https://") or url.begins_with("https://duckduckgo.com/y.js"):
			continue
		found.append({"title": _text_of(link.get_string(1)), "url": url, "snippet": _text_of(snippet.get_string(1)) if snippet else ""})
	return found


# DuckDuckGo's links go through //duckduckgo.com/l/?uddg=REAL&rut=...
static func _real_url(link: String) -> String:
	if link.begins_with("//"):
		link = "https:" + link
	var mark := link.find("uddg=")
	if link.begins_with("https://duckduckgo.com/l/") and mark != -1:
		return link.substr(mark + 5).get_slice("&", 0).uri_decode()
	return link


# Whether net_read may open url: one a search found, or on an allowed host.
func readable(url: String) -> bool:
	return url in _found or allowed(url)


func _host(url: String) -> String:
	return url.substr(8).get_slice("/", 0).get_slice("?", 0).get_slice("#", 0)


# A page's readable text: no scripts, styles or tags, one line per block.
static func page_text(page: String) -> Dictionary:
	var title := RegEx.create_from_string("(?is)<title[^>]*>(.*?)</title>").search(page)
	var text := RegEx.create_from_string("(?is)<(script|style|noscript|svg|head)\\b.*?</\\1\\s*>|<!--.*?-->").sub(page, " ", true)
	text = RegEx.create_from_string("(?i)<(br|/p|/div|/li|/h[1-6]|/tr|/section|/article)\\b[^>]*>").sub(text, "\n", true)
	text = _unescape(RegEx.create_from_string("(?s)<[^>]*>").sub(text, " ", true))
	text = RegEx.create_from_string("[ \\t\\r\\f\u00a0]+").sub(text, " ", true)
	text = RegEx.create_from_string(" ?\\n[ \\n]*").sub(text, "\n", true)
	return {"title": _text_of(title.get_string(1)) if title else "", "text": text.strip_edges()}


static func _text_of(html: String) -> String:
	var text := _unescape(RegEx.create_from_string("(?s)<[^>]*>").sub(html, "", true))
	return RegEx.create_from_string("\\s+").sub(text, " ", true).strip_edges()


static func _unescape(text: String) -> String:
	for entity in [["&lt;", "<"], ["&gt;", ">"], ["&quot;", "\""], ["&#39;", "'"], ["&apos;", "'"], ["&nbsp;", " "]]:
		text = text.replace(entity[0], entity[1])
	var numbers := RegEx.create_from_string("&#(x[0-9a-fA-F]+|[0-9]+);")
	var out := ""
	var last := 0
	for found in numbers.search_all(text):
		var code := found.get_string(1)
		var value := code.substr(1).hex_to_int() if code.begins_with("x") else code.to_int()
		out += text.substr(last, found.get_start() - last) + (char(value) if value > 0 and value < 0x110000 else "")
		last = found.get_end()
	return (out + text.substr(last)).replace("&amp;", "&")


func _search_command(request: Dictionary) -> Dictionary:
	var query = request.get("query")
	if typeof(query) != TYPE_STRING or query.strip_edges().is_empty() or query.length() > 400:
		return {"ok": false, "error": "\"query\" must be text, up to 400 characters"}
	var count = request.get("count", SEARCH_RESULTS)
	if typeof(count) not in [TYPE_INT, TYPE_FLOAT] or count != floorf(count) or count < 1 or count > SEARCH_RESULTS:
		return {"ok": false, "error": "\"count\" must be a whole number from 1 to %d" % SEARCH_RESULTS}
	var pending := SlopitectPending.new()
	_finish_search(pending, query.strip_edges(), int(count))
	return {"ok": true, "wait": pending}


func _finish_search(pending: SlopitectPending, query: String, count: int) -> void:
	var got: Array = await search(query, count)
	if pending.cancelled:
		return
	if not got[0].is_empty():
		pending.finish({"ok": false, "error": got[0]})
	else:
		pending.finish({"ok": true, "query": query, "results": got[1]})


func _read_command(request: Dictionary) -> Dictionary:
	var url = request.get("url")
	if typeof(url) != TYPE_STRING or not url.begins_with("https://") or url.length() > 2000:
		return {"ok": false, "error": "\"url\" must be an https address"}
	if not readable(url):
		return {"ok": false, "error": "net_read opens only pages that net_search found, or ones on the allowed hosts (%s); search for it first" % ", ".join(hosts)}
	var offset = request.get("offset", 0)
	var most = request.get("max_chars", READ_CHARS)
	for value in [offset, most]:
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or value != floorf(value) or value < 0:
			return {"ok": false, "error": "\"offset\" and \"max_chars\" must be whole numbers, 0 or more"}
	if most < 1 or most > MAX_READ_CHARS:
		return {"ok": false, "error": "\"max_chars\" must be from 1 to %d" % MAX_READ_CHARS}
	var pending := SlopitectPending.new()
	_finish_read(pending, url, int(offset), int(most))
	return {"ok": true, "wait": pending}


func _finish_read(pending: SlopitectPending, url: String, offset: int, most: int) -> void:
	# A redirect may stay on the page's own host (http to https, www and
	# such are on it already), or go to an address it could open anyway.
	var host := _host(url)
	var got: Array = await _download_text(url, READ_BYTES, func(next: String): return next.begins_with("https://") and (_host(next) == host or readable(next)))
	if pending.cancelled:
		return
	if not got[0].is_empty():
		pending.finish({"ok": false, "error": got[0]})
		return
	var kind := ""
	for header in got[2]:
		if header.to_lower().begins_with("content-type:"):
			kind = header.substr(13).strip_edges().to_lower()
	if not (kind.is_empty() or kind.begins_with("text/") or kind.contains("xml") or kind.contains("json")):
		pending.finish({"ok": false, "error": "%s is %s, not a page of text (net_fetch downloads files from the allowed hosts)" % [got[1], kind]})
		return
	var body := (got[3] as PackedByteArray).get_string_from_utf8()
	var page := page_text(body) if kind.is_empty() or kind.contains("html") else {"title": "", "text": body}
	var text: String = page["text"]
	pending.finish({"ok": true, "url": got[1], "title": page["title"], "text": text.substr(offset, most),
		"offset": offset, "more": maxi(0, text.length() - offset - most)})


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
