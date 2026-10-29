extends Node
## Billetera del personaje (data/economy.json). Las liras del día: se gastan comprando (opciones de diálogo con "cost": N)
## y entran por el viático que da quien reparte el trabajo y por cada tarea terminada.
## Sin ese archivo el juego no tiene dinero: `enabled` es falso, nada cuesta y el HUD no muestra el contador (el framework es opcional).
##
##   - Las opciones de diálogo con "cost": N solo aparecen si alcanza la plata (DialogueManager) y descuentan al elegirlas.
##   - El viático (`viatico`) se acredita una vez por jornada, cuando se gana `viatico_flag` (la orden de trabajo).
##   - Cada tarea de trabajo terminada paga `pay_per_task` (WorkManager).
##   - Se reinicia a `start` al empezar cada jornada: todo recurso es del día, solo el saber persiste. Se guarda con F5/F9.

signal changed(value: float, max_value: float)

const PATH: String = "res://data/economy.json"

var enabled: bool = false
var value: float = 0.0

var _cfg: Dictionary = {}
var _loaded: Variant = null            # lo leído del guardado; se aplica cuando la carga rápida termina


func _ready() -> void:
	_cfg = GameConfig.read_data(PATH)
	if _cfg.is_empty():
		return
	enabled = true
	value = float(_cfg.get("start", 0))
	LoopManager.loop_started.connect(func(_n: int) -> void: reset())
	LoopManager.game_reset.connect(reset)
	var viatico_flag: String = _cfg.get("viatico_flag", "")
	if viatico_flag != "":
		LoopManager.knowledge_gained.connect(func(flag: String) -> void:
			if flag == viatico_flag:
				credit(float(_cfg.get("viatico", 0))))
	SaveManager.register_section("money", func() -> Variant: return value, func(saved: Variant) -> void: _loaded = saved)
	SaveManager.quick_state_applied.connect(_on_quick_state_applied)


## Pago por una tarea de trabajo terminada (lo llama WorkManager). 0 si no hay economía.
func pay_per_task() -> float:
	return float(_cfg.get("pay_per_task", 0)) if enabled else 0.0


## ¿Alcanza para gastar `amount`?
func can_afford(amount: float) -> bool:
	return not enabled or value >= amount


func credit(amount: float) -> void:
	if not enabled:
		return
	var before: float = value
	value = maxf(0.0, value + amount)
	if value != before:
		changed.emit(value, value)


func debit(amount: float) -> void:
	credit(-amount)


func set_value(new_value: float) -> void:
	value = maxf(0.0, new_value)
	changed.emit(value, value)


func reset() -> void:
	value = float(_cfg.get("start", 0)) if enabled else 0.0
	changed.emit(value, value)


func _on_quick_state_applied() -> void:
	if _loaded == null:
		return
	value = maxf(0.0, float(_loaded))
	_loaded = null
	changed.emit(value, value)
