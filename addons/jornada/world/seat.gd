class_name Seat
extends Area2D
## Lugar para sentarse sobre un objeto (un banco de la iglesia). Lo pone Speeches al entrar a la zona, uno por cada
## puesto de los objetos de data/speeches.json "seats". E sienta al jugador mirando hacia `face`; moverse lo levanta.

const PROMPT_SCENE: PackedScene = preload("res://addons/jornada/scenes/interact_prompt.tscn")
const REACH: float = 14.0

var face: Vector2 = Vector2.UP
## Mira a una mesa (data/speeches.json "toward"); si no, a lo que tenga adelante (la barra).
var at_table: bool = false
var _prompt: InteractPrompt


func _ready() -> void:
	collision_layer = 0
	collision_mask = 4
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = REACH
	shape.shape = circle
	shape.position = Vector2(0, 8)   # se llega desde adelante del banco
	add_child(shape)
	_prompt = PROMPT_SCENE.instantiate()
	_prompt.position = Vector2(0, -26)
	add_child(_prompt)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func can_interact() -> bool:
	var player: PlayerController = ZoneManager.player
	return player != null and not player.seated and not is_taken()


## Ya hay alguien sentado (o parado) justo ahí.
func is_taken() -> bool:
	for node in get_tree().get_nodes_in_group("npc_actors"):
		if node is NpcActor and (node as NpcActor).visible and (node as NpcActor).global_position.distance_to(global_position) < 6.0:
			return true
	return false


func interact() -> void:
	ZoneManager.player.sit(global_position, face)
	ZoneManager.player.seat = self
	Speeches.serve(self)   # en la barra, el que atiende viene a tomarle el pedido


## Sentado, E llama al que atiende (si en esta zona hay alguien que atiende).
func call_service() -> void:
	Speeches.serve(self, true)


func set_highlight(on: bool) -> void:
	_prompt.set_active(on)


func _on_body_entered(body: Node2D) -> void:
	if body is PlayerController:
		(body as PlayerController).set_interactable(self)


func _on_body_exited(body: Node2D) -> void:
	if body is PlayerController:
		(body as PlayerController).clear_interactable(self)
