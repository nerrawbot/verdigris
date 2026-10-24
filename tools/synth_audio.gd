extends SceneTree
## Synthesises every sound in the game into res://assets/audio/*.res (AudioStreamWAV).
## tools\godot.cmd --headless --script res://tools/synth_audio.gd

const OUT := "res://assets/audio/"
const SR := 44100
const SR_LOW := 22050
const PENTA := [0, 2, 4, 7, 9]   # major pentatonic
const ROOT := 50                  # D3

var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 4242
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var t0 := Time.get_ticks_msec()
	# loops
	_save("pad_a", _pad([midi(38), midi(45), midi(50), midi(54), midi(57), midi(64)], 24.0), SR_LOW, true)
	_save("pad_b", _pad([midi(35), midi(42), midi(47), midi(50), midi(54), midi(61)], 24.0), SR_LOW, true)
	_save("pad_c", _pad([midi(43), midi(50), midi(55), midi(59), midi(62), midi(66)], 24.0), SR_LOW, true)
	_save("wind", _wind(16.0), SR_LOW, true)
	_save("rain", _rain(12.0), SR_LOW, true)
	_save("under", _under(12.0), SR_LOW, true)
	print("loops done %d ms" % (Time.get_ticks_msec() - t0))
	# notes
	for k in 11:
		var m: int = ROOT + 12 * (k / 5) + PENTA[k % 5]
		_save("pluck_%d" % k, _pluck(midi(m), 3.2), SR, false)
	for k in 6:
		var m: int = ROOT + 24 + 12 * (k / 5) + PENTA[k % 5]
		_save("chime_%d" % k, _bell(midi(m), 4.5), SR, false)
	print("notes done %d ms" % (Time.get_ticks_msec() - t0))
	# effects
	_save("step", _step(), SR, false)
	_save("jump", _jump(), SR, false)
	_save("land", _land(), SR, false)
	_save("splash", _splash(), SR, false)
	_save("pop", _pop(), SR, false)
	_save("grow", _grow(), SR, false)
	_save("throw", _throw(), SR, false)
	_save("chirp", _chirp(), SR, false)
	_save("flutter", _flutter(), SR, false)
	_save("hum", _hum(), SR, false)
	_save("lantern", _lantern(), SR, false)
	_save("drip", _drip(), SR, false)
	_save("grab", _grab(), SR, false)
	print("all done %d ms" % (Time.get_ticks_msec() - t0))
	quit()


static func midi(m: int) -> float:
	return 440.0 * pow(2.0, (m - 69) / 12.0)


func _save(name: String, s: PackedFloat32Array, rate: int, loop: bool) -> void:
	var peak := 0.0001
	for v in s:
		peak = maxf(peak, absf(v))
	var gain := 0.85 / peak
	var bytes := PackedByteArray()
	bytes.resize(s.size() * 2)
	for i in s.size():
		bytes.encode_s16(i * 2, int(clampf(s[i] * gain, -1.0, 1.0) * 32767.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = rate
	st.stereo = false
	st.data = bytes
	if loop:
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = s.size()
	ResourceSaver.save(st, OUT + name + ".res")


func _env(t: float, a: float, d: float) -> float:
	if t < a:
		return t / a
	return exp(-(t - a) / d)


# ------------------------------------------------------------ loops

func _pad(freqs: Array, dur: float) -> PackedFloat32Array:
	var n := int(dur * SR_LOW)
	var s := PackedFloat32Array()
	s.resize(n)
	s.fill(0.0)
	for fi in freqs.size():
		var base: float = freqs[fi]
		for det in [-1.0, 1.0]:
			var f := roundf(base * (1.0 + det * 0.0025) * dur) / dur
			var lfo_f := roundf((0.05 + fi * 0.017) * dur) / dur
			var ph := rng.randf() * TAU
			var amp := 1.0 / (1.0 + fi * 0.35)
			var w := TAU * f / SR_LOW
			var wl := TAU * lfo_f / SR_LOW
			var f2 := roundf(base * 2.0 * dur) / dur
			var w2 := TAU * f2 / SR_LOW
			for i in n:
				var lfo := 0.55 + 0.45 * sin(wl * i + ph)
				s[i] += (sin(w * i + ph) + 0.18 * sin(w2 * i + ph * 1.3)) * amp * lfo
	return s


func _crossfade_loop(s: PackedFloat32Array, fade: int) -> PackedFloat32Array:
	var n := s.size() - fade
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = s[i]
	for i in fade:
		var t := float(i) / fade
		out[i] = out[i] * t + s[n + i] * (1.0 - t)
	return out


func _wind(dur: float) -> PackedFloat32Array:
	var fade := int(2.0 * SR_LOW)
	var n := int(dur * SR_LOW) + fade
	var s := PackedFloat32Array()
	s.resize(n)
	var b := 0.0
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / SR_LOW
		b = b * 0.995 + rng.randf_range(-1.0, 1.0) * 0.1
		var gust := 0.5 + 0.3 * sin(t * 0.37) + 0.2 * sin(t * 0.91 + 1.0)
		var cut := 0.02 + 0.03 * gust
		lp += (b - lp) * cut
		lp2 += (lp - lp2) * cut
		s[i] = lp2 * gust
	return _crossfade_loop(s, fade)


func _rain(dur: float) -> PackedFloat32Array:
	var fade := int(1.5 * SR_LOW)
	var n := int(dur * SR_LOW) + fade
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var hp := 0.0
	var b0 := 0.0
	for i in n:
		var w := rng.randf_range(-1.0, 1.0)
		b0 = b0 * 0.97 + w * 0.3
		lp += (w - lp) * 0.35
		hp = lp - b0 * 0.5
		s[i] = hp * 0.5 + b0 * 0.25
	# droplets
	for k in int(dur * 140):
		var at := rng.randi_range(0, n - 2000)
		var f := rng.randf_range(1800.0, 4800.0)
		var a := rng.randf_range(0.05, 0.3)
		for j in 900:
			s[at + j] += sin(TAU * f * j / SR_LOW * (1.0 - j / 3000.0)) * a * exp(-j / 120.0)
	return _crossfade_loop(s, fade)


func _under(dur: float) -> PackedFloat32Array:
	var fade := int(1.5 * SR_LOW)
	var n := int(dur * SR_LOW) + fade
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.012
		lp2 += (lp - lp2) * 0.012
		s[i] = lp2 * 8.0
	for k in int(dur * 2.5):
		var at := rng.randi_range(0, n - 6000)
		var f := rng.randf_range(300.0, 700.0)
		for j in 5000:
			var tt := float(j) / SR_LOW
			s[at + j] += sin(TAU * f * tt * (1.0 + tt * 3.0)) * 0.15 * exp(-tt * 25.0)
	return _crossfade_loop(s, fade)


# ------------------------------------------------------------ notes

func _pluck(f: float, dur: float) -> PackedFloat32Array:
	var n := int(dur * SR)
	var period := int(SR / f)
	var buf := PackedFloat32Array()
	buf.resize(period)
	var lp := 0.0
	for i in period:
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.5
		buf[i] = lp
	var s := PackedFloat32Array()
	s.resize(n)
	var idx := 0
	var prev := 0.0
	for i in n:
		var cur := buf[idx]
		var nv := (cur + prev) * 0.4985
		prev = cur
		buf[idx] = nv
		idx = (idx + 1) % period
		var t := float(i) / SR
		# a warm sine body under the string, like a kalimba tine
		s[i] = cur * 0.6 + sin(TAU * f * t) * 0.7 * exp(-t * 1.6) * minf(1.0, t * 400.0)
	return s


func _bell(f: float, dur: float) -> PackedFloat32Array:
	var n := int(dur * SR)
	var s := PackedFloat32Array()
	s.resize(n)
	var partials := [[1.0, 1.0, 2.2], [2.0, 0.5, 1.4], [2.76, 0.35, 0.9], [4.07, 0.2, 0.6], [5.4, 0.12, 0.4]]
	for p in partials:
		var w := TAU * f * float(p[0]) / SR
		var amp: float = p[1]
		var dec: float = p[2]
		for i in n:
			var t := float(i) / SR
			s[i] += sin(w * i) * amp * exp(-t / dec) * minf(1.0, t * 300.0)
	return s


# ------------------------------------------------------------ effects

func _noise_burst(dur: float, cut: float, decay: float) -> PackedFloat32Array:
	var n := int(dur * SR)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		lp += (rng.randf_range(-1.0, 1.0) - lp) * cut
		s[i] = lp * exp(-t / decay)
	return s


func _step() -> PackedFloat32Array:
	var s := _noise_burst(0.07, 0.25, 0.012)
	for i in s.size():
		var t := float(i) / SR
		s[i] += sin(TAU * 140.0 * t) * exp(-t / 0.015) * 0.3
	return s


func _jump() -> PackedFloat32Array:
	var n := int(0.18 * SR)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		var cut := 0.05 + t * 1.5
		lp += (rng.randf_range(-1.0, 1.0) - lp) * cut
		s[i] = lp * sin(PI * t / 0.18) * 0.6 + sin(TAU * (600.0 + t * 1800.0) * t) * 0.08 * exp(-t / 0.05)
	return s


func _land() -> PackedFloat32Array:
	var s := _noise_burst(0.18, 0.08, 0.04)
	for i in s.size():
		var t := float(i) / SR
		s[i] += sin(TAU * (95.0 - t * 120.0) * t) * exp(-t / 0.05) * 0.9
	return s


func _splash() -> PackedFloat32Array:
	var n := int(0.9 * SR)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		lp += (rng.randf_range(-1.0, 1.0) - lp) * (0.4 - t * 0.35)
		s[i] = lp * exp(-t / 0.18) * minf(1.0, t * 80.0)
	for k in 9:
		var at := rng.randi_range(int(0.05 * SR), int(0.6 * SR))
		var f := rng.randf_range(500.0, 1300.0)
		for j in 3000:
			if at + j >= n:
				break
			var tt := float(j) / SR
			s[at + j] += sin(TAU * f * tt * (1.0 + tt * 6.0)) * 0.25 * exp(-tt * 40.0)
	return s


func _pop() -> PackedFloat32Array:
	var n := int(0.16 * SR)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / SR
		ph += TAU * (380.0 + 1400.0 * t / 0.16) / SR
		s[i] = sin(ph) * exp(-t / 0.05) * minf(1.0, t * 500.0)
	return s


func _grow() -> PackedFloat32Array:
	var n := int(1.1 * SR)
	var s := PackedFloat32Array()
	s.resize(n)
	for k in 70:
		var at := rng.randi_range(0, n - 1500)
		var a := rng.randf_range(0.1, 0.5) * (1.0 - float(at) / n * 0.6)
		var lp := 0.0
		for j in 1200:
			lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.6
			s[at + j] += lp * a * exp(-j / 200.0)
	for i in n:
		var t := float(i) / SR
		s[i] += sin(TAU * (220.0 + t * 260.0) * t) * 0.12 * sin(PI * t / 1.1)
	return s


func _throw() -> PackedFloat32Array:
	var n := int(0.22 * SR)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		lp += (rng.randf_range(-1.0, 1.0) - lp) * (0.3 - t)
		s[i] = lp * sin(PI * t / 0.22)
	return s


func _chirp() -> PackedFloat32Array:
	var n := int(0.32 * SR)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / SR
		var f := 1500.0 + 700.0 * sin(t * 40.0) if t < 0.14 else 2100.0 - (t - 0.14) * 2000.0
		ph += TAU * f / SR
		var e := minf(1.0, t * 200.0) * (exp(-t / 0.09) if t < 0.14 else exp(-(t - 0.14) / 0.06) * 0.8)
		s[i] = sin(ph + sin(ph * 2.0) * 0.5) * e
	return s


func _flutter() -> PackedFloat32Array:
	var n := int(0.5 * SR)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.15
		s[i] = lp * maxf(0.0, sin(TAU * 14.0 * t)) * sin(PI * t / 0.5)
	return s


func _hum() -> PackedFloat32Array:
	var n := int(1.4 * SR)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / SR
		var f := 110.0 * (1.0 + 0.01 * sin(TAU * 5.0 * t))
		var e := sin(PI * t / 1.4)
		s[i] = (sin(TAU * f * t) + 0.5 * sin(TAU * f * 2.0 * t) + 0.25 * sin(TAU * f * 3.0 * t)) * e
	return s


func _lantern() -> PackedFloat32Array:
	var n := int(3.5 * SR)
	var s := PackedFloat32Array()
	s.resize(n)
	var notes := [62, 66, 69, 74, 78]
	for k in notes.size():
		var f := midi(notes[k])
		var at := int(k * 0.12 * SR)
		for i in range(at, n):
			var t := float(i - at) / SR
			s[i] += (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.76 * t) * exp(-t / 0.5)) * exp(-t / 1.4) * minf(1.0, t * 300.0) * 0.5
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.03
		s[i] += lp * 1.2 * sin(PI * minf(t / 1.2, 1.0)) * exp(-t / 1.0)
	return s


func _drip() -> PackedFloat32Array:
	var n := int(0.25 * SR)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / SR
		ph += TAU * (1900.0 - 1100.0 * minf(t / 0.05, 1.0)) / SR
		s[i] = sin(ph) * exp(-t / 0.04) * minf(1.0, t * 2000.0)
	return s


func _grab() -> PackedFloat32Array:
	var s := _noise_burst(0.06, 0.5, 0.01)
	for i in s.size():
		var t := float(i) / SR
		s[i] = s[i] * 0.5 + sin(TAU * 820.0 * t) * exp(-t / 0.012) * 0.4
	return s
