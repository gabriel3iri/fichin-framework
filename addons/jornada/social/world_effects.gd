extends Node
## Registro de efectos: lo que un diálogo o un objeto puede hacerle al mundo (campo "effects" de data/dialogue/*.json).
## El framework no sabe qué efectos hay: cada juego registra los suyos al arrancar (en Rabenholz,
## scripts/story/rabenholz_story.gd) con `register("halt_train", func() -> void: ...)`.
## DataValidator comprueba que todo efecto usado en un JSON esté registrado.

var _effects: Dictionary = {}   # id -> Callable


func register(effect_id: String, handler: Callable) -> void:
	if _effects.has(effect_id):
		push_warning("WorldEffects: '%s' se registra dos veces; queda el último" % effect_id)
	_effects[effect_id] = handler


func has(effect_id: String) -> bool:
	return _effects.has(effect_id)


func ids() -> Array:
	return _effects.keys()


func apply(effect_id: String) -> void:
	if not _effects.has(effect_id):
		push_error("WorldEffects: efecto desconocido '%s'" % effect_id)
		return
	(_effects[effect_id] as Callable).call()


## Ayuda para los efectos: manda a un NPC a otro lugar (o afuera, ZoneManager.GONE) fuera de su horario.
func move_actor(actor_id: String, zone_id: String, tile: Vector2i) -> void:
	for node in get_tree().get_nodes_in_group("npc_actors"):
		var actor := node as NpcActor
		if actor != null and actor.npc_id == actor_id:
			actor.redirect(zone_id, tile)
