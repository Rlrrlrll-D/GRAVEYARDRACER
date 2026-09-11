import bpy, os
import numpy as np
from mathutils import Vector

SP = r"D:/GraveyardRacer/GraveyardRacer/tools/blender/_out"  # выход: сюда, потом руками в meshes/
SRC = r"D:/GraveyardRacer/GraveyardRacer/meshes/BuggyBody.fbx"
OUT_DIR = os.path.join(SP, "out")
OUT_FBX = os.path.join(OUT_DIR, "BuggyBody.fbx")
os.makedirs(OUT_DIR, exist_ok=True)
ATLAS = 1024

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=SRC)
ob = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
me = ob.data
old_uv = me.uv_layers[0]
old_uv.name = "UVOld"
src_img = None
for m in me.materials:
    for n in m.node_tree.nodes:
        if n.type == 'TEX_IMAGE' and n.image:
            src_img = n.image
print("source image", src_img.name, src_img.size[:])

# Зоны (локальные координаты меша: X ширина, Y вверх, +Z перед).
ZONES = {
    "hood":  {"faces": [11],               "axes": ("x", "z"), "flipU": False, "flipV": False},
    "rear":  {"faces": [1, 57, 51],        "axes": ("x", "y"), "flipU": True,  "flipV": False},
    "left":  {"faces": [0, 6, 38, 50, 56], "axes": ("z", "y"), "flipU": False, "flipV": False},
    "right": {"faces": [2, 8, 46, 52, 58], "axes": ("z", "y"), "flipU": True,  "flipV": False},
}

def zone_bbox(faces):
    vs = [me.vertices[i].co for fi in faces for i in me.polygons[fi].vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return lo, hi

for name, z in ZONES.items():
    lo, hi = zone_bbox(z["faces"])
    z["lo"], z["hi"] = lo, hi
    a, b = z["axes"]
    z["w"] = getattr(hi, a) - getattr(lo, a)
    z["h"] = getattr(hi, b) - getattr(lo, b)
    print("zone %s: faces=%s lo=%s hi=%s size %.2f x %.2f studs" % (
        name, z["faces"], tuple(round(c, 2) for c in lo), tuple(round(c, 2) for c in hi), z["w"], z["h"]))

# Раскладка атласа: старая развёртка -> [0,0.6]^2; верхняя полоса под капот/корму;
# правая колонка под борта (повёрнуты на 90°, длина борта вдоль V).
OLD_SCALE = 0.6
D_TOP = 80.0 / ATLAS
D_SIDE = 60.0 / ATLAS
pad = 0.015
rects = {}
x = pad
y0 = 0.62 + pad
for name in ("hood", "rear"):
    z = ZONES[name]
    w, h = z["w"] * D_TOP, z["h"] * D_TOP
    rects[name] = (x, y0, x + w, y0 + h, False)
    x += w + 0.03
xs = 0.62 + pad
for name in ("left", "right"):
    z = ZONES[name]
    w, h = z["h"] * D_SIDE, z["w"] * D_SIDE
    rects[name] = (xs, pad, xs + w, pad + h, True)
    xs += w + 0.03
for name, r in rects.items():
    assert r[2] <= 1.0 and r[3] <= 1.0, (name, r)
    print("rect %s: u %.3f..%.3f v %.3f..%.3f rotated=%s" % (name, r[0], r[2], r[1], r[3], r[4]))

new_uv = me.uv_layers.new(name="UVNew")
zone_of_face = {}
for name, z in ZONES.items():
    for fi in z["faces"]:
        zone_of_face[fi] = name
for poly in me.polygons:
    name = zone_of_face.get(poly.index)
    for li in poly.loop_indices:
        if name is None:
            u, v = old_uv.data[li].uv
            new_uv.data[li].uv = (u * OLD_SCALE, v * OLD_SCALE)
        else:
            z = ZONES[name]
            r = rects[name]
            co = me.vertices[me.loops[li].vertex_index].co
            a, b = z["axes"]
            ta = (getattr(co, a) - getattr(z["lo"], a)) / z["w"]
            tb = (getattr(co, b) - getattr(z["lo"], b)) / z["h"]
            if z["flipU"]:
                ta = 1 - ta
            if z["flipV"]:
                tb = 1 - tb
            if r[4]:
                u = r[0] + tb * (r[2] - r[0])
                v = r[1] + ta * (r[3] - r[1])
            else:
                u = r[0] + ta * (r[2] - r[0])
                v = r[1] + tb * (r[3] - r[1])
            new_uv.data[li].uv = (u, v)

# Перепечь старую текстуру в новую развёртку (Cycles, только цвет).
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 16
scene.cycles.bake_type = 'DIFFUSE'
scene.render.bake.use_pass_direct = False
scene.render.bake.use_pass_indirect = False
scene.render.bake.use_pass_color = True
scene.render.bake.margin = 12
mat = me.materials[0]
nt = mat.node_tree
uvnode = nt.nodes.new("ShaderNodeUVMap")
uvnode.uv_map = "UVOld"
srcnode = [n for n in nt.nodes if n.type == 'TEX_IMAGE' and n.image][0]
nt.links.new(uvnode.outputs["UV"], srcnode.inputs["Vector"])
new_img = bpy.data.images.new("BuggyBody_v2", ATLAS, ATLAS, alpha=False)
tgt = nt.nodes.new("ShaderNodeTexImage")
tgt.image = new_img
nt.nodes.active = tgt
me.uv_layers.active = new_uv
new_uv.active_render = True
bpy.ops.object.select_all(action='DESELECT')
ob.select_set(True)
bpy.context.view_layer.objects.active = ob
bpy.ops.object.bake(type='DIFFUSE')
new_png = os.path.join(OUT_DIR, "BuggyBody.png")
new_img.filepath_raw = new_png
new_img.file_format = 'PNG'
new_img.save()
print("baked ->", new_png)

# Картинки развёртки до/после: проволока UV поверх текстуры.
def load_rgb(img):
    w, h = img.size
    return np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)[:, :, :3]

def draw_line(buf, x0, y0, x1, y1, col):
    n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
    for i in range(n):
        t = i / max(n - 1, 1)
        x = int(round(x0 + (x1 - x0) * t))
        y = int(round(y0 + (y1 - y0) * t))
        if 0 <= x < buf.shape[1] and 0 <= y < buf.shape[0]:
            buf[y, x] = col

def uv_wire(uvlayer, base_rgb, size, zone_tint=None):
    h0, w0 = base_rgb.shape[:2]
    ys = (np.arange(size) * h0 // size)
    xs_ = (np.arange(size) * w0 // size)
    buf = base_rgb[ys][:, xs_].copy() * 0.55
    if zone_tint:
        for name, r in rects.items():
            u0, v0, u1, v1 = r[:4]
            x0, x1 = int(u0 * size), int(u1 * size)
            y0_, y1 = int(v0 * size), int(v1 * size)
            buf[y0_:y1, x0:x1] = buf[y0_:y1, x0:x1] * 0.5 + np.array(zone_tint[name], np.float32) * 0.5
    for poly in me.polygons:
        pts = [uvlayer.data[li].uv for li in poly.loop_indices]
        col = (1.0, 1.0, 1.0)
        if zone_tint and poly.index in zone_of_face:
            col = (1.0, 1.0, 0.2)
        for i in range(len(pts)):
            a, b = pts[i], pts[(i + 1) % len(pts)]
            draw_line(buf, a.x * size, a.y * size, b.x * size, b.y * size, col)
    return buf

def save_rgb(buf, path):
    h, w = buf.shape[:2]
    img = bpy.data.images.new(os.path.basename(path), w, h, alpha=False)
    rgba = np.concatenate([np.clip(buf, 0, 1), np.ones((h, w, 1), np.float32)], axis=2)
    img.pixels[:] = rgba.ravel().tolist()
    img.filepath_raw = path
    img.file_format = 'PNG'
    img.save()

tints = {"hood": (0.9, 0.2, 0.2), "rear": (0.2, 0.5, 1.0), "left": (0.2, 0.9, 0.3), "right": (0.9, 0.6, 0.1)}
save_rgb(uv_wire(old_uv, load_rgb(src_img), 1024), os.path.join(SP, "uv_before.png"))
save_rgb(uv_wire(new_uv, load_rgb(new_img), 1024, tints), os.path.join(SP, "uv_after.png"))
print("layouts saved")

# Материал на новую текстуру, старую UV долой, экспорт.
srcnode.image = new_img
for l in list(nt.links):
    if l.to_node == srcnode and l.to_socket.name == "Vector":
        nt.links.remove(l)
nt.nodes.remove(uvnode)
nt.nodes.remove(tgt)
me.uv_layers.remove(me.uv_layers["UVOld"])
me.uv_layers[0].name = "UVMap"
bpy.ops.export_scene.fbx(filepath=OUT_FBX, use_selection=True, apply_scale_options='FBX_SCALE_ALL',
                         bake_space_transform=True, path_mode='COPY', embed_textures=True,
                         use_tspace=True, object_types={'MESH'})
print("exported", OUT_FBX, os.path.getsize(OUT_FBX))
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "buggy_v2.blend"))
print("DONE")
