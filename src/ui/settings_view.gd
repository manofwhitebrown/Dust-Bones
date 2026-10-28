class_name SettingsView
extends Control
## Modal settings: sound, music, haptics, two-step erase, version. Persists via SettingsStore.

signal closed

const BOOL_KEYS_TO_RESET: PackedStringArray = ["tut_brush", "tut_digger", "tut_museum"]
const STRING_KEYS_TO_RESET: PackedStringArray = ["museum_new"]
const ROW_H: float = 128.0
const FADE: float = 0.18

var _erase_confirm: Control

@onready var _sheet: PanelContainer = $Sheet
@onready var _sound: CheckButton = $Sheet/Box/Sound
@onready var _music: CheckButton = $Sheet/Box/Music
@onready var _haptics: CheckButton = $Sheet/Box/Haptics
@onready var _erase: Button = $Sheet/Box/Erase
@onready var _confirm_box: VBoxContainer = $Sheet/Box/ConfirmBox
@onready var _hold: HoldButton = $Sheet/Box/ConfirmBox/Hold
@onready var _cancel: Button = $Sheet/Box/ConfirmBox/Cancel
@onready var _version: Label = $Sheet/Box/Version
@onready var _close: Button = $Sheet/Box/Close


func _ready() -> void:
	visible = false
	_confirm_box.visible = false
	_version.text = "Dust & Bones  v%s" % String(ProjectSettings.get_setting("application/config/version", "0"))
	_sound.toggled.connect(func(on: bool) -> void: AudioManager.set_sound_on(on))
	_music.toggled.connect(func(on: bool) -> void: AudioManager.set_music_on(on))
	_haptics.toggled.connect(func(on: bool) -> void: SettingsStore.set_bool(Haptics.KEY, on))
	_erase.pressed.connect(func() -> void:
		_erase.visible = false
		_confirm_box.visible = true)
	_cancel.pressed.connect(_reset_confirm)
	_hold.confirmed.connect(_do_erase)
	_close.pressed.connect(close)
	$Dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventScreenTouch and (e as InputEventScreenTouch).pressed:
			close())


func open() -> void:
	_sound.set_pressed_no_signal(AudioManager.is_sound_on())
	_music.set_pressed_no_signal(AudioManager.is_music_on())
	_haptics.set_pressed_no_signal(Haptics.enabled())
	_reset_confirm()
	modulate.a = 0.0
	visible = true
	create_tween().tween_property(self, "modulate:a", 1.0, FADE)


func close() -> void:
	if not visible:
		return
	_reset_confirm()
	var tw: Tween = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, FADE)
	tw.tween_callback(hide)
	closed.emit()


func _reset_confirm() -> void:
	_erase.visible = true
	_confirm_box.visible = false


func _do_erase() -> void:
	_hold.disabled = true # a held button can only fire once
	GameState.reset_all_data()
	for k: String in BOOL_KEYS_TO_RESET:
		SettingsStore.set_bool(k, false)
	for k: String in STRING_KEYS_TO_RESET:
		SettingsStore.set_string(k, "")
	get_tree().reload_current_scene()
