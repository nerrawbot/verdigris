extends Node2D
## An echo: a keeper's glyph scratched into the back wall. Reading it ([E])
## gives one line of the works' story. Lines are dealt out in order of reading,
## so the story always unfolds from the start wherever you wander first.

const LINES := [
	"They built the works to wash the rain. It came down grey, and left as rivers.",
	"Every lantern was a keeper's promise: while one burns, the pumps will turn.",
	"The city above went quiet one autumn. The works kept washing rain for no one.",
	"Moss came back first. It asked for nothing and covered everything.",
	"The keepers wove their nests in the warm places, for whoever came after.",
	"Springseeds remember the shape of the rain. Throw one, and it climbs toward the sky.",
	"Kites ride the warm breath of the vents. They were here before the works, and will be after.",
	"The trundlers graze on old paint. They are very slow, and never late.",
	"Down in the galleries the glimmers keep what light the water swallowed.",
	"The Spire was the tallest promise. From its crown you could see every lantern at once.",
	"Nothing here is broken. It is only resting, the way you rest.",
	"Small things fit through the cracks, and the cracks are where the light gets in.",
	"When all the lanterns sing, the works will remember what warmth was for.",
	"Take your time. The rain will come again, and it will be gentle.",
]

var id := 0
var read := false
var glow := 0.0
var t := 0.0
var seed_value := 0
var game: Node


func setup(tile: Vector2i, eid: int) -> void:
	id = eid
	seed_value = eid * 131 + 7
	position = Vector2((tile.x + 0.5) * 16.0, (tile.y + 1) * 16.0 - 18.0)
	z_index = -20


func interact_point() -> Vector2:
	return position + Vector2(0, 10)


func _process(dt: float) -> void:
	t += dt
	glow = move_toward(glow, 1.0 if read else 0.0, dt * 0.8)
	if game.near_camera(position, 800.0):
		queue_redraw()


func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var pulse := 0.5 + 0.5 * sin(t * 1.4 + id)
	var col := Color(0.55, 0.9, 0.8, 0.22 + 0.18 * pulse).lerp(Color(1.6, 1.3, 0.8, 0.9), glow)
	draw_circle(Vector2.ZERO, 16.0, Color(col.r, col.g, col.b, 0.05 + 0.05 * pulse), true, -1.0, true)
	draw_arc(Vector2.ZERO, 10.0, 0, TAU, 28, col, 1.4, true)
	# a few strokes, different for each echo
	for k in 4:
		var a := rng.randf() * TAU
		var r0 := rng.randf_range(0.0, 4.0)
		var r1 := rng.randf_range(6.0, 9.0)
		draw_line(Vector2(cos(a), sin(a)) * r0, Vector2(cos(a + rng.randf_range(-0.6, 0.6)), sin(a + rng.randf_range(-0.6, 0.6))) * r1, col, 1.2, true)
	draw_circle(Vector2(0, 0), 1.6, col, true, -1.0, true)
