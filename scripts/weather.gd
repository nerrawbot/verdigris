extends Node
## Time of day and rain. Everything that changes with the light reads from here.

const DAY_LENGTH := 900.0   # seconds for a full day

var t_day := 0.3            # 0 midnight, 0.25 morning, 0.5 noon, 0.75 dusk
var time_scale := 1.0
var rain := 0.0             # 0..1 current intensity
var rain_target := 0.0
var next_rain := 150.0
var rain_left := 0.0
var rng := RandomNumberGenerator.new()

# outputs, refreshed each frame
var ambient := Color.WHITE
var sky_top := Color.WHITE
var sky_horizon := Color.WHITE
var sun_col := Color.WHITE
var sun_amount := 0.5
var star_amount := 0.0
var sky_tint := Color.WHITE
var night := 0.0            # 0 day .. 1 deep night
var wind := 0.15

const KEYS := [
	# t, ambient, sky top, horizon, sun colour, sun amount
	[0.00, Color(0.30, 0.33, 0.48), Color(0.02, 0.03, 0.08), Color(0.09, 0.11, 0.2), Color(0.6, 0.7, 1.0), 0.25],
	[0.20, Color(0.34, 0.36, 0.5), Color(0.05, 0.07, 0.15), Color(0.2, 0.2, 0.32), Color(0.8, 0.7, 0.9), 0.2],
	[0.27, Color(0.72, 0.6, 0.6), Color(0.3, 0.36, 0.55), Color(0.98, 0.66, 0.48), Color(1.0, 0.7, 0.45), 0.8],
	[0.36, Color(0.86, 0.86, 0.86), Color(0.36, 0.52, 0.74), Color(0.82, 0.86, 0.9), Color(1.0, 0.95, 0.85), 0.55],
	[0.64, Color(0.88, 0.87, 0.84), Color(0.38, 0.54, 0.76), Color(0.85, 0.87, 0.88), Color(1.0, 0.93, 0.8), 0.55],
	[0.75, Color(0.76, 0.56, 0.5), Color(0.3, 0.27, 0.48), Color(1.0, 0.56, 0.36), Color(1.0, 0.55, 0.3), 0.9],
	[0.83, Color(0.38, 0.38, 0.54), Color(0.05, 0.06, 0.14), Color(0.2, 0.17, 0.3), Color(0.7, 0.6, 0.9), 0.25],
	[1.00, Color(0.30, 0.33, 0.48), Color(0.02, 0.03, 0.08), Color(0.09, 0.11, 0.2), Color(0.6, 0.7, 1.0), 0.25],
]


func _ready() -> void:
	rng.randomize()


func step(dt: float) -> void:
	t_day = fposmod(t_day + dt * time_scale / DAY_LENGTH, 1.0)
	# rain schedule
	if rain_left > 0.0:
		rain_left -= dt * time_scale
		if rain_left <= 0.0:
			rain_target = 0.0
			next_rain = rng.randf_range(180.0, 360.0)
	else:
		next_rain -= dt * time_scale
		if next_rain <= 0.0:
			rain_target = rng.randf_range(0.5, 1.0)
			rain_left = rng.randf_range(70.0, 140.0)
	rain = move_toward(rain, rain_target, dt * time_scale / 25.0)
	_evaluate()


func _evaluate() -> void:
	var a: Array = KEYS[0]
	var b: Array = KEYS[1]
	for i in KEYS.size() - 1:
		if t_day >= KEYS[i][0] and t_day <= KEYS[i + 1][0]:
			a = KEYS[i]
			b = KEYS[i + 1]
			break
	var f: float = (t_day - a[0]) / maxf(b[0] - a[0], 0.0001)
	f = f * f * (3.0 - 2.0 * f)
	ambient = (a[1] as Color).lerp(b[1], f)
	sky_top = (a[2] as Color).lerp(b[2], f)
	sky_horizon = (a[3] as Color).lerp(b[3], f)
	sun_col = (a[4] as Color).lerp(b[4], f)
	sun_amount = lerpf(a[5], b[5], f)
	night = clampf(1.0 - (ambient.get_luminance() - 0.34) / 0.5, 0.0, 1.0)
	star_amount = clampf((night - 0.5) * 2.0, 0.0, 1.0) * (1.0 - rain)
	# rain greys everything and cools it
	var grey := Color(0.55, 0.6, 0.66)
	ambient = ambient.lerp(ambient * Color(0.78, 0.82, 0.92), rain)
	sky_top = sky_top.lerp(grey * (1.0 - night * 0.8), rain * 0.75)
	sky_horizon = sky_horizon.lerp(grey * 1.1 * (1.0 - night * 0.75), rain * 0.7)
	sun_amount *= 1.0 - rain * 0.85
	sky_tint = Color(1, 1, 1).lerp(sky_horizon * 1.2, 0.35)
	wind = 0.15 + rain * 0.6


func is_night() -> bool:
	return night > 0.6
