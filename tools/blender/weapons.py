# Стволы для слота WEAPON (PLAN_SHOP §6 шаг 5, 2026-09-12): COFFIN NAILER (дробовик-гвоздомёт
# с магазином-гробиком) и REAPER'S RATTLE (гатлинг). Низкополигональные, из примитивов,
# в ТОЙ ЖЕ СИСТЕМЕ, что MachineGun.fbx: ось качания (GunCradle) в НАЧАЛЕ КООРДИНАТ,
# ствол смотрит в −X, верх +Z, ширина по Y (после импорта в Roblox x→−x: дуло на +X).
# Текстура: цвета материалов + AO + зерно, печём в атлас 512², экспорт FBX со встроенной
# текстурой. В конце печатается, что вписать в ShopCatalog.mount: смещение центра детали
# от оси (weld C0) и точка дула (Muzzle) — уже в координатах Roblox.
#
#   blender -b -P tools/blender/weapons.py -- <out_dir>
import bpy, bmesh, os, sys, math
import numpy as np
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_DIR = argv[0] if argv else r"D:/GraveyardRacer/GraveyardRacer/tools/blender/_out"
ROOT = r"D:/GraveyardRacer/GraveyardRacer"
ATLAS = 512
os.makedirs(OUT_DIR, exist_ok=True)

COLORS = {
    "iron":  (0.16, 0.165, 0.18),
    "dark":  (0.09, 0.09, 0.10),
    "rust":  (0.40, 0.22, 0.12),
    "wood":  (0.36, 0.22, 0.12),
    "brass": (0.55, 0.42, 0.20),
    "bone":  (0.70, 0.64, 0.52),
}

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def mat(name):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = [n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'][0]
    c = COLORS[name]
    b.inputs["Base Color"].default_value = (*c, 1)
    b.inputs["Roughness"].default_value = 0.8
    return m

def box(center, size, color, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    ob = bpy.context.active_object
    ob.scale = (size[0], size[1], size[2])
    ob.rotation_euler = rot
    ob.data.materials.append(mat(color))
    return ob

def cyl(center, radius, length, color, axis='X', verts=12, r2=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=length, location=center)
    ob = bpy.context.active_object
    if axis == 'X':
        ob.rotation_euler = (0, math.pi / 2, 0)
    elif axis == 'Y':
        ob.rotation_euler = (math.pi / 2, 0, 0)
    ob.data.materials.append(mat(color))
    return ob

def cone(center, r1, r2, length, color, verts=12):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2, depth=length, location=center)
    ob = bpy.context.active_object
    ob.rotation_euler = (0, -math.pi / 2, 0)  # остриё (radius2) в −X
    ob.data.materials.append(mat(color))
    return ob

def prism(points_xz, y0, y1, color, name="prism"):
    """Призма из 2D-контура в плоскости XZ, вытянутая по Y (гробик-магазин)."""
    me = bpy.data.meshes.new(name); ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    bm = bmesh.new()
    a = [bm.verts.new((x, y0, z)) for x, z in points_xz]
    b = [bm.verts.new((x, y1, z)) for x, z in points_xz]
    bm.faces.new(a); bm.faces.new(list(reversed(b)))
    n = len(a)
    for i in range(n):
        bm.faces.new((a[i], b[i], b[(i + 1) % n], a[(i + 1) % n]))
    bm.normal_update()
    bm.to_mesh(me); bm.free()
    me.materials.append(mat(color))
    return ob

def join_all(name):
    obs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    bpy.ops.object.join()
    ob = bpy.context.active_object
    ob.name = name; ob.data.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # нормали наружу, без дублей
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.remove_doubles(threshold=0.0005); bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    return ob

# ---------------------------------------------------------------- COFFIN NAILER
def build_nailer():
    reset()
    box((-0.2, 0, 0.12), (2.0, 1.05, 0.85), "iron")                 # ствольная коробка
    box((-0.2, 0, 0.62), (1.2, 0.5, 0.18), "dark")                  # верхняя планка
    box((-2.15, 0, 0.18), (2.0, 0.62, 0.55), "dark")                # квадратный ствол-гвоздомёт
    cone((-3.32, 0, 0.18), 0.30, 0.55, 0.42, "iron", verts=8)       # раструб
    cyl((-3.50, 0, 0.18), 0.32, 0.12, "dark", verts=8)               # канал ствола — тёмный диск в раструбе
    for rx, rz in ((-0.9, 0.42), (0.5, 0.42), (-0.9, -0.2), (0.5, -0.2)):  # заклёпки по бокам коробки
        box((rx, 0.54, rz), (0.12, 0.06, 0.12), "dark")
        box((rx, -0.54, rz), (0.12, 0.06, 0.12), "dark")
    box((-2.55, 0, -0.6), (0.5, 0.1, 0.1), "bone")                  # гвоздь торчит из магазина
    box((-0.6, 0.62, 0.05), (0.9, 0.16, 0.5), "rust")               # боковые пластины
    box((-0.6, -0.62, 0.05), (0.9, 0.16, 0.5), "rust")
    # магазин-гробик под стволом (контур гроба в плоскости XZ)
    prism([(-2.3, -0.28), (-1.6, -0.12), (-0.5, -0.12), (-0.3, -0.35), (-0.5, -0.95), (-1.6, -0.95), (-2.3, -0.75)],
          -0.26, 0.26, "wood", "magazine")
    box((-1.35, 0, -0.14), (1.8, 0.56, 0.06), "brass")              # окантовка крышки
    box((0.95, 0, -0.05), (0.6, 0.5, 0.55), "dark")                 # затыльник
    box((0.85, 0, -0.55), (0.32, 0.36, 0.55), "wood", rot=(0, 0.35, 0))  # рукоять
    box((-0.5, 0, 0.9), (0.12, 0.08, 0.3), "bone")                  # мушка-косточка
    return join_all("Nailer")

# ---------------------------------------------------------------- REAPER'S RATTLE
def build_rattle():
    reset()
    box((0.35, 0, 0.05), (1.5, 1.0, 0.95), "iron")                  # ствольная коробка
    box((1.3, 0, 0.0), (0.7, 0.75, 0.75), "dark")                   # мотор
    cyl((-1.9, 0, 0.1), 0.13, 3.2, "dark", verts=8)                 # ось ротора
    for k in range(6):
        a = k * math.pi / 3
        cyl((-2.1, 0.33 * math.cos(a), 0.1 + 0.33 * math.sin(a)), 0.105, 3.0, "iron", verts=8)
    cyl((-3.25, 0, 0.1), 0.5, 0.22, "rust", verts=12)                # передняя обойма
    cyl((-1.6, 0, 0.1), 0.5, 0.2, "rust", verts=12)                  # средняя обойма
    cyl((-0.55, 0, 0.1), 0.56, 0.25, "dark", verts=12)               # казённая обойма
    box((0.35, 0.72, -0.05), (0.95, 0.45, 0.62), "rust")             # короб с лентой справа
    box((0.35, 0.72, 0.30), (0.95, 0.47, 0.06), "brass")             # крышка короба
    box((0.4, 0, 0.62), (0.7, 0.4, 0.16), "dark")                    # прицельная планка
    box((-0.1, 0, 0.78), (0.12, 0.08, 0.22), "bone")                 # мушка
    return join_all("Rattle")

# ---------------------------------------------------------------- запекание + экспорт
def bake_and_export(ob, name):
    me = ob.data
    bpy.ops.object.select_all(action='DESELECT'); ob.select_set(True); bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.02)
    bpy.ops.object.mode_set(mode='OBJECT')

    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'; scene.cycles.device = 'CPU'
    scene.render.bake.margin = 8; scene.render.bake.margin_type = 'EXTEND'
    scene.render.bake.use_pass_direct = False; scene.render.bake.use_pass_indirect = False
    scene.render.bake.use_pass_color = True
    world = bpy.data.worlds.new("w"); scene.world = world; world.use_nodes = True
    try:
        world.light_settings.distance = 0.9
    except Exception:
        pass
    # целевая картинка в каждом материале
    def target(img):
        for m in me.materials:
            t = m.node_tree.nodes.get("BakeTarget") or m.node_tree.nodes.new("ShaderNodeTexImage")
            t.name = "BakeTarget"; t.image = img; m.node_tree.nodes.active = t
    col_img = bpy.data.images.new(name + "_col", ATLAS, ATLAS, alpha=False)
    target(col_img); scene.cycles.samples = 1
    bpy.ops.object.bake(type='DIFFUSE')
    ao_img = bpy.data.images.new(name + "_ao", ATLAS, ATLAS, alpha=False, float_buffer=True)
    ao_img.colorspace_settings.name = 'Non-Color'
    target(ao_img); scene.cycles.samples = 32
    bpy.ops.object.bake(type='AO')
    col = np.array(col_img.pixels[:], dtype=np.float32).reshape(ATLAS, ATLAS, 4)[..., :3]
    ao = np.array(ao_img.pixels[:], dtype=np.float32).reshape(ATLAS, ATLAS, 4)[..., 0]
    rng = np.random.default_rng(7)
    grain = 0.92 + 0.16 * rng.random((ATLAS, ATLAS, 1)).astype(np.float32)
    out = np.clip(col * (0.55 + 0.45 * np.clip(ao, 0, 1)[..., None] ** 1.5) * grain, 0, 1)
    final = bpy.data.images.new(name, ATLAS, ATLAS, alpha=False)
    final.pixels[:] = np.concatenate([out, np.ones((ATLAS, ATLAS, 1), np.float32)], axis=2).ravel().tolist()
    png = os.path.join(ROOT, "meshes", "textures", name + ".png")
    final.filepath_raw = png; final.file_format = 'PNG'; final.save()

    # один материал с этой текстурой на экспорт
    single = bpy.data.materials.new(name + "Baked"); single.use_nodes = True
    nt = single.node_tree; b = [n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'][0]
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = final
    nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
    me.materials.clear(); me.materials.append(single)
    for p in me.polygons:
        p.material_index = 0
    fbx = os.path.join(OUT_DIR, name + ".fbx")
    bpy.ops.export_scene.fbx(filepath=fbx, use_selection=True, apply_scale_options='FBX_SCALE_ALL',
                             bake_space_transform=True, path_mode='COPY', embed_textures=True,
                             use_tspace=True, object_types={'MESH'})
    # то же в meshes/
    import shutil
    shutil.copy(fbx, os.path.join(ROOT, "meshes", name + ".fbx"))

    vs = np.array([v.co[:] for v in me.vertices])
    lo, hi = vs.min(0), vs.max(0); c = (lo + hi) / 2
    tip_x = lo[0]
    # Roblox (x, y, z) = (−x_b, z_b, +y_b): импортёр зеркалит ТОЛЬКО X (проверено по
    # вершинам меша через EditableMesh 2026-09-13; с −y_b дуло гатлинга уезжало вбок)
    print("MOUNT %s: size=(%.3f, %.3f, %.3f) faces=%d" % (name, hi[0] - lo[0], hi[2] - lo[2], hi[1] - lo[1], len(me.polygons)))
    print("MOUNT %s: cradle offset (weld C0) = Vector3.new(%.3f, %.3f, %.3f)" % (name, -c[0], c[2], c[1]))
    print("MOUNT %s: muzzle = Vector3.new(%.3f, <высота оси ствола z_b>, <y_b оси>)  (tip x_b = %.3f)" % (name, -tip_x, tip_x))
    return name

def render_preview(objs_by_name):
    """Рендер обоих стволов рядом для согласования вида (Workbench, студийный свет)."""
    reset()
    ys = [-2.0, 2.0]
    for (name, fbx), y in zip(objs_by_name, ys):
        bpy.ops.import_scene.fbx(filepath=fbx)
        ob = [o for o in bpy.context.selected_objects if o.type == 'MESH'][0]
        ob.location = (0, y, 0)
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.resolution_x = 1400; scene.render.resolution_y = 800
    world = bpy.data.worlds.new("w"); scene.world = world; world.use_nodes = True
    bg = world.node_tree.nodes["Background"]; bg.inputs[0].default_value = (0.22, 0.24, 0.28, 1); bg.inputs[1].default_value = 1.0
    sun_d = bpy.data.lights.new("sun", 'SUN'); sun_d.energy = 3.0; sun_d.angle = 0.4
    sun = bpy.data.objects.new("sun", sun_d); scene.collection.objects.link(sun); sun.rotation_euler = (0.8, 0.4, 1.2)
    cam_d = bpy.data.cameras.new("cam"); cam = bpy.data.objects.new("cam", cam_d); scene.collection.objects.link(cam)
    scene.camera = cam; cam_d.lens = 50
    def shoot(fname, pos, look):
        cam.location = pos
        cam.rotation_euler = (Vector(look) - Vector(pos)).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = os.path.join(OUT_DIR, fname); bpy.ops.render.render(write_still=True)
    shoot("weapons_front34.png", (-9, -6, 5), (-1, 0, 0))
    shoot("weapons_rear34.png", (8, -6, 4.5), (-0.5, 0, 0))

ob = build_nailer(); bake_and_export(ob, "Nailer")
ob = build_rattle(); bake_and_export(ob, "Rattle")
render_preview([("Nailer", os.path.join(OUT_DIR, "Nailer.fbx")), ("Rattle", os.path.join(OUT_DIR, "Rattle.fbx"))])
print("DONE")
