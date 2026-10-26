extends Reference

# Raw PNGs are read once; module assets do not require Godot import metadata.
const ROOT = "res://ftc_mods/ftc.talent_market/UI/Assets/"
var sheets = {}
var regions = {}
var images = {}

func sheet(filename):
	if sheets.has(filename):
		return sheets[filename]
	var file = File.new()
	if not file.file_exists(ROOT + filename):
		return null
	var image = Image.new()
	if image.load(ROOT + filename) != OK or image.get_width() <= 0 or image.get_height() <= 0:
		return null
	var texture = ImageTexture.new()
	texture.create_from_image(image, Texture.FLAG_FILTER)
	sheets[filename] = texture
	images[filename] = image
	return texture

func cell(filename, columns, rows, column, row, trim = false, maximum_height = 0):
	var key = "%s:%d:%d:%d:%d:%s:%d" % [filename, columns, rows, column, row, trim, maximum_height]
	if regions.has(key):
		return regions[key]
	var atlas = sheet(filename)
	if atlas == null or columns < 1 or rows < 1 or column < 0 or row < 0 or column >= columns or row >= rows:
		return null
	var texture = AtlasTexture.new()
	texture.atlas = atlas
	var size = atlas.get_size() / Vector2(columns, rows)
	var region = Rect2(Vector2(column, row) * size, size)
	if trim:
		var ink = images[filename].get_rect(region).get_used_rect()
		if ink.size.x > 0 and ink.size.y > 0:
			region = Rect2(region.position + ink.position, ink.size)
	if maximum_height > 0 and region.size.y > maximum_height:
		var crop = images[filename].get_rect(region)
		var width = max(1, int(round(region.size.x * float(maximum_height) / region.size.y)))
		crop.resize(width, maximum_height, Image.INTERPOLATE_BILINEAR)
		var reduced = ImageTexture.new()
		reduced.create_from_image(crop, Texture.FLAG_FILTER)
		regions[key] = reduced
		return reduced
	texture.region = region
	regions[key] = texture
	return texture

func style(texture, patch = 24.0, padding = 12.0):
	var box = StyleBoxTexture.new()
	box.texture = texture
	# These are the native Godot 3 StyleBoxTexture margins used by game themes.
	for side in ["left", "right", "top", "bottom"]:
		box.set("margin_" + side, patch)
		box.set("content_margin_" + side, padding)
	return box

func icon(texture, dimensions):
	var rect = TextureRect.new()
	rect.texture = texture
	rect.expand = true
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.rect_min_size = dimensions
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect
