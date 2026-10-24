# Verdigris

A quiet 2D wander through the overgrown underworks of a dead waterworks, in the spirit of Rain World but gentler: nothing hunts you, falls don't hurt, and you can grow your own paths. Godot 4.7. All art is procedural shaders and meshes, apart from the far skyline, which is rendered in Blender. All audio is synthesised.

## Playing
Open the folder in Godot 4.7 and press Play, or run:

    D:\Godot\Godot_v4.7.2-stable_win64.exe --path D:\Godot\w.Claude\verdigris

| | |
|---|---|
| A D / arrows | wander |
| Space | jump (hold for height). Wall-jump off any wall. Underwater: a swim dash |
| W / S | climb poles and vines. Hold W to grab a pole. Push into rough rock, or press W beside it, to cling and climb (smooth concrete is too slick). Standing still, hold to peek up/down |
| E | pick springseeds, grab a drift-kite to glide, sing to a lantern, read an echo, hum to a trundler |
| Q | call out. The nearest sleeping lantern answers with a chime, and a mote of light drifts its way |
| F / left click | throw a springseed. It grows a climbable vine wherever it lands (kelp underwater) |
| hold S at a nest or lit lantern | rest: saves, time drifts by. While resting, M lets you dream-travel to any found nest or lit lantern |
| M / Tab / Esc | map / lantern count / pause (controls and "begin again") |

14 echoes (glyphs in the back walls) tell the works' story a line at a time, in the order you find them. There are 9 old lanterns across 5 regions: the Hollows, the Pipeworks, the Canopy, the Sunken Galleries and the Spire. Each one you wake adds a voice to the music. When all nine sing, the works remember warmth. Days take 15 minutes, and rain comes and goes.

## How it's built
- `tools/gen_world.gd` generates the world and bakes it to `assets/world/world.res` (seed 1207).
  - A 10×8 cell grid of rooms (caves, multi-level halls, shafts, canopy) plus an open valley with the Spire, joined by a spanning tree plus extra loops. Everything below row 204 is flooded.
  - A movement model (walk, jump 4 tiles, climb rock, poles, swim) checks the map in both directions and adds poles until every floor can be reached **and left again** (`round trip N, traps 0`).
  - It also writes `shots/world_map.png`.
  - It bakes a sunlight map (`sun`, 4 cells per tile): parallel rays slanting down-right from every opening onto the outside, stopped by stone and dimmed by water. The shaders sharpen it with a short march (`sun_at` in `shaders/common.gdshaderinc`) to light back walls, rim sunlit edges and draw shafts with drifting dust (`atmos.gdshader`).
- `scripts/game.gd` builds everything at runtime:
  - `terrain_view.gd`: 512 px chunks with the back / front / water shaders, plus foliage and pole meshes.
  - `backdrop.gd`: the far parallax layers.
  - `player.gd`: custom tile physics, procedural body.
  - `obj/*`: plants, seeds, vines, lanterns, nests, kites, trundlers, glimmer fish, vents.
  - `weather.gd`, `audio.gd` (generative music), `hud.gd`, `map_view.gd`.
  - `shaders/grade.gdshader` (canvas layer 5): split toning, film curve, lifted blacks, vignette and grain. Each region has its own light and shadow tint (`LIGHT_TINT` / `SHADE_TINT` in game.gd).
  - `foreground.gd`: sparse dark vines, chains and cables in front of everything, with parallax 1.15.
- `tools/synth_audio.gd` synthesises every sound into `assets/audio/*.res`.
- `art_src/backdrops.py` renders the megastructure skyline in background Blender:
  `D:\Blender\blender.exe --background --factory-startup --python art_src/backdrops.py`, then `tools/crop_backdrops.gd`, then `--import`.
  Keep `process/fix_alpha_border=false` in the backdrop `.import` files.

## Checks
    tools\godot.cmd --headless --script res://tools/check.gd                  # every script compiles
    tools\godot.cmd --headless res://scenes/game.tscn -- --walktest            # 26 movement and interaction checks
    tools\godot.cmd res://scenes/game.tscn -- --shots [only=name,closeups,ui,bench]

Last run: walk test 26/26 passed. The bench averaged about 8 ms per frame at 1600×900 (worst view 10 ms).
