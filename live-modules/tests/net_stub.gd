extends SlopitectModule
# Test stand-in for net.gd: a fake Poly Haven, no internet.
var allow_cdn := false
var fetched: Array = []
func setup() -> String:
	return ""
func allowed(url: String) -> bool:
	for host in ["api.polyhaven.com", "dl.polyhaven.org"] + (["cdn.polyhaven.com"] if allow_cdn else []):
		if url.begins_with("https://%s/" % host):
			return true
	return false
func _fixtures() -> String:
	return OS.get_user_data_dir() + "/fixtures"
func fetch(url: String, path: String, max_bytes: int = 50 * 1024 * 1024) -> String:
	await get_tree().process_frame
	await get_tree().process_frame
	if not allowed(url):
		return "refused " + url
	fetched.append(url)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(_fixtures())
	if url.begins_with("https://api.polyhaven.com/assets?t="):
		var kind := url.get_slice("=", 1)
		var cats := ["wood", "brick", "rock", "metal", "fabric"] if kind == "textures" else ["furniture", "props", "nature"]
		var list := {}
		var n := 30 if kind == "textures" else 15
		for i in n:
			var id := "%s_%02d" % [cats[i % cats.size()], i]
			list[id] = {"name": "%s %d" % [cats[i % cats.size()].capitalize(), i], "categories": [cats[i % cats.size()]],
				"download_count": 1000 - i, "polycount": 5000 + i * 100, "thumbnail_url": "x"}
		_write(path, JSON.stringify(list))
		return ""
	if url.begins_with("https://cdn.polyhaven.com/asset_img/thumbs/"):
		var id := url.get_file().get_slice(".", 0)
		var image := Image.create(128, 128, false, Image.FORMAT_RGB8)
		image.fill(Color.from_hsv(float(hash(id) % 360) / 360.0, 0.6, 0.9))
		image.fill_rect(Rect2i(32, 32, 64, 64), Color.from_hsv(float(hash(id + "x") % 360) / 360.0, 0.7, 0.5))
		image.save_png(path)
		return ""
	if url.begins_with("https://api.polyhaven.com/files/"):
		var id := url.get_file()
		var jpg := _fixtures() + "/%s.jpg" % id
		var image := Image.create(256, 256, false, Image.FORMAT_RGB8)
		for y in 256:
			for x in 256:
				image.set_pixel(x, y, Color(0.5 + 0.4 * sin(x * 0.2), 0.3, 0.2 + 0.2 * ((x / 32 + y / 32) % 2)))
		image.save_jpg(jpg)
		var size := FileAccess.open(jpg, FileAccess.READ).get_length()
		_write(path, JSON.stringify({"Diffuse": {"1k": {"jpg": {"url": "https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/%s/%s_diff_1k.jpg" % [id, id], "size": size, "md5": FileAccess.get_md5(jpg)}}}}))
		return ""
	if url.begins_with("https://dl.polyhaven.org/"):
		var id := url.get_base_dir().get_file()
		DirAccess.copy_absolute(_fixtures() + "/%s.jpg" % id, path)
		return ""
	return "no fixture for " + url
func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
