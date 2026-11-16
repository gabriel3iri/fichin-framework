extends "res://addons/jornada/testkit/game_case.gd"
## El ejemplo de punta a punta: arranca, el calendario avanza, se olvida lo del día y la gente sigue su horario.


func test_los_datos_estan_bien() -> void:
	assert_eq(DataValidator.validate_all(), 0, "DataValidator.validate_all()")


func test_arranca_en_la_plaza_con_la_intro() -> void:
	assert_true(await start_game(false))
	assert_eq(zm.current_zone, "plaza")
	var intro: Array = tree.root.find_children("*", "CanvasLayer", true, false).filter(_is_intro)
	assert_eq(intro.size(), 1, "la tarjeta de la intro")


func test_cada_jornada_es_el_dia_siguiente() -> void:
	await start_game()
	assert_eq(lm.today(), {"year": 1952, "month": 4, "day": 14, "weekday": 0}, "lunes 14 de abril")
	lm.gain_knowledge("journal_owned")
	lm.gain_knowledge("oven_lit")
	lm.gain_knowledge("tomas_route")
	lm.end_day("time")
	await frames(2)
	await until(_in_game, 10.0)
	assert_eq(lm.loop_number, 2)
	assert_eq(lm.today()["day"], 15, "martes 15")
	assert_false(lm.has_knowledge("oven_lit"), "el estado del día se olvida")
	assert_true(lm.has_knowledge("tomas_route"), "lo que le contaron, no")
	assert_true(lm.has_knowledge("journal_owned"), "la libreta sigue")


func test_hablar_con_marta_cuenta_quien_viene() -> void:
	await start_game()
	await go("panaderia", Vector2i(7, 8))
	assert_true(dm.start("marta"), "doña Marta habla")
	await _choose(0)   # ¿Qué hago primero?
	assert_true(lm.has_knowledge("oven_lit"), "el horno se prende primero")
	await _wait_text()
	dm.advance()
	await _choose(1)   # ¿Quién viene por aquí?
	assert_true(lm.has_knowledge("tomas_exists"), "sabe que hay un cartero")
	assert_true(lm.has_knowledge("lucia_exists"), "sabe que Lucía busca a su gato")
	dm.abort()


func _wait_text() -> void:
	await until(func() -> bool: return not dm.text_revealing, 5.0)


func _choose(index: int) -> void:
	await _wait_text()
	dm.choose(index)
	await frames(2)


func test_el_cartero_pasa_por_la_panaderia() -> void:
	await start_game()
	set_clock(9, 50)
	await go("panaderia", Vector2i(7, 8))
	await frames(5)
	var tomas: Node = tree.current_scene.get_node("Actors/Tomas")
	assert_true(tomas.visible, "a las 09:50 el cartero está en la panadería")
	assert_true(reachable("plaza", Vector2i(21, 12), Vector2i(36, 14)), "se llega caminando a su siguiente parada")


func _in_game() -> bool:
	return tree.current_scene != null and tree.current_scene.name == "Main" and is_instance_valid(zm.player)


func _is_intro(n: Node) -> bool:
	return n.get_script() != null and n.get_script().resource_path.ends_with("intro_card.gd")


## La cámara del framework deja el mundo siempre en un píxel entero de pantalla, con cualquier zoom: con el zoom 1,5
## el mapa podía quedar en medio píxel y todo el cuarto temblaba.
func test_la_camara_en_pixeles_enteros() -> void:
	var settings: Node = autoload("SettingsManager")
	var original: Variant = settings.get_value("camera_zoom")
	await start_game()
	for zoom_index in 3:
		settings.set_value("camera_zoom", zoom_index)
		for place: Array in [["plaza", Vector2i(21, 12), "move_left"], ["panaderia", Vector2i(7, 8), "move_right"]]:
			await go(place[0], place[1])
			Input.action_press(place[2])
			for i in 30:
				await frames(1)
				var origin: Vector2 = tree.root.get_viewport().canvas_transform.origin
				var off: Vector2 = (origin - origin.round()).abs()
				if not assert_true(off.x < 0.01 and off.y < 0.01, "zoom %d en %s: %s" % [zoom_index, place[0], origin]):
					break
			Input.action_release(place[2])
	settings.set_value("camera_zoom", original)


## Todo lo que se toca con E se alcanza (game_case.unreachable_interactables).
func test_todo_lo_que_se_toca_se_alcanza() -> void:
	await start_game()
	tm.pause()
	var problems: Array[String] = await unreachable_interactables()
	assert_eq(problems, [] as Array[String], "%d cosas fuera de alcance" % problems.size())


## Los muebles bajos tienen la base tan honda como su dibujo (game_case.shallow_furniture).
func test_los_muebles_tienen_profundidad() -> void:
	await start_game()
	var problems: Array[String] = shallow_furniture()
	assert_eq(problems, [] as Array[String], "%d muebles finitos" % problems.size())


## La feria del domingo es una jornada especial (data/game.json "special_days"): su fecha, su horario, su gente con sus
## horarios y diálogos (data/feria) y nadie más; después vuelve un día de los de siempre.
func test_la_feria_es_una_jornada_especial() -> void:
	await start_game()
	lm.next_special_day = "feria"
	await _next_day()
	assert_eq(lm.special_day, "feria")
	assert_eq(lm.today(), {"year": 1952, "month": 4, "day": 20, "weekday": 6}, "domingo 20 de abril")
	assert_eq(int(tm.minutes), 9 * 60, "la feria empieza a las 09:00")
	assert_eq(int(tm.loop_end), 12 * 60, "y termina a las 12:00")
	assert_false(lm.is_regular_day(), "hide_regular: lo de todos los días no corre")
	await frames(5)
	var marta: NpcActor = tree.current_scene.get_node("Actors/Marta")
	assert_true(marta.visible and marta.zone == "plaza", "doña Marta vende en la plaza")
	assert_eq(marta.doing(), "vender")
	assert_false(tree.current_scene.get_node("Actors/Tomas").visible, "el cartero no tiene horario en la feria")
	var lines: Array[String] = []
	var grab := func(_who: String, text: String, _sd: String, _options: Array, _next: bool) -> void: lines.append(text)
	dm.line_shown.connect(grab)
	assert_true(dm.start("marta"))
	dm.line_shown.disconnect(grab)
	assert_eq(lines, [tr("dlg_marta_feria")] as Array[String], "habla con el diálogo de la feria")
	dm.abort()
	await _next_day()
	assert_eq(lm.special_day, "", "después de la feria, un día como los demás")
	assert_eq(int(tm.minutes), 7 * 60, "que empieza a las 07:00")
	assert_eq(int(tm.loop_end), 13 * 60)


## Una jornada especial sin "start" ni "end" usa el horario de la jornada del juego (no uno fijo).
func test_una_jornada_especial_sin_horario_usa_el_del_juego() -> void:
	var days: Dictionary = autoload("GameConfig").data["special_days"]
	days["corta"] = {"date": "1952-04-21"}
	await start_game()
	lm.next_special_day = "corta"
	await _next_day()
	days.erase("corta")
	assert_eq(lm.special_day, "corta")
	assert_eq(int(tm.minutes), 7 * 60, "empieza cuando empieza la jornada del juego")
	assert_eq(int(tm.loop_end), 13 * 60, "y termina cuando termina")
	assert_true(lm.is_regular_day(), "sin hide_regular, el día de siempre sigue")


## El validador revisa las jornadas especiales: con datos rotos, cuenta cada error.
func test_el_validador_revisa_las_jornadas_especiales() -> void:
	var keys: Dictionary = DataValidator._load_csv_keys()
	assert_eq(DataValidator._validate_special_days(keys), 0, "la feria está bien")
	var days: Dictionary = autoload("GameConfig").data["special_days"]
	days["rota"] = {"date": "20-04-1952", "start": "10:00", "end": "09:00", "data_dir": "res://data/no_existe",
			"cast": {"payaso": "res://no_existe.png"}, "zone_scenes": {"luna": "res://no_existe.tscn"}, "tint": [1.0]}
	var errors: int = DataValidator._validate_special_days(keys)
	days.erase("rota")
	assert_eq(errors, 8, "fecha, horario, carpeta, hoja y horario del payaso, zona y escena, tinte")


## La pregunta del diario (data/journal.json "questions") se abre con el diario y se responde al saber del cartero.
func test_la_pregunta_del_diario() -> void:
	await start_game()
	assert_true(jm.questions().is_empty(), "sin diario no hay preguntas")
	lm.gain_knowledge("journal_owned")
	assert_eq(jm.questions().size(), 1)
	assert_eq(jm.question_state(jm.questions()[0]), 1, "abierta")
	assert_eq(jm.open_question_count(), 1)
	lm.gain_knowledge("tomas_exists")
	assert_eq(jm.question_state(jm.questions()[0]), 2, "respondida")
	assert_eq(jm.open_question_count(), 0)
	var keys: Dictionary = DataValidator._load_csv_keys()
	var broken: Array = jm.data()["questions"] + [{"id": "who_comes", "text_key": "q_no_existe", "opens": [], "answered_by": ["flag_no_existe"]}]
	assert_eq(DataValidator._validate_questions(broken, keys), 4, "id repetido, texto, sin opens y flag inventado")


## Un punto del horario con "doing": se ve lo que hace mientras está ahí (NpcActor.doing).
func test_marta_amasa_por_la_manana() -> void:
	await start_game()
	set_clock(7, 30)
	await go("panaderia", Vector2i(7, 8))
	await frames(5)
	var marta: NpcActor = tree.current_scene.get_node("Actors/Marta")
	assert_eq(marta.doing(), "amasar", "a las 07:30 amasa")


## Un juego sin flag para un rol (aquí, la sospecha) no rompe: la advertencia y el arresto pasan igual.
func test_la_sospecha_sin_flags_de_rol() -> void:
	await start_game()
	var gm: Node = autoload("GameManager")
	var reasons: Array[String] = []
	var original: Callable = lm.end_of_day_handler
	lm.end_of_day_handler = func(reason: String) -> void: reasons.append(reason)
	gm.add_suspicion(100)
	await frames(2)
	lm.end_of_day_handler = original
	assert_eq(reasons, ["arrest"] as Array[String], "el arresto termina la jornada")
	assert_false(lm.has_knowledge(""), "no se anotó un flag vacío")
	gm.suspicion = 0


func _next_day() -> void:
	lm.end_day("time")
	await frames(2)
	await until(_in_game, 10.0)
	await frames(2)


## El validador revisa data/work.json: sin flag para la orden, entrega mal escrita, tarea sin nombre, sin duración, en
## una zona que no existe y con un minijuego que no es Minigame. El ejemplo no trae trabajo: se le pasa uno inventado.
func test_el_validador_revisa_el_trabajo() -> void:
	var keys: Dictionary = DataValidator._load_csv_keys()
	assert_eq(DataValidator._validate_work_data({}, keys), 0, "sin trabajo no hay nada que revisar")
	var work: Dictionary = {"deadline": "mediodía", "tasks": [
		{"id": "hornear", "name_key": "no_existe", "zone": "luna", "minigame": "res://tests/test_primer_dia.gd"},
		{"id": "hornear"}]}
	assert_eq(DataValidator._validate_work_data(work, keys), 7, "orden, entrega, nombre, duración, zona, minijuego, id repetido")
