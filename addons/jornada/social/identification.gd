extends Node
## Identificar a la gente (data/identify.json), al estilo de Return of the Obra Dinn: fichas con una cara y lo que se ve
## de cada uno, y una lista de nombres que se van desbloqueando con flags (documentos, registros, testimonios). El
## jugador le pone a cada ficha el nombre que cree; el juego nunca dice cuál está mal: cada vez que hay `batch`
## aciertos sin confirmar (3), los confirma juntos. Así no se puede adivinar de a uno.
## Lo que el jugador anota sobrevive a los loops (es su libreta) y entra en el guardado. Con todo confirmado da
## `complete_flag` (no puede ser una deducción: esas las da solo DeductionSystem).
##
## identify.json:
##   tab_key, empty_key        pestaña del diario y el texto mientras no hay nada
##   batch                     aciertos que se confirman juntos (3)
##   toast_key                 aviso al confirmar (%d = cuántos)
##   seen_toast_key            aviso cuando aparecen caras nuevas en el diario
##   complete_flag             se gana con todo confirmado
##   groups                    [{id, title_key, show_any: [flags]}]: cómo se agrupan las fichas; un grupo aparece
##                             cuando el jugador vio esas caras (cualquiera de show_any; vacío = desde el principio).
##                             La pestaña aparece con el primer grupo visible.
##   names                     [{id, name_key, unlock_any: [flags]}]: sin unlock_any, desde el principio
##   cards                     [{id, group, portrait, look_key, answer: id de names, clues: [{key, requires_any}],
##                               flag?}]: `flag` se gana al confirmar esa ficha

signal changed
signal confirmed(card_ids: Array)

const PATH: String = "res://data/identify.json"

## Ficha -> nombre que eligió el jugador.
var guesses: Dictionary = {}
var confirmed_ids: Array[String] = []

var _cfg: Dictionary = {}
var _cards: Dictionary = {}   # id -> ficha


func _ready() -> void:
	_cfg = GameConfig.read_data(PATH)
	if _cfg.is_empty():
		return
	for card: Dictionary in _cfg.get("cards", []):
		_cards[card["id"]] = card
	SaveManager.register_section("identification", to_dict, from_dict)
	LoopManager.game_reset.connect(reset)
	LoopManager.knowledge_gained.connect(_on_knowledge_gained)


func enabled() -> bool:
	return not _cfg.is_empty()


func config() -> Dictionary:
	return _cfg


## ¿Ya se puede usar? (hace falta el diario y haber visto alguna cara)
func is_available() -> bool:
	return enabled() and JournalManager.has_journal() and not visible_groups().is_empty()


func groups() -> Array:
	return _cfg.get("groups", [])


## Grupos cuyas caras ya vio el jugador.
func visible_groups() -> Array:
	return groups().filter(_group_seen)


func cards(group_id: String = "") -> Array:
	return _cfg.get("cards", []).filter(func(c: Dictionary) -> bool: return group_id == "" or c["group"] == group_id)


func _group_seen(group: Dictionary) -> bool:
	var show: Array = group.get("show_any", [])
	return show.is_empty() or show.any(func(f: String) -> bool: return LoopManager.has_knowledge(f))


## Un flag que muestra un grupo nuevo avisa que hay caras nuevas en el diario.
## Si ya había caras vistas cuando consigue el diario, avisa en ese momento.
func _on_knowledge_gained(flag: String) -> void:
	if _cfg.has("seen_toast_key") and JournalManager.has_journal():
		var news: bool = flag == GameConfig.flag("has_journal") and not visible_groups().is_empty()
		for group: Dictionary in groups():
			var show: Array = group.get("show_any", [])
			if flag in show and show.filter(func(f: String) -> bool: return LoopManager.has_knowledge(f)).size() == 1:
				news = true
		if news:
			Toasts.show_key(_cfg["seen_toast_key"])
	changed.emit()


func card(card_id: String) -> Dictionary:
	return _cards.get(card_id, {})


## Nombres que el jugador ya puede usar (los desbloqueó algún flag), en el orden de identify.json.
func names_available() -> Array:
	return _cfg.get("names", []).filter(func(n: Dictionary) -> bool:
		var unlock: Array = n.get("unlock_any", [])
		return unlock.is_empty() or unlock.any(func(f: String) -> bool: return LoopManager.has_knowledge(f)))


func name_text(name_id: String) -> String:
	for n: Dictionary in _cfg.get("names", []):
		if n["id"] == name_id:
			return tr(n["name_key"])
	return ""


func guess_of(card_id: String) -> String:
	return guesses.get(card_id, "")


func is_confirmed(card_id: String) -> bool:
	return card_id in confirmed_ids


## Pistas de una ficha que ya se tienen.
func clues(card_id: String) -> Array[String]:
	var out: Array[String] = []
	for clue: Dictionary in card(card_id).get("clues", []):
		var needed: Array = clue.get("requires_any", [])
		if needed.is_empty() or needed.any(func(f: String) -> bool: return LoopManager.has_knowledge(f)):
			out.append(clue["key"])
	return out


## Le pone a la ficha el nombre `name_id`. Un nombre va en una sola ficha: si estaba en otra (sin confirmar), se
## mueve. Las confirmadas no se tocan.
func guess(card_id: String, name_id: String) -> void:
	if not _cards.has(card_id) or is_confirmed(card_id):
		return
	for other: String in guesses.keys():
		if guesses[other] == name_id and not is_confirmed(other):
			guesses.erase(other)
	guesses[card_id] = name_id
	_check()
	changed.emit()


func clear(card_id: String) -> void:
	if is_confirmed(card_id):
		return
	guesses.erase(card_id)
	changed.emit()


## [confirmadas, total]
func progress() -> Array[int]:
	return [confirmed_ids.size(), _cards.size()]


## Cada vez que hay `batch` aciertos sin confirmar, se confirman juntos (en el orden de las fichas).
func _check() -> void:
	var batch: int = maxi(int(_cfg.get("batch", 3)), 1)
	var right: Array[String] = []
	for c: Dictionary in _cfg.get("cards", []):
		if not is_confirmed(c["id"]) and guesses.get(c["id"], "") == c["answer"]:
			right.append(c["id"])
	var newly: Array[String] = []
	while right.size() >= batch or (not right.is_empty() and confirmed_ids.size() + right.size() == _cards.size()):
		var take: int = mini(batch, right.size())
		newly.append_array(right.slice(0, take))
		right = right.slice(take)
	if newly.is_empty():
		return
	confirmed_ids.append_array(newly)
	for card_id: String in newly:
		var flag: String = card(card_id).get("flag", "")
		if flag != "":
			LoopManager.gain_knowledge(flag)
	if _cfg.has("toast_key"):
		Toasts.show_key(_cfg["toast_key"], [newly.size()])
	confirmed.emit(newly)
	if confirmed_ids.size() == _cards.size() and _cfg.get("complete_flag", "") != "":
		LoopManager.gain_knowledge(_cfg["complete_flag"])


func reset() -> void:
	guesses.clear()
	confirmed_ids.clear()
	changed.emit()


func to_dict() -> Dictionary:
	return {"guesses": guesses.duplicate(), "confirmed": confirmed_ids.duplicate()}


func from_dict(value: Variant) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		return
	guesses = (value.get("guesses", {}) as Dictionary).duplicate()
	confirmed_ids.assign(value.get("confirmed", []))
	changed.emit()
