"""Renders the far parallax layers of Verdigris: ruined megastructures, rendered
grey with alpha so Godot can tint them by time of day and fog.

Run in the background (it builds its own scene and never saves a .blend):
    D:\\Blender\\blender.exe --background --factory-startup --python art_src/backdrops.py
Writes assets/backdrop/{far,mid,near}.png (4096 x 2048).
"""
import bpy
import bmesh
import math
import os
import random
from mathutils import Matrix, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "backdrop")
W_BU = 40.0     # scene width in blender units (= image width)
H_BU = 20.0
DEPTH_BUCKETS = 3


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


class Builder:
    """Accumulates geometry into one bmesh per depth bucket."""

    def __init__(self):
        self.bms = [bmesh.new() for _ in range(DEPTH_BUCKETS)]

    def bm(self, y):
        return self.bms[min(DEPTH_BUCKETS - 1, max(0, int(y / 6.0)))]

    def box(self, x, y, z0, w, d, h, rot=0.0):
        m = Matrix.Translation((x, y, z0 + h / 2)) @ Matrix.Rotation(rot, 4, "Y") @ Matrix.Diagonal((w, d, h, 1))
        bmesh.ops.create_cube(self.bm(y), size=1.0, matrix=m)

    def beam(self, a, b, t, y):
        a = Vector((a[0], y, a[1]))
        b = Vector((b[0], y, b[1]))
        d = b - a
        length = d.length
        if length < 1e-4:
            return
        ang = math.atan2(d.x, d.z)
        m = Matrix.Translation((a + b) / 2) @ Matrix.Rotation(ang, 4, "Y") @ Matrix.Diagonal((t, t, length, 1))
        bmesh.ops.create_cube(self.bm(y), size=1.0, matrix=m)

    def cyl(self, x, y, z0, r, h, segs=16, r2=None):
        m = Matrix.Translation((x, y, z0 + h / 2))
        bmesh.ops.create_cone(self.bm(y), cap_ends=True, segments=segs, radius1=r, radius2=r if r2 is None else r2, depth=h, matrix=m)

    def hcyl(self, x0, x1, y, z, r, segs=14):
        m = Matrix.Translation(((x0 + x1) / 2, y, z)) @ Matrix.Rotation(math.pi / 2, 4, "Y")
        bmesh.ops.create_cone(self.bm(y), cap_ends=True, segments=segs, radius1=r, radius2=r, depth=abs(x1 - x0), matrix=m)

    def sphere(self, x, y, z, r):
        m = Matrix.Translation((x, y, z))
        bmesh.ops.create_uvsphere(self.bm(y), u_segments=20, v_segments=12, radius=r, matrix=m)

    def blob(self, x, y, z, r):
        m = Matrix.Translation((x, y, z)) @ Matrix.Diagonal((1.0, 0.6, 0.8, 1))
        bmesh.ops.create_icosphere(self.bm(y), subdivisions=2, radius=r, matrix=m)

    def finish(self, name):
        objs = []
        for i, bm in enumerate(self.bms):
            if len(bm.verts) == 0:
                continue
            me = bpy.data.meshes.new(f"{name}_{i}")
            bm.to_mesh(me)
            bm.free()
            ob = bpy.data.objects.new(f"{name}_{i}", me)
            bpy.context.scene.collection.objects.link(ob)
            mat = bpy.data.materials.new(f"M_{name}_{i}")
            mat.use_nodes = True
            bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
            v = 0.62 + 0.14 * i     # further back = paler, as if through haze
            bsdf.inputs["Base Color"].default_value = (v, v, v * 1.02, 1)
            bsdf.inputs["Roughness"].default_value = 0.9
            me.materials.append(mat)
            objs.append(ob)
        return objs


# ---------------------------------------------------------------- structures

def tower(b, x, y, w, h, rng):
    z = 0.0
    tw = w
    tiers = rng.randint(1, 4)
    for t in range(tiers):
        th = h / tiers * rng.uniform(0.7, 1.2)
        b.box(x, y, z, tw, tw * 0.8, th)
        # window bands and ledges
        for k in range(int(th / 0.6)):
            b.box(x, y - tw * 0.41, z + k * 0.6 + 0.3, tw * 1.04, 0.05, 0.06)
        z += th
        tw *= rng.uniform(0.55, 0.85)
    if rng.random() < 0.7:
        ah = rng.uniform(1.0, 4.0)
        b.cyl(x, y, z, 0.05, ah, 6)
        for k in range(3):
            b.box(x, y, z + ah * (0.3 + k * 0.2), 0.6 - k * 0.15, 0.04, 0.04)
    if rng.random() < 0.5:
        # broken top: a jagged crown
        for k in range(4):
            b.box(x + rng.uniform(-tw, tw) * 0.4, y, z, tw * 0.2, tw * 0.5, rng.uniform(0.2, 1.0))
    return z


def cooling_tower(b, x, y, r, h):
    rings = 10
    for k in range(rings):
        t0 = k / rings
        t1 = (k + 1) / rings
        r0 = r * (1.0 - 0.35 * math.sin(math.pi * t0 * 0.85))
        r1 = r * (1.0 - 0.35 * math.sin(math.pi * t1 * 0.85))
        b.cyl(x, y, h * t0, r0, h / rings, 24, r1)


def tank(b, x, y, r, z, rng):
    b.sphere(x, y, z, r)
    for k in range(4):
        a = k * math.pi / 2 + 0.4
        b.beam((x + math.cos(a) * r * 0.8, 0.0), (x + math.cos(a) * r * 0.6, z), 0.08, y)
    b.cyl(x, y, z + r * 0.9, 0.05, r * 0.8, 6)


def truss(b, x0, x1, z, hgt, y, t=0.05):
    b.beam((x0, z), (x1, z), t, y)
    b.beam((x0, z + hgt), (x1, z + hgt), t, y)
    n = max(2, int(abs(x1 - x0) / hgt))
    for k in range(n + 1):
        xa = x0 + (x1 - x0) * k / n
        b.beam((xa, z), (xa, z + hgt), t * 0.8, y)
        if k < n:
            xb = x0 + (x1 - x0) * (k + 1) / n
            b.beam((xa, z), (xb, z + hgt), t * 0.6, y)


def lattice_pylon(b, x, y, w, h):
    b.beam((x - w / 2, 0), (x - w * 0.1, h), 0.07, y)
    b.beam((x + w / 2, 0), (x + w * 0.1, h), 0.07, y)
    k = 0.0
    while k < h - 0.3:
        f0 = k / h
        f1 = min(1.0, (k + 0.8) / h)
        b.beam((x - w / 2 * (1 - f0 * 0.8), k), (x + w / 2 * (1 - f1 * 0.8), k + 0.8), 0.04, y)
        b.beam((x + w / 2 * (1 - f0 * 0.8), k), (x - w / 2 * (1 - f1 * 0.8), k + 0.8), 0.04, y)
        k += 0.8
    b.box(x, y, h, w * 0.9, 0.1, 0.08)


def chain(b, x, y, z_top, length):
    z = z_top
    while z > z_top - length:
        b.box(x, y, z - 0.18, 0.05, 0.08, 0.18)
        z -= 0.2


def arch_bridge(b, x0, x1, z, y, rng):
    span = x1 - x0
    for k in range(24):
        a0 = math.pi * k / 24
        a1 = math.pi * (k + 1) / 24
        p0 = (x0 + span / 2 - math.cos(a0) * span / 2, z + math.sin(a0) * span * 0.25)
        p1 = (x0 + span / 2 - math.cos(a1) * span / 2, z + math.sin(a1) * span * 0.25)
        b.beam(p0, p1, 0.25, y)
    deck = z + span * 0.25 + 0.2
    b.box((x0 + x1) / 2, y, deck, span * (1.0 if rng.random() < 0.5 else 0.6), 0.5, 0.25)
    for k in range(1, 12):
        xa = x0 + span * k / 12
        top = deck
        bot = z + math.sin(math.pi * k / 12) * span * 0.25
        b.beam((xa, bot), (xa, top), 0.06, y)
    b.box(x0, y, 0, 0.6, 0.6, z + 0.2)
    b.box(x1, y, 0, 0.6, 0.6, z + 0.2)


def foliage(b, x, y, z, size, rng):
    for k in range(rng.randint(4, 8)):
        b.blob(x + rng.uniform(-size, size), y - 0.5, z + rng.uniform(-size * 0.4, size * 0.4), size * rng.uniform(0.35, 0.7))


# ---------------------------------------------------------------- layers

def build_far(rng):
    b = Builder()
    for row_y0, row_y1, dens in ((9.0, 17.0, 0.55), (0.0, 8.0, 1.0)):
      x = -W_BU / 2 - 1
      while x < W_BU / 2 + 1:
        y = rng.uniform(row_y0, row_y1)
        roll = rng.random()
        if roll < 0.55:
            w = rng.uniform(1.0, 3.2)
            tower(b, x, y, w, rng.uniform(7.0, 18.0), rng)
            x += w + rng.uniform(0.2, 1.8)
        elif roll < 0.75:
            r = rng.uniform(1.4, 2.4)
            cooling_tower(b, x, y, r, r * 2.6)
            x += r * 2 + rng.uniform(0.3, 1.0)
        elif roll < 0.85:
            span = rng.uniform(6.0, 11.0)
            arch_bridge(b, x, x + span, rng.uniform(3.0, 6.0), y, rng)
            x += span * 0.6
        else:
            lattice_pylon(b, x, y, rng.uniform(1.0, 2.0), rng.uniform(6.0, 13.0))
            x += 1.5
    for k in range(5):
        z = rng.uniform(4.0, 10.0)
        xa = rng.uniform(-W_BU / 2, W_BU / 2)
        b.hcyl(xa, xa + rng.uniform(4.0, 10.0), rng.uniform(4, 14), z, rng.uniform(0.15, 0.35))
    b.box(0, 9, 0, W_BU + 4, 18, 1.4)
    return b.finish("far")


def build_mid(rng):
    b = Builder()
    for row_y0, row_y1, dens in ((9.0, 17.0, 0.55), (0.0, 8.0, 1.0)):
      x = -W_BU / 2 - 1
      while x < W_BU / 2 + 1:
        y = rng.uniform(row_y0, row_y1)
        roll = rng.random()
        if roll < 0.35:
            w = rng.uniform(0.8, 2.2)
            top = tower(b, x, y, w, rng.uniform(5.0, 14.0), rng)
            if rng.random() < 0.5:
                chain(b, x + w * 0.5, y - 0.6, top * 0.8, rng.uniform(2.0, 5.0))
            x += w + rng.uniform(0.3, 1.2)
        elif roll < 0.5:
            r = rng.uniform(0.8, 1.6)
            tank(b, x, y, r, rng.uniform(2.5, 6.0), rng)
            x += r * 2 + 0.5
        elif roll < 0.65:
            # smokestacks
            for k in range(rng.randint(1, 3)):
                b.cyl(x + k * 0.7, y, 0, rng.uniform(0.18, 0.32), rng.uniform(5.0, 10.0), 12, 0.15)
            x += 2.4
        elif roll < 0.8:
            h = rng.uniform(4.0, 8.0)
            span = rng.uniform(3.0, 7.0)
            lattice_pylon(b, x, y, 1.0, h)
            lattice_pylon(b, x + span, y, 1.0, h)
            truss(b, x, x + span, h - 0.8, 0.6, y)
            for k in range(3):
                chain(b, x + span * (0.25 + k * 0.25), y, h - 0.8, rng.uniform(1.0, 3.0))
            x += span + 0.8
        else:
            # gantry crane
            h = rng.uniform(5.0, 9.0)
            lattice_pylon(b, x, y, 0.9, h)
            truss(b, x - 1.0, x + rng.uniform(3.0, 5.5), h, 0.45, y, 0.04)
            chain(b, x + 2.5, y, h, rng.uniform(1.5, 4.0))
            x += 4.5
    for k in range(9):
        z = rng.uniform(1.5, 7.0)
        xa = rng.uniform(-W_BU / 2, W_BU / 2)
        b.hcyl(xa, xa + rng.uniform(3.0, 9.0), rng.uniform(2, 15), z, rng.uniform(0.12, 0.28))
    b.box(0, 9, 0, W_BU + 4, 18, 0.9)
    return b.finish("mid")


def build_near(rng):
    b = Builder()
    for row_y0, row_y1, dens in ((7.0, 13.0, 0.55), (0.0, 6.0, 1.0)):
      x = -W_BU / 2 - 1
      while x < W_BU / 2 + 1:
        y = rng.uniform(row_y0, row_y1)
        roll = rng.random()
        if roll < 0.4:
            # ruined wall with arched openings
            w = rng.uniform(2.0, 5.0)
            h = rng.uniform(2.0, 6.0)
            n = max(1, int(w / 1.2))
            for k in range(n + 1):
                xa = x + w * k / n
                b.box(xa, y, 0, 0.35, 0.6, h * rng.uniform(0.6, 1.0))
            for k in range(n):
                if rng.random() < 0.75:
                    xa = x + w * k / n
                    xb = x + w * (k + 1) / n
                    for s in range(8):
                        a0 = math.pi * s / 8
                        a1 = math.pi * (s + 1) / 8
                        cx = (xa + xb) / 2
                        rr = (xb - xa) / 2
                        b.beam((cx - math.cos(a0) * rr, h * 0.6 + math.sin(a0) * rr * 0.7), (cx - math.cos(a1) * rr, h * 0.6 + math.sin(a1) * rr * 0.7), 0.2, y)
            if rng.random() < 0.7:
                foliage(b, x + w * rng.random(), y, h * 0.8, rng.uniform(0.6, 1.2), rng)
            x += w + rng.uniform(0.5, 2.0)
        elif roll < 0.6:
            # a big pipe elbow rising from the ground
            r = rng.uniform(0.3, 0.6)
            h = rng.uniform(2.0, 6.0)
            b.cyl(x, y, 0, r, h, 16)
            b.hcyl(x, x + rng.uniform(2.0, 5.0), y, h, r)
            for k in range(4):
                b.cyl(x, y, h * k / 4, r * 1.15, 0.12, 16)
            x += 3.0
        elif roll < 0.8:
            # a dead tree or a shaggy one
            h = rng.uniform(2.5, 6.0)
            b.beam((x, 0), (x + rng.uniform(-0.5, 0.5), h), 0.25, y)
            for k in range(rng.randint(2, 4)):
                z = h * rng.uniform(0.5, 0.95)
                d = rng.choice([-1, 1])
                b.beam((x, z), (x + d * rng.uniform(0.6, 1.4), z + rng.uniform(0.3, 1.0)), 0.08, y)
            if rng.random() < 0.6:
                foliage(b, x, y, h, rng.uniform(0.8, 1.5), rng)
            x += rng.uniform(1.5, 3.0)
        else:
            w = rng.uniform(1.0, 2.0)
            tower(b, x, y, w, rng.uniform(4.0, 8.0), rng)
            x += w + 1.0
    b.box(0, 7, 0, W_BU + 4, 14, 0.6)
    return b.finish("near")


# ---------------------------------------------------------------- render

def setup_render():
    sc = bpy.context.scene
    for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT", "BLENDER_WORKBENCH"):
        try:
            sc.render.engine = eng
            break
        except TypeError:
            continue
    sc.render.resolution_x = 4096
    sc.render.resolution_y = 2048
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    try:
        sc.view_settings.view_transform = "Standard"
    except TypeError:
        pass
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (0.42, 0.44, 0.48, 1)
    bg.inputs["Strength"].default_value = 1.0
    sc.world = world
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = W_BU
    cam = bpy.data.objects.new("Cam", cam_data)
    cam.location = (0, -40, H_BU / 2)
    cam.rotation_euler = (math.pi / 2, 0, 0)
    sc.collection.objects.link(cam)
    sc.camera = cam
    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = 2.6
    sun_data.angle = math.radians(8)
    sun = bpy.data.objects.new("Sun", sun_data)
    sun.rotation_euler = (math.radians(50), math.radians(-35), math.radians(-20))
    sc.collection.objects.link(sun)


def render_layer(name, builder_fn, seed):
    for ob in list(bpy.data.objects):
        if ob.type == "MESH":
            bpy.data.objects.remove(ob, do_unlink=True)
    builder_fn(random.Random(seed))
    path = os.path.join(OUT, name + ".png")
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("rendered", path)


def main():
    os.makedirs(OUT, exist_ok=True)
    reset()
    setup_render()
    render_layer("far", build_far, 11)
    render_layer("mid", build_mid, 23)
    render_layer("near", build_near, 37)


main()
