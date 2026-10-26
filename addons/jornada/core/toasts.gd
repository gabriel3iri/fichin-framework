extends CanvasLayer
## Avisos breves arriba al centro ("Orden de trabajo recibida", "Anotado en el diario").
## Hace cola; cada aviso dura ~2,6 s. Toda la UI usa keys del CSV, nunca texto literal.

## Se pidió un aviso (clave del CSV). Para quien quiera reaccionar o comprobarlo en una prueba.
signal shown(key: String)

const SHOW_TIME: float = 2.6
const NOTE_KINDS: Array = [KnowledgeRegistry.Kind.WITNESS, KnowledgeRegistry.Kind.TESTIMONY, KnowledgeRegistry.Kind.DOCUMENT, KnowledgeRegistry.Kind.HEARD]

var _queue: Array[String] = []
## Lo aprendido durante una conversación: se anota recién al final, cuando el jugador elige "Anotar en el diario"
## (DialogueManager), para no tapar con avisos lo que está leyendo.
var _pending_notes: Array[String] = []
var _busy: bool = false
var _panel: PanelContainer
var _label: Label


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	_panel.modulate.a = 0.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", UiStyle.panel(true))
	_label = Label.new()
	_label.add_theme_color_override("font_color", Color(1, 0.804, 0.612))
	_panel.add_child(_label)
	add_child(_panel)
	LoopManager.knowledge_gained.connect(_on_knowledge_gained)
	JournalManager.flag_noted.connect(_on_flag_noted)


func _process(_delta: float) -> void:
	# Los avisos no se pintan encima del diario ni de la pantalla de deducción: quedan en cola.
	_panel.visible = not (Journal.is_open or DeductionScreen.is_playing)


func show_key(key: String, args: Array = []) -> void:
	shown.emit(key)
	var text: String = tr(key)
	if not args.is_empty():
		text = text % args
	_queue.append(text)
	if not _busy:
		_next()


func _next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	_label.text = _queue.pop_front()
	_panel.reset_size()
	await get_tree().process_frame   # el Label calcula su tamaño recién en el frame siguiente
	_panel.reset_size()
	_panel.position = Vector2((get_viewport().get_visible_rect().size.x - _panel.size.x) / 2.0, 12.0)
	var tween: Tween = create_tween()
	tween.tween_property(_panel, "modulate:a", 1.0, 0.12)
	tween.tween_interval(SHOW_TIME)
	tween.tween_property(_panel, "modulate:a", 0.0, 0.25)
	tween.tween_callback(_next)


func _on_knowledge_gained(flag: String) -> void:
	if flag == GameConfig.flag("has_journal"):
		_journal_hint()


## Se escribió algo en el diario (JournalManager): sin diario no se anota nada, el técnico solo lo recuerda.
func _on_flag_noted(flag: String) -> void:
	var kind: int = KnowledgeRegistry.kind_of(flag)
	if kind not in NOTE_KINDS:
		return
	if DialogueManager.is_active:
		_pending_notes.append(flag)
		return
	AudioManager.play_sfx("knowledge_gained", -4.0)
	show_key("toast_evidence_doc" if kind == KnowledgeRegistry.Kind.DOCUMENT else "toast_evidence")
	_journal_hint()


func pending_notes() -> Array[String]:
	return _pending_notes


## El jugador anotó lo de la conversación: un solo aviso con el sonido.
func commit_notes() -> void:
	if _pending_notes.is_empty():
		return
	AudioManager.play_sfx("knowledge_gained", -4.0)
	show_key("toast_notes" if _pending_notes.size() > 1 else "toast_evidence", [_pending_notes.size()] if _pending_notes.size() > 1 else [])
	_pending_notes.clear()
	_journal_hint()


## La primera vez que se anota algo, se avisa que el diario existe y cómo se abre (una sola vez; ajuste "tutorials").
func _journal_hint() -> void:
	if SettingsManager.get_value("tutorials") and not SettingsManager.get_value("seen_journal_hint") \
			and JournalManager.has_journal():
		SettingsManager.set_value("seen_journal_hint", true)
		show_key("toast_journal_hint")
