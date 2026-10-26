extends Node
## Reglas del juego para los sistemas genéricos (data/game.json). Es el primer autoload: los demás le preguntan por
## roles ("el flag de tener el diario", "quiénes son chicos") en vez de saber nombres de este juego, así el mismo
## código sirve para otro juego con otro game.json. Se carga en _init: otros autoloads lo leen al crearse.

const PATH: String = "res://data/game.json"
## Cómo se dice en game.json qué parte del nombre se sabe desde el principio (bits de JournalManager).
const NAME_PARTS: Dictionary = {"first": 1, "last": 2, "full": 3}

var data: Dictionary = {}


func _init() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) == TYPE_DICTIONARY:
		data = parsed
	else:
		push_error("GameConfig: no se pudo leer %s" % PATH)


## Datos de una mecánica (data/<algo>.json). Si el archivo no existe, el juego no la usa: devuelve {} sin quejarse.
## Si existe pero está mal escrito, avisa.
static func read_data(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("no se pudo leer %s (JSON mal formado)" % path)
		return {}
	return parsed


## Un valor por ruta con puntos ("suspicion.arrest"); `fallback` si no está.
func value(path: String, fallback: Variant = null) -> Variant:
	var node: Variant = data
	for key: String in path.split("."):
		if typeof(node) != TYPE_DICTIONARY or not (node as Dictionary).has(key):
			return fallback
		node = node[key]
	return node


func start_zone() -> String:
	return value("start.zone", "")


func start_tile() -> Vector2i:
	var tile: Array = value("start.tile", [0, 0])
	return Vector2i(int(tile[0]), int(tile[1]))


## Comienzo y fin de la jornada, en minutos desde medianoche.
func day_start() -> int:
	return _clock(value("day.start", "06:00"))


func day_end() -> int:
	return _clock(value("day.end", "18:00"))


## Qué pasa al terminar la jornada: "loop" (vuelve al mismo día) o "next_day" (pasa al siguiente).
func day_mode() -> String:
	return value("day.at_end", "loop")


## Tipos de flag que se olvidan al terminar la jornada ("trust", "state", "negative"...), salvo persistent_flags.
func reset_kinds() -> Array:
	return value("day.reset_kinds", [])


const WEEKDAYS: Array[String] = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]


## Fecha de la jornada `day` (1 = la primera): {year, month, day, weekday 0 = lunes}. En modo loop es siempre la
## primera; en next_day avanza un día por jornada. Sin "first_date" en game.json, vacío.
func date_for_day(day: int) -> Dictionary:
	var first: String = value("day.first_date", "")
	if first == "":
		return {}
	var parts: PackedStringArray = first.split("-")
	var unix: int = Time.get_unix_time_from_datetime_dict({"year": int(parts[0]), "month": int(parts[1]), "day": int(parts[2])})
	var offset: int = 0 if day_mode() == "loop" else maxi(day - 1, 0)
	var date: Dictionary = Time.get_datetime_dict_from_unix_time(unix + offset * 86400)
	return {"year": date["year"], "month": date["month"], "day": date["day"], "weekday": (int(date["weekday"]) + 6) % 7}


## ¿Vale para la jornada `day` algo con "days" (números de jornada) y/o "weekdays" ("mon".."sun")? Sin esos campos,
## vale todos los días. Lo usan los horarios de los NPCs y los eventos con hora.
func matches_day(entry: Dictionary, day: int) -> bool:
	if entry.has("days") and not (entry["days"] as Array).any(func(d: Variant) -> bool: return int(d) == day):
		return false
	if entry.has("weekdays"):
		var date: Dictionary = date_for_day(day)
		if date.is_empty() or not WEEKDAYS[int(date["weekday"])] in (entry["weekdays"] as Array):
			return false
	return true


## El flag de este juego que cumple un rol del framework ("journal_owned", "suspicion_arrest"...); "" si no hay.
func flag(role: String) -> String:
	return value("flags." + role, "")


## Flags que sobreviven al reinicio de la jornada aunque su tipo se reinicie (confianza, estado, negativos).
func persistent_flags() -> Array:
	return value("persistent_flags", [])


## ¿`id` está en un grupo de gente ("outsiders", "kids", "known_by_surname", "no_surname")?
func in_group(group: String, id: String) -> bool:
	return id in (value("people." + group, []) as Array)


## Qué se sabe del nombre de cada persona desde el principio: id -> bits (1 nombre, 2 apellido, 3 los dos).
func known_from_start() -> Dictionary:
	var out: Dictionary = {}
	var raw: Dictionary = value("people.known_from_start", {})
	for id: String in raw:
		out[id] = int(NAME_PARTS.get(raw[id], 0))
	return out


static func _clock(text: String) -> int:
	var parts: PackedStringArray = text.split(":")
	return int(parts[0]) * 60 + int(parts[1])
