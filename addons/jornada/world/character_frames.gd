class_name CharacterFrames
extends RefCounted
## Construye los SpriteFrames de un personaje a partir de su hoja (tools/make_pixel_art.py):
## 15 cuadros de 16x32 = 3 vistas (down, up, side) x [idle, 4 de caminata].
## La vista "side" mira a la derecha; para ir a la izquierda se usa flip_h.
## Si la hoja trae 27 cuadros, los 12 últimos son la carrera: 4 por vista, mismo orden. Con 45 (el protagonista)
## siguen las diagonales de tres cuartos "ddown" (abajo-derecha) y "dup" (arriba-derecha): 5 de caminata cada una y
## después 4 de carrera cada una; a la izquierda, con flip_h.

const FRAME_SIZE: Vector2i = Vector2i(16, 32)
const FRAMES_PER_VIEW: int = 5
const VIEWS: Array[String] = ["down", "up", "side"]
## Un ciclo de 4 cuadros = dos pasos = ~24 px de recorrido; a 8 cuadros/s eso son 48 px/s.
## Se usa para ajustar speed_scale a la velocidad real y que los pies no patinen.
const WALK_FPS: float = 8.0
const WALK_REFERENCE_SPEED: float = 48.0
## Carrera: 4 cuadros = dos zancadas de ~20 px; a 12 cuadros/s acompaña los 120 px/s del jugador corriendo.
const RUN_FRAMES: int = 4
const RUN_FPS: float = 12.0
const RUN_REFERENCE_SPEED: float = 120.0
const DIAG_VIEWS: Array[String] = ["ddown", "dup"]


static func build(sheet: Texture2D) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	for v in VIEWS.size():
		var view: String = VIEWS[v]
		var idle := StringName("idle_" + view)
		var walk := StringName("walk_" + view)
		frames.add_animation(idle)
		frames.set_animation_loop(idle, true)
		frames.set_animation_speed(idle, 1.0)
		frames.add_frame(idle, _cell(sheet, v * FRAMES_PER_VIEW))
		frames.add_animation(walk)
		frames.set_animation_loop(walk, true)
		frames.set_animation_speed(walk, WALK_FPS)
		for i in range(1, FRAMES_PER_VIEW):
			frames.add_frame(walk, _cell(sheet, v * FRAMES_PER_VIEW + i))
		if sheet.get_width() >= FRAME_SIZE.x * (VIEWS.size() * (FRAMES_PER_VIEW + RUN_FRAMES)):
			var run := StringName("run_" + view)
			frames.add_animation(run)
			frames.set_animation_loop(run, true)
			frames.set_animation_speed(run, RUN_FPS)
			for i in RUN_FRAMES:
				frames.add_frame(run, _cell(sheet, VIEWS.size() * FRAMES_PER_VIEW + v * RUN_FRAMES + i))
	var diag_from: int = VIEWS.size() * (FRAMES_PER_VIEW + RUN_FRAMES)
	if sheet.get_width() >= FRAME_SIZE.x * (diag_from + DIAG_VIEWS.size() * (FRAMES_PER_VIEW + RUN_FRAMES)):
		for d in DIAG_VIEWS.size():
			var view: String = DIAG_VIEWS[d]
			var idle := StringName("idle_" + view)
			var walk := StringName("walk_" + view)
			var run := StringName("run_" + view)
			frames.add_animation(idle)
			frames.add_frame(idle, _cell(sheet, diag_from + d * FRAMES_PER_VIEW))
			frames.add_animation(walk)
			frames.set_animation_speed(walk, WALK_FPS)
			for i in range(1, FRAMES_PER_VIEW):
				frames.add_frame(walk, _cell(sheet, diag_from + d * FRAMES_PER_VIEW + i))
			frames.add_animation(run)
			frames.set_animation_speed(run, RUN_FPS)
			for i in RUN_FRAMES:
				frames.add_frame(run, _cell(sheet, diag_from + DIAG_VIEWS.size() * FRAMES_PER_VIEW + d * RUN_FRAMES + i))
	return frames


static func _cell(sheet: Texture2D, index: int) -> AtlasTexture:
	var cell := AtlasTexture.new()
	cell.atlas = sheet
	cell.region = Rect2(index * FRAME_SIZE.x, 0, FRAME_SIZE.x, FRAME_SIZE.y)
	return cell


## Vista que corresponde a una dirección: "side" (con flip si va a la izquierda), "up" o "down"; con `diagonals`,
## también "ddown" / "dup" cuando la dirección es oblicua.
static func view_for(facing: Vector2, diagonals: bool = false) -> String:
	if diagonals and absf(facing.x) > 0.38 * facing.length() and absf(facing.y) > 0.38 * facing.length():
		return "dup" if facing.y < 0.0 else "ddown"
	if absf(facing.x) > absf(facing.y):
		return "side"
	return "up" if facing.y < 0.0 else "down"


## Aplica animación y orientación a un AnimatedSprite2D.
## `speed` en px/s (0 = quieto). Ajusta speed_scale para que el paso acompañe el desplazamiento.
## `running`: usa la carrera si la hoja la tiene (si no, camina más rápido).
static func apply(sprite: AnimatedSprite2D, facing: Vector2, speed: float, running: bool = false) -> void:
	var view: String = view_for(facing, sprite.sprite_frames.has_animation(&"idle_ddown"))
	sprite.flip_h = view in ["side", "ddown", "dup"] and facing.x < 0.0
	var anim := StringName(("walk_" if speed > 0.5 else "idle_") + view)
	var reference: float = WALK_REFERENCE_SPEED
	if running and speed > 0.5 and sprite.sprite_frames.has_animation(StringName("run_" + view)):
		anim = StringName("run_" + view)
		reference = RUN_REFERENCE_SPEED
	if sprite.animation != anim:
		sprite.play(anim)
	sprite.speed_scale = speed / reference if speed > 0.5 else 1.0
