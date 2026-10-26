extends Node
## Eventos horarios del canon 02 que no dependen de dónde esté el jugador (data/events.json).
## Se disparan una vez por loop en cuanto el reloj pasa su hora, aunque el reloj haya saltado.

const EVENTS_PATH: String = "res://data/events.json"

var _events: Array = []
var _fired: Dictionary = {}
## Fuentes de sonido con lugar: nombre -> func() -> float (cuántos dB restar según dónde esté el jugador).
## Un evento con "source": "<nombre>" se oye más bajo cuanto más lejos. En Rabenholz, TrainSystem registra "train".
var _sources: Dictionary = {}


func register_sound_source(source_name: String, attenuation_db: Callable) -> void:
	_sources[source_name] = attenuation_db


func _ready() -> void:
	_events = GameConfig.read_data(EVENTS_PATH).get("events", [])
	TimeManager.minute_changed.connect(_on_minute_changed)
	LoopManager.loop_started.connect(func(_n: int) -> void: _fired.clear())


func _on_minute_changed(_hour: int, _minute: int) -> void:
	var now: int = TimeManager.now_minutes()
	for event: Dictionary in _events:
		var id: String = event["id"]
		if _fired.has(id) or now < TimeManager.parse_clock(event["time"]) \
				or not GameConfig.matches_day(event, LoopManager.loop_number):
			continue
		_fired[id] = true
		for flag: String in event.get("grants", []):
			LoopManager.gain_knowledge(flag)
		if event.has("sfx"):
			var db: float = float(event.get("sfx_db", -6.0))
			if _sources.has(event.get("source", "")):
				db += float((_sources[event["source"]] as Callable).call())
			AudioManager.play_sfx(event["sfx"], db)
		if event.has("toast_key"):
			Toasts.show_key(event["toast_key"])
