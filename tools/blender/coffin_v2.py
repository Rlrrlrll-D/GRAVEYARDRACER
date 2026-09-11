import bpy, bmesh, os
import numpy as np
from mathutils import Vector

# Всё в МИРОВЫХ координатах Blender после импорта: Z вверх, Y — длина (нос = -Y, корма = +Y), X — ширина.
SP = r"D:/GraveyardRacer/GraveyardRacer/tools/blender/_out"  # исходник CoffinBody_orig.fbx = git 77e14e7:meshes/CoffinBody.fbx
SRC = os.path.join(SP, "CoffinBody_orig.fbx")   # исходник с ручками и крестом (git HEAD~1)
OUT_FBX = os.path.join(SP, "out", "CoffinBody.fbx")
ATLAS = 1024

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=SRC)
ob = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
me = ob.data
W = ob.matrix_world
R = W.to_3x3()

bm = bmesh.new()
bm.from_mesh(me)
bm.verts.ensure_lookup_table()
seen = set()
islands = []
for v in bm.verts:
    if v.index in seen:
        continue
    stack = [v]; comp = []; seen.add(v.index)
    while stack:
        cur = stack.pop(); comp.append(cur)
        for e in cur.link_edges:
            o = e.other_vert(cur)
            if o.index not in seen:
                seen.add(o.index); stack.append(o)
    islands.append(comp)
def wbbox(comp):
    ws = [W @ v.co for v in comp]
    lo = Vector((min(p.x for p in ws), min(p.y for p in ws), min(p.z for p in ws)))
    hi = Vector((max(p.x for p in ws), max(p.y for p in ws), max(p.z for p in ws)))
    return lo, hi
handles, cross = [], []
for comp in islands:
    if len(comp) != 8:
        continue
    lo, hi = wbbox(comp)
    if lo.z >= 2.6 and hi.z <= 3.0 and min(abs(lo.x), abs(hi.x)) >= 1.8:
        handles.append(comp)
    elif lo.z >= 5.1:
        cross.append(comp)
print("islands", len(islands), "handles", len(handles), "cross", len(cross))
for c in cross:
    lo, hi = wbbox(c)
    print("  cross box world lo=%s hi=%s" % (tuple(round(v, 3) for v in lo), tuple(round(v, 3) for v in hi)))
bmesh.ops.delete(bm, geom=[v for c in handles + cross for v in c], context='VERTS')
bm.to_mesh(me)
bm.free()
me.update()
print("faces now:", len(me.polygons))

P = me.polygons
def wn(f): return (R @ f.normal).normalized()
def wc(f): return W @ f.center
def faces_where(cond): return [f.index for f in P if cond(wn(f), wc(f))]
zone_faces = {
    "lid":   faces_where(lambda n, c: n.z > 0.3 and c.z > 4.4 and c.y < -0.5),
    "rear":  faces_where(lambda n, c: n.y > 0.85 and c.y > 6.0),
    "left":  faces_where(lambda n, c: n.x < -0.5 and c.x < -1.0 and -1.2 < c.y < 6.9 and c.z > 1.2),
    "right": faces_where(lambda n, c: n.x > 0.5 and c.x > 1.0 and -1.2 < c.y < 6.9 and c.z > 1.2),
}
for k, v in zone_faces.items():
    print("zone", k, "faces", len(v), "area %.1f" % sum(P[i].area for i in v))

ZONES = {
    "lid":   {"faces": zone_faces["lid"],   "axes": ("x", "y"), "flipU": False, "flipV": True},
    "rear":  {"faces": zone_faces["rear"],  "axes": ("x", "z"), "flipU": True,  "flipV": False},
    "left":  {"faces": zone_faces["left"],  "axes": ("y", "z"), "flipU": True,  "flipV": False},
    "right": {"faces": zone_faces["right"], "axes": ("y", "z"), "flipU": False, "flipV": False},
}
def zone_bbox(faces):
    ws = [W @ me.vertices[i].co for fi in faces for i in me.polygons[fi].vertices]
    lo = Vector((min(p.x for p in ws), min(p.y for p in ws), min(p.z for p in ws)))
    hi = Vector((max(p.x for p in ws), max(p.y for p in ws), max(p.z for p in ws)))
    return lo, hi
for name, z in ZONES.items():
    lo, hi = zone_bbox(z["faces"]); z["lo"], z["hi"] = lo, hi
    a, b = z["axes"]
    z["w"] = getattr(hi, a) - getattr(lo, a); z["h"] = getattr(hi, b) - getattr(lo, b)
    print("zone %s bbox lo=%s hi=%s size %.2f x %.2f" % (name, tuple(round(c, 2) for c in lo), tuple(round(c, 2) for c in hi), z["w"], z["h"]))

OLD_SCALE = 0.55
D_TOP = 60.0 / ATLAS
D_SIDE = 52.0 / ATLAS
pad = 0.015
rects = {}
x = pad; y0 = 0.57 + pad
for name in ("lid", "rear"):
    z = ZONES[name]; w, h = z["w"] * D_TOP, z["h"] * D_TOP
    rects[name] = (x, y0, x + w, y0 + h, False); x += w + 0.03
xs = 0.57 + pad
for name in ("left", "right"):
    z = ZONES[name]; w, h = z["h"] * D_SIDE, z["w"] * D_SIDE
    rects[name] = (xs, pad, xs + w, pad + h, True); xs += w + 0.03
for name, r in rects.items():
    assert r[2] <= 1.0 and r[3] <= 1.0, (name, r)
    print("rect %s: u %.3f..%.3f v %.3f..%.3f rotated=%s" % (name, r[0], r[2], r[1], r[3], r[4]))

old_uv = me.uv_layers[0]
new_uv = me.uv_layers.new(name="UVNew")
zone_of_face = {fi: name for name, z in ZONES.items() for fi in z["faces"]}
for poly in me.polygons:
    name = zone_of_face.get(poly.index)
    for li in poly.loop_indices:
        if name is None:
            u, v = old_uv.data[li].uv
            new_uv.data[li].uv = (u * OLD_SCALE, v * OLD_SCALE)
        else:
            z = ZONES[name]; r = rects[name]
            co = W @ me.vertices[me.loops[li].vertex_index].co
            a, b = z["axes"]
            ta = (getattr(co, a) - getattr(z["lo"], a)) / z["w"]
            tb = (getattr(co, b) - getattr(z["lo"], b)) / z["h"]
            if z["flipU"]: ta = 1 - ta
            if z["flipV"]: tb = 1 - tb
            if r[4]:
                u = r[0] + tb * (r[2] - r[0]); v = r[1] + ta * (r[3] - r[1])
            else:
                u = r[0] + ta * (r[2] - r[0]); v = r[1] + tb * (r[3] - r[1])
            new_uv.data[li].uv = (u, v)
me.uv_layers.remove(old_uv)
me.uv_layers[0].name = "UVMap"

def draw_line(buf, x0, y0, x1, y1, col):
    n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
    for i in range(n):
        t = i / max(n - 1, 1)
        xx = int(round(x0 + (x1 - x0) * t)); yy = int(round(y0 + (y1 - y0) * t))
        if 0 <= xx < buf.shape[1] and 0 <= yy < buf.shape[0]:
            buf[yy, xx] = col
tints = {"lid": (0.9, 0.2, 0.2), "rear": (0.2, 0.5, 1.0), "left": (0.2, 0.9, 0.3), "right": (0.9, 0.6, 0.1)}
size = 1024
buf = np.full((size, size, 3), 0.12, np.float32)
for name, r in rects.items():
    u0, v0, u1, v1 = r[:4]
    buf[int(v0 * size):int(v1 * size), int(u0 * size):int(u1 * size)] = np.array(tints[name], np.float32) * 0.5
uvl = me.uv_layers[0]
for poly in me.polygons:
    pts = [uvl.data[li].uv for li in poly.loop_indices]
    col = (1.0, 1.0, 0.2) if poly.index in zone_of_face else (1.0, 1.0, 1.0)
    for i in range(len(pts)):
        a_, b_ = pts[i], pts[(i + 1) % len(pts)]
        draw_line(buf, a_.x * size, a_.y * size, b_.x * size, b_.y * size, col)
img = bpy.data.images.new("uv_coffin", size, size, alpha=False)
img.pixels[:] = np.concatenate([buf, np.ones((size, size, 1), np.float32)], axis=2).ravel().tolist()
img.filepath_raw = os.path.join(SP, "uv_coffin_after.png"); img.file_format = 'PNG'; img.save()

bpy.ops.object.select_all(action='DESELECT')
ob.select_set(True); bpy.context.view_layer.objects.active = ob
bpy.ops.export_scene.fbx(filepath=OUT_FBX, use_selection=True, apply_scale_options='FBX_SCALE_ALL',
                         bake_space_transform=True, path_mode='COPY', embed_textures=True,
                         use_tspace=True, object_types={'MESH'})
print("exported", OUT_FBX, os.path.getsize(OUT_FBX))

base = bpy.data.materials.new("base"); base.diffuse_color = (0.55, 0.55, 0.58, 1)
me.materials.clear(); me.materials.append(base)
for name, col in tints.items():
    m = bpy.data.materials.new(name); m.diffuse_color = (*col, 1); me.materials.append(m)
    idx = len(me.materials) - 1
    for fi in ZONES[name]["faces"]:
        me.polygons[fi].material_index = idx
scene = bpy.context.scene
scene.render.engine = 'BLENDER_WORKBENCH'
scene.display.shading.light = 'STUDIO'; scene.display.shading.color_type = 'MATERIAL'
scene.render.resolution_x = 900; scene.render.resolution_y = 600
world = bpy.data.worlds.new("w"); scene.world = world; world.color = (0.12, 0.12, 0.14)
cam_data = bpy.data.cameras.new("cam"); cam = bpy.data.objects.new("cam", cam_data); scene.collection.objects.link(cam)
scene.camera = cam; cam_data.lens = 40
vs = [W @ v.co for v in me.vertices]
center = Vector([(min(v[i] for v in vs) + max(v[i] for v in vs)) / 2 for i in range(3)])
def shoot(name, offset):
    pos = center + Vector(offset); cam.location = pos
    cam.rotation_euler = (center - pos).to_track_quat('-Z', 'Y').to_euler()
    scene.render.filepath = os.path.join(SP, name + ".png"); bpy.ops.render.render(write_still=True)
shoot("coffin_zones_rear34", (-13, 12, 8))
shoot("coffin_zones_front34", (13, -13, 9))
print("DONE")
