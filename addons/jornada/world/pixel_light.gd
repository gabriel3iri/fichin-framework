class_name PixelLight
extends RefCounted
## Texturas de luz y sombra en pixel art, generadas en código y cacheadas: sombras de contacto
## (elipse de dos tonos) y halos con anillos escalonados y borde tramado (nada de degradé suave).
## DayLight decide cuánto se ven: los halos están en el grupo "glow" y no se tiñen con la hora.

const WARM: Color = Color(1.0, 0.78, 0.45)

static var _blobs: Dictionary = {}
static var _halos: Dictionary = {}
static var _add_material: CanvasItemMaterial


## Sombra de contacto bajo los pies (centro = origen del nodo, apoyada en y = 0).
static func add_blob(parent: Node2D, size: Vector2i, y: float = -1.0) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = "Shadow"
	sprite.texture = blob(size)
	sprite.position = Vector2(0, y)
	parent.add_child(sprite)
	parent.move_child(sprite, 0)
	return sprite


## Halo aditivo que DayLight enciende con la hora. `min_glow` lo deja prendido aunque sea de día
## (fragua, estufa, velas). `reach` (px, medido desde la base del objeto) es hasta dónde ilumina a
## personajes y objetos, con fuerza `power`; 0 = solo se ve el halo.
static func add_halo(parent: Node2D, at: Vector2, radius: int, squash: float = 1.0, min_glow: float = 0.0,
		reach: float = 0.0, power: float = 1.0) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = "Halo"
	sprite.texture = halo(radius, squash)
	sprite.position = at
	sprite.material = add_material()
	sprite.modulate.a = 0.0
	sprite.set_meta("min_glow", min_glow)
	sprite.set_meta("reach", reach)
	sprite.set_meta("power", power)
	sprite.add_to_group("glow")
	parent.add_child(sprite)
	return sprite


static func blob(size: Vector2i) -> ImageTexture:
	if _blobs.has(size):
		return _blobs[size]
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var half := Vector2(size) / 2.0
	for y in size.y:
		for x in size.x:
			var d: Vector2 = (Vector2(x, y) + Vector2(0.5, 0.5) - half) / half
			var r: float = d.length_squared()
			if r <= 0.45:
				img.set_pixel(x, y, Color(0.05, 0.04, 0.1, 0.42))
			elif r <= 1.0:
				img.set_pixel(x, y, Color(0.05, 0.04, 0.1, 0.26))
	var tex := ImageTexture.create_from_image(img)
	_blobs[size] = tex
	return tex


static func halo(radius: int, squash: float = 1.0) -> ImageTexture:
	var key := Vector2(radius, squash)
	if _halos.has(key):
		return _halos[key]
	var h: int = maxi(2, int(radius * 2 * squash))
	var img := Image.create(radius * 2, h, false, Image.FORMAT_RGBA8)
	var bands: Array = [[0.3, 0.34], [0.55, 0.2], [0.8, 0.1], [1.0, 0.045]]
	for y in h:
		for x in radius * 2:
			var d := Vector2((x + 0.5 - radius) / radius, (y + 0.5 - h / 2.0) / (h / 2.0))
			var r: float = d.length()
			for i in bands.size():
				var edge: float = bands[i][0]
				if r <= edge:
					var a: float = bands[i][1]
					# Borde tramado: el último 8 % de cada anillo alterna con el anillo de afuera.
					if r > edge - 0.08 and (x + y) % 2 == 0 and i + 1 < bands.size():
						a = bands[i + 1][1]
					img.set_pixel(x, y, Color(WARM.r, WARM.g, WARM.b, a))
					break
	var tex := ImageTexture.create_from_image(img)
	_halos[key] = tex
	return tex


static func add_material() -> CanvasItemMaterial:
	if _add_material == null:
		_add_material = CanvasItemMaterial.new()
		_add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add_material
