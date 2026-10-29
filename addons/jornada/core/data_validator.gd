class_name DataValidator
extends RefCounted
## Valida al arrancar (solo debug) que los diálogos usen flags del registro y keys del CSV.
## Canon 04 §3: un flag mal escrito debe romper en el editor, no en producción.

const DIALOGUE_DIR: String = "res://data/dialogue/"
const CSV_PATH: String = "res://assets/translations/game.csv"
## Textos de la UI del framework (menú, opciones, diario, HUD, avisos): el juego no los repite.
const FRAMEWORK_CSV_PATH: String = "res://addons/jornada/translations/jornada.csv"

const CONDITION_FLAG_LISTS: Array[String] = ["knowledge", "not_knowledge", "knowledge_any"]
const OPTION_FLAG_LISTS: Array[String] = ["requires", "requires_any", "not_requires", "reveals"]


static func validate_all() -> int:
	var errors: int = 0
	var csv_keys: Dictionary = _load_csv_keys()
	for file_name in DirAccess.get_files_at(DIALOGUE_DIR):
		if file_name.ends_with(".json"):
			errors += _validate_file(DIALOGUE_DIR + file_name, csv_keys)
	errors += _validate_schedules()
	errors += _validate_journal(csv_keys)
	errors += _validate_inspectables()
	errors += _validate_locks(csv_keys)
	errors += _validate_private_rooms()
	errors += _validate_game_config()
	errors += _validate_annoyance(csv_keys)
	errors += _validate_barks(csv_keys)
	errors += _validate_identify(csv_keys)
	errors += _validate_search(csv_keys)
	errors += _validate_escort(csv_keys)
	errors += _validate_notices(csv_keys)
	errors += _validate_music()
	errors += _validate_energy()
	errors += _validate_relations(csv_keys)
	errors += _validate_speeches(csv_keys)
	errors += _validate_script_keys(csv_keys, "res://scripts")
	errors += _validate_script_keys(csv_keys, "res://addons/jornada")
	if errors > 0:
		push_error("DataValidator: %d errores en los datos de diálogo." % errors)
	else:
		print("DataValidator: diálogos OK")
	return errors


static func _validate_file(path: String, csv_keys: Dictionary) -> int:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("%s: JSON inválido" % path)
		return 1
	var errors: int = 0
	var ids: Dictionary = {}
	for entry: Dictionary in parsed.get("entries", []):
		ids[entry.get("id", "")] = true
	for entry: Dictionary in parsed.get("entries", []):
		var where: String = "%s [%s]" % [path.get_file(), entry.get("id", "?")]
		errors += _check_key(entry.get("text_key", ""), csv_keys, where)
		if entry.has("sd_key"):
			errors += _check_key(entry["sd_key"], csv_keys, where)
		errors += _check_flags(entry.get("reveals", []), where)
		errors += _check_no_deductions(entry.get("reveals", []), where)
		errors += _check_effects(entry.get("effects", []), where)
		errors += _check_next(entry.get("next", ""), ids, where)
		if entry.has("learns_name") and not str(entry["learns_name"]) in ["first", "last", "full"]:
			push_error("%s: learns_name tiene que ser first, last o full (dice '%s')" % [where, entry["learns_name"]])
			errors += 1
		var cond: Dictionary = entry.get("condition", {})
		for list_name in CONDITION_FLAG_LISTS:
			errors += _check_flags(cond.get(list_name, []), where)
		for zone_id: String in cond.get("zones", []):
			if not ZoneManager.has_zone(zone_id):
				push_error("%s: la zona '%s' de la condición no existe" % [where, zone_id])
				errors += 1
		for opt: Dictionary in entry.get("options", []):
			errors += _check_key(opt.get("text_key", ""), csv_keys, where)
			errors += _check_next(opt.get("next", ""), ids, where)
			for list_name in OPTION_FLAG_LISTS:
				errors += _check_flags(opt.get(list_name, []), where)
			errors += _check_no_deductions(opt.get("reveals", []), where)
			errors += _check_effects(opt.get("effects", []), where)
	return errors


static func _check_flags(flags: Array, where: String) -> int:
	var errors: int = 0
	for flag: String in flags:
		if not KnowledgeRegistry.is_valid(flag):
			push_error("%s: flag desconocido '%s'" % [where, flag])
			errors += 1
	return errors


## Todo efecto de un diálogo tiene que estar registrado en WorldEffects (lo registra el juego al arrancar).
static func _check_effects(effects: Array, where: String) -> int:
	var errors: int = 0
	for effect: String in effects:
		if not WorldEffects.has(effect):
			push_error("%s: efecto desconocido '%s'" % [where, effect])
			errors += 1
	return errors


## Canon 04: las deducciones las concede DeductionSystem, nunca un diálogo.
static func _check_no_deductions(flags: Array, where: String) -> int:
	var errors: int = 0
	for flag: String in flags:
		if KnowledgeRegistry.is_valid(flag) and KnowledgeRegistry.kind_of(flag) == KnowledgeRegistry.Kind.DEDUCTION:
			push_error("%s: '%s' es una deducción y no puede concederse desde un diálogo" % [where, flag])
			errors += 1
	return errors


## Diario (canon 10 §7): todo flag con entrada tiene `flag_*` y `desc_*`; las deducciones, `ded_*`;
## y los datos de data/journal.json apuntan a flags, zonas y keys que existen.
static func _validate_journal(csv_keys: Dictionary) -> int:
	var errors: int = 0
	var listed: Array = [KnowledgeRegistry.Kind.WITNESS, KnowledgeRegistry.Kind.TESTIMONY, KnowledgeRegistry.Kind.DOCUMENT, KnowledgeRegistry.Kind.PHYSICAL, KnowledgeRegistry.Kind.HEARD, KnowledgeRegistry.Kind.DEDUCTION]
	for flag: String in KnowledgeRegistry.FLAGS:
		if KnowledgeRegistry.kind_of(flag) in listed:
			errors += _check_key("flag_" + flag, csv_keys, "diario")
			errors += _check_key("desc_" + flag, csv_keys, "diario")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/journal.json"))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("data/journal.json: inválido o ausente")
		return errors + 1
	for def: Dictionary in parsed.get("deductions", []):
		errors += _check_key(def["title_key"], csv_keys, "deducción " + def["id"])
		errors += _check_flags([def["id"]] + def["all_of"] + def["any_of"], "deducción " + def["id"])
	for person: Dictionary in parsed.get("people", []):
		var where: String = "persona " + person["id"]
		for key: String in ["name_key", "role_key", "bio_key"]:
			errors += _check_key(person[key], csv_keys, where)
		errors += _check_flags(person["flags"], where)
		if person["heard"] != "":
			errors += _check_flags([person["heard"]], where)
	var roster: Dictionary = parsed.get("roster", {})
	for key: String in ["tab_key", "empty_key", "title_key", "subtitle_key"]:
		if roster.has(key):
			errors += _check_key(roster[key], csv_keys, "lista del diario")
	if roster.has("unlock_flag"):
		errors += _check_flags([roster["unlock_flag"]], "lista del diario")
	for entry: Dictionary in roster.get("entries", []):
		errors += _check_key(entry["name_key"], csv_keys, "lista del diario")
		errors += _check_key(entry["role_key"], csv_keys, "lista del diario")
	for zone_id: String in ZoneManager.zone_ids():
		errors += _check_key("zone_" + zone_id, csv_keys, "zona")
	return errors


## Fastidio: cada NPC con reacción tiene sus textos, su flag existe y, si salta, su diálogo tiene la entrada <npc>_snap.
static func _validate_annoyance(csv_keys: Dictionary) -> int:
	var errors: int = 0
	for npc_id: String in AnnoyanceSystem.config():
		var cfg: Dictionary = AnnoyanceSystem.config()[npc_id]
		var where: String = "fastidio " + npc_id
		errors += _check_key(cfg["gesture_key"], csv_keys, where)
		errors += _check_key(cfg["word_key"], csv_keys, where)
		if cfg.has("snap_flag"):
			errors += _check_flags([cfg["snap_flag"]], where)
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/dialogue/%s.json" % npc_id))
			var has_snap: bool = false
			if typeof(parsed) == TYPE_DICTIONARY:
				for entry: Dictionary in parsed.get("entries", []):
					if entry.get("id", "") == npc_id + "_snap":
						has_snap = true
			if not has_snap:
				push_error("%s: falta la entrada %s_snap en su diálogo" % [where, npc_id])
				errors += 1
	return errors


## Puertas con llave: las dos zonas existen y están conectadas, y los flags y textos son reales.
## Habitaciones ajenas (data/private_rooms.json): la zona existe, está conectada y el ocupante tiene su diálogo de puerta.
static func _validate_private_rooms() -> int:
	var errors: int = 0
	for room: String in PrivateRooms.rooms():
		var rule: Dictionary = PrivateRooms.rooms()[room]
		var where: String = "habitación ajena " + room
		if not ZoneManager.has_zone(room) or ZoneManager.connection(str(rule.get("from", "")), room).is_empty():
			push_error("%s: la zona no existe o no está conectada con '%s'" % [where, rule.get("from", "")])
			errors += 1
		if not FileAccess.file_exists(DIALOGUE_DIR + "door_%s.json" % rule.get("occupant", "")):
			push_error("%s: falta data/dialogue/door_%s.json" % [where, rule.get("occupant", "")])
			errors += 1
	return errors


## data/game.json: que lo que nombra exista (zona de inicio, flags de cada rol, gente, el jefe y su confianza).
static func _validate_game_config() -> int:
	var errors: int = 0
	var where: String = "data/game.json"
	if not ZoneManager.has_zone(GameConfig.start_zone()):
		push_error("%s: la zona de inicio '%s' no existe" % [where, GameConfig.start_zone()])
		errors += 1
	for key: String in ["scenes.menu", "scenes.game", "ui.menu_background"]:
		var path: String = GameConfig.value(key, "")
		if (key.begins_with("scenes.") or path != "") and not ResourceLoader.exists(path):
			push_error("%s: %s apunta a '%s', que no existe" % [where, key, path])
			errors += 1
	if GameConfig.day_end() <= GameConfig.day_start():
		push_error("%s: la jornada termina antes de empezar" % where)
		errors += 1
	if not GameConfig.day_mode() in ["loop", "next_day"]:
		push_error("%s: day.at_end tiene que ser \"loop\" o \"next_day\" (dice \"%s\")" % [where, GameConfig.day_mode()])
		errors += 1
	var kinds: Array = KnowledgeRegistry.Kind.keys().map(func(k: String) -> String: return k.to_lower())
	for kind: String in GameConfig.reset_kinds():
		if not kind in kinds:
			push_error("%s: day.reset_kinds nombra el tipo '%s', que no existe (%s)" % [where, kind, ", ".join(kinds)])
			errors += 1
	var first_date: String = GameConfig.value("day.first_date", "")
	if first_date != "" and not RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}$").search(first_date):
		push_error("%s: day.first_date tiene que ser AAAA-MM-DD (dice '%s')" % [where, first_date])
		errors += 1
	var days_files: Array = Array(DirAccess.get_files_at("res://data/schedules")).filter(func(f: String) -> bool: return f.ends_with(".json")) \
			.map(func(f: String) -> String: return "res://data/schedules/" + f) + ["res://data/events.json"]
	for path: String in days_files:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		var entries: Array = parsed.get("entries", parsed.get("events", [])) if parsed is Dictionary else []
		for entry: Dictionary in entries:
			for weekday: Variant in entry.get("weekdays", []):
				if not weekday in GameConfig.WEEKDAYS:
					push_error("%s: weekday '%s' no existe (%s)" % [path.get_file(), weekday, ", ".join(GameConfig.WEEKDAYS)])
					errors += 1
	var flags: Array = (GameConfig.value("flags", {}) as Dictionary).keys().filter(func(k: String) -> bool:
		return not k.begins_with("_")).map(func(k: String) -> String: return GameConfig.flag(k))
	errors += _check_flags(flags + GameConfig.persistent_flags(), where)
	# textos de la intro y los pensamientos: claves del CSV
	var csv_keys: Dictionary = _load_csv_keys()
	var text_keys: Array = []
	var intro: Dictionary = GameConfig.value("intro", {})
	if not intro.is_empty():
		text_keys.append_array([intro.get("title", ""), intro.get("continue", "intro_continue")] + intro.get("lines", []))
	var thoughts: Dictionary = GameConfig.value("thoughts", {})
	text_keys.append_array(thoughts.get("wake_first", []) + thoughts.get("wake_later", []))
	for single: String in ["journal_kept", "work_order"]:
		if thoughts.has(single):
			text_keys.append(thoughts[single])
	for key: String in text_keys:
		errors += _check_key(key, csv_keys, where)
	# gente que existe: ficha en el diario o personaje con horario (los pasajeros no tienen ficha)
	var known: Array = JournalManager.people().map(func(p: Dictionary) -> String: return p["id"])
	for file: String in DirAccess.get_files_at("res://data/schedules"):
		if file.ends_with(".json"):
			known.append(file.get_basename())
	var people: Dictionary = GameConfig.value("people", {})
	for group: String in people:
		var ids: Array = people[group] if people[group] is Array else (people[group] as Dictionary).keys()
		for id: String in ids:
			if not id in known:
				push_error("%s: people.%s nombra a '%s', que no tiene ficha ni horario" % [where, group, id])
				errors += 1
	var boss: String = GameConfig.value("work.boss", "")
	if boss != "":
		var levels: Dictionary = GameConfig.value("work.trust_at_tasks", {})
		errors += _check_flags(levels.values().map(func(n: Variant) -> String: return "%s_trust_%d" % [boss, int(n)]), where)
	return errors


static func _validate_locks(csv_keys: Dictionary) -> int:
	var errors: int = 0
	var locks: Dictionary = DoorLocks.all()
	for lock_id: String in locks:
		var zones: PackedStringArray = lock_id.split(">")
		var where: String = "cerradura " + lock_id
		if zones.size() != 2 or not ZoneManager.has_zone(zones[0]) or ZoneManager.connection(zones[0], zones[1]).is_empty():
			push_error("%s: las zonas no existen o no están conectadas" % where)
			errors += 1
			continue
		errors += _check_flags(locks[lock_id].get("open_if_any", []), where)
		errors += _check_key(locks[lock_id].get("toast_key", ""), csv_keys, where)
	return errors


## Objetos examinables: existen su zona y su diálogo, dan flags reales y se pueden alcanzar a pie.
static func _validate_inspectables() -> int:
	var errors: int = 0
	if not FileAccess.file_exists("res://data/inspectables.json"):
		return 0   # el juego no usa esta mecánica
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/inspectables.json"))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("data/inspectables.json: inválido")
		return 1
	for extra: Dictionary in parsed.get("extra_decor", []):
		if not ZoneManager.has_zone(extra["zone"]):
			push_error("inspectables: mueble extra en zona inexistente '%s'" % extra["zone"])
			errors += 1
	for obj: Dictionary in parsed.get("objects", []):
		var where: String = "inspectable " + obj["id"]
		if not ZoneManager.has_zone(obj["zone"]):
			push_error("%s: zona inexistente '%s'" % [where, obj["zone"]])
			errors += 1
			continue
		if not FileAccess.file_exists("res://data/dialogue/obj_%s.json" % obj["id"]):
			push_error("%s: falta data/dialogue/obj_%s.json" % [where, obj["id"]])
			errors += 1
		errors += _check_flags(obj["gives"], where)
		var cell := Vector2i(obj["tile"][0], obj["tile"][1])
		var reachable: bool = false
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var near := cell + Vector2i(dx, dy)
				if (dx != 0 or dy != 0 or not obj["host"]) and not ZoneManager.is_cell_solid(obj["zone"], near):
					reachable = true
		if not obj["host"] and ZoneManager.is_cell_solid(obj["zone"], cell):
			push_error("%s: la celda %s cae sobre un obstáculo" % [where, cell])
			errors += 1
		elif not reachable:
			push_error("%s: no hay ninguna celda libre a menos de 2 casillas de %s" % [where, cell])
			errors += 1
	return errors


## Todo texto escrito como literal en un script (tr("x"), show_key("x")) tiene que existir en game.csv o en el CSV del framework:
## un toast sin traducir se vería como "toast_work_failed" en pantalla.
static func _validate_script_keys(csv_keys: Dictionary, dir_path: String) -> int:
	var errors: int = 0
	var regex := RegEx.create_from_string("(?:\\btr|show_key)\\(\"([a-z][a-z0-9_]+)\"\\s*[),]")
	for file_name in DirAccess.get_files_at(dir_path):
		if not file_name.ends_with(".gd"):
			continue
		var text: String = FileAccess.get_file_as_string(dir_path + "/" + file_name)
		for match in regex.search_all(text):
			errors += _check_key(match.get_string(1), csv_keys, dir_path.trim_prefix("res://") + "/" + file_name)
	for sub_dir in DirAccess.get_directories_at(dir_path):
		if not sub_dir.begins_with("_"):
			errors += _validate_script_keys(csv_keys, dir_path + "/" + sub_dir)
	return errors


## data/search.json (SearchSystem): quién busca, sus flags y zonas existen y todos los textos que arma caben (≤200 caracteres y
## ≤3 frases) con el peor caso de nombre y de lugar.
static func _validate_search(csv_keys: Dictionary) -> int:
	var cfg: Dictionary = GameConfig.read_data("res://data/search.json")
	if cfg.is_empty():
		return 0
	var errors: int = 0
	var where: String = "search.json"
	var npc: String = str(cfg.get("npc", ""))
	if not FileAccess.file_exists("res://data/schedules/%s.json" % npc) or not DialogueManager.has_dialogue(npc):
		push_error("%s: '%s' necesita horario y diálogo" % [where, npc])
		errors += 1
	elif not DialogueManager.entry_ids(npc).has(str(cfg.get("entry", ""))):
		push_error("%s: el diálogo de %s no tiene la entrada '%s'" % [where, npc, cfg.get("entry", "")])
		errors += 1
	var flags: Array = (cfg.get("flags", {}).get("warned", []) as Array) + [cfg.get("flags", {}).get("lost", "")]
	errors += _check_flags(flags, where)
	for id: String in cfg.get("messengers", []):
		if not FileAccess.file_exists("res://data/schedules/%s.json" % id):
			push_error("%s: el mensajero '%s' no tiene horario" % [where, id])
			errors += 1
	var zones: Array = cfg.get("zone_tags", {}).keys() + cfg.get("door_of", {}).keys() + cfg.get("door_of", {}).values() \
			+ cfg.get("no_go", []) + cfg.get("places", {}).keys()
	for zone: String in zones:
		if not ZoneManager.has_zone(zone):
			push_error("%s: la zona '%s' no existe" % [where, zone])
			errors += 1
	for checkpoint: Dictionary in cfg.get("checkpoints", []):
		if not RegEx.create_from_string("^\\d{2}:\\d{2}$").search(str(checkpoint.get("time", ""))) or int(checkpoint.get("warning", 0)) < 1 \
				or int(checkpoint["warning"]) > (cfg["flags"]["warned"] as Array).size():
			push_error("%s: hito inválido %s" % [where, checkpoint])
			errors += 1
	# Textos: existen y, juntos, caben
	# Peor caso: nombre y lugar con el largo máximo que declara search.json (no depende de los nombres de ningún juego).
	var max_name: int = int(cfg.get("max_name_chars", 24))
	var max_place: int = int(cfg.get("max_place_chars", 24))
	var places: Dictionary = cfg.get("places", {})
	for zone: String in places:   # las zonas con texto propio (taberna, iglesia, cuarto) no usan {lugar}
		var place_text: String = TranslationServer.translate(places[zone])
		if place_text.length() > max_place:
			push_error("%s: el nombre del lugar '%s' (%s) pasa de max_place_chars (%d)" % [where, zone, place_text, max_place])
			errors += 1
	var worst: Dictionary = {"quien": "x".repeat(max_name), "lugar": "x".repeat(max_place)}
	var kinds: Array = ["here", "seen"]
	for tag: String in cfg.get("zone_tags", {}).values():
		if not tag in kinds:
			kinds.append(tag)
	for key: String in [cfg.get("call_key", ""), cfg.get("messenger_key", "")] + cfg.get("places", {}).values():
		errors += _check_key(key, csv_keys, where)
	for kind: String in kinds:
		errors += _check_key("search_excuse_" + kind, csv_keys, where)
		for level in range(1, (cfg["flags"]["warned"] as Array).size() + 1):
			for progress: String in ["none", "some"]:
				var warn_key: String = "search_warn_%d_%s" % [level, progress]
				errors += _check_key(warn_key, csv_keys, where)
				var sample: String = (TranslationServer.translate("search_excuse_" + kind) + " " + TranslationServer.translate(warn_key)).format(worst)
				var sentences: int = RegEx.create_from_string("[.!?](\\s|$)").search_all(sample).size()
				if sample.length() > 200 or sentences > 3:
					push_error("%s: la línea armada (%s, aviso %d %s) mide %d caracteres y %d frases" % [where, kind, level, progress, sample.length(), sentences])
					errors += 1
	return errors


## data/identify.json (Identification): datos, opciones, grupos y fichas coherentes; flags, personas, textos y retratos
## que existen; cada ficha responde todos los datos de su grupo con opciones que existen (y las `unique`, una vez).
static func _validate_identify(csv_keys: Dictionary) -> int:
	var cfg: Dictionary = GameConfig.read_data("res://data/identify.json")
	if cfg.is_empty():
		return 0
	var errors: int = 0
	var where: String = "identify.json"
	for key: String in ["tab_key", "empty_key", "toast_key", "seen_toast_key"]:
		if cfg.has(key):
			errors += _check_key(cfg[key], csv_keys, where)
	var closing: Array = [cfg.get("complete_flag", "")]
	for done: Dictionary in cfg.get("complete_flags", []):
		closing.append(done["flag"])
	for group: Dictionary in cfg.get("groups", []):
		closing.append(group.get("complete_flag", ""))
	closing = closing.filter(func(f: String) -> bool: return f != "")
	errors += _check_flags(closing, where)
	errors += _check_no_deductions(closing, where)
	var people: Array = JournalManager.people().map(func(p: Dictionary) -> String: return p["id"])
	var options: Dictionary = {}   # dato -> ids de sus opciones
	for field_id: String in cfg.get("fields", {}):
		var def: Dictionary = cfg["fields"][field_id]
		var here: String = "%s dato %s" % [where, field_id]
		errors += _check_key(def.get("title_key", ""), csv_keys, here)
		if not str(def.get("journal_bit", "")) in ["", "first", "last"]:
			push_error("%s: journal_bit tiene que ser first o last" % here)
			errors += 1
		options[field_id] = []
		for o: Dictionary in def.get("options", []):
			options[field_id].append(o["id"])
			errors += _check_key(o["key"], csv_keys, here)
			errors += _check_flags(o.get("unlock_any", []), here + " " + o["id"])
			for pid: String in o.get("people", []):
				if not pid in people:
					push_error("%s %s: '%s' no está en el diario" % [here, o["id"], pid])
					errors += 1
	var group_fields: Dictionary = {}
	for group: Dictionary in cfg.get("groups", []):
		group_fields[group["id"]] = group.get("fields", ["name"])
		errors += _check_key(group["title_key"], csv_keys, where)
		errors += _check_flags(group.get("show_any", []), where + " " + group["id"])
		for field_id: String in group_fields[group["id"]]:
			if not options.has(field_id):
				push_error("%s grupo %s: el dato '%s' no está en fields" % [where, group["id"], field_id])
				errors += 1
	var used: Dictionary = {}   # "dato:opción" de los datos unique
	for c: Dictionary in cfg.get("cards", []):
		var here: String = "%s ficha %s" % [where, c["id"]]
		if not group_fields.has(c["group"]):
			push_error("%s: el grupo '%s' no existe" % [here, c["group"]])
			errors += 1
			continue
		var answer: Dictionary = c.get("answer", {})
		for field_id: String in group_fields[c["group"]]:
			var value: String = str(answer.get(field_id, ""))
			if not value in options.get(field_id, []):
				push_error("%s: la respuesta de '%s' ('%s') no es una opción" % [here, field_id, value])
				errors += 1
			elif cfg["fields"][field_id].get("unique", false):
				if used.has(field_id + ":" + value):
					push_error("%s: '%s' es la respuesta de dos fichas" % [here, value])
					errors += 1
				used[field_id + ":" + value] = true
		if c.has("person") and not c["person"] in people:
			push_error("%s: la persona '%s' no está en el diario" % [here, c["person"]])
			errors += 1
		if not ResourceLoader.exists(c.get("portrait", "")):
			push_error("%s: no existe el retrato %s" % [here, c.get("portrait", "")])
			errors += 1
		errors += _check_key(c.get("look_key", ""), csv_keys, here)
		for clue: Dictionary in c.get("clues", []):
			errors += _check_key(clue["key"], csv_keys, here)
			errors += _check_flags(clue.get("requires_any", []), here)
		if c.has("flag"):
			errors += _check_flags([c["flag"]], here)
	return errors


## data/escort.json: quien escolta existe y tiene las entradas, el destino y donde aparece el jugador se pueden pisar, el flag
## de arranque existe y todos los textos están en el CSV.
static func _validate_escort(csv_keys: Dictionary) -> int:
	var cfg: Dictionary = GameConfig.read_data("res://data/escort.json")
	if cfg.is_empty():
		return 0
	var errors: int = 0
	var where: String = "escort.json"
	var npc: String = str(cfg.get("npc", ""))
	if not FileAccess.file_exists("res://data/schedules/%s.json" % npc) or not DialogueManager.has_dialogue(npc):
		push_error("%s: '%s' necesita horario y diálogo" % [where, npc])
		return 1
	var entries: Array = DialogueManager.entry_ids(npc)
	var wanted: Array = (cfg.get("nag_entries", []) as Array) + [cfg.get("force_entry", ""), cfg.get("arrive_entry", ""), cfg.get("arrive_forced_entry", "")]
	for entry: String in wanted:
		if not entries.has(entry):
			push_error("%s: el diálogo de %s no tiene la entrada '%s'" % [where, npc, entry])
			errors += 1
	errors += _check_flags([cfg.get("start", {}).get("flag", "")], where)
	for zone: String in (cfg.get("start", {}).get("from_zones", []) as Array) + [cfg.get("destination", {}).get("zone", "")]:
		if not ZoneManager.has_zone(zone):
			push_error("%s: la zona '%s' no existe" % [where, zone])
			errors += 1
	var dest_zone: String = str(cfg.get("destination", {}).get("zone", ""))
	if ZoneManager.has_zone(dest_zone):
		for field: String in ["tile", "player_tile"]:
			var tile: Array = cfg["destination"].get(field, [])
			if tile.size() != 2 or ZoneManager.is_cell_solid(dest_zone, Vector2i(int(tile[0]), int(tile[1]))):
				push_error("%s: destination.%s %s no es una celda libre de %s" % [where, field, tile, dest_zone])
				errors += 1
	for key: String in (cfg.get("call_keys", []) as Array) + [cfg.get("force_bark", "")]:
		errors += _check_key(key, csv_keys, where)
	if int(cfg.get("max_nags", 0)) > (cfg.get("nag_entries", []) as Array).size():
		push_error("%s: max_nags pide más vueltas que nag_entries" % where)
		errors += 1
	return errors


## data/audio.json: todo tema nombrado (por hora, de persecución, del menú) existe en assets/audio/music/.
static func _validate_music() -> int:
	var cfg: Dictionary = GameConfig.read_data("res://data/audio.json")
	if cfg.is_empty():
		return 0
	var tracks: Array = (cfg.get("music_periods", []) as Array).map(func(p: Dictionary) -> String: return str(p.get("track", "")))
	tracks.append(str(cfg.get("chase", {}).get("track", "")))
	tracks.append(str(cfg.get("menu_music", "")))
	var errors: int = 0
	for track: String in tracks:
		if track != "" and not ResourceLoader.exists("res://assets/audio/music/%s.ogg" % track):
			push_error("audio.json: falta el tema '%s' en assets/audio/music/" % track)
			errors += 1
	return errors


## data/energy.json: números que tienen sentido y alimentos con energía.
static func _validate_energy() -> int:
	var cfg: Dictionary = GameConfig.read_data("res://data/energy.json")
	if cfg.is_empty():
		return 0
	var errors: int = 0
	var where: String = "energy.json"
	for field: String in ["max", "run_cost_per_second", "walk_regen_per_second", "rest_regen_per_second"]:
		if float(cfg.get(field, 0)) <= 0.0:
			push_error("%s: '%s' tiene que ser mayor que cero" % [where, field])
			errors += 1
	var max_value: float = float(cfg.get("max", 100))
	if float(cfg.get("start", max_value)) > max_value:
		push_error("%s: start pasa de max" % where)
		errors += 1
	var exhausted: Dictionary = cfg.get("exhausted", {})
	if float(exhausted.get("run_again_at", 20)) > max_value or float(exhausted.get("walk_factor", 0.75)) <= 0.0:
		push_error("%s: exhausted tiene valores imposibles" % where)
		errors += 1
	for id: String in cfg.get("foods", {}):
		if float(cfg["foods"][id].get("energy", 0)) <= 0.0:
			push_error("%s: el alimento '%s' tiene que dar energía" % [where, id])
			errors += 1
	return errors


## data/relations.json (Relations): personas y grupos que existen, profundidades y tipos conocidos, frases y negativas
## en el CSV y flags del registro.
static func _validate_relations(csv_keys: Dictionary) -> int:
	var cfg: Dictionary = GameConfig.read_data(Relations.PATH)
	if cfg.is_empty():
		return 0
	var errors: int = 0
	var where: String = "relations.json"
	var people: Array = (GameConfig.read_data("res://data/journal.json").get("people", []) as Array).map(
			func(p: Dictionary) -> String: return p["id"])
	var groups: Dictionary = cfg.get("groups", {})
	var check_ids: Callable = func(ids: Variant, what: String) -> int:
		if ids is String:
			if groups.has(ids):
				return 0
			push_error("%s: %s nombra el grupo '%s', que no existe" % [where, what, ids])
			return 1
		var bad: int = 0
		for pid: String in ids:
			if not pid in people:
				push_error("%s: %s nombra a '%s', que no está en journal.json" % [where, what, pid])
				bad += 1
		return bad
	for group: String in groups:
		errors += check_ids.call(groups[group], "el grupo " + group)
	for rule: Dictionary in cfg.get("knows", []):
		errors += check_ids.call(rule.get("who", []), "knows") + check_ids.call(rule.get("about", []), "knows")
		if not String(rule.get("depth", "")) in Relations.DEPTHS:
			push_error("%s: depth '%s' no es none, role, name ni full" % [where, rule.get("depth", "")])
			errors += 1
	for rule: Dictionary in cfg.get("voices", []):
		errors += check_ids.call(rule.get("who", []), "voices")
		if String(rule.get("voice", "")) == "":
			push_error("%s: una voz sin nombre" % where)
			errors += 1
	var types: Dictionary = cfg.get("types", {})
	for type_id: String in types:
		if types[type_id].has("cap") and not String(types[type_id]["cap"]) in Relations.DEPTHS:
			push_error("%s: el tipo '%s' tiene un cap imposible" % [where, type_id])
			errors += 1
	for t: Dictionary in cfg.get("ties", []):
		errors += check_ids.call([t.get("a", ""), t.get("b", "")], "un lazo")
		for field: String in ["a_says", "b_says"]:
			errors += _check_key(String(t.get(field, "")), csv_keys, where)
	for gate: Dictionary in cfg.get("gates", []):
		if gate.has("who"):
			errors += check_ids.call(gate["who"], "gates")
		errors += _check_flags(gate.get("requires", []), where)
		errors += _check_key(String(gate.get("refuse", "")), csv_keys, where)
		if String(gate.get("refuse", "")) == "":
			push_error("%s: una condición sin 'refuse'" % where)
			errors += 1
	return errors


## data/speeches.json (Speeches): frases en el CSV, flags del registro y quien habla con horario.
static func _validate_speeches(csv_keys: Dictionary) -> int:
	var cfg: Dictionary = GameConfig.read_data("res://data/speeches.json")
	var errors: int = 0
	for speech: Dictionary in cfg.get("speeches", []):
		var where: String = "speeches.json (%s)" % speech.get("npc", "?")
		if not FileAccess.file_exists("res://data/schedules/%s.json" % speech.get("npc", "")):
			push_error("%s: no tiene horario" % where)
			errors += 1
		if (speech.get("lines", []) as Array).is_empty():
			push_error("%s: sin frases" % where)
			errors += 1
		for key: String in speech.get("lines", []):
			errors += _check_key(key, csv_keys, where)
		errors += _check_flags(speech.get("reveals", []), where)
	return errors


## data/game.json "notices": flag que existe y textos del CSV.
static func _validate_notices(csv_keys: Dictionary) -> int:
	var errors: int = 0
	for notice: Dictionary in GameConfig.value("notices", []):
		errors += _check_flags([notice.get("flag", "")], "game.json notices")
		for field: String in ["title", "text", "button"]:
			errors += _check_key(str(notice.get(field, "notice_ok" if field == "button" else "")), csv_keys, "game.json notices")
	return errors


## data/barks.json (tools/gen_barks.py): cada frase existe en game.csv y cada NPC tiene horario.
static func _validate_barks(csv_keys: Dictionary) -> int:
	if not FileAccess.file_exists("res://data/barks.json"):
		return 0   # el juego no usa esta mecánica
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/barks.json"))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("data/barks.json: inválido")
		return 1
	var errors: int = 0
	var npcs: Array = []
	for npc_id: String in parsed["solo"]:
		npcs.append(npc_id)
		for line: Dictionary in parsed["solo"][npc_id]:
			errors += _check_key(line["key"], csv_keys, "barks.json solo/" + npc_id)
			errors += _check_bark_line(line, "barks.json solo/" + npc_id)
	for pair_id: String in parsed["pairs"]:
		npcs.append_array(pair_id.split("|"))
		for line: Dictionary in parsed["pairs"][pair_id]:
			errors += _check_key(line["a"]["key"], csv_keys, "barks.json " + pair_id)
			errors += _check_key(line["b"]["key"], csv_keys, "barks.json " + pair_id)
			errors += _check_bark_line(line["a"], "barks.json " + pair_id) + _check_bark_line(line["b"], "barks.json " + pair_id)
	npcs.append_array(parsed["generic"]["members"])
	for line: Dictionary in parsed["generic"]["lines"]:
		errors += _check_key(line["a"]["key"], csv_keys, "barks.json generic")
		errors += _check_key(line["b"]["key"], csv_keys, "barks.json generic")
	for call: Dictionary in parsed.get("calls", []):
		var where_call: String = "barks.json call " + call["id"]
		if not call.get("dialogue", false):   # los llamados que abren un diálogo no llevan frase
			errors += _check_key(call.get("key", ""), csv_keys, where_call)
		elif not DialogueManager.has_dialogue(call["npc"]):
			push_error("%s: dialogue:true pero %s no tiene diálogo" % [where_call, call["npc"]])
			errors += 1
		for zone_field: String in ["zone", "npc_zone"]:
			if call.has(zone_field) and not ZoneManager.has_zone(call[zone_field]):
				push_error("%s: %s '%s' no existe" % [where_call, zone_field, call[zone_field]])
				errors += 1
		for time_field: String in ["time_min", "time_max"]:
			if call.has(time_field) and not RegEx.create_from_string("^\\d{2}:\\d{2}$").search(str(call[time_field])):
				push_error("%s: %s tiene que ser HH:MM" % [where_call, time_field])
				errors += 1
		if call.has("sfx") and not ResourceLoader.exists("res://assets/audio/sfx/%s.ogg" % call["sfx"]):
			push_error("%s: no existe el sonido '%s'" % [where_call, call["sfx"]])
			errors += 1
		npcs.append(call["npc"])
		for flag: String in call.get("knowledge", []) + call.get("not_knowledge", []) + call.get("reveals", []):
			if not KnowledgeRegistry.FLAGS.has(flag):
				push_error("barks.json call %s: flag desconocido '%s'" % [call["id"], flag])
				errors += 1
	var settings: Dictionary = parsed.get("settings", {})
	var zone_settings: Dictionary = settings.get("zones", {})
	for group: Dictionary in [settings] + zone_settings.values():
		for key: String in group:
			if key != "zones" and not ChatterSystem.DEFAULTS.has(key):
				push_error("barks.json settings: '%s' no es un ajuste (ver ChatterSystem.DEFAULTS)" % key)
				errors += 1
	for zone_id: String in zone_settings:
		if not ZoneManager.has_zone(zone_id):
			push_error("barks.json settings.zones: zona '%s' no existe" % zone_id)
			errors += 1
	for keys: Array in parsed["brush"].values() + parsed["brush_npc"].values():
		for key: String in keys:
			errors += _check_key(key, csv_keys, "barks.json brush")
	for npc_id: String in npcs:
		if not FileAccess.file_exists("res://data/schedules/%s.json" % npc_id):
			push_error("barks.json: '%s' no tiene horario (data/schedules)" % npc_id)
			errors += 1
	return errors


## Una línea del barullo: `zones` existen; `names` nombra a alguien con diálogo (persona del diario) y first/last/full.
static func _check_bark_line(line: Dictionary, where: String) -> int:
	var errors: int = 0
	for zone_id: String in line.get("zones", []):
		if not ZoneManager.has_zone(zone_id):
			push_error("%s (%s): zona '%s' no existe" % [where, line["key"], zone_id])
			errors += 1
	var names: Dictionary = line.get("names", {})
	for npc_id: String in names:
		if JournalManager.person_for_dialogue(npc_id) == "":
			push_error("%s (%s): '%s' no es una persona del diario" % [where, line["key"], npc_id])
			errors += 1
		if not names[npc_id] in ["first", "last", "full"]:
			push_error("%s (%s): names.%s tiene que ser first, last o full" % [where, line["key"], npc_id])
			errors += 1
	return errors


static func _check_key(key: String, csv_keys: Dictionary, where: String) -> int:
	if key == "" or csv_keys.is_empty() or csv_keys.has(key):
		return 0
	push_error("%s: key '%s' no está en game.csv ni en jornada.csv" % [where, key])
	return 1


static func _check_next(next_id: String, ids: Dictionary, where: String) -> int:
	if next_id == "" or ids.has(next_id):
		return 0
	push_error("%s: next '%s' no existe" % [where, next_id])
	return 1


static func _load_csv_keys() -> Dictionary:
	var keys: Dictionary = {}
	for path: String in [FRAMEWORK_CSV_PATH, CSV_PATH]:
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		file.get_csv_line()  # cabecera
		while not file.eof_reached():
			var row: PackedStringArray = file.get_csv_line()
			if row.size() > 0 and row[0] != "":
				keys[row[0]] = true
	return keys


## Toda celda de aparición (al cruzar una puerta o un borde) tiene que estar libre.
static func _validate_spawns() -> int:
	var errors: int = 0
	for zone_id: String in ZoneManager.zone_ids():
		var conns: Dictionary = ZoneManager._zones[zone_id].get("connections", {})
		for target: String in conns:
			var conn: Dictionary = conns[target]
			if conn.has("spawn_tile"):
				var cell := Vector2i(conn["spawn_tile"][0], conn["spawn_tile"][1])
				if ZoneManager.is_cell_solid(zone_id, cell):
					push_error("%s: la celda de aparición hacia/desde %s (%s) cae sobre un obstáculo" % [zone_id, target, cell])
					errors += 1
	return errors


static func _validate_schedules() -> int:
	var errors: int = _validate_spawns()
	var zones: Dictionary = {}
	var zones_parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/zones.json"))
	if typeof(zones_parsed) == TYPE_DICTIONARY:
		zones = zones_parsed["zones"]
	for zone_id: String in zones:
		for target: String in zones[zone_id].get("connections", {}):
			if not zones.has(target):
				push_error("zones.json: %s conecta con zona inexistente '%s'" % [zone_id, target])
				errors += 1
	for file_name in DirAccess.get_files_at("res://data/schedules/"):
		if not file_name.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/schedules/" + file_name))
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("%s: JSON inválido" % file_name)
			errors += 1
			continue
		var last: int = -1
		for entry: Dictionary in parsed.get("entries", []):
			var minutes: int = TimeManager.parse_clock(entry["time"])
			if minutes <= last:
				push_error("%s: horas fuera de orden en %s" % [file_name, entry["time"]])
				errors += 1
			last = minutes
			var zone_id: String = entry["zone"]
			if zone_id != "gone" and not zones.has(zone_id):
				push_error("%s: zona desconocida '%s'" % [file_name, zone_id])
				errors += 1
			elif zone_id != "gone":
				var cells: Array = [entry["tile"]] + entry.get("via", [])
				if entry.get("sit", false):
					# Sentado: el asiento (banco, banqueta) es obstáculo; hace falta una celda libre al lado para llegar.
					cells = entry.get("via", [])
					var seat := Vector2i(int(entry["tile"][0]), int(entry["tile"][1]))
					if [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT].all(func(d: Vector2i) -> bool: return ZoneManager.is_cell_solid(zone_id, seat + d)):
						push_error("%s: %s en %s se sienta en %s, pero no hay celda libre al lado" % [file_name, entry["time"], zone_id, seat])
						errors += 1
				for raw: Array in cells:
					if ZoneManager.is_cell_solid(zone_id, Vector2i(raw[0], raw[1])):
						push_error("%s: %s en %s cae sobre una pared u objeto (celda %s)" % [file_name, entry["time"], zone_id, raw])
						errors += 1
	return errors
