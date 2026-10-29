class_name Prop
extends StaticBody2D
## Objeto decorativo con colisión (farol, banco, cajón). Origen = pies del objeto.

@export var prop_texture: Texture2D
@export var collider_size: Vector2 = Vector2(12, 6)
## Plano sobre el piso (una alfombra): se ordena por su borde de arriba, así queda debajo de quien la pisa.
@export var flat: bool = false
## Cuadros de animación en tira horizontal (el fuego de una chimenea, el péndulo de un reloj) y su velocidad.
@export var frames: int = 1
@export var fps: float = 6.0
## Px que se levanta el dibujo sin mover la base (lo que se apoya sobre un mostrador).
@export var raise: float = 0.0
## Sombrita en el piso al pie (false para lo que cuelga de una pared: un cuadro, una estación del vía crucis).
@export var shadow: bool = true

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
}


func _ready() -> void:
	_sprite.texture = prop_texture
	_sprite.position = Vector2(0, -prop_texture.get_height() / 2.0 - raise)
	_sprite.hframes = maxi(frames, 1)
	set_process(frames > 1)
	if flat:
		position.y -= prop_texture.get_height()
		_sprite.position.y += prop_texture.get_height()
	# La forma viene compartida desde la escena: cada objeto necesita la suya, si no todos quedan del tamaño del último
	# que se cargó (la fuente se atravesaba con la base de un árbol).
	_shape.shape = _shape.shape.duplicate()
	(_shape.shape as RectangleShape2D).size = collider_size
	_shape.position = Vector2(0, -collider_size.y / 2.0)
	_shape.disabled = collider_size == Vector2.ZERO   # [0, 0] en world.json: se camina por encima (hojas de un portón)
	if collider_size.y <= 12.0 and not flat and shadow:   # los muebles con base grande (cama) ya apoyan en el piso
		var w: int = clampi(roundi(maxf(collider_size.x + 4.0, prop_texture.get_width() / float(maxi(frames, 1)) * 0.7)), 8, 56)
		PixelLight.add_blob(self, Vector2i(w, clampi(w / 3, 3, 10)))
	for light: Array in LIGHTS.get(prop_texture.resource_path.get_file().get_basename(), []):
		PixelLight.add_halo(self, light[0], light[1], light[2], light[3], light[4], light[5])


func _process(_delta: float) -> void:
	# Cada objeto con su fase (por posición): dos chimeneas no laten juntas.
	var phase: float = fposmod(position.x * 0.37 + position.y * 0.11, 1.0)
	_sprite.frame = int(Time.get_ticks_msec() / 1000.0 * fps + phase * frames) % frames


## Rectángulo (en coordenadas de la zona) que ocupa en el piso; lo usa la navegación de los NPCs.
func footprint() -> Rect2:
	if collider_size == Vector2.ZERO:
		return Rect2()
	return Rect2(position + Vector2(-collider_size.x / 2.0, -collider_size.y), collider_size)
