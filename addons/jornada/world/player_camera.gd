class_name PlayerCamera
extends Camera2D
## Cámara del jugador. La mueve el jugador en cada cuadro dibujado (PlayerController._process), pegada a él: sin
## suavizado ni interpolación de física propia, así el personaje y el mundo se redondean a píxel juntos.
## No sale del mapa de la zona; si la zona es más chica que la pantalla (interiores), la centra. El límite lo hace
## esta clase (no los limit_* de Camera2D) para poder dejar la cámara SIEMPRE en un píxel entero de pantalla: con el
## zoom 1,5 (un píxel del juego = 1,5 de pantalla) el mapa podía quedar en medio píxel (origen 78,5) y el redondeo
## saltaba de un lado al otro: todo el cuarto temblaba un píxel. El acercamiento sale del ajuste "camera_zoom" (tecla Z).

const ZOOMS: Array[float] = [1.0, 1.5, 2.0]
## Límites "abiertos" para la Camera2D: el borde lo pone `follow`.
const NO_LIMIT: int = 10000000

## Dónde va respecto de los pies del jugador (el `position` de la escena: un poco más arriba, en el pecho).
var _offset: Vector2
## Lo que se puede ver de la zona (px del mundo).
var _area := Rect2()


func _ready() -> void:
	_offset = position
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	process_callback = Camera2D.CAMERA2D_PROCESS_IDLE
	position_smoothing_enabled = false
	limit_left = -NO_LIMIT
	limit_top = -NO_LIMIT
	limit_right = NO_LIMIT
	limit_bottom = NO_LIMIT
	ZoneManager.zone_changed.connect(_on_zone_changed)
	SettingsManager.changed.connect(_on_setting_changed)
	_apply_zoom()


## La lleva al jugador (sus pies en `feet`): sin salir del mapa y en un píxel entero de pantalla.
func follow(feet: Vector2) -> void:
	global_position = target_for(feet)


## Centro de la cámara para un jugador con los pies en `feet`.
func target_for(feet: Vector2) -> Vector2:
	var center: Vector2 = feet + _offset
	if _area.has_area():
		var screen: Vector2 = _screen_size()
		for axis in 2:
			if _area.size[axis] <= screen[axis]:
				center[axis] = _area.get_center()[axis]
			else:
				center[axis] = clampf(center[axis], _area.position[axis] + screen[axis] / 2.0,
						_area.end[axis] - screen[axis] / 2.0)
	# La esquina de la pantalla cae en un píxel entero: el origen del mundo en pantalla es entero y no hay redondeo
	# que pueda ir y venir. (La mitad de la pantalla, 320 x 180, ya es entera.)
	return (center * zoom).round() / zoom


func _screen_size() -> Vector2:
	return Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height")) / zoom


func _on_setting_changed(key: String) -> void:
	if key == "camera_zoom" and ZoneManager.zone_root != null:
		_on_zone_changed(ZoneManager.current_zone)


func _apply_zoom() -> void:
	var z: float = ZOOMS[clampi(int(SettingsManager.get_value("camera_zoom")), 0, ZOOMS.size() - 1)]
	zoom = Vector2(z, z)


func _exit_tree() -> void:
	ZoneManager.zone_changed.disconnect(_on_zone_changed)
	SettingsManager.changed.disconnect(_on_setting_changed)


func _on_zone_changed(_zone_id: String) -> void:
	var layer := ZoneManager.zone_root.get_node_or_null("Ground") as TileMapLayer
	if layer == null:
		return
	_apply_zoom()
	var rect: Rect2i = layer.get_used_rect()
	var tile: Vector2i = layer.tile_set.tile_size
	_area = Rect2(Vector2(rect.position * tile), Vector2(rect.size * tile))
	var inset: Array = ZoneManager.camera_inset(ZoneManager.current_zone)
	_area = _area.grow_individual(-inset[0], -inset[1], -inset[2], -inset[3])
	var player := get_parent() as Node2D
	if player != null:
		follow(player.global_position)
	reset_smoothing()
