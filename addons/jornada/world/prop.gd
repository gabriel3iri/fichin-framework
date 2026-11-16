class_name Prop
extends StaticBody2D
## Objeto decorativo con colisión (farol, banco, cajón). Origen = pies del objeto.

@export var prop_texture: Texture2D
@export var collider_size: Vector2 = Vector2(12, 6)
## Px que build_world estira la base hasta la pared que tiene al lado (x: a la izquierda, y: hacia arriba, z: a la
## derecha), para que no quede una rendija por donde pasar detrás de un mueble apoyado en la pared.
@export var wall_reach: Vector3 = Vector3.ZERO
## Plano sobre el piso (una alfombra): se ordena por su borde de arriba, así queda debajo de quien la pisa.
@export var flat: bool = false
## Cuadros de animación en tira horizontal (el fuego de una chimenea, el péndulo de un reloj) y su velocidad.
@export var frames: int = 1
@export var fps: float = 6.0
## Px que se levanta el dibujo sin mover la base (lo que se apoya sobre un mostrador).
@export var raise: float = 0.0
## Sombrita en el piso al pie (false para lo que cuelga de una pared: un cuadro, una estación del vía crucis).
@export var shadow: bool = true
## Cuelga de la pared del fondo (un cuadro, un farol, un nicho): se ordena por la pared, WALL_LIFT px más arriba de
## sus pies, así quien camina pegado a la pared pasa por delante y no por detrás.
@export var hung: bool = false

const WALL_LIFT: float = 16.0
## Puerta de reja (world.json "closed_if_any" y "open"): cerrada (sólida, con prop_texture) mientras el jugador tenga
## alguno de estos flags; si no, abierta: sin colisión y con open_texture. La navegación de los NPCs la pasa siempre.
@export var closed_if_any: PackedStringArray = PackedStringArray()
@export var open_texture: Texture2D

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _shape: CollisionShape2D = $CollisionShape2D


## Fuentes de luz por sprite: [posición, radio del halo, aplastado, encendido mínimo, alcance, fuerza].
## El farol suma un charco en el piso; el alcance ilumina a personajes y objetos cercanos (DayLight).
const LIGHTS: Dictionary = {
	"lamp": [[Vector2(0, -39), 28, 1.0, 0.0, 84.0, 1.0], [Vector2(0, -1), 22, 0.35, 0.0, 0.0, 0.0]],
	"stove": [[Vector2(0, -13), 12, 1.0, 0.5, 40.0, 0.6]],
	"forge": [[Vector2(0, -11), 24, 1.0, 0.7, 72.0, 0.9]],
	"altar": [[Vector2(-8, -30), 7, 1.0, 0.6, 30.0, 0.4], [Vector2(9, -30), 7, 1.0, 0.6, 30.0, 0.4]],
	"long_table": [[Vector2(1, -22), 6, 1.0, 0.6, 34.0, 0.45]],
	"round_table": [[Vector2(4, -22), 6, 1.0, 0.6, 30.0, 0.4]],
	"kachelofen": [[Vector2(0, -17), 14, 1.0, 0.6, 56.0, 0.7]],
	"grave_cross_a": [[Vector2(3, -8), 4, 1.0, 0.5, 18.0, 0.3]],
	"grave_stone_b": [[Vector2(3, -8), 4, 1.0, 0.5, 18.0, 0.3]],
	"grave_tall": [[Vector2(3, -8), 4, 1.0, 0.5, 18.0, 0.3]],
	"grave_child": [[Vector2(3, -8), 4, 1.0, 0.5, 18.0, 0.3]],
	"grave_lantern": [[Vector2(0, -23), 10, 1.0, 0.4, 48.0, 0.6]],
	"fireplace": [[Vector2(0, -18), 20, 1.0, 0.8, 96.0, 1.0]],
	"kitchen_range": [[Vector2(-6, -12), 10, 1.0, 0.7, 50.0, 0.6]],
	"bread_oven": [[Vector2(0, -16), 16, 1.0, 0.7, 80.0, 0.8]],
	"iron_stove": [[Vector2(0, -11), 6, 1.0, 0.6, 34.0, 0.4]],
	"glue_stove": [[Vector2(0, -9), 6, 1.0, 0.6, 34.0, 0.4]],
	"cellar_lantern": [[Vector2(0, -50), 12, 1.0, 0.7, 70.0, 0.7]],
	"nightstand": [[Vector2(-4, -24), 6, 1.0, 0.6, 30.0, 0.4]],
	"wall_sconce": [[Vector2(0, -50), 8, 1.0, 0.6, 44.0, 0.5]],
	"church_altar": [[Vector2(8, -70), 7, 1.0, 0.5, 40.0, 0.3]],
	"candelabrum": [[Vector2(0, -45), 5, 1.0, 0.5, 28.0, 0.25]],
	"votive_rack": [[Vector2(0, -14), 7, 1.0, 0.6, 32.0, 0.3]],
	"herrgottswinkel": [[Vector2(-3, -47), 5, 1.0, 0.6, 30.0, 0.35]],
	"barrel_table": [[Vector2(-5, -28), 5, 1.0, 0.6, 30.0, 0.4]],
	"carab_stove": [[Vector2(0, -10), 6, 1.0, 0.6, 34.0, 0.4]],
	"carab_desk": [[Vector2(-16, -29), 6, 1.0, 0.5, 36.0, 0.4]],
	"jail_lamp": [[Vector2(0, -54), 10, 1.0, 0.8, 64.0, 0.7]],
	"guard_table": [[Vector2(-9, -22), 7, 1.0, 0.8, 44.0, 0.55]],
	"crypt_lantern": [[Vector2(0, -35), 12, 1.0, 0.9, 80.0, 0.8]],
	"candle_stubs": [[Vector2(-8, -8), 6, 1.0, 0.9, 40.0, 0.5], [Vector2(7, -9), 6, 1.0, 0.9, 40.0, 0.5]],
}


## Profundidad de los muebles bajos (mesas, mostradores, bancos, escritorios). La base de colisión de un objeto suele ser
## una franja fina al pie del dibujo: quien se para detrás queda pegado al frente, "sobre" la mesa, o tapado hasta el
## pecho. La base tiene que ser tan honda como para que, detrás, el mueble tape solo COVER px (los pies y las piernas)
## al personaje. world.json "props": {"depth": {"cover", "cap", "min_width", "max_height"}} cambia los valores (o
## "depth": false lo apaga). La usa build_world al armar los interiores y la revisa el testkit (shallow_furniture).
const DEPTH_DEFAULTS: Dictionary = {"cover": 12, "cap": 16, "min_width": 20, "max_height": 40}


## Base que corresponde a un mueble con este dibujo (`frames` cuadros en tira): la misma si no es un mueble bajo y ancho.
static func furniture_base(texture: Texture2D, frames: int, collider: Vector2, cfg: Variant) -> Vector2:
	if collider == Vector2.ZERO or texture == null or (cfg is bool and not cfg):
		return collider
	var rules: Dictionary = DEPTH_DEFAULTS.merged(cfg if cfg is Dictionary else {}, true)
	var image: Image = texture.get_image()
	if image == null:
		return collider
	if image.is_compressed():
		image.decompress()
	var width: int = image.get_width() / maxi(frames, 1)
	var top: int = image.get_height()
	var left: int = width
	var right: int = -1
	for y in image.get_height():
		for x in width:
			if image.get_pixel(x, y).a >= 0.78:
				top = mini(top, y)
				left = mini(left, x)
				right = maxi(right, x)
	if right < 0:
		return collider
	var tall: int = image.get_height() - top
	var wide: int = right - left + 1
	if tall < 14 or tall > int(rules["max_height"]) or wide < int(rules["min_width"]):
		return collider
	var depth: float = minf(float(rules["cap"]), float(tall - int(rules["cover"])))
	return Vector2(maxf(collider.x, wide - 4.0), maxf(collider.y, depth))


var _closed: bool = true


func _ready() -> void:
	_sprite.texture = prop_texture
	_sprite.position = Vector2(0, -prop_texture.get_height() / 2.0 - raise)
	_sprite.hframes = maxi(frames, 1)
	set_process(frames > 1 or is_gate())
	if flat:
		position.y -= prop_texture.get_height()
		_sprite.position.y += prop_texture.get_height()
	var lift := Vector2(0, WALL_LIFT if hung else 0.0)
	position -= lift
	_sprite.position += lift
	# La forma viene compartida desde la escena: cada objeto necesita la suya, si no todos quedan del tamaño del último
	# que se cargó (la fuente se atravesaba con la base de un árbol).
	_shape.shape = _shape.shape.duplicate()
	var box: Rect2 = _base()
	(_shape.shape as RectangleShape2D).size = box.size
	_shape.position = box.get_center()
	_shape.disabled = collider_size == Vector2.ZERO   # [0, 0] en world.json: se camina por encima (hojas de un portón)
	if is_gate():
		_update_gate()
	if collider_size.y <= 12.0 and not flat and shadow:   # los muebles con base grande (cama) ya apoyan en el piso
		var w: int = clampi(roundi(maxf(collider_size.x + 4.0, prop_texture.get_width() / float(maxi(frames, 1)) * 0.7)), 8, 56)
		PixelLight.add_blob(self, Vector2i(w, clampi(w / 3, 3, 10)))
	for light: Array in LIGHTS.get(prop_texture.resource_path.get_file().get_basename(), []):
		var at: Vector2 = light[0] + lift + Vector2(0, prop_texture.get_height() if flat else 0)   # medido desde los pies
		PixelLight.add_halo(self, at, light[1], light[2], light[3], light[4], light[5])


func _process(_delta: float) -> void:
	if is_gate():
		_update_gate()
		if frames <= 1:
			return
	# Cada objeto con su fase (por posición): dos chimeneas no laten juntas.
	var phase: float = fposmod(position.x * 0.37 + position.y * 0.11, 1.0)
	_sprite.frame = int(Time.get_ticks_msec() / 1000.0 * fps + phase * frames) % frames


func is_gate() -> bool:
	return not closed_if_any.is_empty()


## ¿Está cerrada ahora? (una puerta de reja; lo demás, siempre «cerrado»: sólido según su collider)
func is_closed() -> bool:
	return _closed


func _update_gate() -> void:
	var closed: bool = false
	for flag: String in closed_if_any:
		if LoopManager.has_knowledge(flag):
			closed = true
			break
	if closed == _closed and _sprite.texture != null:
		return
	_closed = closed
	var tex: Texture2D = prop_texture if closed or open_texture == null else open_texture
	_sprite.texture = tex
	_sprite.position = Vector2(0, -tex.get_height() / 2.0 - raise)
	_shape.set_deferred("disabled", not closed or collider_size == Vector2.ZERO)


## Rectángulo (en coordenadas de la zona) que ocupa en el piso; lo usa la navegación de los NPCs.
## Una puerta de reja no ocupa nada: la grilla se arma una vez por zona y la reja se abre y se cierra.
func footprint() -> Rect2:
	if collider_size == Vector2.ZERO or is_gate():
		return Rect2()
	var box: Rect2 = _base()
	return Rect2(position + box.position, box.size)


## La base de colisión respecto del origen (los pies), con lo que se estira hasta la pared.
func _base() -> Rect2:
	var size := Vector2(collider_size.x + wall_reach.x + wall_reach.z, collider_size.y + wall_reach.y)
	return Rect2(Vector2(-collider_size.x / 2.0 - wall_reach.x, -size.y), size)
