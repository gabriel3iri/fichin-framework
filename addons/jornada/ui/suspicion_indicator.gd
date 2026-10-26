class_name SuspicionIndicator
extends Control
## Indicador de sospecha (canon 09 §4 y §8): un ojo y cuatro marcas que se encienden por umbral.
## Sin números. Permanece oculto mientras la sospecha no llega al primer umbral (30): hasta ahí
## el jugador no tiene motivo para saber que el pueblo lo está mirando.

const TIER_THRESHOLDS: Array[int] = [30, 45, 60, 80]
const TIER_COLORS: Array[Color] = [
	Color(1.0, 0.804, 0.612),   # amarillo tenue
	Color(0.878, 0.502, 0.235), # naranja
	Color(0.902, 0.224, 0.275), # rojo alerta
	Color(0.902, 0.224, 0.275),
]
const PIP_OFF: Color = Color(0.231, 0.231, 0.2)

@onready var _eye: TextureRect = $Eye
@onready var _pips: HBoxContainer = $Pips

var _tier: int = 0
var _fade: Tween


func _ready() -> void:
	modulate.a = 0.0
	GameManager.suspicion_changed.connect(_on_suspicion_changed)
	_on_suspicion_changed(GameManager.suspicion)


func _exit_tree() -> void:
	GameManager.suspicion_changed.disconnect(_on_suspicion_changed)


func _process(_delta: float) -> void:
	if _tier >= 4:  # a partir de 80 el ojo parpadea
		_eye.modulate.a = 1.0 if int(Time.get_ticks_msec() / 250) % 2 == 0 else 0.4
	else:
		_eye.modulate.a = 1.0


func _on_suspicion_changed(value: int) -> void:
	var tier: int = 0
	for threshold in TIER_THRESHOLDS:
		if value >= threshold:
			tier += 1
	var shown_before: bool = _tier > 0
	_tier = tier
	var color: Color = TIER_COLORS[maxi(tier, 1) - 1]
	_eye.self_modulate = color
	for i in _pips.get_child_count():
		(_pips.get_child(i) as ColorRect).color = color if i < tier else PIP_OFF
	if (tier > 0) != shown_before:
		if _fade != null:
			_fade.kill()
		_fade = create_tween()
		_fade.tween_property(self, "modulate:a", 1.0 if tier > 0 else 0.0, 0.4)
