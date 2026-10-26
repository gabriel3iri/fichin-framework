class_name Inspectable
extends Area2D
## Objeto o lugar examinable (placa, libro, registro, borde del tablero...). E reproduce
## data/dialogue/obj_<id>.json con el mismo motor que los NPCs: las condiciones (hora, flags),
## las evidencias que otorga y la sospecha que cuesta salen de ese archivo.
## Los genera tools/gen_inspectables.py (data/inspectables.json) y los coloca addons/jornada/tools/build_world.gd.
##
## - El aviso [E] solo aparece si ahora hay algo que decir (p. ej. la lista de pasajeros, desde las 17:00).
## - Un destello discreto marca los objetos que todavía pueden dar una evidencia que el jugador no tiene; el que da
##   el diario (GameConfig, rol has_journal) brilla más, para que en el segundo loop no pase de largo.

@export var object_id: String = ""
@export var gives: PackedStringArray = []
@export var prompt_y: float = -22.0
@export var sprite_texture: Texture2D
@export var sprite_lift: float = -10.0
## Si es verdadero, el objeto solo se ve mientras tiene algo que decir (la libreta del diario: en el primer loop no
## está y, una vez agarrada, desaparece de la mesa).
@export var only_when_available: bool = false

@onready var _prompt: InteractPrompt = $Prompt
@onready var _sprite: Sprite2D = $Sprite2D

var _highlighted: bool = false
var _news: bool = false
var _time: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 4
	_prompt.position = Vector2(0, prompt_y)
	if sprite_texture != null:
		_sprite.texture = sprite_texture
		_sprite.position = Vector2(0, sprite_lift - sprite_texture.get_height() / 2.0)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	TimeManager.minute_changed.connect(_refresh.unbind(2))
	LoopManager.knowledge_gained.connect(_refresh.unbind(1))
	DialogueManager.dialogue_ended.connect(_refresh.unbind(1))
	_refresh()


func _exit_tree() -> void:
	TimeManager.minute_changed.disconnect(_refresh.unbind(2))
	LoopManager.knowledge_gained.disconnect(_refresh.unbind(1))
	DialogueManager.dialogue_ended.disconnect(_refresh.unbind(1))


## Si ahora no tiene nada que decir, no le gana el [E] a una persona que esté al lado.
func can_interact() -> bool:
	return DialogueManager.can_start(object_id)


func interact() -> void:
	DialogueManager.start(object_id)


func set_highlight(on: bool) -> void:
	_highlighted = on
	_refresh()


func _refresh() -> void:
	var available: bool = DialogueManager.can_start(object_id)
	_prompt.set_active(_highlighted and available)
	if only_when_available:
		visible = available
		monitoring = available
	var pending: bool = false
	for flag in gives:
		if not LoopManager.has_knowledge(flag):
			pending = true
	_news = available and pending
	set_process(_news)
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


## Destello de 3 px que respira despacio, sobre el objeto.
func _draw() -> void:
	if not _news:
		return
	var phase: float = 0.5 + 0.5 * sin(_time * 3.0)
	var color := Color(1.0, 0.86, 0.55, 0.35 + 0.55 * phase)
	if GameConfig.flag("has_journal") in gives:
		_draw_strong_glint(phase, color)
		return
	var top: float = prompt_y + 4.0
	draw_rect(Rect2(-0.5, top - 1.0, 1.0, 3.0), color)
	draw_rect(Rect2(-1.5, top, 3.0, 1.0), color)


func _on_body_entered(body: Node2D) -> void:
	if body is PlayerController:
		(body as PlayerController).set_interactable(self)


func _on_body_exited(body: Node2D) -> void:
	if body is PlayerController:
		(body as PlayerController).clear_interactable(self)


## Brillo grande: un halo que respira sobre el objeto y una estrella de cuatro puntas que crece y se achica.
func _draw_strong_glint(phase: float, color: Color) -> void:
	var center := Vector2(0, sprite_lift - 2.0)
	draw_circle(center, 7.0 + 2.0 * phase, Color(1.0, 0.9, 0.6, 0.10 + 0.12 * phase))
	var star := Vector2(3, prompt_y + 6.0)
	var arm: float = 2.0 + roundf(2.0 * phase)
	draw_rect(Rect2(star.x - 0.5, star.y - arm, 1.0, arm * 2.0 + 1.0), color)
	draw_rect(Rect2(star.x - arm, star.y, arm * 2.0 + 1.0, 1.0), color)
	draw_rect(Rect2(star.x - 0.5, star.y, 1.0, 1.0), Color(1, 1, 1, 0.6 + 0.4 * phase))
