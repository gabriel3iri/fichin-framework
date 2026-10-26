class_name Prop
extends StaticBody2D
## Objeto decorativo con colisión (farol, banco, cajón). Origen = pies del objeto.

@export var prop_texture: Texture2D
@export var collider_size: Vector2 = Vector2(12, 6)

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _shape: CollisionShape2D = $CollisionShape2D


## Fuentes de luz por sprite: [posición, radio del halo, aplastado, encendido mínimo, alcance, fuerza].
## El farol suma un charco en el piso; el alcance ilumina a personajes y objetos cercanos (DayLight).
const LIGHTS: Dictionary = {
	"lamp": [[Vector2(0, -39), 28, 1.0, 0.0, 84.0, 1.0], [Vector2(0, -1), 22, 0.35, 0.0, 0.0, 0.0]],
	"stove": [[Vector2(0, -13), 12, 1.0, 0.5, 40.0, 0.6]],
	"forge": [[Vector2(0, -11), 24, 1.0, 0.7, 72.0, 0.9]],
	"altar": [[Vector2(-8, -30), 7, 1.0, 0.6, 30.0, 0.4], [Vector2(9, -30), 7, 1.0, 0.6, 30.0, 0.4]],
}


func _ready() -> void:
	_sprite.texture = prop_texture
	_sprite.position = Vector2(0, -prop_texture.get_height() / 2.0)
	# La forma viene compartida desde la escena: cada objeto necesita la suya, si no todos quedan del tamaño del último
	# que se cargó (la fuente se atravesaba con la base de un árbol).
	_shape.shape = _shape.shape.duplicate()
	(_shape.shape as RectangleShape2D).size = collider_size
	_shape.position = Vector2(0, -collider_size.y / 2.0)
	if collider_size.y <= 12.0:   # los muebles con base grande (cama) ya apoyan en el piso
		var w: int = clampi(roundi(maxf(collider_size.x + 4.0, prop_texture.get_width() * 0.7)), 8, 56)
		PixelLight.add_blob(self, Vector2i(w, clampi(w / 3, 3, 10)))
	for light: Array in LIGHTS.get(prop_texture.resource_path.get_file().get_basename(), []):
		PixelLight.add_halo(self, light[0], light[1], light[2], light[3], light[4], light[5])


## Rectángulo (en coordenadas de la zona) que ocupa en el piso; lo usa la navegación de los NPCs.
func footprint() -> Rect2:
	return Rect2(position + Vector2(-collider_size.x / 2.0, -collider_size.y), collider_size)
