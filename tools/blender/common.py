"""Shared helpers for the model scripts. Every model script builds in studs (1 Blender unit
= 1 stud while modelling), then `finish()` exports GLB and FBX to art/models/, renders a
preview to art/previews/ and records size and triangle count in art/models/manifest.json.

Run one model:   blender -b -P art/scripts/dock.py
            or:  python art/scripts/dock.py   (with the `bpy` module from PyPI)
Run them all:    python art/scripts/build_all.py
"""

import json
import math
import os
import sys
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector

ART = Path(__file__).resolve().parents[1]
MODELS = ART / "models"
PREVIEWS = ART / "previews"
MANIFEST = MODELS / "manifest.json"

# Scale: 1 Blender unit = 1 stud, scene units set to None, and Studio's 3D Importer set to
# Scale Unit "Stud" (its default). See art/README.md.
PREVIEW_PX = 1024
PREVIEW_SAMPLES = int(os.environ.get("ART_SAMPLES", "48"))

# The house palette lives in palette.py (no Blender needed to read it).
from palette import PALETTE  # noqa: E402,F401


def srgb_to_linear(c):
    c = c / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "NONE"
    _materials.clear()


_materials = {}


def mat(name, rgb=None, rough=0.8, emit=0.0, metal=0.0):
    """A flat-colour material. `rgb` is 0..255 sRGB; defaults to the palette entry."""
    key = (name, rgb, emit)
    if key in _materials and _materials[key].name in bpy.data.materials:
        return _materials[key]
    rgb = rgb or PALETTE[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    lin = [srgb_to_linear(c) for c in rgb] + [1.0]
    bsdf.inputs["Base Color"].default_value = lin
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit > 0:
        bsdf.inputs["Emission Color"].default_value = lin
        bsdf.inputs["Emission Strength"].default_value = emit
    m.diffuse_color = lin
    _materials[key] = m
    return m


def _finish_obj(obj, material, name, bevel=0.0):
    obj.name = name or obj.name
    if material is not None:
        obj.data.materials.clear()
        obj.data.materials.append(material)
    if bevel > 0:
        mod = obj.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 1
        mod.limit_method = "ANGLE"
    return obj


def box(size, loc=(0, 0, 0), material=None, name=None, rot=(0, 0, 0), bevel=0.0):
    """A box `size` = (x, y, z) studs, centred at `loc`. Blender is Z-up; Y is depth."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.object
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return _finish_obj(o, material, name, bevel)


def cyl(radius, depth, loc=(0, 0, 0), material=None, name=None, rot=(0, 0, 0), verts=8, bevel=0.0, radius2=None):
    if radius2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=loc, rotation=rot)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=radius, radius2=radius2, depth=depth, location=loc, rotation=rot)
    return _finish_obj(bpy.context.object, material, name, bevel)


def cone(radius, depth, loc=(0, 0, 0), material=None, name=None, rot=(0, 0, 0), verts=8):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=radius, radius2=0, depth=depth, location=loc, rotation=rot)
    return _finish_obj(bpy.context.object, material, name)


def sphere(radius, loc=(0, 0, 0), material=None, name=None, scale=(1, 1, 1), subdiv=1, seg=None):
    if seg:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=seg[0], ring_count=seg[1], radius=radius, location=loc)
    else:
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=radius, location=loc)
    o = bpy.context.object
    o.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return _finish_obj(o, material, name)


def jitter(obj, amount, seed=1):
    """Nudge vertices a little so rocks and logs look hand-made, not perfect."""
    import random

    rng = random.Random(seed)
    for v in obj.data.vertices:
        v.co += Vector((rng.uniform(-amount, amount), rng.uniform(-amount, amount), rng.uniform(-amount, amount)))


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.object
    o.name = name
    return o


def apply_all_modifiers():
    for o in bpy.context.scene.objects:
        if o.type != "MESH":
            continue
        bpy.context.view_layer.objects.active = o
        for m in list(o.modifiers):
            bpy.ops.object.modifier_apply(modifier=m.name)


def triangles(objs=None):
    total = 0
    for o in objs or bpy.context.scene.objects:
        if o.type != "MESH":
            continue
        dg = bpy.context.evaluated_depsgraph_get()
        mesh = o.evaluated_get(dg).to_mesh()
        mesh.calc_loop_triangles()
        total += len(mesh.loop_triangles)
        o.evaluated_get(dg).to_mesh_clear()
    return total


def bounds(objs=None):
    lo = Vector((math.inf,) * 3)
    hi = Vector((-math.inf,) * 3)
    for o in objs or bpy.context.scene.objects:
        if o.type != "MESH":
            continue
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


def flat_shade_all():
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            for p in o.data.polygons:
                p.use_smooth = False


def _setup_render(lo, hi, view):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = PREVIEW_SAMPLES
    scene.cycles.use_denoising = True
    scene.render.resolution_x = scene.render.resolution_y = PREVIEW_PX
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("sky")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.78, 0.86, 0.93, 1)
    bg.inputs["Strength"].default_value = 0.9
    scene.world = world
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.2
    sun.data.angle = math.radians(8)
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(35))
    scene.collection.objects.link(sun)

    center = (lo + hi) / 2
    size = max((hi - lo).length, 0.5)
    # Ground disc for a soft contact shadow, a little below the model.
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=size * 1.5, depth=0.01, location=(center.x, center.y, lo.z - 0.005))
    ground = bpy.context.object
    ground.name = "_preview_ground"
    ground.data.materials.append(mat("_ground", (205, 215, 200), rough=1))

    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    yaw, pitch = view
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = max(size * 0.9, max(hi - lo) * 1.12)
    d = size * 3
    direction = Vector((math.sin(math.radians(yaw)) * math.cos(math.radians(pitch)),
                        -math.cos(math.radians(yaw)) * math.cos(math.radians(pitch)),
                        math.sin(math.radians(pitch))))
    cam.location = center + direction * d
    cam.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
    cam.data.clip_end = d * 4
    return ground, sun, cam


def finish(name, replaces, notes="", view=(35, 28), max_tris=10000):
    """Export, preview and record the model now in the scene. Returns the manifest entry."""
    MODELS.mkdir(parents=True, exist_ok=True)
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    apply_all_modifiers()
    flat_shade_all()
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    tris = triangles(meshes)
    n_parts = len(meshes)
    lo, hi = bounds(meshes)
    size = hi - lo
    if tris > max_tris:
        raise SystemExit(f"{name}: {tris} triangles is over the {max_tris} budget")

    # One mesh, one material: each part's flat colour becomes a vertex colour, then the
    # parts join into a single mesh (Roblox allows one material per mesh).
    single = bake_to_vertex_colors(meshes, name)
    meshes = [single]
    _export(single, name)
    lo, hi = bounds(meshes)

    ground, sun, cam = _setup_render(lo, hi, view)
    bpy.context.scene.render.filepath = str(PREVIEWS / f"{name}.png")
    bpy.ops.render.render(write_still=True)
    _shrink_png(PREVIEWS / f"{name}.png")
    for o in (ground, sun, cam):
        bpy.data.objects.remove(o, do_unlink=True)

    size = hi - lo
    entry = {
        "name": name,
        "studs": [round(size.x, 2), round(size.z, 2), round(size.y, 2)],  # Roblox X, Y (up), Z
        "triangles": tris,
        "parts": n_parts,
        "replaces": replaces,
        "notes": notes,
    }
    data = json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {}
    data[name] = entry
    MANIFEST.write_text(json.dumps(dict(sorted(data.items())), indent=2) + "\n")
    print(f"[art] {name}: {entry['studs']} studs, {tris} triangles, {n_parts} parts joined")
    return entry


def paint(obj, fn):
    """Colour each face from fn(center, normal) -> (r, g, b) in 0..255 sRGB, in the object's
    own coordinates. Used for fish markings and stripes; plain parts keep one colour."""
    attr = obj.data.color_attributes.get("Col") or obj.data.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
    for poly in obj.data.polygons:
        rgb = fn(poly.center, poly.normal)
        lin = tuple(srgb_to_linear(c) for c in rgb) + (1.0,)
        for li in poly.loop_indices:
            attr.data[li].color = lin
    return obj


def _shrink_png(path):
    """Keep previews small in git: 256-colour PNG (needs Pillow; skipped without it)."""
    try:
        from PIL import Image
    except ImportError:
        return
    im = Image.open(path).convert("RGB")
    im.quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.FLOYDSTEINBERG).save(path, optimize=True)


def bake_to_vertex_colors(meshes, name):
    for o in meshes:
        if o.data.color_attributes.get("Col"):
            continue  # already painted
        col = (0.8, 0.8, 0.8, 1.0)
        if o.data.materials and o.data.materials[0]:
            col = tuple(o.data.materials[0].diffuse_color)
        attr = o.data.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
        for d in attr.data:
            d.color = col  # BYTE_COLOR stores sRGB; .color takes linear values
    single = join(meshes, name) if len(meshes) > 1 else meshes[0]
    single.name = name
    single.data.name = name
    single.data.color_attributes.active_color = single.data.color_attributes["Col"]
    vc = bpy.data.materials.new(name + "_VertexColor")
    vc.use_nodes = True
    nt = vc.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 0.85
    attr_node = nt.nodes.new("ShaderNodeVertexColor")
    attr_node.layer_name = "Col"
    nt.links.new(attr_node.outputs["Color"], bsdf.inputs["Base Color"])
    single.data.materials.clear()
    single.data.materials.append(vc)
    # Origin at the bottom centre, so the model sits on the ground where it's placed.
    lo, hi = bounds([single])
    bpy.context.scene.cursor.location = ((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z)
    bpy.ops.object.select_all(action="DESELECT")
    single.select_set(True)
    bpy.context.view_layer.objects.active = single
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    single.location = (0, 0, 0)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return single


def _export(obj, name):
    """GLB and FBX at 1 unit = 1 stud, Y up, as Roblox's Blender guide asks."""
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=str(MODELS / f"{name}.glb"), use_selection=True, export_format="GLB",
        export_yup=True, export_apply=True, export_vertex_color="ACTIVE",
    )
    bpy.ops.export_scene.fbx(
        filepath=str(MODELS / f"{name}.fbx"), use_selection=True,
        apply_scale_options="FBX_SCALE_UNITS", axis_forward="Z", axis_up="Y",
        mesh_smooth_type="FACE", use_mesh_modifiers=True, colors_type="SRGB",
        add_leaf_bones=False, bake_anim=False,
    )


def main_guard(build):
    """Call build() when the script runs as `blender -b -P` or as plain python with bpy."""
    reset()
    build()
