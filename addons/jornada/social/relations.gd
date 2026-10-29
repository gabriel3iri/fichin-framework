class_name Relations
extends RefCounted
## Quién sabe de quién y cómo lo cuenta (data/relations.json). Lo usa «le quería preguntar por alguien» de
## DialogueManager: sin el archivo, cualquiera contesta por cualquiera, como antes.
##
## - from_loop: antes de esa jornada nadie habla de nadie (refuse_early).
## - gates: condiciones para que alguien hable de los vecinos (en ciertas zonas, o una persona en particular); la
##   primera que falta contesta con su `refuse` y, con `entry`, la charla sigue por esa entrada de quien contesta.
## - groups + knows: hasta dónde conoce cada uno a cada otro (none, role, name, full). Las reglas se aplican en orden y
##   la última que coincide manda.
## - ties + types: lazos entre dos personas con un tipo (rencor, familia, secreto...) que cambia la respuesta: cuántos
##   datos da de una vez (steps), hasta dónde llega (cap), si gasta el cupo (free) y si esquiva (dodge). Un lazo puede
##   traer la frase de cada uno sobre el otro (a_says, b_says).
## - voices: con qué voz contesta cada uno (chicos, el cura, los de afuera...), en orden, manda la última regla que
##   coincide. DialogueManager busca primero las frases de esa voz (ver DialogueManager._about_line).

const PATH: String = "res://data/relations.json"
const DEPTHS: Array[String] = ["none", "role", "name", "full"]

static var _data: Dictionary = {}
static var _loaded: bool = false


static func data() -> Dictionary:
	if not _loaded:
		_data = GameConfig.read_data(PATH)
		_loaded = true
	return _data


static func enabled() -> bool:
	return not data().is_empty()


static func from_loop() -> int:
	return int(data().get("from_loop", 1))


## Ids del grupo, o la lista tal cual si ya es una lista de ids.
static func members(group_or_ids: Variant) -> Array:
	if group_or_ids is Array:
		return group_or_ids
	return data().get("groups", {}).get(String(group_or_ids), [])


## Hasta dónde conoce `who` a `about` (índice en DEPTHS).
static func depth(who: String, about: String) -> int:
	var out: int = 0
	for rule: Dictionary in data().get("knows", []):
		if who in members(rule.get("who", [])) and about in members(rule.get("about", [])):
			out = maxi(0, DEPTHS.find(String(rule.get("depth", "none"))))
	return out


## La voz con la que contesta `who` ("" si ninguna regla de "voices" lo nombra).
static func voice(who: String) -> String:
	var out: String = ""
	for rule: Dictionary in data().get("voices", []):
		if who in members(rule.get("who", [])):
			out = String(rule.get("voice", ""))
	return out


## El lazo entre dos personas (vacío si no hay) con la frase de `who` sobre `about` en "says".
static func tie(who: String, about: String) -> Dictionary:
	for t: Dictionary in data().get("ties", []):
		var a: String = t.get("a", "")
		var b: String = t.get("b", "")
		if (a == who and b == about) or (b == who and a == about):
			var out: Dictionary = t.duplicate()
			out["says"] = t.get("a_says" if a == who else "b_says", "")
			return out
	return {}


## Reglas del tipo de lazo (steps, cap, free, dodge).
static func rules(tie_type: String) -> Dictionary:
	return data().get("types", {}).get(tie_type, {})


## La primera condición que falta para que `who` hable de los vecinos en `zone` (vacío si puede). Trae su `refuse` y,
## si tiene, `entry`: la charla sigue por esa entrada del diálogo de quien contesta (Hanns ofrece otra cerveza).
static func gate(who: String, zone: String) -> Dictionary:
	for gate: Dictionary in data().get("gates", []):
		if gate.has("who") and not who in members(gate["who"]):
			continue
		if gate.has("zones") and not zone in (gate["zones"] as Array):
			continue
		for flag: String in gate.get("requires", []):
			if not LoopManager.has_knowledge(flag):
				return gate
	return {}
