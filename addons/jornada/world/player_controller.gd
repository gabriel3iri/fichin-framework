class_name PlayerController
extends CharacterBody2D
## Movimiento top-down en 4/8 direcciones. Origen del nodo = pies del personaje.

signal direction_changed(direction: Vector2)

## Canon 09 §3: 5 unidades por segundo real (1 unidad = 1 tile = 16 px). Correr cuesta sospecha.
@export var walk_speed: float = 80.0
## Por debajo de esto (px por cuadro de física) un eje no se mueve: es el empuje de la colisión, no un paso.
const MIN_STEP: float = 0.25
@export var run_speed: float = 120.0
## Hoja de 15 cuadros (ver CharacterFrames).
@export var sheet: Texture2D

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D

var facing: Vector2 = Vector2.DOWN
var can_move: bool = true

## Todo lo interactuable al alcance; se resalta (aviso [E]) y se activa solo el más cercano.
var _candidates: Array[Node] = []
var _interactable: Node = null
var _run_seconds: float = 0.0
var _thought: Label
var _thought_tween: Tween
@onready var _camera: PlayerCamera = get_node_or_null("Camera2D") as PlayerCamera


func _ready() -> void:
	# Se dibuja donde está (sin interpolar entre pasos de física): la cámara lo sigue exacto y nada tiembla.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_sprite.sprite_frames = CharacterFrames.build(sheet)
	_sprite.play(&"idle_down")
	PixelLight.add_blob(self, Vector2i(12, 4))
	_sprite.frame_changed.connect(_on_frame_changed)
	DialogueManager.dialogue_started.connect(_on_dialogue_started)
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)
	LoopManager.knowledge_gained.connect(_on_knowledge_gained)
	# Cada loop recarga la escena: el técnico que aparece a las 06:00 es el que despierta (el aviso de loop_started
	# llega antes de recargar, al jugador anterior).
	_wake_up.call_deferred()


func _exit_tree() -> void:
	DialogueManager.dialogue_started.disconnect(_on_dialogue_started)
	DialogueManager.dialogue_ended.disconnect(_on_dialogue_ended)
	LoopManager.knowledge_gained.disconnect(_on_knowledge_gained)


## Pensamiento sobre la cabeza (en cursiva de color tenue): orienta al jugador sin cartel de tutorial.
func think(text: String, seconds: float = 4.0) -> void:
	if _thought == null:
		_thought = Label.new()
		_thought.custom_minimum_size = Vector2(190, 0)
		_thought.size = Vector2(190, 12)
		_thought.position = Vector2(-95, -60)
		_thought.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_thought.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		_thought.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_thought.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_thought.add_theme_color_override("font_color", UiStyle.DIM.lightened(0.25))
		_thought.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.05))
		_thought.add_theme_constant_override("outline_size", 4)
		_thought.z_index = 100
		_thought.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_thought)
	_thought.text = text
	_thought.modulate.a = 1.0
	if _thought_tween != null:
		_thought_tween.kill()
	_thought_tween = create_tween()
	_thought_tween.tween_interval(seconds)
	_thought_tween.tween_property(_thought, "modulate:a", 0.0, 0.5)


## Al despertar (data/game.json "thoughts"): una frase fija por jornada mientras dure "wake_first" y después una al
## azar de "wake_later" sin repetir la anterior. "journal_kept": la primera vez que se despierta con el diario lleno,
## desde la jornada "journal_kept_from" (en un loop, la sorpresa de que la libreta no se borró).
var _last_wake: String = ""


func _wake_up() -> void:
	if TimeManager.now_minutes() > GameConfig.day_start() + 2:
		return   # cargó una partida a mitad del día: no se despierta
	await get_tree().create_timer(1.6, false).timeout
	if LoopManager.next_wake_thought != "":
		think(tr(LoopManager.next_wake_thought), 5.5)
		LoopManager.next_wake_thought = ""
		return
	var thoughts: Dictionary = GameConfig.value("thoughts", {})
	var day: int = LoopManager.loop_number
	var kept: String = thoughts.get("journal_kept", "")
	if kept != "" and day >= int(thoughts.get("journal_kept_from", 3)) and JournalManager.has_journal() \
			and not JournalManager.journal_surprise_done:
		JournalManager.journal_surprise_done = true
		think(tr(kept), 5.5)
		return
	var first: Array = thoughts.get("wake_first", [])
	var later: Array = thoughts.get("wake_later", [])
	var key: String = ""
	if day <= first.size():
		key = first[day - 1]
	elif not later.is_empty():
		var options: Array = later.filter(func(k: String) -> bool: return k != _last_wake)
		key = options.pick_random() if not options.is_empty() else later[0]
	if key == "":
		return
	_last_wake = key
	think(tr(key), 5.0)


func _on_knowledge_gained(flag: String) -> void:
	var work_thought: String = GameConfig.value("thoughts", {}).get("work_order", "")
	if flag == GameConfig.flag("work_received") and LoopManager.loop_number == 1 and work_thought != "":
		think(tr(work_thought), 4.5)


## E: avanza el diálogo activo o interactúa con el objeto cercano.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	if DialogueManager.is_active:
		DialogueManager.advance()  # no hace nada si hay opciones: se eligen con 1-9
	elif is_instance_valid(_interactable):
		_interactable.interact()
	else:
		return
	get_viewport().set_input_as_handled()


func set_interactable(target: Node) -> void:
	if target not in _candidates:
		_candidates.append(target)


func clear_interactable(target: Node) -> void:
	_candidates.erase(target)
	if _interactable == target:
		_interactable = null
		if is_instance_valid(target):
			target.set_highlight(false)


func reset_interactable() -> void:
	_candidates.clear()
	_interactable = null


func _update_interactable() -> void:
	var best: Node = null
	var best_distance: float = INF
	for candidate in _candidates:
		if not is_instance_valid(candidate):
			continue
		if candidate.has_method("can_interact") and not candidate.can_interact():
			continue
		# Gana lo más cercano, y lo que está adelante cuenta como más cerca que lo que está a la espalda.
		var offset: Vector2 = candidate.global_position - global_position
		var distance: float = offset.length_squared() * (0.5 if offset.normalized().dot(facing) > 0.5 else 1.0)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	if best == _interactable:
		return
	if is_instance_valid(_interactable):
		_interactable.set_highlight(false)
	_interactable = best
	if best != null and can_move:
		best.set_highlight(true)


func _physics_process(delta: float) -> void:
	_update_interactable()
	var input_dir: Vector2 = Vector2.ZERO
	if can_move:
		input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var speed: float = run_speed if Input.is_action_pressed("run") else walk_speed
	velocity = input_dir * speed
	var before: Vector2 = global_position
	move_and_slide()
	# Contra una pared la física lo empuja y lo devuelve unas centésimas de píxel por cuadro: la cámara lo seguía y
	# temblaba. Un eje que se movió menos de un cuarto de píxel no se movió.
	var moved: Vector2 = global_position - before
	if absf(moved.x) < MIN_STEP:
		moved.x = 0.0
	if absf(moved.y) < MIN_STEP:
		moved.y = 0.0
	global_position = before + moved
	_track_running(delta, input_dir != Vector2.ZERO and speed == run_speed)

	if input_dir != Vector2.ZERO:
		# En diagonal mira en diagonal (el protagonista tiene vistas de tres cuartos, ver CharacterFrames).
		var new_facing: Vector2 = input_dir
		if new_facing != facing:
			facing = new_facing
			direction_changed.emit(facing)
	# Se anima con el desplazamiento real: contra una pared la caminata se detiene.
	CharacterFrames.apply(_sprite, facing, moved.length() / delta, speed == run_speed)


## Un paso en cada cuadro de contacto del ciclo (0 y 2), con el sonido del suelo que se pisa.
func _on_frame_changed() -> void:
	if can_move and (_sprite.animation.begins_with("walk") or _sprite.animation.begins_with("run")) and (_sprite.frame == 0 or _sprite.frame == 2):
		AudioManager.play_footstep(ZoneManager.surface_at(global_position))


## Canon 09 §2.2: correr en público sube 1 punto de sospecha cada 10 segundos.
func _track_running(delta: float, running: bool) -> void:
	if not running:
		_run_seconds = 0.0
		return
	_run_seconds += delta
	if _run_seconds >= 10.0:
		_run_seconds -= 10.0
		GameManager.add_suspicion(1)


## Gira al jugador hacia un punto (p. ej. el NPC con quien habla).
func face_towards(point: Vector2) -> void:
	var delta: Vector2 = point - global_position
	if delta == Vector2.ZERO:
		return
	facing = delta
	CharacterFrames.apply(_sprite, facing, 0.0)


## La cámara va pegada al jugador en cada cuadro dibujado. El jugador no se interpola (ver _ready): si la cámara y el
## sprite se calculaban y redondeaban a píxel por separado, el personaje iba y venía 1-2 px respecto de la pantalla
## (el temblor que se veía al caminar y, sobre todo, al chocar o resbalar contra una pared).
func _process(_delta: float) -> void:
	if _camera != null:
		_camera.follow(global_position)


## Cambio de zona o carga: la cámara va directo a la nueva posición.
func snap_camera() -> void:
	reset_physics_interpolation()
	if _camera != null:
		_camera.follow(global_position)
		_camera.reset_smoothing()
		_camera.force_update_scroll()


## Se queda quieto `seconds` segundos (atónito, sorprendido): no camina aunque se aprieten las flechas.
func freeze(seconds: float) -> void:
	can_move = false
	CharacterFrames.apply(_sprite, facing, 0.0)
	await get_tree().create_timer(seconds, false).timeout
	if not DialogueManager.is_active:
		can_move = true


func _on_dialogue_started(_npc_id: String) -> void:
	can_move = false
	if is_instance_valid(_interactable):
		_interactable.set_highlight(false)


func _on_dialogue_ended(_npc_id: String) -> void:
	can_move = true
	if is_instance_valid(_interactable):
		_interactable.set_highlight(true)
