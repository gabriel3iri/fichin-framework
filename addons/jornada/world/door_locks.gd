class_name DoorLocks
extends RefCounted
## Puertas cerradas con llave (data/locks.json). Una puerta se abre si pasó la hora `open_from`, si el jugador tiene
## alguno de los flags de `open_if_any`, o si no hay regla. Canon 07 loops 11-13: el archivo del Rathaus está
## cerrado; se abre con la vía policial (gennaro_investigation_open) o después de las 17:15, cuando Brandt se va.

const PATH: String = "res://data/locks.json"

static var _locks: Dictionary = {}
static var _loaded: bool = false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_locks = GameConfig.read_data(PATH).get("locks", {})


static func all() -> Dictionary:
	_load()
	return _locks


## El aviso si la puerta `from_zone` → `to_zone` está cerrada ahora: [clave, argumentos]; vacío si se puede pasar.
## "hours" ({"open", "close"}): un negocio abierto al público solo en ese horario (antes avisa a qué hora abre).
static func closed_message(from_zone: String, to_zone: String) -> Array:
	_load()
	var rule: Dictionary = _locks.get("%s>%s" % [from_zone, to_zone], {})
	if rule.has("hours"):
		var now: int = TimeManager.now_minutes()
		var hours: Dictionary = rule["hours"]
		if hours.has("open") and now < TimeManager.parse_clock(hours["open"]):
			return ["toast_closed_until", [hours["open"]]]
		if hours.has("close") and now >= TimeManager.parse_clock(hours["close"]):
			return ["toast_closed_today", []]
	var key: String = closed_reason(from_zone, to_zone)
	return [] if key == "" else [key, []]


## Devuelve la clave del aviso si la puerta `from_zone` → `to_zone` está cerrada con llave ahora; "" si se puede pasar.
## (El horario de los negocios, "hours", lo mira closed_message.)
static func closed_reason(from_zone: String, to_zone: String) -> String:
	_load()
	var rule: Dictionary = _locks.get("%s>%s" % [from_zone, to_zone], {})
	if not (rule.has("open_from") or rule.has("open_if_any") or rule.has("closed_if_any")):
		return ""   # sin regla, o solo horario
	# Cerrada mientras tenga alguno de estos flags (p. ej. detenido en la celda).
	for flag: String in rule.get("closed_if_any", []):
		if LoopManager.has_knowledge(str(flag)):
			return rule.get("toast_key", "toast_door_locked")
	if rule.has("open_from") and TimeManager.now_minutes() >= TimeManager.parse_clock(rule["open_from"]):
		return ""
	for flag: String in rule.get("open_if_any", []):
		if LoopManager.has_knowledge(flag):
			return ""
	# Solo closed_if_any (sin open_*): abierta si no aplica el cierre de arriba.
	if rule.has("closed_if_any") and not rule.has("open_from") and not rule.has("open_if_any"):
		return ""
	return rule.get("toast_key", "toast_door_locked")
