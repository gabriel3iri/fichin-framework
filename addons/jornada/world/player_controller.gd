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
## Sentado en un asiento (Seat): no camina; cualquier tecla de movimiento lo levanta y vuelve adonde estaba parado.
var seated: bool = false
## El asiento donde está sentado (Seat): E llama desde ahí al que atiende.
var seat: Node = null
## Cuánto se corre el dibujo al sentarse (cuadro de sentado de CharacterFrames; negativo lo sube al asiento).
const SIT_DROP: float = -4.0
var _seat_px: Vector2 = Vector2.ZERO
## Lo que lleva en la mano (una jarra en el bar): un dibujo chico que sigue a la mano según hacia dónde mira.
var _held: Sprite2D
const HAND_DOWN: Vector2 = Vector2(-5, -11)
const HAND_SIDE: Vector2 = Vector2(5, -11)
var _stand_px: Vector2 = Vector2.ZERO

## Todo lo interactuable al alcance; se resalta (aviso [E]) y se activa solo el más cercano.
var _candidates: Array[Node] = []
var _interactable: Node = null
var _run_seconds: float = 0.0
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


## Pensamiento sobre la cabeza, en un globo de pensamiento (nube azulada con burbujitas; ui/speech_bubbles.gd): orienta
## al jugador sin cartel de tutorial. Se acomoda antes que el barullo, que no lo tapa.
func think(text: String, seconds: float = 4.0) -> void:
	if ChatterSystem.bubbles != null:
		ChatterSystem.bubbles.say(self, Vector2(0.0, -33.0), text, seconds, &"thought")


## Lo que está pensando ahora (vacío si nada).
func thought_text() -> String:
	return ChatterSystem.bubbles.text_of(self) if ChatterSystem.bubbles != null else ""


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
	elif seated and is_instance_valid(seat) and seat.has_method("call_service"):
		seat.call_service()   # sentado en el bar: llama al tabernero sin levantarse
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


## Le pone algo en la mano (null lo saca). De espaldas no se ve: lo tapa el cuerpo.
func hold(texture: Texture2D) -> void:
	if texture == null:
		if _held != null:
			_held.queue_free()
			_held = null
		return
	if _held == null:
		_held = Sprite2D.new()
		_held.centered = true
		add_child(_held)
	_held.texture = texture
	_place_held()


func is_holding() -> bool:
	return _held != null


func _place_held() -> void:
	if _held == null:
		return
	var view: String = CharacterFrames.view_for(facing)
	_held.visible = view != "up"
	var hand: Vector2 = HAND_SIDE if view == "side" else HAND_DOWN
	if view == "side" and facing.x < 0.0:
		hand.x = -hand.x
	if seated:
		hand.y += SIT_DROP + 5.0   # el cuadro de sentado baja el cuerpo 5 px (pixel/sit.py) y el dibujo sube SIT_DROP
	_held.position = hand
	_held.z_index = 1


func sit(at: Vector2, face: Vector2) -> void:
	if seated:
		return
	seated = true
	_stand_px = global_position
	_seat_px = at
	global_position = at
	facing = face
	direction_changed.emit(facing)
	_sprite.position.y += SIT_DROP
	CharacterFrames.apply(_sprite, facing, 0.0, false, true)
	if is_instance_valid(_interactable):
		_interactable.set_highlight(false)
	_interactable = null


func stand() -> void:
	if not seated:
		return
	seated = false
	seat = null
	_sprite.position.y -= SIT_DROP
	if global_position == _seat_px:   # si otro lo llevó a otro lado (un traslado), queda donde lo dejaron
		global_position = _stand_px


func _physics_process(delta: float) -> void:
	if seated:
		if global_position != _seat_px:
			stand()   # lo movió otro sistema (fundido, traslado): ya no está en el banco
		elif can_move and not DialogueManager.is_active and Input.get_vector("move_left", "move_right", "move_up", "move_down") != Vector2.ZERO:
			stand()
		else:
			Stamina.step(delta, false, false)   # sentado descansa
			return
	_update_interactable()
	var input_dir: Vector2 = Vector2.ZERO
	if can_move and not DialogueManager.is_active:   # mientras alguien le habla no se va, venga de donde venga el control
		input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var moving: bool = input_dir != Vector2.ZERO
	var running: bool = moving and Input.is_action_pressed("run") and Stamina.can_run()   # sin energía no corre
	var speed: float = run_speed if running else walk_speed * Stamina.walk_factor()
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
	Stamina.step(delta, moving, running)
	_track_running(delta, running)

	if input_dir != Vector2.ZERO:
		# En diagonal mira en diagonal (el protagonista tiene vistas de tres cuartos, ver CharacterFrames).
		var new_facing: Vector2 = input_dir
		if new_facing != facing:
			facing = new_facing
			direction_changed.emit(facing)
	# Se anima con el desplazamiento real: contra una pared la caminata se detiene.
	CharacterFrames.apply(_sprite, facing, moved.length() / delta, running)


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
	CharacterFrames.apply(_sprite, facing, 0.0, false, seated)


## La cámara va pegada al jugador en cada cuadro dibujado. El jugador no se interpola (ver _ready): si la cámara y el
## sprite se calculaban y redondeaban a píxel por separado, el personaje iba y venía 1-2 px respecto de la pantalla
## (el temblor que se veía al caminar y, sobre todo, al chocar o resbalar contra una pared).
func _process(_delta: float) -> void:
	_place_held()
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
	CharacterFrames.apply(_sprite, facing, 0.0, false, seated)
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
