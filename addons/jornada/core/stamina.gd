extends Node
## Energía del personaje (data/energy.json). Correr la gasta; caminar y estar quieto la recuperan; comer la llena.
## Sin ese archivo el juego no tiene energía: `enabled` es falso y correr no cuesta nada (el framework es opcional).
##
##   - Con la barra en 0 queda «sin aliento»: camina más lento unos segundos y no puede correr hasta recuperar `run_again_at`.
##   - Los alimentos de `foods` se registran como efectos de diálogo `eat_<id>` (WorldEffects): un diálogo u objeto con
##     "effects": ["eat_<id>"] llena `energy` puntos. Las opciones y entradas pueden pedir "energy_below": N para aparecer solo
##     cuando falta energía (DialogueManager), así no se ofrece comida a quien no la necesita.
##   - Se reinicia al empezar cada jornada. Se guarda con el guardado rápido (F5/F9).
## Quien mueve al personaje (PlayerController) llama a `step` en cada cuadro de física y respeta `can_run`/`walk_factor`.

signal changed(value: float, max_value: float)
signal exhausted
signal recovered

const PATH: String = "res://data/energy.json"

var enabled: bool = false
var max_value: float = 100.0
var value: float = 100.0

var _cfg: Dictionary = {}
var _exhausted: bool = false
var _breath_left: float = 0.0          # segundos de caminata lenta que quedan tras quedarse en 0
var _last_emitted: float = -1.0
var _loaded: Variant = null            # lo leído del guardado; se aplica cuando la carga rápida termina


func _ready() -> void:
	_cfg = GameConfig.read_data(PATH)
	if _cfg.is_empty():
		return
	enabled = true
	max_value = float(_cfg.get("max", 100))
	value = float(_cfg.get("start", max_value))
	for id: String in _cfg.get("foods", {}):
		WorldEffects.register("eat_" + id, eat.bind(id))
	LoopManager.loop_started.connect(func(_n: int) -> void: reset())
	LoopManager.game_reset.connect(reset)
	SaveManager.register_section("energy", func() -> Variant: return value, func(saved: Variant) -> void: _loaded = saved)
	SaveManager.quick_state_applied.connect(_on_quick_state_applied)


## ¿Puede correr ahora? (falso mientras está sin aliento)
func can_run() -> bool:
	return not enabled or not _exhausted


## Multiplicador de la velocidad de caminata: más lenta unos segundos después de quedarse sin energía.
func walk_factor() -> float:
	if enabled and _breath_left > 0.0:
		return float(_cfg.get("exhausted", {}).get("walk_factor", 0.75))
	return 1.0


func is_exhausted() -> bool:
	return enabled and _exhausted


## Un cuadro de física: gasta si corre, recupera si camina o está quieto.
func step(delta: float, moving: bool, running: bool) -> void:
	if not enabled:
		return
	var before: float = value
	if running:
		value -= float(_cfg.get("run_cost_per_second", 5.0)) * delta
	elif moving:
		value += float(_cfg.get("walk_regen_per_second", 1.0)) * delta
	else:
		value += float(_cfg.get("rest_regen_per_second", 3.0)) * delta
	if _breath_left > 0.0:
		_breath_left = maxf(0.0, _breath_left - delta)
	_settle(before)


func restore(amount: float) -> void:
	if not enabled:
		return
	var before: float = value
	value += amount
	_settle(before)


## Come o bebe `food_id` (de data/energy.json "foods").
func eat(food_id: String) -> void:
	restore(float(_cfg.get("foods", {}).get(food_id, {}).get("energy", 0)))


func set_value(new_value: float) -> void:
	var before: float = value
	value = new_value
	_settle(before)


func reset() -> void:
	value = float(_cfg.get("start", max_value)) if enabled else max_value
	_exhausted = false
	_breath_left = 0.0
	_last_emitted = -1.0
	changed.emit(value, max_value)


func _settle(before: float) -> void:
	value = clampf(value, 0.0, max_value)
	if value <= 0.0 and before > 0.0 and not _exhausted:
		_exhausted = true
		_breath_left = float(_cfg.get("exhausted", {}).get("seconds", 6.0))
		exhausted.emit()
		Toasts.show_key("toast_out_of_breath")
	if _exhausted and value >= float(_cfg.get("exhausted", {}).get("run_again_at", 20.0)):
		_exhausted = false
		recovered.emit()
	if absf(value - _last_emitted) >= 0.25 or value == 0.0 or value == max_value:
		if value != _last_emitted:
			_last_emitted = value
			changed.emit(value, max_value)


func _on_quick_state_applied() -> void:
	if _loaded == null:
		return
	value = clampf(float(_loaded), 0.0, max_value)
	_exhausted = value <= 0.0
	_breath_left = 0.0
	_loaded = null
	_last_emitted = -1.0
	changed.emit(value, max_value)
