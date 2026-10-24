extends Resource
## Baked world: tile layers plus the placed objects. Written by tools/gen_world.gd.

@export var w := 0
@export var h := 0
@export var solid := PackedByteArray()        # material per tile (World.AIR/ROCK/CONC/METAL)
@export var back := PackedByteArray()         # back layer: 0 open, 1 rock, 2 built
@export var flags := PackedByteArray()        # World.F_* bits
@export var region := PackedByteArray()
@export var depth := PackedByteArray()        # solid: tiles to nearest air
@export var air_dist := PackedByteArray()     # air: tiles to nearest solid
@export var water_depth := PackedByteArray()  # water: rows below the surface + 1
@export var moss := PackedByteArray()
@export var sky := PackedByteArray()          # 255 = open to the sky (rain falls here)
@export var sun := PackedByteArray()          # sunlight reaching each tile along SUN_SLOPE
@export var start := Vector2i()
@export var objects: Array = []
