class_name WorkSpot
extends StaticBody2D
## Puesto de trabajo (panel, palanca, tablero...). E inicia la tarea de `task_id`.
## Origen = pies del objeto. Una vez hecha la tarea ya no muestra el aviso [E].

@export var task_id: String = ""
@export var prop_texture: Texture2D
@export var prompt_y: float = -36.0

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _area: Area2D = $InteractArea
@onready var _prompt: InteractPrompt = $Prompt

var _highlighted: bool = false


func _ready() -> void:
	_sprite.texture = prop_texture
	_sprite.position = Vector2(0, -prop_texture.get_height() / 2.0)
	_prompt.position = Vector2(0, prompt_y)
	PixelLight.add_blob(self, Vector2i(clampi(prop_texture.get_width() - 2, 10, 30), 4))
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)
	WorkManager.task_completed.connect(_refresh_prompt.unbind(1))
	WorkManager.progress_changed.connect(_refresh_prompt)


func _exit_tree() -> void:
	WorkManager.task_completed.disconnect(_refresh_prompt.unbind(1))
	WorkManager.progress_changed.disconnect(_refresh_prompt)


func interact() -> void:
	WorkManager.try_start(task_id)


func set_highlight(on: bool) -> void:
	_highlighted = on
	_refresh_prompt()


func _refresh_prompt() -> void:
	_prompt.set_active(_highlighted and not WorkManager.is_done(task_id))


func _on_body_entered(body: Node2D) -> void:
	if body is PlayerController:
		(body as PlayerController).set_interactable(self)


func _on_body_exited(body: Node2D) -> void:
	if body is PlayerController:
		(body as PlayerController).clear_interactable(self)


## Rectángulo (en coordenadas de la zona) que ocupa en el piso; lo usa la navegación de los NPCs.
func footprint() -> Rect2:
	return Rect2(position + Vector2(-6.0, -6.0), Vector2(12.0, 6.0))
