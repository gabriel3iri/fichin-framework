extends Node
## Opciones del jugador (canon 09 §11 y docs/technical/ui_menu_spec.md). Se guardan en
## user://settings.cfg y se aplican al instante. Crea los buses de audio Music, SFX y Ambient.

signal changed(key: String)

const PATH: String = "user://settings.cfg"
const LANGUAGES: Array[String] = ["es", "en", "de"]
const TEXT_SPEEDS: Array[float] = [35.0, 70.0, 140.0, 100000.0]    # caracteres por segundo: lento / normal / rápido / instantáneo
const TIME_SCALES: Array[float] = [0.667, 1.0, 1.333]              # 40x / 60x / 80x (canon 09 §11)
const DEFAULTS: Dictionary = {
	"master": 0.8, "music": 0.7, "sfx": 0.8, "ambient": 0.6,
	"fullscreen": false, "vsync": true, "language": "es",
	"text_speed": 1, "tutorials": true, "time_scale": 1, "debug_name_tags": false, "camera_zoom": 1, "seen_journal_hint": false,
}

## Ayudas de depuración que valen solo mientras dura la sesión: no se guardan (si no, un atajo apretado sin querer
## queda prendido para siempre, como los nombres de todos con N).
const SESSION_ONLY: Array[String] = ["debug_name_tags"]

var values: Dictionary = DEFAULTS.duplicate()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus_name in ["Music", "SFX", "Ambient"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var idx: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
	_load()
	for key: String in values:
		_apply(key)


func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	values[key] = value
	_apply(key)
	_save()
	changed.emit(key)


func text_chars_per_second() -> float:
	return TEXT_SPEEDS[clampi(int(get_value("text_speed")), 0, TEXT_SPEEDS.size() - 1)]


func _apply(key: String) -> void:
	match key:
		"master": _set_bus("Master", get_value("master"))
		"music": _set_bus("Music", get_value("music"))
		"sfx": _set_bus("SFX", get_value("sfx"))
		"ambient": _set_bus("Ambient", get_value("ambient"))
		"fullscreen":
			var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if get_value("fullscreen") else DisplayServer.WINDOW_MODE_WINDOWED
			DisplayServer.window_set_mode(mode)
		"vsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if get_value("vsync") else DisplayServer.VSYNC_DISABLED)
		"language": TranslationServer.set_locale(str(get_value("language")))
		"time_scale": TimeManager.time_scale = TIME_SCALES[clampi(int(get_value("time_scale")), 0, TIME_SCALES.size() - 1)]


func _set_bus(bus_name: String, linear: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
		AudioServer.set_bus_mute(idx, linear <= 0.001)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for key: String in DEFAULTS:
		if key not in SESSION_ONLY:
			values[key] = cfg.get_value("settings", key, DEFAULTS[key])


func _save() -> void:
	var cfg := ConfigFile.new()
	for key: String in values:
		if key not in SESSION_ONLY:
			cfg.set_value("settings", key, values[key])
	cfg.save(PATH)
