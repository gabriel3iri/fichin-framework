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
