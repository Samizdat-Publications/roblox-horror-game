"""Helpers for the Don't Wave Back hero models (M9).

Every hero model is authored in the exact local frame of the part-built version it covers,
written in ROBLOX axes: x right, y up, z back (a model's front looks along -z). `rb()` turns a
Roblox (x, y, z) into Blender's (x, -z, y), so Blender +Y is the model's front and the glTF
export (Y up) lands back in Roblox axes. common.finish() records the bounding-box centre in
that frame, and the game places the MeshPart at anchorCFrame * CFrame.new(center).
"""

import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

import common


def rb(x, y, z):
    """Roblox (x, y, z) -> Blender (x, y, z)."""
    return (x, -z, y)


def rbox(size, loc, material, name="box", rot_y=0.0, rot_x=0.0, rot_z=0.0, bevel=0.0):
    """A box sized and placed in Roblox axes. rot_y turns about up, rot_x tips about the
    right axis, rot_z rolls about the back axis (radians, Roblox sense)."""
    sx, sy, sz = size
    o = common.box((sx, sz, sy), rb(*loc), material, name, bevel=bevel)
    # Roblox CFrame.Angles(x, y, z) order is X then Y then Z in object space; build the same
    # rotation in Roblox axes and convert the matrix.
    r = Matrix.Rotation(rot_x, 3, "X") @ Matrix.Rotation(rot_y, 3, "Y") @ Matrix.Rotation(rot_z, 3, "Z")
    c = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))  # Roblox -> Blender
    m = c @ r @ c.inverted()
    loc_v = o.location.copy()
    o.matrix_world = Matrix.Translation(loc_v) @ m.to_4x4()
    bpy.context.view_layer.update()
    return o


def mesh_object(name, verts, faces, material):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    if material is not None:
        o.data.materials.append(material)
    fix_normals(o)
    return o


def fix_normals(o):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(o.data)
    bm.free()
    o.data.update()


def solidify(o, thickness, offset=-1.0):
    m = o.modifiers.new("solid", "SOLIDIFY")
    m.thickness = thickness
    m.offset = offset
    m.use_even_offset = True
    m.use_rim = True
    return o


def tube(name, points, radii, material, verts=6, cap=True):
    """A tapered tube through Roblox-axis points (list of (x, y, z)), one radius per point."""
    pts = [Vector(rb(*p)) for p in points]
    n = len(pts)
    t0 = (pts[1] - pts[0]).normalized()
    ref = Vector((0, 0, 1)) if abs(t0.z) < 0.9 else Vector((1, 0, 0))
    nrm = t0.cross(ref).normalized()
    prev_t = t0
    rings = []
    for i in range(n):
        if i == 0:
            t = t0
        elif i == n - 1:
            t = (pts[i] - pts[i - 1]).normalized()
        else:
            t = ((pts[i + 1] - pts[i]).normalized() + (pts[i] - pts[i - 1]).normalized()).normalized()
        axis = prev_t.cross(t)
        if axis.length > 1e-6:
            nrm = (Matrix.Rotation(prev_t.angle(t), 3, axis.normalized()) @ nrm).normalized()
        prev_t = t
        bi = t.cross(nrm).normalized()
        rings.append([pts[i] + (nrm * math.cos(2 * math.pi * k / verts) + bi * math.sin(2 * math.pi * k / verts)) * radii[i] for k in range(verts)])
    vs = [tuple(v) for ring in rings for v in ring]
    fs = []
    for i in range(n - 1):
        for k in range(verts):
            fs.append((i * verts + k, i * verts + (k + 1) % verts, (i + 1) * verts + (k + 1) % verts, (i + 1) * verts + k))
    if cap:
        fs.append(tuple(range(verts))[::-1])
        fs.append(tuple((n - 1) * verts + k for k in range(verts)))
    return mesh_object(name, vs, fs, material)


def jitter_obj(o, amount, seed):
    rng = random.Random(seed)
    for v in o.data.vertices:
        v.co += Vector((rng.uniform(-amount, amount), rng.uniform(-amount, amount), rng.uniform(-amount, amount)))
