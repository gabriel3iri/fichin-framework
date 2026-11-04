extends Node
## Barullo del pueblo (data/barks.json, generado por tools/gen_barks.py):
##   · frases sueltas: cada NPC de la zona del jugador dice algo de tanto en tanto
##   · charlas: cuando dos se cruzan, uno habla y el otro contesta (pares propios o de vecinos en general)
##   · brush_off: al hablarle a alguien que no tiene diálogo ahora, contesta con una frase corta
##   · llamados ("calls"): un NPC le habla al jugador desde lejos al acercarse a un lugar, y puede dar flags
##     (el encargo de las velas de Simeon). Cada uno sale una vez por loop. Campos opcionales:
##       time_min / time_max   ventana horaria ("HH:MM")
##       dialogue: true        en vez de una frase, abre el diálogo del NPC (la entrada que corresponda por sus condiciones)
##       npc_zone              el NPC tiene que estar en esa zona (aunque no sea la del jugador): la voz llega "a través
##                             de la puerta", sin que se lo vea; el sonido (sfx) suena antes. Puede ser una lista de zonas
##       min_distance          además de estar a menos de `radius`, el jugador tiene que estar a más de esto (px) del
##                             lugar: el llamado sale cuando se aleja (los primeros pasos desde la cama)
##       sfx                   sonido que acompaña al llamado (p. ej. golpes en la puerta)
##       loop_min / loop_max   solo en esas jornadas (desde el segundo día, una versión corta)
##       approach: true        con dialogue: el NPC entra caminando hasta el jugador (NpcActor.approach_player) y
##                             recién al llegar habla; al terminar la charla vuelve a su horario
##       think_key             en vez de que hable el NPC, el jugador contesta solo (piensa en voz alta)
## Cada frase sale en un globo (ui/speech_bubbles.gd): de cerca entero, de lejos medio transparente (alpha_for); los
## globos no se pisan y, si no hay lugar para uno nuevo, quien iba a hablar espera. No da flags ni sospecha.
## Nombres: los que reconocen las fichas (Identification.name_at) salen resaltados en el globo y el jugador los anota
## con un clic (si no, se los perdió): quedan como nombres sueltos para las fichas. Una frase con nombre dura
## `seconds_name` más, para que dé tiempo. Si la línea lleva `names` ({npc: "first"|"last"|"full"}) y esa persona está
## a la vista (le hablan a ella), el clic además le pone el nombre (JournalManager.learn_name), como en un diálogo.
## Una línea suelta puede llevar `zones` (solo se dice ahí: lo que se habla en la taberna).
## Ritmo y duración: `settings` de barks.json (claves de DEFAULTS), con `settings.zones.<zona>` para un lugar con
## más barullo (más globos a la vez, más seguido).

const PATH: String = "res://data/barks.json"
## Opacidad según la distancia al jugador (px): entera hasta NEAR, FAR_ALPHA desde FAR.
const NEAR: float = 96.0
const FAR: float = 280.0
const FAR_ALPHA: float = 0.35
## Dos NPCs "se cruzan" a menos de esta distancia.
const PAIR_RANGE: Vector2 = Vector2(48.0, 30.0)
const TICK: float = 0.25
## Ritmo del barullo (barks.json "settings" los pisa, y "settings.zones.<zona>" para una zona):
##   solo_min..solo_max   cada cuánto habla solo cada NPC (s reales; F los acelera como a todo)
##   pair_cooldown        un mismo par no vuelve a charlar antes de esto
##   max_at_once          globos de barullo a la vez en la zona;  min_gap: entre dos frases nuevas
##   seconds_*            cuánto dura un globo: base + por letra, entre min y max (cortos: casi no dan tiempo a leer)
##   reply_after          la respuesta sale cuando a la primera frase le queda esta fracción de su tiempo
##   seconds_name         lo que dura de más un globo con un nombre para anotar
##   bubble_width         ancho máximo del texto de un globo (px)
const DEFAULTS: Dictionary = {
	"solo_min": 10.0, "solo_max": 26.0, "pair_cooldown": 75.0, "max_at_once": 3, "min_gap": 1.2,
	"seconds_base": 0.8, "seconds_per_char": 0.03, "seconds_min": 1.3, "seconds_max": 2.8, "reply_after": 0.75,
	"seconds_name": 2.0, "bubble_width": 112,
}
## Llamados con "approach": a cuánto del jugador habla y cuánto espera como mucho que llegue (s reales).
const TALK_RANGE: float = 40.0
const APPROACH_SECONDS: float = 15.0

var _data: Dictionary = {}
var _clock: float = 0.0
var _tick_left: float = 0.0
var _last_start: float = -100.0
var _next_solo: Dictionary = {}      # npc_id -> _clock en que puede volver a hablar solo
var _pair_ready: Dictionary = {}     # "a|b" -> _clock en que ese par puede volver a charlar
var _last_key: Dictionary = {}       # npc_id -> última frase dicha (para no repetirla)
var _calls_done: Dictionary = {}     # id del llamado -> true (se vacía cada loop)
var _generation: int = 0             # sube con cada loop o partida nueva: corta las esperas de _approach_and_talk
var _zone_seconds: float = 0.0       # cuánto hace que el jugador anda por esta zona (con control): "or_after_seconds"
## Los globos (en una CanvasLayer propia, debajo del HUD): NpcActor.show_bark los usa.
var bubbles: SpeechBubbles


func _ready() -> void:
	_data = GameConfig.read_data(PATH)
	var layer := CanvasLayer.new()
	layer.layer = 5   # debajo del HUD (10) y del diario
	add_child(layer)
	bubbles = SpeechBubbles.new()
	bubbles.alpha_for = alpha_for
	bubbles.find_name = func(word: String, before: String) -> Array:
		return Identification.name_at(word, before) if Identification.can_hear() else []
	bubbles.name_clicked.connect(_on_name_clicked)
	bubbles.max_text_width = int(setting("bubble_width"))
	layer.add_child(bubbles)
	LoopManager.game_reset.connect(bubbles.clear)
	ZoneManager.zone_changed.connect(func(_z: String) -> void:
		_next_solo.clear()
		_zone_seconds = 0.0)
	LoopManager.loop_started.connect(func(_n: int) -> void:
		_calls_done.clear()
		_generation += 1)   # un llamado que esperaba a alguien caminando queda sin efecto
	LoopManager.game_reset.connect(func() -> void: _generation += 1)


func _process(delta: float) -> void:
	if get_tree().paused or DialogueManager.is_active or ZoneManager.player == null:
		return
	_clock += delta
	if ZoneManager.player.can_move:
		_zone_seconds += delta
	_tick_left -= delta
	if _tick_left > 0.0:
		return
	_tick_left = TICK
	_tick()


## Opacidad de una frase dicha en `pos` según lo lejos que esté el jugador.
func alpha_for(pos: Vector2) -> float:
	var player: PlayerController = ZoneManager.player
	if player == null:
		return 1.0
	var t: float = clampf((pos.distance_to(player.global_position) - NEAR) / (FAR - NEAR), 0.0, 1.0)
	return lerpf(1.0, FAR_ALPHA, t)


## Un ajuste del ritmo del barullo: el de la zona del jugador si lo tiene, si no el general, si no DEFAULTS.
func setting(key: String) -> float:
	var settings: Dictionary = _data.get("settings", {})
	var zone: Dictionary = settings.get("zones", {}).get(ZoneManager.current_zone, {})
	return float(zone.get(key, settings.get(key, DEFAULTS[key])))


## Cuánto dura en pantalla un globo con `text` (más, si trae un nombre para anotar).
func bubble_seconds(text: String) -> float:
	var seconds: float = clampf(setting("seconds_base") + text.length() * setting("seconds_per_char"),
			setting("seconds_min"), setting("seconds_max"))
	return seconds + (setting("seconds_name") if bubbles != null and bubbles.has_names(text) else 0.0)


## El jugador hizo clic en un nombre de un globo: lo anota (y, si la frase se lo decía a alguien a la vista, le pone
## ese nombre a esa persona).
func _on_name_clicked(field_id: String, option_id: String, _speaker: Node2D, meta: Dictionary) -> void:
	var bit: int = {"first": JournalManager.FIRST, "last": JournalManager.LAST}.get(
			Identification.field(field_id).get("journal_bit", ""), 0)
	var named: Dictionary = meta.get("names", {})
	for npc_id: String in named:
		var person: String = JournalManager.person_for_dialogue(npc_id)
		if person != "" and _visible_here(npc_id) and Identification.is_answer(person, field_id, option_id):
			JournalManager.learn_name(person, bit)
	# El clic suena siempre (la lapicera); el técnico solo lo piensa la primera vez.
	if Identification.hear(field_id, option_id):
		AudioManager.play_sfx("ui_click", -2.0, 0.05)
		if ZoneManager.player != null:
			ZoneManager.player.think(tr("think_name_noted") % Identification.option_text(field_id, option_id), 2.5)
	else:
		AudioManager.play_sfx("ui_click", -10.0, 0.05)   # ya lo tenía: el clic, más bajo


## "No tengo nada que decirle": propia del NPC si tiene, si no según sea hombre, mujer o chico.
func brush_off(actor: NpcActor) -> void:
	var keys: Array = _data.get("brush_npc", {}).get(actor.npc_id, [])
	if keys.is_empty():
		keys = _data.get("brush", {}).get(_data.get("kind", {}).get(actor.npc_id, "male"), [])
	if keys.is_empty():
		return
	actor.show_bark(tr(_pick_key(actor.npc_id, keys.map(func(k: String) -> Dictionary: return {"key": k}))), UiStyle.ACCENT, 2.0)


func _tick() -> void:
	var present: Array[NpcActor] = []
	var busy: int = 0
	for node in get_tree().get_nodes_in_group("npc_actors"):
		var actor := node as NpcActor
		if actor == null or not actor.visible or actor.zone != ZoneManager.current_zone:
			continue
		if actor.is_barking():
			busy += 1
		elif not actor.is_talking():
			present.append(actor)
	_separate_name_tags()
	_check_calls()
	if busy >= int(setting("max_at_once")) or _clock - _last_start < setting("min_gap"):
		return
	if _try_pair(present):
		return
	present.shuffle()
	for actor: NpcActor in present:
		if not _next_solo.has(actor.npc_id):
			# al entrar a la zona no hablan todos juntos
			_next_solo[actor.npc_id] = _clock + randf_range(minf(2.0, setting("solo_min")), setting("solo_max"))
			continue
		if _clock < _next_solo[actor.npc_id]:
			continue
		var lines: Array = _available(_data.get("solo", {}).get(actor.npc_id, []), actor)
		if lines.is_empty():
			continue
		var line: Dictionary = _pick_line(actor.npc_id, lines)
		if not bubbles.has_room(actor, actor.bark_head(), tr(line["key"])):
			_next_solo[actor.npc_id] = _clock + 1.0   # no hay lugar para el globo: lo dice en un rato
			continue
		_next_solo[actor.npc_id] = _clock + randf_range(setting("solo_min"), setting("solo_max"))
		_say(actor, line)
		return


## Llamados: si el jugador está cerca del lugar y el NPC en la zona (y se cumplen los flags), el NPC le habla. Sin "zone",
## el lugar es el NPC mismo: le habla al que se le acerca, esté donde esté (salvo en "except_zones"). Con
## "or_after_seconds" también sale si el jugador lleva ese tiempo en la zona sin acercarse (Klara golpea si el técnico
## va hacia la puerta o se queda en el cuarto).
func _check_calls() -> void:
	var player: PlayerController = ZoneManager.player
	for call: Dictionary in _data.get("calls", []):
		var follows: bool = not call.has("zone")
		if _calls_done.has(call["id"]) or (not follows and call["zone"] != ZoneManager.current_zone):
			continue
		if ZoneManager.current_zone in call.get("except_zones", []):
			continue
		var spot: Vector2
		if follows:
			var near: NpcActor = _caller(call)
			if near == null or not near.visible:
				continue
			spot = near.global_position
		else:
			spot = ZoneManager.tile_px(Vector2i(call["tile"][0], call["tile"][1]))
		var distance: float = player.global_position.distance_to(spot)
		var near: bool = distance <= float(call.get("radius", 64)) and distance >= float(call.get("min_distance", 0))
		if not near and not (call.has("or_after_seconds") and _zone_seconds >= float(call["or_after_seconds"])):
			continue
		if not player.can_move:
			continue   # recién despierto, en una escena o trabajando: espera
		var actor: NpcActor = _ready_caller(call)
		if actor == null:
			continue
		if call.get("dialogue", false):
			if DialogueManager.is_active or Notices.is_busy():
				continue   # se reintenta cuando termine la charla o el cartel en curso
			_fire(call, actor)
			continue
		_calls_done[call["id"]] = true
		if call.has("think_key"):
			if call.has("sfx"):
				AudioManager.play_sfx(call["sfx"], -2.0)
			player.think(tr(call["think_key"]), 4.5)
			for flag: String in call.get("reveals", []):
				LoopManager.gain_knowledge(flag)
			continue
		actor.show_bark(tr(call["key"]), UiStyle.ACCENT, 4.0)
		for flag: String in call.get("reveals", []):
			LoopManager.gain_knowledge(flag)


## Quien llama, si el llamado vale ahora (hora, jornada, flags y que esté y no hable con otro); null si no.
func _ready_caller(call: Dictionary) -> NpcActor:
	if not _call_time_ok(call):
		return null
	if LoopManager.loop_number < int(call.get("loop_min", 1)) or LoopManager.loop_number > int(call.get("loop_max", 9999)):
		return null
	if not call.get("knowledge", []).all(func(f: String) -> bool: return LoopManager.has_knowledge(f)):
		return null
	if call.get("not_knowledge", []).any(func(f: String) -> bool: return LoopManager.has_knowledge(f)):
		return null
	var actor: NpcActor = _caller(call)
	return null if actor == null or actor.is_talking() else actor


func _fire(call: Dictionary, actor: NpcActor) -> void:
	_calls_done[call["id"]] = true
	if call.get("approach", false):
		_approach_and_talk(call, actor)
	else:
		_open_dialogue(call)


## Un llamado con "first" es lo primero que pasa en su zona: Door.enter y la E del jugador lo preguntan antes de cruzar o
## de tocar algo, y si todavía no salió sale ahora y el jugador no hace lo otro (Klara golpea aunque el técnico vaya
## derecho a la puerta o al diario). Verdadero si lo frenó.
func intercept() -> bool:
	if DialogueManager.is_active or Notices.is_busy() or ZoneManager.player == null:
		return false
	for call: Dictionary in _data.get("calls", []):
		if not call.get("first", false) or not call.get("dialogue", false) or _calls_done.has(call["id"]):
			continue
		if call.get("zone", "") != ZoneManager.current_zone:
			continue
		var actor: NpcActor = _ready_caller(call)
		if actor != null:
			_fire(call, actor)
			return true
	return false


func _call_time_ok(call: Dictionary) -> bool:
	var now: int = TimeManager.now_minutes()
	if call.has("time_min") and now < TimeManager.parse_clock(call["time_min"]):
		return false
	return not (call.has("time_max") and now > TimeManager.parse_clock(call["time_max"]))


## Quien llama: en la zona del jugador y a la vista; o, con `npc_zone`, en esa otra zona o una de esas (se lo oye, no se
## lo ve).
func _caller(call: Dictionary) -> NpcActor:
	var wanted: Variant = call.get("npc_zone", ZoneManager.current_zone)
	var zones: Array = wanted if wanted is Array else [wanted]
	for node in get_tree().get_nodes_in_group("npc_actors"):
		if node is NpcActor and node.npc_id == call["npc"] and node.zone in zones \
				and (node.visible or node.zone != ZoneManager.current_zone):
			return node
	return null


## Llamado que abre una charla: da los flags (que eligen la entrada del diálogo), suena el sonido y habla.
func _open_dialogue(call: Dictionary) -> void:
	for flag: String in call.get("reveals", []):
		LoopManager.gain_knowledge(flag)
	if call.has("sfx") and not call.has("wait"):
		call = call.merged({"wait": 1.2})   # lo que tarda en abrir/contestar quien está del otro lado
	if not await _prelude(call):
		return
	ZoneManager.player.can_move = true
	# En esa espera pudo irse quien llamaba: entonces no habla. Si otra cosa le ganó la charla, el llamado vuelve a salir.
	if _caller(call) != null and (DialogueManager.is_active or not DialogueManager.start(call["npc"])):
		_calls_done.erase(call["id"])


## Lo que pasa antes de que el que llama hable o entre, con el jugador quieto: el sonido ("sfx", el toc toc), un globo de
## sorpresa sobre el jugador ("alert": "!"), una espera ("wait" s), lo que contesta el jugador en voz alta ("player_key",
## y otra espera para leerlo) y el sonido de entrar ("sfx_after", la puerta). Falso si en el medio terminó el loop o
## empezó otra partida (la escena ya no existe).
func _prelude(call: Dictionary) -> bool:
	var generation: int = _generation
	var player: PlayerController = ZoneManager.player
	player.can_move = false
	if call.has("sfx"):
		AudioManager.play_sfx(call["sfx"], -2.0)
	if call.has("alert"):
		bubbles.say(player, Vector2(0.0, -33.0), str(call["alert"]), 1.4, &"thought")
	if not await _wait(float(call.get("wait", 0.0)), generation):
		return false
	if call.has("player_key"):
		var text: String = tr(call["player_key"])
		bubbles.say(player, Vector2(0.0, -33.0), text, bubble_seconds(text), &"speech")
		if not await _wait(bubble_seconds(text) * 0.7, generation):
			return false
	if call.has("sfx_after"):
		AudioManager.play_sfx(call["sfx_after"], -2.0)
	return true


func _wait(seconds: float, generation: int) -> bool:
	if seconds > 0.0:
		await get_tree().create_timer(seconds, false).timeout
	if generation != _generation or not is_instance_valid(ZoneManager.player):
		return false
	return true


## Llamado que entra a buscarlo: camina hasta el jugador (por la puerta o el borde, nunca aparece a su lado), habla al
## llegar y, terminada la charla, vuelve a su horario. Si en APPROACH_SECONDS no llegó, habla desde donde esté.
func _approach_and_talk(call: Dictionary, actor: NpcActor) -> void:
	for flag: String in call.get("reveals", []):
		LoopManager.gain_knowledge(flag)
	var generation: int = _generation
	if not await _prelude(call):
		return
	actor = _caller(call)
	if actor == null:
		ZoneManager.player.can_move = true
		return
	actor.approach_player()
	ZoneManager.player.can_move = false   # la escena es suya: el jugador la espera
	var waited: float = 0.0
	while waited < APPROACH_SECONDS:
		await get_tree().process_frame
		if generation != _generation or not is_instance_valid(actor) or not is_instance_valid(ZoneManager.player):
			return   # terminó el loop o empezó otra partida: la escena ya no existe
		waited += get_process_delta_time()
		if actor.zone == ZoneManager.current_zone and actor.global_position.distance_to(ZoneManager.player.global_position) <= TALK_RANGE:
			break
	ZoneManager.player.can_move = true
	if DialogueManager.is_active or not DialogueManager.start(actor.npc_id):
		actor.end_detour()
		_calls_done.erase(call["id"])   # otra cosa le ganó la charla: vuelve a salir
		return
	var npc_id: String = actor.npc_id
	var ended: Array = [false]
	var done := func(ended_id: String) -> void:
		if ended_id == npc_id:
			ended[0] = true
	DialogueManager.dialogue_ended.connect(done)
	while not ended[0] and is_instance_valid(actor) and generation == _generation:
		await get_tree().process_frame
	DialogueManager.dialogue_ended.disconnect(done)
	if is_instance_valid(actor):
		actor.end_detour()


## Si dos nombres se pisan, el del que está más al norte sube un renglón (o dos, si hay tres juntos).
func _separate_name_tags() -> void:
	var actors: Array = get_tree().get_nodes_in_group("npc_actors").filter(func(n: Node) -> bool:
		return n is NpcActor and n.visible and n.zone == ZoneManager.current_zone)
	actors.sort_custom(func(a: NpcActor, b: NpcActor) -> bool: return a.global_position.y > b.global_position.y)
	var placed: Array = []    # [centro x, y del renglón, medio ancho]
	for actor: NpcActor in actors:
		var half: float = actor.name_tag_width() * 0.5 + 3.0
		var rows: int = 0
		var x: float = actor.global_position.x
		while rows < 3 and placed.any(func(p: Array) -> bool:
				return absf(p[0] - x) < p[2] + half and absf(p[1] - (actor.global_position.y - rows * NpcActor.NAME_TAG_ROW)) < NpcActor.NAME_TAG_ROW):
			rows += 1
		actor.lift_name_tag(rows)
		placed.append([x, actor.global_position.y - rows * NpcActor.NAME_TAG_ROW, half])


## Busca dos NPCs cerca uno del otro con algo que decirse; si los hay, arranca la charla.
func _try_pair(present: Array[NpcActor]) -> bool:
	for i in present.size():
		for j in range(i + 1, present.size()):
			var a: NpcActor = present[i]
			var b: NpcActor = present[j]
			if a.npc_id == b.npc_id:
				continue
			var offset: Vector2 = (a.global_position - b.global_position).abs()
			if offset.x > PAIR_RANGE.x or offset.y > PAIR_RANGE.y:
				continue
			var pair_id: String = "%s|%s" % [a.npc_id, b.npc_id] if a.npc_id < b.npc_id else "%s|%s" % [b.npc_id, a.npc_id]
			if _clock < _pair_ready.get(pair_id, 0.0):
				continue
			var exchange: Array = _exchange_for(a, b)
			if exchange.is_empty():
				continue
			var line: Dictionary = exchange[1].pick_random()
			var first: NpcActor = exchange[0]
			if not bubbles.has_room(first, first.bark_head(), tr(line["a"]["key"])):
				continue
			_pair_ready[pair_id] = _clock + setting("pair_cooldown")
			var seconds: float = _say(first, line["a"])
			_reply(exchange[2], line["b"], seconds * setting("reply_after"))
			return true
	return false


## [primero, líneas, segundo] para el par (en el orden en que está escrito), o [] si no tienen nada que decirse.
func _exchange_for(a: NpcActor, b: NpcActor) -> Array:
	var pairs: Dictionary = _data.get("pairs", {})
	for order: Array in [[a, b], [b, a]]:
		var lines: Array = _available_pairs(pairs.get("%s|%s" % [order[0].npc_id, order[1].npc_id], []))
		if not lines.is_empty():
			return [order[0], lines, order[1]]
	var generic: Dictionary = _data.get("generic", {})
	var members: Array = generic.get("members", [])
	if a.npc_id in members and b.npc_id in members:
		var lines: Array = _available_pairs(generic.get("lines", []))
		if not lines.is_empty():
			return [a, lines, b]
	return []


## La respuesta de una charla: si todavía no hay lugar para su globo, espera un poco (hasta dos segundos).
func _reply(actor: NpcActor, line: Dictionary, delay: float) -> void:
	await get_tree().create_timer(maxf(delay, 0.3), false).timeout
	for attempt in 8:
		if not is_instance_valid(actor) or not actor.visible or actor.is_talking():
			return
		if bubbles.has_room(actor, actor.bark_head(), tr(line["key"])):
			_say(actor, line)
			return
		await get_tree().create_timer(0.25, false).timeout


## Dice la línea en un globo; devuelve cuánto dura.
func _say(actor: NpcActor, line: Dictionary) -> float:
	_last_start = _clock
	_last_key[actor.npc_id] = line["key"]
	var text: String = tr(line["key"])
	var seconds: float = bubble_seconds(text)
	actor.show_bark(text, UiStyle.TEXT, seconds, &"speech", {"names": line.get("names", {})})
	return seconds


func _visible_here(npc_id: String) -> bool:
	for node in get_tree().get_nodes_in_group("npc_actors"):
		if node is NpcActor and node.npc_id == npc_id and node.visible and node.zone == ZoneManager.current_zone:
			return true
	return false


## Elige una línea al azar sin repetir la última que dijo ese NPC.
func _pick_line(npc_id: String, lines: Array) -> Dictionary:
	var options: Array = lines.filter(func(l: Dictionary) -> bool: return l["key"] != _last_key.get(npc_id, ""))
	if options.is_empty():
		options = lines
	return options.pick_random()


func _pick_key(npc_id: String, lines: Array) -> String:
	var key: String = _pick_line(npc_id, lines)["key"]
	_last_key[npc_id] = key
	return key


## Las frases que puede decir ahora: en su franja horaria, en la zona y, con "doing", solo mientras hace eso
## (NpcActor.doing(): los planos, el telegrama).
func _available(lines: Array, actor: NpcActor = null) -> Array:
	return lines.filter(func(l: Dictionary) -> bool:
		return _in_window(l) and (not l.has("doing") or (actor != null and actor.doing() == l["doing"])))


func _available_pairs(lines: Array) -> Array:
	return lines.filter(func(l: Dictionary) -> bool: return _in_window(l["a"]) and _in_window(l["b"]))


func _in_window(line: Dictionary) -> bool:
	if line.has("zones") and not ZoneManager.current_zone in line["zones"]:
		return false
	if not line.has("from"):
		return true
	var now: int = TimeManager.now_minutes()
	return now >= TimeManager.parse_clock(line["from"]) and now <= TimeManager.parse_clock(line["to"])
