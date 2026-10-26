extends Node
## Testimonios por vista (canon 04, tipo WITNESS): "el jugador vio algo con sus ojos". Si el jugador está en la zona
## correcta, dentro de la pantalla del NPC y en la ventana horaria de la regla, el flag se concede solo.
## Las reglas están en data/witness.json. No da información extra: sólo anota lo que de verdad se vio.
## (Lo que exige interactuar —ver el barro de las botas— sale de un diálogo, no de acá.)

const RULES_PATH: String = "res://data/witness.json"
## El NPC cuenta como "a la vista" dentro de la pantalla de 640x360 centrada en el jugador.
const SIGHT_RANGE: Vector2 = Vector2(300.0, 170.0)

var _rules: Array = []
var _streak: Dictionary = {}   # id de regla -> minutos seguidos en vista


func _ready() -> void:
	_rules = GameConfig.read_data(RULES_PATH).get("rules", [])
	TimeManager.minute_changed.connect(_on_minute_changed)
	LoopManager.loop_started.connect(func(_n: int) -> void: _streak.clear())


func rules() -> Array:
	return _rules


func _on_minute_changed(_hour: int, _minute: int) -> void:
	var player: PlayerController = ZoneManager.player
	if player == null:
		return
	var now: int = TimeManager.now_minutes()
	for rule: Dictionary in _rules:
		var id: String = rule["id"]
		if LoopManager.has_knowledge(rule["flag"]):
			continue
		if ZoneManager.current_zone != rule["zone"] or now < TimeManager.parse_clock(rule["time_min"]) \
				or now > TimeManager.parse_clock(rule["time_max"]):
			_streak[id] = 0
			continue
		# Lo que hace alguien se anota solo si sabe quién es (el nombre o el apellido).
		var who: String = JournalManager.person_for_dialogue(rule["actor"])
		if who != "" and JournalManager.name_bits(who) == 0:
			_streak[id] = 0
			continue
		var needs_ok: bool = true
		for needed: String in rule.get("requires", []):
			needs_ok = needs_ok and LoopManager.has_knowledge(needed)
		if not needs_ok or not _in_sight(player, rule["actor"]):
			_streak[id] = 0
			continue
		_streak[id] = int(_streak.get(id, 0)) + 1
		if int(_streak[id]) >= int(rule.get("minutes", 1)):
			# Primero la conclusión del técnico, en voz alta; después, si tiene diario, el aviso.
			var thought: String = tr("think_" + rule["flag"])
			if thought == "think_" + rule["flag"]:
				thought = tr("think_note_generic") % JournalManager.display_name(who)
			player.think(thought, 4.5)
			LoopManager.gain_knowledge(rule["flag"])


func _in_sight(player: PlayerController, actor_id: String) -> bool:
	for node in get_tree().get_nodes_in_group("npc_actors"):
		var actor := node as NpcActor
		if actor == null or actor.npc_id != actor_id or not actor.visible or actor.zone != ZoneManager.current_zone:
			continue
		var offset: Vector2 = (actor.global_position - player.global_position).abs()
		if offset.x <= SIGHT_RANGE.x and offset.y <= SIGHT_RANGE.y:
			return true
	return false
