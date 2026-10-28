class_name MuseumView
extends Control
## Specimens grouped by era with completion bars. Reads only get_collection*(); cards build art lazily.

const ERA_ORDER: Array[String] = ["Cambrian", "Ordovician", "Silurian", "Devonian", "Carboniferous",
		"Permian", "Triassic", "Jurassic", "Cretaceous", "Paleogene", "Neogene", "Quaternary"]
const COLUMNS: int = 3
const GRID_GAP: int = 20
const PREFETCH_PX: float = 500.0
const BUTTON_H: float = 120.0
const NEW_KEY: String = "museum_new"
const SPECIMEN_DIR: String = "res://assets/sprites/specimens/"
const DETAIL_FADE: float = 0.2

var _site_filter: String = ""
var _cards: Dictionary = {} # id -> MuseumCard
var _unbuilt: Array[MuseumCard] = []
var _bars: Dictionary = {} # era -> {bar, label}
var _stale: bool = true
var _structure_dirty: bool = true
var _pending_new: Dictionary = {}
var _detail: Control
var _detail_art: Control
var _detail_name: Label
var _detail_meta: Label
var _detail_value: Label
var _detail_fact: Label
var _detail_tween: Tween
var _populate_queued: bool = false

@onready var _title_count: Label = $VBox/Header/Count
@onready var _overall: ProgressBar = $VBox/Overall
@onready var _filters: HBoxContainer = $VBox/Filters
@onready var _scroll: ScrollContainer = $VBox/Scroll
@onready var _content: VBoxContainer = $VBox/Scroll/Content


func _ready() -> void:
	_scroll.scroll_deadzone = 24
	_scroll.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void: _queue_populate())
	_scroll.resized.connect(_queue_populate)
	for id: String in SettingsStore.get_string(NEW_KEY).split(",", false):
		_pending_new[id] = true
	EventBus.specimen_discovered.connect(_on_discovered)
	EventBus.site_changed.connect(func(_s: Dictionary) -> void: _structure_dirty = true; _stale = true)
	EventBus.prestige_done.connect(func(_i: Dictionary) -> void: _structure_dirty = true; _stale = true)
	visibility_changed.connect(_on_visibility)
	_build_detail()


func is_detail_open() -> bool:
	return _detail.visible


func close_detail() -> void:
	if not _detail.visible:
		return
	if _detail_tween != null:
		_detail_tween.kill()
	_detail_tween = create_tween()
	_detail_tween.tween_property(_detail, "modulate:a", 0.0, DETAIL_FADE)
	_detail_tween.tween_callback(_detail.hide)


func _on_visibility() -> void:
	if is_visible_in_tree():
		_refresh()
	else:
		close_detail()


func _on_discovered(id: String) -> void:
	_pending_new[id] = true
	SettingsStore.set_string(NEW_KEY, ",".join(PackedStringArray(_pending_new.keys())))
	_stale = true
	if is_visible_in_tree():
		_refresh()


func _refresh() -> void:
	if not _stale:
		_queue_populate()
		return
	_stale = false
	var entries: Array[Dictionary] = GameState.get_collection(_site_filter)
	var progress: Dictionary = GameState.get_collection_progress()
	if _structure_dirty or _cards.size() != entries.size():
		_rebuild(entries)
	else:
		for e: Dictionary in entries:
			(_cards[String(e["id"])] as MuseumCard).set_entry(e)
	_update_progress(progress)
	_update_filters()
	_queue_populate()


func _rebuild(entries: Array[Dictionary]) -> void:
	_structure_dirty = false
	for c: Node in _content.get_children():
		c.queue_free()
	_cards.clear()
	_bars.clear()
	_unbuilt.clear()
	var by_era: Dictionary = {}
	for e: Dictionary in entries:
		var era: String = String(e["era"])
		if not by_era.has(era):
			by_era[era] = []
		(by_era[era] as Array).append(e)
	var eras: Array[String] = []
	for era: String in ERA_ORDER:
		if by_era.has(era):
			eras.append(era)
	for era: String in by_era:
		if not eras.has(era):
			eras.append(era)
	for era: String in eras:
		var head: HBoxContainer = HBoxContainer.new()
		head.add_theme_constant_override("separation", 16)
		var name_label: Label = Label.new()
		name_label.text = era
		name_label.theme_type_variation = &"Heading"
		name_label.add_theme_font_size_override("font_size", 44)
		head.add_child(name_label)
		var bar: ProgressBar = ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0.0, 30.0)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(bar)
		var count: Label = Label.new()
		count.add_theme_font_size_override("font_size", 34)
		head.add_child(count)
		_content.add_child(head)
		_bars[era] = {"bar": bar, "label": count}
		var grid: GridContainer = GridContainer.new()
		grid.columns = COLUMNS
		grid.add_theme_constant_override("h_separation", GRID_GAP)
		grid.add_theme_constant_override("v_separation", GRID_GAP)
		for e: Dictionary in by_era[era]:
			var card: MuseumCard = MuseumCard.new()
			card.set_entry(e)
			card.pressed.connect(_show_detail.bind(card))
			grid.add_child(card)
			_cards[String(e["id"])] = card
			_unbuilt.append(card)
		_content.add_child(grid)


func _update_progress(progress: Dictionary) -> void:
	_title_count.text = "%d / %d" % [int(progress["discovered"]), int(progress["total"])]
	_overall.max_value = maxf(float(progress["total"]), 1.0)
	_overall.value = float(progress["discovered"])
	var by_era: Dictionary = progress["by_era"]
	for era: String in _bars:
		var info: Dictionary = by_era.get(era, {"discovered": 0, "total": 0})
		var bar: ProgressBar = _bars[era]["bar"]
		bar.max_value = maxf(float(info["total"]), 1.0)
		bar.value = float(info["discovered"])
		(_bars[era]["label"] as Label).text = "%d/%d" % [int(info["discovered"]), int(info["total"])]


func _update_filters() -> void:
	var unlocked: Dictionary = {String(GameState.get_current_site().get("id", "")): true}
	for e: Dictionary in GameState.get_collection(""):
		if bool(e["discovered"]):
			unlocked[String(e["site"])] = true
	var want: bool = unlocked.size() > 1
	if _filters.visible != want:
		_filters.visible = want
	if not want or _filters.get_child_count() > 0:
		return
	var group: ButtonGroup = ButtonGroup.new()
	var options: Array[String] = [""]
	for s: String in unlocked:
		options.append(s)
	for s: String in options:
		var b: Button = Button.new()
		b.text = "All" if s == "" else s.capitalize().replace("_", " ")
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = s == _site_filter
		b.custom_minimum_size = Vector2(0.0, BUTTON_H)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_set_filter.bind(s))
		_filters.add_child(b)


func _set_filter(site: String) -> void:
	_site_filter = site
	_structure_dirty = true
	_stale = true
	_scroll.scroll_vertical = 0
	_refresh()


# Wait one frame so containers have laid cards out before measuring their rects.
func _queue_populate() -> void:
	if _populate_queued:
		return
	_populate_queued = true
	await get_tree().process_frame
	_populate_queued = false
	_populate_visible()


func _populate_visible() -> void:
	if not is_visible_in_tree():
		return
	var view: Rect2 = _scroll.get_global_rect().grow(PREFETCH_PX)
	var keep: Array[MuseumCard] = []
	var changed_new: bool = false
	for card: MuseumCard in _unbuilt:
		if not is_instance_valid(card):
			continue
		if card.get_global_rect().intersects(view):
			card.ensure_art()
		else:
			keep.append(card)
	_unbuilt = keep
	var tight: Rect2 = _scroll.get_global_rect()
	for id: String in _pending_new.keys():
		var card: MuseumCard = _cards.get(id)
		if card != null and card.art_built and bool(card.entry.get("discovered", false)) \
				and card.get_global_rect().intersects(tight):
			card.shimmer()
			_pending_new.erase(id)
			changed_new = true
	if changed_new:
		SettingsStore.set_string(NEW_KEY, ",".join(PackedStringArray(_pending_new.keys())))


func _build_detail() -> void:
	_detail = Control.new()
	_detail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_detail.visible = false
	add_child(_detail)
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(Palette.UMBER, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_input)
	_detail.add_child(dim)
	var sheet: PanelContainer = PanelContainer.new()
	sheet.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	sheet.custom_minimum_size = Vector2(900.0, 0.0)
	sheet.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sheet.grow_vertical = Control.GROW_DIRECTION_BOTH
	_detail.add_child(sheet)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	sheet.add_child(box)
	_detail_art = Control.new()
	_detail_art.custom_minimum_size = Vector2(0.0, 480.0)
	box.add_child(_detail_art)
	_detail_name = Label.new()
	_detail_name.theme_type_variation = &"Heading"
	_detail_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_detail_name)
	_detail_meta = Label.new()
	_detail_meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_detail_meta)
	_detail_value = Label.new()
	_detail_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_detail_value)
	_detail_fact = Label.new()
	_detail_fact.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_fact.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_fact.add_theme_font_size_override("font_size", 36)
	box.add_child(_detail_fact)
	var close: Button = Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(0.0, 128.0)
	close.pressed.connect(close_detail)
	box.add_child(close)


func _on_dim_input(event: InputEvent) -> void:
	if (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed):
		close_detail()


func _show_detail(card: MuseumCard) -> void:
	Sfx.play(&"ui_tap")
	var e: Dictionary = card.entry
	var found: bool = bool(e.get("discovered", false))
	var rarity: String = String(e.get("rarity", "common"))
	for c: Node in _detail_art.get_children():
		c.queue_free()
	var path: String = SPECIMEN_DIR + String(e["id"]) + ".png"
	var art: Control
	if ResourceLoader.exists(path):
		var tr: TextureRect = TextureRect.new()
		tr.texture = load(path) as Texture2D
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art = tr
	else:
		var f: ProceduralFossil = ProceduralFossil.new()
		art = f
		f.setup(String(e["id"]), rarity)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.modulate = Color.WHITE if found else MuseumCard.SILHOUETTE
	_detail_art.add_child(art)
	_detail_name.text = String(e["name"]) if found else "Undiscovered"
	_detail_meta.text = "%s  ·  %s" % [String(e["era"]), rarity.to_upper()]
	_detail_meta.add_theme_color_override("font_color", Palette.rarity_color(rarity).darkened(0.4))
	_detail_value.text = "Value  %s" % NumFormat.fmt(float(e["value"])) if found else "Keep digging to find it"
	_detail_fact.text = String(e["fact"]) if found else ""
	_detail_fact.visible = found
	_detail.modulate.a = 0.0
	_detail.visible = true
	if _detail_tween != null:
		_detail_tween.kill()
	_detail_tween = create_tween()
	_detail_tween.tween_property(_detail, "modulate:a", 1.0, DETAIL_FADE)
