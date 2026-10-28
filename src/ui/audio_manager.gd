extends Node
## Audio autoload. Buses: Master / SFX / Music. Everything has a toggle path (sound, music).
## One-shots use a small player pool; the brush loop follows swipe speed and decays on its own.

const BUS_SFX: StringName = &"SFX"
const BUS_MUSIC: StringName = &"Music"
const SOUND_DIR: String = "res://assets/audio/"
const KEY_SOUND: String = "sound"
const KEY_MUSIC: String = "music"
const POOL_SIZE: int = 8
const SPEED_MAX: float = 3000.0 # canvas px/s that maps to full brush volume
const BRUSH_GAIN: float = 0.5
const BRUSH_PITCH_LOW: float = 0.8
const BRUSH_PITCH_HIGH: float = 1.5
const BRUSH_ATTACK: float = 10.0 # volume slew per second (smooth, no pops)
const BRUSH_DECAY: float = 3.5 # target falloff per second when no swipe events arrive
const SILENCE: float = 0.001
const COIN_STREAK_MSEC: int = 600
const COIN_PITCH_STEP: float = 0.05
const COIN_STREAK_MAX: int = 14
const MUSIC_DB: float = -14.0
const MUSIC_FADE: float = 1.5
const BUS_MUSIC_DB: float = -4.0

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _pool_i: int = 0
var _loop: AudioStreamPlayer
var _music: AudioStreamPlayer
var _brush_target: float = 0.0
var _brush_level: float = 0.0
var _streak: int = 0
var _last_coin_msec: int = -100000
var _music_tween: Tween
var _suspended: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus(BUS_SFX, 0.0)
	_ensure_bus(BUS_MUSIC, BUS_MUSIC_DB)
	for i in POOL_SIZE:
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.bus = BUS_SFX
		add_child(p)
		_pool.append(p)
	_loop = AudioStreamPlayer.new()
	_loop.bus = BUS_SFX
	_loop.stream = _get_stream(&"brush_loop", true)
	add_child(_loop)
	_music = AudioStreamPlayer.new()
	_music.bus = BUS_MUSIC
	_music.stream = _get_stream(&"music_loop", true)
	_music.volume_db = -60.0
	add_child(_music)
	set_process(false)
	_apply_toggles()


func _exit_tree() -> void:
	_music.stop() # release the playback so shutdown is clean
	_loop.stop()
	for p in _pool:
		p.stop()
		p.stream = null
	_music.stream = null
	_loop.stream = null
	_streams.clear()


func is_sound_on() -> bool:
	return SettingsStore.get_bool(KEY_SOUND, true)


func is_music_on() -> bool:
	return SettingsStore.get_bool(KEY_MUSIC, true)


func set_sound_on(on: bool) -> void:
	SettingsStore.set_bool(KEY_SOUND, on)
	if not on:
		brush_stop()
		_loop.stop()
	_apply_toggles()


func set_music_on(on: bool) -> void:
	SettingsStore.set_bool(KEY_MUSIC, on)
	_apply_toggles()


func play(sound: StringName, pitch: float = 1.0) -> void:
	if not is_sound_on() or _suspended:
		return
	var s: AudioStream = _get_stream(sound, false)
	if s == null:
		return
	var p: AudioStreamPlayer = _pool[_pool_i]
	_pool_i = (_pool_i + 1) % POOL_SIZE
	p.stream = s
	p.pitch_scale = pitch
	p.play()


## Coin tick whose pitch climbs with a streak of quick successive ticks.
func coin_tick() -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_coin_msec > COIN_STREAK_MSEC:
		_streak = 0
	_last_coin_msec = now
	play(&"coin_tick", 1.0 + COIN_PITCH_STEP * float(mini(_streak, COIN_STREAK_MAX)))
	_streak += 1


func brush_move(speed: float) -> void:
	if not is_sound_on() or _suspended:
		return
	_brush_target = maxf(_brush_target, clampf(speed / SPEED_MAX, 0.0, 1.0))
	if not _loop.playing:
		_brush_level = 0.0
		_loop.volume_db = linear_to_db(SILENCE)
		_loop.play()
	_loop.pitch_scale = lerpf(BRUSH_PITCH_LOW, BRUSH_PITCH_HIGH, clampf(speed / SPEED_MAX, 0.0, 1.0))
	set_process(true)


func brush_stop() -> void:
	_brush_target = 0.0


func _process(delta: float) -> void:
	_brush_target = move_toward(_brush_target, 0.0, BRUSH_DECAY * delta)
	_brush_level = move_toward(_brush_level, _brush_target, BRUSH_ATTACK * delta)
	_loop.volume_db = linear_to_db(maxf(_brush_level * BRUSH_GAIN, SILENCE))
	if _brush_level <= SILENCE and _brush_target <= SILENCE:
		_loop.stop()
		set_process(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_suspend(true)
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_suspend(false)


func _suspend(on: bool) -> void:
	_suspended = on
	_music.stream_paused = on
	_loop.stream_paused = on
	for p in _pool:
		p.stream_paused = on
	if on:
		brush_stop()


func _apply_toggles() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index(BUS_SFX), not is_sound_on())
	AudioServer.set_bus_mute(AudioServer.get_bus_index(BUS_MUSIC), not is_music_on())
	if _music_tween != null:
		_music_tween.kill()
	if is_music_on():
		if not _music.playing:
			_music.volume_db = -60.0
			_music.play()
		_music_tween = create_tween()
		_music_tween.tween_property(_music, "volume_db", MUSIC_DB, MUSIC_FADE)
	elif _music.playing:
		_music.stop()


func _ensure_bus(bus_name: StringName, volume_db: float) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var idx: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, &"Master")
	AudioServer.set_bus_volume_db(idx, volume_db)


func _get_stream(sound: StringName, looped: bool) -> AudioStream:
	if _streams.has(sound):
		return _streams[sound]
	var path: String = SOUND_DIR + String(sound) + ".wav"
	if not ResourceLoader.exists(path):
		return null
	var s: AudioStream = load(path) as AudioStream
	if looped and s is AudioStreamWAV:
		var w: AudioStreamWAV = s
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = w.data.size() / 2 # 16-bit mono
	_streams[sound] = s
	return s
