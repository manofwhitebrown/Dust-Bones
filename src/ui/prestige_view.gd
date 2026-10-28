class_name PrestigeView
extends Control
## Prestige tab: preview from GameState, what resets/persists, hold-to-confirm. Fires once.

const RESETS_TEXT: String = "Resets: coins, brushes, diggers and upgrades."
const KEEPS_TEXT: String = "Keeps: your museum, every discovery, and all Fieldwork."

var _busy: bool = false

@onready var _site: Label = $Scroll/Box/Site
@onready var _gain: Label = $Scroll/Box/Gain
@onready var _bonus: Label = $Scroll/Box/Bonus
@onready var _resets: Label = $Scroll/Box/Resets
@onready var _keeps: Label = $Scroll/Box/Keeps
@onready var _begin: Button = $Scroll/Box/Begin
@onready var _confirm: VBoxContainer = $Scroll/Box/Confirm
@onready var _hold: HoldButton = $Scroll/Box/Confirm/Hold
@onready var _cancel: Button = $Scroll/Box/Confirm/Cancel
@onready var _note: Label = $Scroll/Box/Note


func _ready() -> void:
	_resets.text = RESETS_TEXT
	_keeps.text = KEEPS_TEXT
	_confirm.visible = false
	_begin.pressed.connect(func() -> void:
		Sfx.play(&"ui_tap")
		_begin.visible = false
		_confirm.visible = true)
	_cancel.pressed.connect(_back_to_start)
	_hold.confirmed.connect(_on_confirmed)
	EventBus.prestige_available_changed.connect(func(_a: bool) -> void: refresh())
	EventBus.prestige_done.connect(_on_done)
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			refresh())


func refresh() -> void:
	_apply_preview(GameState.get_prestige_preview())


func _apply_preview(preview: Dictionary) -> void:
	var can: bool = bool(preview.get("can_prestige", false)) and not _busy
	var next_site: Dictionary = preview.get("next_site", {})
	_site.text = ("Next: %s" % String(next_site.get("name", ""))) if not next_site.is_empty() \
			else "No further sites yet"
	_gain.text = "+%s Fieldwork" % NumFormat.fmt(float(preview.get("fieldwork_gain", 0.0)))
	var bonus: String = String(preview.get("bonus_text", ""))
	_bonus.text = bonus
	_bonus.visible = bonus != ""
	_note.text = "" if can else "Keep digging - prestige unlocks once you've earned enough."
	_note.visible = not can
	_begin.disabled = not can
	if not can:
		_back_to_start()


func _back_to_start() -> void:
	_hold.disabled = false
	_confirm.visible = false
	_begin.visible = true


func _on_confirmed() -> void:
	if _busy:
		return
	_busy = true # no way to trigger twice: stays locked until prestige_done
	_hold.disabled = true
	_begin.disabled = true
	GameState.do_prestige()
	# Safety: if the core ignores the request, unlock after a moment.
	get_tree().create_timer(3.0).timeout.connect(_unlock_if_stuck)


func _unlock_if_stuck() -> void:
	if _busy:
		_busy = false
		refresh()


func _on_done(_info: Dictionary) -> void:
	_busy = false
	_back_to_start()
	refresh()
