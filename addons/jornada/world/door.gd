class_name Door
extends Area2D
## Puerta entre zonas. E la cruza (0 minutos de juego, fundido de 0,3 s).

@export var target_zone: String = ""
## Cartelito sobre el marco (número de habitación); "" = sin cartel. sign_y: altura de su centro.
@export var sign_text: String = ""
@export var sign_y: float = -42.0

## Dígitos de 3×5 px para el cartel (fila por fila, de arriba abajo).
const DIGITS: Dictionary = {
	"0": ["111", "101", "101", "101", "111"], "1": ["010", "110", "010", "010", "111"],
	"2": ["111", "001", "111", "100", "111"], "3": ["111", "001", "011", "001", "111"],
	"4": ["101", "101", "111", "001", "001"], "5": ["111", "100", "111", "001", "111"],
	"6": ["111", "100", "111", "101", "111"], "7": ["111", "001", "010", "010", "010"],
	"8": ["111", "101", "111", "101", "111"], "9": ["111", "101", "111", "001", "111"],
}
const SIGN_PLATE: Color = Color("#B08A3E")
const SIGN_EDGE: Color = Color("#5A4220")
const SIGN_INK: Color = Color("#2A1E10")

@onready var _prompt: InteractPrompt = $Prompt


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func interact() -> void:
	# Habitaciones ajenas (data/private_rooms.json): hay que golpear o forzar la cerradura.
	var private_rule: Dictionary = PrivateRooms.rule_for(ZoneManager.current_zone, target_zone)
	if not private_rule.is_empty():
		PrivateRooms.interact(self, private_rule)
		return
	enter()


## Cruza la puerta (si no hay una cerradura de por medio, data/locks.json).
func enter() -> void:
	var closed: Array = DoorLocks.closed_message(ZoneManager.current_zone, target_zone)
	if not closed.is_empty():
		AudioManager.play_sfx("door_close", -8.0)
		Toasts.show_key(closed[0], closed[1])
		return
	AudioManager.play_sfx("door_open", -4.0)
	ZoneManager.change_zone(target_zone)


func set_highlight(on: bool) -> void:
	_prompt.set_active(on)


func _on_body_entered(body: Node2D) -> void:
	if body is PlayerController:
		(body as PlayerController).set_interactable(self)


func _on_body_exited(body: Node2D) -> void:
	if body is PlayerController:
		(body as PlayerController).clear_interactable(self)



## Placa de latón con el número, en píxeles enteros (como el resto del mundo).
func _draw() -> void:
	if sign_text == "":
		return
	var width: int = sign_text.length() * 4 + 3
	var origin := Vector2(-floorf(width / 2.0), sign_y - 4.0)
	draw_rect(Rect2(origin, Vector2(width, 9)), SIGN_EDGE)
	draw_rect(Rect2(origin + Vector2(1, 1), Vector2(width - 2, 7)), SIGN_PLATE)
	for i in sign_text.length():
		var rows: Array = DIGITS.get(sign_text[i], [])
		for y in rows.size():
			for x in 3:
				if rows[y][x] == "1":
					draw_rect(Rect2(origin + Vector2(2 + i * 4 + x, 2 + y), Vector2.ONE), SIGN_INK)
