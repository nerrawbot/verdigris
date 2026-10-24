extends Node
## Generative score and ambience. Slow pads drift between three chords; a
## pentatonic melody wanders on top and grows denser with every lantern lit.
## Wind, rain and the underwater hush follow where the player is.

const DIR := "res://assets/audio/"

var streams := {}
var pads: Array = []
var pad_idx := 0
var pad_timer := 30.0
var wind: AudioStreamPlayer
var rain: AudioStreamPlayer
var under: AudioStreamPlayer
var voices: Array = []
var voice_i := 0
var beat := 0.0
var deg := 5
var chime_timer := 14.0
var lit := 0
var lowpass: AudioEffectLowPassFilter
var master_idx := 0
var underwater := false
var muted_music := false
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	_setup_buses()
	var dir := DirAccess.open(DIR)
	if dir:
		for f in dir.get_files():
			if f.ends_with(".res"):
				streams[f.get_basename()] = load(DIR + f)
	for name in ["pad_a", "pad_b", "pad_c"]:
		var p := _player(name, "Music", -80.0)
		pads.append(p)
	wind = _player("wind", "Ambience", -80.0)
	rain = _player("rain", "Ambience", -80.0)
	under = _player("under", "Ambience", -80.0)
	for k in 12:
		var v := AudioStreamPlayer.new()
		v.bus = "SFX"
		add_child(v)
		voices.append(v)


func _setup_buses() -> void:
	for b in [["Music", 0.45], ["Ambience", 0.0], ["SFX", 0.25]]:
		if AudioServer.get_bus_index(b[0]) >= 0:
			continue
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, b[0])
		AudioServer.set_bus_send(i, "Master")
		if b[1] > 0.0:
			var rv := AudioEffectReverb.new()
			rv.room_size = 0.8
			rv.damping = 0.4
			rv.wet = b[1]
			rv.dry = 1.0
			AudioServer.add_bus_effect(i, rv)
	master_idx = AudioServer.get_bus_index("Master")
	lowpass = AudioEffectLowPassFilter.new()
	lowpass.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(master_idx, lowpass)


func _player(name: String, bus: String, vol: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = streams.get(name)
	p.bus = bus
	p.volume_db = vol
	add_child(p)
	if p.stream != null:
		p.play()
	return p


func play(name: String, vol_db := 0.0, pitch_var := 0.0) -> void:
	var s: AudioStream = streams.get(name)
	if s == null:
		return
	var v: AudioStreamPlayer = voices[voice_i]
	voice_i = (voice_i + 1) % voices.size()
	v.stream = s
	v.volume_db = vol_db
	v.pitch_scale = 1.0 + rng.randf_range(-pitch_var, pitch_var)
	v.play()


func lantern_lit(count: int) -> void:
	lit = count
	play("lantern", -4.0)
	for k in 3:
		get_tree().create_timer(0.35 + k * 0.28).timeout.connect(play.bind("chime_%d" % (k * 2 % 6), -10.0))


## openness 0..1 (sky above), rain 0..1, uw: camera underwater, night 0..1
func update_env(dt: float, openness: float, rain_amt: float, uw: bool, night: float, resting: bool) -> void:
	underwater = uw
	var target_cut := 700.0 if uw else 20000.0
	lowpass.cutoff_hz = lerpf(lowpass.cutoff_hz, target_cut, 1.0 - exp(-dt * (6.0 if uw else 3.0)))
	_fade(wind, lerpf(-30.0, -14.0, openness) + (-6.0 if uw else 0.0), dt)
	_fade(rain, -80.0 if rain_amt < 0.02 else lerpf(-34.0, -9.0, rain_amt * (0.35 + 0.65 * openness)), dt)
	_fade(under, -10.0 if uw else -80.0, dt * 2.0)
	# pads crossfade slowly between chords
	pad_timer -= dt
	if pad_timer <= 0.0:
		pad_timer = rng.randf_range(35.0, 55.0)
		pad_idx = (pad_idx + 1 + rng.randi_range(0, 1)) % pads.size()
	var base := -19.0 + minf(lit, 9) * 0.7 - night * 2.0
	if muted_music:
		base = -80.0
	for i in pads.size():
		_fade(pads[i], base if i == pad_idx else -60.0, dt * 0.25)
	# melody
	if muted_music:
		return
	beat -= dt
	if beat <= 0.0:
		beat = 0.55 if not resting else 0.9
		var p := 0.12 + 0.045 * lit
		if uw:
			p *= 0.5
		if rng.randf() < p:
			deg = clampi(deg + [-2, -1, -1, 1, 1, 2][rng.randi_range(0, 5)], 0, 10)
			if night > 0.6 and deg > 7:
				deg -= 2
			play("pluck_%d" % deg, -15.0 + minf(lit, 9) * 0.5 + rng.randf_range(-3.0, 0.0))
			if lit >= 5 and rng.randf() < 0.25:
				var harm := clampi(deg + 2, 0, 10)
				get_tree().create_timer(0.14).timeout.connect(play.bind("pluck_%d" % harm, -19.0))
	chime_timer -= dt
	if chime_timer <= 0.0:
		chime_timer = rng.randf_range(10.0, 26.0) / (1.0 + lit * 0.15)
		play("chime_%d" % rng.randi_range(0, 5), -21.0 + minf(lit, 9) * 0.6)


func _fade(p: AudioStreamPlayer, target: float, dt: float) -> void:
	p.volume_db = lerpf(p.volume_db, target, 1.0 - exp(-dt * 1.5))
