# КАТАФАЛК — третий кузов слота BODY (PLAN_SHOP §2: «кузов катафалк 12000»).
# Викторианский катафалк на том же шасси: длинный капот, открытая козлы-кабина водителя и
# застеклённый катафалк-павильон с гробом внутри — колонны, карниз с дентикулами, фонари,
# занавеси, крест в задней раме. Юзер 2026-09-14: «только побольше деталей».
#
#   blender -b -P tools/blender/hearse.py -- <out_dir>
#
# СИСТЕМА КООРДИНАТ — как у гроба (coffin_v2): X ширина, Y длина (нос −Y, корма +Y),
# Z вверх ОТ ЗЕМЛИ (z = 0 — пятно контакта колёс), начало — центр колёсной базы.
# Roblox при импорте зеркалит только X: Roblox (x, y, z) = (−x_b, z_b, +y_b), поэтому
# начало координат на земле даёт FitPivot = 0, как у гроба.
#
# МЕРКИ ШАССИ (сняты из ServerStorage.VehicleTemplate 2026-09-14, не угадывать заново):
#   колёса: центр (±2.50, ±4.16, 1.59), ⌀3.18 — верх колеса z = 3.18, наружу до |x| = 4.09;
#   сиденье водителя: центр (0, 0.68, 1.80), верх подушки z ≈ 2.32 (сама деталь невидима —
#     скамью рисуем мы);
#   пулемёт: ось качания (0, 0.19), ствол метёт радиусом ~3.3 в полосе z 3.9…6.0.
# ОТСЮДА ДВА ЖЁСТКИХ ПРАВИЛА: (1) всё, что ближе 3.6 по Y к оси турели, держим НИЖЕ z 3.8;
# (2) крыша павильона — выше 6.5. Иначе ствол прошивает кузов.
import bpy, bmesh, os, sys, math
import numpy as np
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_DIR = argv[0] if argv else r"D:/GraveyardRacer/GraveyardRacer/tools/blender/_out"
ROOT = r"D:/GraveyardRacer/GraveyardRacer"
ATLAS = 1024
os.makedirs(OUT_DIR, exist_ok=True)

WHEEL_X, WHEEL_Y, WHEEL_R = 2.50, 4.16, 1.59

# ЦВЕТА ЗАДАЁМ В sRGB, А НЕ В ЛИНЕЙНОМ (2026-09-14): бейк DIFFUSE пишет в sRGB-картинку,
# и линейные 0.52 выходили светло-бежевыми 192 — кузов был вдвое светлее гроба. Ниже —
# готовые sRGB-байты, srgb() переводит их в линейный Base Color.
# Тон держим на уровне гроба (его доски в атласе ≈ 150,105,71): краски магазина ДОМНОЖАЮТ
# текстуру, поэтому настоящий чёрный лак сделал бы кузов некрашеным.
def srgb(r, g, b):
    def lin(c):
        c /= 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (lin(r), lin(g), lin(b))

COLORS = {
    "wood":   srgb(150, 100, 62),   # лакированный орех — панели
    "wood2":  srgb(118, 78, 48),    # палуба, пол, тёмные вставки
    "iron":   srgb(58, 58, 62),
    "pewter": srgb(150, 148, 142),  # молдинги, колонны, оковка
    "brass":  srgb(168, 124, 52),   # фонари, гербы
    "bone":   srgb(206, 194, 166),  # гроб внутри
    "cloth":  srgb(120, 32, 34),    # занавеси
    "glass":  srgb(170, 182, 176),  # стёкла фонарей
}

# --- раскладка (всё в studs, см. шапку) ---------------------------------------
NOSE, TAIL = -7.60, 9.00
BODY_X = 2.60          # борт кузова
PANEL_X = 2.66         # панель с надписью (зона left/right) — чуть навыпуск
TRIM_X = 2.74          # молдинги вокруг панели
DOOR_X = 2.72          # борта кабины
BOARD_X = 3.10         # подножки
DECK_Z = 2.00          # палуба павильона
PANEL_Z0, PANEL_Z1 = 3.70, 4.85   # панель с надписью: НИЖЕ 3.70 её режет колесо (верх 3.18 + крыло)
GLASS_Z0, GLASS_Z1 = 5.00, 6.50   # остекление
CORNICE_Z = 6.50
ROOF_Z0, ROOF_Z1 = 6.70, 7.00     # крыша: низ выше ствола (6.0)
CAB_Y0, CAB_Y1 = -2.50, 2.60      # открытая кабина
PAV_Y0, PAV_Y1 = 3.80, 9.00       # павильон (стойки и панели) — дальше 3.6 от оси турели
ROOF_Y0, ROOF_Y1 = 3.60, 9.20

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def mat(name):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = [n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'][0]
    b.inputs["Base Color"].default_value = (*COLORS[name], 1)
    b.inputs["Roughness"].default_value = 0.75
    return m

def box(center, size, color, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    ob = bpy.context.active_object
    ob.scale = size
    ob.rotation_euler = rot
    ob.data.materials.append(mat(color))
    return ob

def slab(x0, x1, y0, y1, z0, z1, color):
    """Коробка по границам — так читаемее, чем центр+размер."""
    return box(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), (x1 - x0, y1 - y0, z1 - z0), color)

def cyl(center, radius, length, color, axis='Z', verts=12):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=length, location=center)
    ob = bpy.context.active_object
    if axis == 'X':
        ob.rotation_euler = (0, math.pi / 2, 0)
    elif axis == 'Y':
        ob.rotation_euler = (math.pi / 2, 0, 0)
    ob.data.materials.append(mat(color))
    return ob

def _prism(points, axis, a0, a1, color, name):
    """Призма из 2D-контура, вытянутая вдоль axis ('x' или 'z')."""
    me = bpy.data.meshes.new(name); ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    bm = bmesh.new()
    def pt(p, a):
        if axis == 'x':
            return (a, p[0], p[1])   # контур в плоскости YZ
        return (p[0], p[1], a)       # контур в плоскости XY
    a = [bm.verts.new(pt(p, a0)) for p in points]
    b = [bm.verts.new(pt(p, a1)) for p in points]
    bm.faces.new(a); bm.faces.new(list(reversed(b)))
    n = len(a)
    for i in range(n):
        bm.faces.new((a[i], b[i], b[(i + 1) % n], a[(i + 1) % n]))
    bm.normal_update()
    bm.to_mesh(me); bm.free()
    me.materials.append(mat(color))
    return ob

def fender(y_c, x0, x1, r_in, r_out, a0=8, a1=172, segs=9, color="wood2"):
    """Крыло над колесом: кольцевой сектор в плоскости YZ, вытянутый по X."""
    pts = []
    for i in range(segs + 1):
        a = math.radians(a0 + (a1 - a0) * i / segs)
        pts.append((y_c + r_out * math.cos(a), WHEEL_R + r_out * math.sin(a)))
    for i in range(segs, -1, -1):
        a = math.radians(a0 + (a1 - a0) * i / segs)
        pts.append((y_c + r_in * math.cos(a), WHEEL_R + r_in * math.sin(a)))
    return _prism(pts, 'x', x0, x1, color, "fender")

def lantern(x, y, z, h=1.15, w=0.42, color="brass"):
    """Каретный фонарь: сужающийся кверху корпус, стеклянные бока, крышка со шпилем."""
    _prism([(-w / 2, -w / 2), (w / 2, -w / 2), (w / 2, w / 2), (-w / 2, w / 2)], 'z', 0, 0, color, "tmp").select_set(False)
    bpy.data.objects.remove(bpy.context.scene.objects["tmp"], do_unlink=True)
    body = _prism([(x - w / 2, y - w / 2), (x + w / 2, y - w / 2), (x + w / 2, y + w / 2), (x - w / 2, y + w / 2)],
                  'z', z, z + h * 0.72, color, "lantern")
    slab(x - w * 0.36, x + w * 0.36, y - w * 0.55, y + w * 0.55, z + h * 0.12, z + h * 0.62, "glass")
    slab(x - w * 0.55, x + w * 0.55, y - w * 0.36, y + w * 0.36, z + h * 0.12, z + h * 0.62, "glass")
    # крышка-пирамидка и шпиль
    bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=w * 0.78, radius2=0.0, depth=h * 0.28,
                                    location=(x, y, z + h * 0.86), rotation=(0, 0, math.radians(45)))
    bpy.context.active_object.data.materials.append(mat(color))
    cyl((x, y, z + h * 1.04), 0.05, h * 0.18, color, verts=6)
    slab(x - w * 0.62, x + w * 0.62, y - w * 0.62, y + w * 0.62, z - 0.06, z, color)  # пятка
    return body

def urn(x, y, z, s=1.0, color="pewter"):
    """Погребальная урна на углу крыши: цоколь, чаша, крышка, шпиль."""
    slab(x - 0.22 * s, x + 0.22 * s, y - 0.22 * s, y + 0.22 * s, z, z + 0.10 * s, color)
    cyl((x, y, z + 0.16 * s), 0.13 * s, 0.12 * s, color, verts=10)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=7, radius=0.21 * s, location=(x, y, z + 0.38 * s))
    ob = bpy.context.active_object
    ob.scale = (1, 1, 1.15)
    ob.data.materials.append(mat(color))
    cyl((x, y, z + 0.60 * s), 0.10 * s, 0.10 * s, color, verts=8)
    cyl((x, y, z + 0.74 * s), 0.035 * s, 0.22 * s, color, verts=6)
    return ob

def cross(x, y, z, h, w, t, color, plane='xz'):
    """Крест: вертикаль h, перекладина w, толщина t."""
    if plane == 'xz':
        slab(x - t / 2, x + t / 2, y - t / 2, y + t / 2, z, z + h, color)
        slab(x - w / 2, x + w / 2, y - t / 2, y + t / 2, z + h * 0.62 - t / 2, z + h * 0.62 + t / 2, color)
    else:  # 'yz' — крест на борту/двери, плоскость YZ
        slab(x - t / 2, x + t / 2, y - t / 2, y + t / 2, z, z + h, color)
        slab(x - t / 2, x + t / 2, y - w / 2, y + w / 2, z + h * 0.62 - t / 2, z + h * 0.62 + t / 2, color)

# ================================================================= САМ КУЗОВ
def build():
    reset()

    # --- рама и подножки ---------------------------------------------------
    for sx in (-1, 1):
        slab(sx * 2.30, sx * 2.56, NOSE + 0.2, TAIL - 0.1, 1.15, 1.55, "iron")          # лонжерон
        slab(sx * 2.60, sx * BOARD_X, CAB_Y0 + 0.3, CAB_Y1 - 0.1, 1.52, 1.70, "wood2")  # подножка
        slab(sx * 2.58, sx * (BOARD_X + 0.04), CAB_Y0 + 0.3, CAB_Y1 - 0.1, 1.70, 1.78, "pewter")  # кант подножки
        for yy in (-1.6, -0.4, 0.8, 2.0):                                                # кронштейны подножки
            slab(sx * 2.62, sx * 3.02, yy - 0.09, yy + 0.09, 1.30, 1.54, "iron")
    for yy in (NOSE + 0.6, -3.0, 1.0, 5.0, TAIL - 0.6):                                  # поперечины
        slab(-2.35, 2.35, yy - 0.12, yy + 0.12, 1.22, 1.46, "iron")

    # --- нос: бампер, радиатор, фары ---------------------------------------
    slab(-2.95, 2.95, NOSE, NOSE + 0.26, 1.42, 1.86, "iron")
    for sx in (-1, 1):
        slab(sx * 2.30, sx * 2.62, NOSE + 0.26, NOSE + 0.70, 1.50, 1.78, "iron")         # кронштейн бампера
        slab(sx * 1.58, sx * 1.92, NOSE + 0.30, NOSE + 0.66, 1.60, 4.42, "pewter")       # стойка решётки
    slab(-1.94, 1.94, NOSE + 0.30, NOSE + 0.66, 4.22, 4.50, "pewter")                    # верх решётки
    slab(-1.94, 1.94, NOSE + 0.30, NOSE + 0.66, 1.56, 1.82, "pewter")                    # низ решётки
    slab(-1.72, 1.72, NOSE + 0.42, NOSE + 0.56, 1.82, 4.22, "iron")                      # тёмный проём
    for i in range(9):                                                                    # вертикальные прутья
        x = -1.52 + i * 0.38
        slab(x - 0.055, x + 0.055, NOSE + 0.36, NOSE + 0.62, 1.84, 4.20, "pewter")
    cross(0, NOSE + 0.36, 4.50, 0.66, 0.44, 0.10, "pewter")                              # крестик на решётке
    for sx in (-1, 1):
        slab(sx * 2.04, sx * 2.30, NOSE + 0.55, NOSE + 0.75, 2.95, 3.15, "iron")         # кронштейн фары
        cyl((sx * 2.18, NOSE + 0.62, 3.55), 0.48, 0.54, "brass", axis='Y', verts=14)     # корпус фары
        cyl((sx * 2.18, NOSE + 0.35, 3.55), 0.41, 0.10, "glass", axis='Y', verts=14)     # стекло
        cyl((sx * 2.18, NOSE + 0.96, 3.55), 0.20, 0.30, "brass", axis='Y', verts=8)      # затыльник
        slab(sx * 2.22 - 0.06, sx * 2.22 + 0.06, NOSE + 0.62, NOSE + 0.78, 3.10, 3.55, "iron")

    # --- капот --------------------------------------------------------------
    # Спинка капота падает от радиатора к щитку: и по-каретному правильно, и ствол не
    # цепляет — у щитка (радиус 2.4 от оси турели) верх 3.58, ниже полосы ствола 3.9.
    HOOD_Y0, HOOD_Y1 = NOSE + 0.70, CAB_Y0 - 0.05
    HOOD_Z0 = 1.88
    HOOD_KEYS = [(HOOD_Y0, 4.24), (HOOD_Y0 + 1.9, 4.10), (HOOD_Y1 - 0.9, 3.82), (HOOD_Y1, 3.58)]
    def hood_top(y):
        for (ya, za), (yb, zb) in zip(HOOD_KEYS, HOOD_KEYS[1:]):
            if ya <= y <= yb:
                return za + (zb - za) * (y - ya) / (yb - ya)
        return HOOD_KEYS[0][1] if y < HOOD_Y0 else HOOD_KEYS[-1][1]
    _prism([(HOOD_Y0, HOOD_Z0)] + HOOD_KEYS + [(HOOD_Y1, HOOD_Z0)], 'x', -1.88, 1.88, "wood", "hood")
    _prism([(y, z + 0.10) for y, z in HOOD_KEYS] + [(y, z - 0.05) for y, z in reversed(HOOD_KEYS)],
           'x', -1.94, 1.94, "wood2", "hood_top")                                         # крышка внахлёст
    _prism([(y, z + 0.20) for y, z in HOOD_KEYS] + [(y, z + 0.08) for y, z in reversed(HOOD_KEYS)],
           'x', -0.10, 0.10, "pewter", "hood_hinge")                                      # петля-хребет
    for sx in (-1, 1):
        for i in range(8):                                                                # жалюзи
            y = HOOD_Y0 + 0.55 + i * 0.48
            slab(sx * 1.82, sx * 1.92, y - 0.15, y + 0.15, 2.35, hood_top(y) - 0.55, "iron")
        slab(sx * 1.86, sx * 1.96, HOOD_Y0 + 0.1, HOOD_Y1 - 0.1, 2.14, 2.26, "pewter")    # молдинг борта капота
    for yy in (HOOD_Y0 + 0.50, HOOD_Y1 - 0.80):                                           # ремни капота
        zt = hood_top(yy)
        slab(-1.97, 1.97, yy - 0.11, yy + 0.11, 1.92, zt + 0.14, "iron")
        slab(-0.24, 0.24, yy - 0.15, yy + 0.15, zt + 0.10, zt + 0.24, "brass")            # пряжка
    urn(0, HOOD_Y0 + 0.20, hood_top(HOOD_Y0 + 0.20) + 0.10, s=0.8, color="brass")         # фигурка на пробке радиатора

    # --- передние крылья ----------------------------------------------------
    for sx in (-1, 1):
        fender(-WHEEL_Y, sx * 2.32, sx * 4.20, 1.80, 1.93, color="wood2")
        slab(sx * 2.32, sx * 4.20, -WHEEL_Y - 1.94, -WHEEL_Y - 1.80, 1.70, 2.40, "wood2")  # передний фартук
        slab(sx * 2.30, sx * 4.22, -WHEEL_Y - 0.09, -WHEEL_Y + 0.09, 3.49, 3.58, "pewter") # гребень крыла

    # --- кабина (козлы) -----------------------------------------------------
    slab(-2.50, 2.50, CAB_Y0, CAB_Y1, 1.56, 1.76, "wood2")                               # пол
    slab(-2.10, 2.10, CAB_Y0 - 0.04, CAB_Y0 + 0.55, 1.76, 3.46, "wood")                  # щиток
    slab(-2.14, 2.14, CAB_Y0 - 0.06, CAB_Y0 + 0.60, 3.46, 3.60, "pewter")                # кант щитка
    for sx in (-1, 1):                                                                    # приборы
        cyl((sx * 0.85, CAB_Y0 + 0.05, 2.92), 0.30, 0.10, "brass", axis='Y', verts=12)
        cyl((sx * 0.85, CAB_Y0 + 0.01, 2.92), 0.24, 0.06, "glass", axis='Y', verts=12)
    for sx in (-1, 1):                                                                    # низкие борта-двери
        slab(sx * 2.56, sx * DOOR_X, CAB_Y0 + 0.55, CAB_Y1 - 0.35, 1.70, 3.16, "wood")
        slab(sx * 2.54, sx * (DOOR_X + 0.04), CAB_Y0 + 0.55, CAB_Y1 - 0.35, 3.16, 3.28, "pewter")   # кант борта
        slab(sx * 2.60, sx * (DOOR_X + 0.03), CAB_Y0 + 0.85, CAB_Y1 - 0.65, 2.28, 2.38, "pewter")   # бусина
        cross(sx * 2.71, 1.35, 2.02, 0.70, 0.44, 0.10, "pewter", plane='yz')                        # крест на двери
        slab(sx * 2.50, sx * 2.74, 0.10, 0.26, 2.40, 2.56, "brass")                                 # ручка
    slab(-1.62, 1.62, 0.30, 1.06, 1.76, 2.36, "cloth")                                   # подушка скамьи
    slab(-1.66, 1.66, 0.26, 1.10, 2.30, 2.40, "wood2")                                   # кант подушки
    slab(-1.62, 1.62, 1.32, 1.52, 1.80, 3.36, "cloth")                                   # спинка (ниже ствола)
    slab(-1.66, 1.66, 1.28, 1.56, 3.36, 3.48, "wood2")
    for zz in (2.30, 2.72, 3.14):                                                        # стёжка спинки
        slab(-1.58, 1.58, 1.28, 1.34, zz - 0.05, zz + 0.05, "wood2")
    cyl((0, -0.55, 2.66), 0.62, 0.09, "iron", axis='Y', verts=16)                        # руль
    cyl((0, -0.55, 2.66), 0.10, 0.36, "iron", axis='Y', verts=10)
    for a in range(3):
        ang = math.radians(90 + a * 120)
        slab(-0.05 + 0.30 * math.cos(ang), 0.05 + 0.30 * math.cos(ang), -0.62, -0.48,
             2.66 + 0.30 * math.sin(ang) - 0.05, 2.66 + 0.30 * math.sin(ang) + 0.05, "iron")
    slab(-0.10, 0.10, -0.60, 0.05, 1.80, 2.60, "iron")                                   # колонка руля
    # переборка за кабиной: строго ниже 3.8 — там метёт ствол
    slab(-2.50, 2.50, CAB_Y1, CAB_Y1 + 0.22, 1.76, 3.60, "wood")
    slab(-2.56, 2.56, CAB_Y1 - 0.03, CAB_Y1 + 0.25, 3.60, 3.72, "pewter")

    # --- задние крылья ------------------------------------------------------
    for sx in (-1, 1):
        fender(WHEEL_Y, sx * 2.32, sx * 4.20, 1.76, 1.89, color="wood2")                 # верх ≤ 3.48: не лезет на надпись
        slab(sx * 2.32, sx * 4.20, WHEEL_Y + 1.76, WHEEL_Y + 1.89, 1.70, 2.70, "wood2")  # задний фартук
        slab(sx * 2.30, sx * 4.22, WHEEL_Y - 0.09, WHEEL_Y + 0.09, 3.44, 3.53, "pewter")

    # --- павильон: палуба, панели, надпись ---------------------------------
    slab(-BODY_X, BODY_X, CAB_Y1 + 0.20, TAIL, 1.76, DECK_Z, "wood2")                    # палуба
    for sx in (-1, 1):
        slab(sx * 2.46, sx * BODY_X, CAB_Y1 + 0.22, TAIL, DECK_Z - 0.05, PANEL_Z0 - 0.15, "wood")  # нижняя панель борта
        slab(sx * 2.44, sx * TRIM_X, CAB_Y1 + 0.22, TAIL, PANEL_Z0 - 0.15, PANEL_Z0, "pewter")   # молдинг под надписью
        slab(sx * 2.52, sx * PANEL_X, PAV_Y0, TAIL - 0.04, PANEL_Z0 - 0.04, PANEL_Z1 + 0.04, "wood")  # ПАНЕЛЬ С НАДПИСЬЮ (зона)
        slab(sx * 2.44, sx * TRIM_X, PAV_Y0 - 0.2, TAIL, PANEL_Z1, PANEL_Z1 + 0.14, "pewter")    # молдинг над надписью
        for yy in (PAV_Y0 - 0.04, TAIL - 0.08):                                                  # вертикальные накладки по краям панели
            slab(sx * 2.50, sx * (TRIM_X + 0.02), yy - 0.09, yy + 0.09, PANEL_Z0, PANEL_Z1, "pewter")
        # нижняя панель: две филёнки в рамках — иначе борт читается как глухой ящик
        for y0, y1 in ((CAB_Y1 + 0.45, PAV_Y0 + 2.2), (PAV_Y0 + 2.5, TAIL - 0.25)):
            for yy in (y0, y1):
                slab(sx * 2.58, sx * 2.66, yy - 0.07, yy + 0.07, DECK_Z + 0.20, PANEL_Z0 - 0.32, "pewter")
            for zz in (DECK_Z + 0.22, PANEL_Z0 - 0.30):
                slab(sx * 2.58, sx * 2.66, y0, y1, zz - 0.06, zz + 0.06, "pewter")
    # передняя стенка павильона (ниже 3.8 — ствол) и задняя стенка с зоной черепа
    slab(-BODY_X, BODY_X, CAB_Y1 + 0.20, CAB_Y1 + 0.46, DECK_Z, 3.58, "wood")            # передняя стенка платформы
    slab(-2.66, 2.66, CAB_Y1 + 0.16, CAB_Y1 + 0.50, 3.58, 3.70, "pewter")
    slab(-2.50, 2.50, TAIL, TAIL + 0.16, DECK_Z - 0.04, PANEL_Z1 + 0.04, "wood")          # ЗАДНЯЯ ПАНЕЛЬ (зона rear)
    slab(-2.62, 2.62, TAIL - 0.02, TAIL + 0.22, PANEL_Z1, PANEL_Z1 + 0.14, "pewter")
    slab(-2.62, 2.62, TAIL - 0.02, TAIL + 0.22, DECK_Z - 0.14, DECK_Z, "pewter")
    for sx in (-1, 1):                                                                     # задние стойки-накладки
        slab(sx * 2.30, sx * 2.52, TAIL - 0.02, TAIL + 0.20, DECK_Z, PANEL_Z1, "pewter")
        slab(sx * 2.02, sx * 2.14, TAIL + 0.10, TAIL + 0.22, DECK_Z + 0.25, PANEL_Z1 - 0.25, "pewter")
    for zz in (DECK_Z + 0.25, PANEL_Z1 - 0.25):                                            # рамка вокруг черепа
        slab(-2.08, 2.08, TAIL + 0.10, TAIL + 0.22, zz - 0.06, zz + 0.06, "pewter")
    slab(-2.20, 2.20, TAIL + 0.16, TAIL + 0.40, 1.42, 1.86, "iron")                       # задний бампер-ступень
    for sx in (-1, 1):
        slab(sx * 1.55, sx * 1.95, TAIL + 0.18, TAIL + 0.52, 1.86, 1.98, "iron")

    # --- павильон: колонны, остекление, занавеси ---------------------------
    posts_y = (PAV_Y0 + 0.10, PAV_Y0 + 1.83, PAV_Y0 + 3.57, TAIL - 0.10)
    for sx in (-1, 1):
        for i, yy in enumerate(posts_y):
            w = 0.20 if i in (1, 2) else 0.26                                              # средние тоньше
            slab(sx * (BODY_X - 0.30), sx * (BODY_X + 0.02), yy - w, yy + w, GLASS_Z0, GLASS_Z1, "wood")
            slab(sx * (BODY_X - 0.34), sx * (BODY_X + 0.06), yy - w - 0.05, yy + w + 0.05, GLASS_Z0, GLASS_Z0 + 0.16, "pewter")
            slab(sx * (BODY_X - 0.34), sx * (BODY_X + 0.06), yy - w - 0.05, yy + w + 0.05, GLASS_Z1 - 0.16, GLASS_Z1, "pewter")
            if i in (0, 3):                                                                # витые накладки на угловых
                for zz in (GLASS_Z0 + 0.42, GLASS_Z0 + 0.86, GLASS_Z0 + 1.30):
                    slab(sx * (BODY_X - 0.32), sx * (BODY_X + 0.04), yy - w - 0.03, yy + w + 0.03, zz - 0.05, zz + 0.05, "pewter")
        # занавеси по краям каждого проёма
        for yy in posts_y:
            for d in (-1, 1):
                for k in range(3):
                    fy = yy + d * (0.34 + k * 0.17)
                    if PAV_Y0 - 0.1 < fy < TAIL + 0.1:
                        slab(sx * (BODY_X - 0.42), sx * (BODY_X - 0.26 + 0.04 * k), fy - 0.07, fy + 0.07,
                             GLASS_Z0 + 0.10, GLASS_Z1 - 0.10 - 0.05 * k, "cloth")
        slab(sx * (BODY_X - 0.44), sx * (BODY_X - 0.22), PAV_Y0, TAIL, GLASS_Z1 - 0.24, GLASS_Z1 - 0.10, "cloth")  # ламбрекен
    # задний проём: крест в раме
    for sx in (-1, 1):
        slab(sx * 2.30, sx * 2.56, TAIL - 0.10, TAIL + 0.14, GLASS_Z0, GLASS_Z1, "wood")
    slab(-2.56, 2.56, TAIL - 0.10, TAIL + 0.14, GLASS_Z1 - 0.18, GLASS_Z1, "pewter")
    slab(-2.56, 2.56, TAIL - 0.10, TAIL + 0.14, GLASS_Z0, GLASS_Z0 + 0.18, "pewter")
    cross(0, TAIL + 0.02, GLASS_Z0 + 0.20, 1.12, 0.86, 0.14, "pewter")
    # фронтон павильона (над водителем): резная доска
    slab(-2.50, 2.50, PAV_Y0 - 0.20, PAV_Y0 + 0.06, GLASS_Z1 - 0.55, GLASS_Z1, "wood")
    slab(-2.56, 2.56, PAV_Y0 - 0.24, PAV_Y0 + 0.10, GLASS_Z1 - 0.18, GLASS_Z1, "pewter")
    cross(0, PAV_Y0 - 0.08, GLASS_Z1 - 0.50, 0.36, 0.26, 0.08, "pewter")

    # --- гроб внутри (виден сквозь проёмы) ---------------------------------
    CY = (PAV_Y0 + TAIL) / 2
    slab(-1.70, 1.70, PAV_Y0 + 0.35, TAIL - 0.35, DECK_Z, 4.52, "wood2")                  # катафалк-постамент
    slab(-1.82, 1.82, PAV_Y0 + 0.25, TAIL - 0.25, 4.47, 4.66, "pewter")                   # карниз постамента
    for yy in (PAV_Y0 + 1.2, CY, TAIL - 1.2):                                              # ножки-кронштейны
        slab(-1.76, 1.76, yy - 0.10, yy + 0.10, DECK_Z + 0.1, 4.52, "pewter")
    for sx in (-1, 1):                                                                     # свечи по углам постамента
        for yy in (PAV_Y0 + 0.55, TAIL - 0.55):
            cyl((sx * 1.52, yy, 4.94), 0.09, 0.56, "bone", verts=8)
            cyl((sx * 1.52, yy, 4.70), 0.15, 0.12, "brass", verts=8)
    hex_pts = [(-0.46, CY - 2.55), (0.46, CY - 2.55), (0.96, CY - 1.35), (0.80, CY + 2.45),
               (-0.80, CY + 2.45), (-0.96, CY - 1.35)]
    _prism(hex_pts, 'z', 4.62, 5.76, "bone", "coffin")                                     # сам гроб
    _prism([(p[0] * 1.06, p[1] + (0.06 if p[1] > CY else -0.06)) for p in hex_pts], 'z', 5.71, 5.90, "bone", "coffin_lid")
    for sx in (-1, 1):                                                                     # крест на боку гроба — его и видно сквозь колонны
        cross(sx * 0.92, CY - 0.30, 4.95, 0.62, 0.40, 0.09, "brass", plane='yz')
    cross(0, CY - 0.35, 5.90, 0.95, 0.62, 0.12, "brass")                                   # крест на крышке
    for sx in (-1, 1):                                                                      # ручки гроба
        for yy in (CY - 1.9, CY - 0.2, CY + 1.6):
            slab(sx * 0.86, sx * 1.06, yy - 0.22, yy + 0.22, 5.02, 5.16, "brass")

    # --- карниз, дентикулы, крыша, урны ------------------------------------
    slab(-2.86, 2.86, ROOF_Y0 + 0.08, ROOF_Y1 - 0.08, CORNICE_Z, CORNICE_Z + 0.12, "wood")
    slab(-2.94, 2.94, ROOF_Y0 + 0.02, ROOF_Y1 - 0.02, CORNICE_Z + 0.12, ROOF_Z0, "pewter")  # карниз
    n_dent = 17
    for i in range(n_dent):                                                                 # дентикулы по бортам
        y = ROOF_Y0 + 0.28 + i * (ROOF_Y1 - ROOF_Y0 - 0.56) / (n_dent - 1)
        for sx in (-1, 1):
            slab(sx * 2.80, sx * 2.96, y - 0.09, y + 0.09, CORNICE_Z - 0.16, CORNICE_Z, "pewter")
    for i in range(7):                                                                      # дентикулы по торцам
        x = -2.10 + i * 0.70
        for yy in (ROOF_Y0 + 0.10, ROOF_Y1 - 0.10):
            slab(x - 0.09, x + 0.09, yy - 0.08, yy + 0.08, CORNICE_Z - 0.16, CORNICE_Z, "pewter")
    slab(-2.95, 2.95, ROOF_Y0, ROOF_Y1, ROOF_Z0 - 0.05, ROOF_Z1, "wood")                  # КРЫША (зона top)
    for sx in (-1, 1):                                                                      # бортик крыши
        slab(sx * 2.86, sx * 2.99, ROOF_Y0 - 0.04, ROOF_Y1 + 0.04, ROOF_Z1 - 0.05, ROOF_Z1 + 0.10, "pewter")
    for yy in (ROOF_Y0 - 0.02, ROOF_Y1 + 0.02):
        slab(-2.99, 2.99, yy - 0.06, yy + 0.06, ROOF_Z1 - 0.05, ROOF_Z1 + 0.10, "pewter")
    for sx in (-1, 1):                                                                      # урны по углам
        urn(sx * 2.58, ROOF_Y0 + 0.30, ROOF_Z1 - 0.04, s=1.0)
        urn(sx * 2.58, ROOF_Y1 - 0.30, ROOF_Z1 - 0.04, s=1.0)

    # --- фонари на павильоне -------------------------------------------------
    for sx in (-1, 1):
        lantern(sx * (BODY_X + 0.30), PAV_Y0 + 0.10, GLASS_Z0 + 0.10)
        lantern(sx * (BODY_X + 0.30), TAIL - 0.10, GLASS_Z0 + 0.10)
        for yy in (PAV_Y0 + 0.10, TAIL - 0.10):                                            # кронштейн фонаря
            slab(sx * (BODY_X - 0.02), sx * (BODY_X + 0.36), yy - 0.08, yy + 0.08, GLASS_Z0 - 0.14, GLASS_Z0 + 0.14, "pewter")

    # --- выхлоп и мелочи -----------------------------------------------------
    cyl((-2.42, 1.2, 1.30), 0.17, 6.6, "iron", axis='Y', verts=10)
    cyl((-2.42, 4.7, 1.30), 0.23, 1.1, "iron", axis='Y', verts=10)
    slab(-2.58, -2.26, TAIL - 0.6, TAIL + 0.45, 1.18, 1.42, "iron")
    for sx in (-1, 1):                                                                      # гербовые щитки на нижней панели
        slab(sx * 2.60, sx * 2.70, PAV_Y0 + 4.35, PAV_Y0 + 4.75, DECK_Z + 0.40, PANEL_Z0 - 0.45, "brass")

    return join_all("HearseBody")

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
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.remove_doubles(threshold=0.0004); bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    return ob

# ============================================================ РАЗВЁРТКА И ЗОНЫ
# Четыре зоны RankSkull прямоугольниками с известными UV (как у гроба): крыша, корма и
# две боковые панели с надписью ранга. Остальное — smart project в нижнюю часть атласа.
def unwrap(ob):
    me = ob.data
    P = me.polygons
    def fn(f): return f.normal
    def fc(f): return f.center
    sel = {
        "top":   lambda n, c: n.z > 0.9 and abs(c.z - ROOF_Z1) < 0.02 and ROOF_Y0 < c.y < ROOF_Y1,
        "rear":  lambda n, c: n.y > 0.9 and abs(c.y - (TAIL + 0.16)) < 0.02 and DECK_Z < c.z < PANEL_Z1,
        "left":  lambda n, c: n.x < -0.9 and abs(c.x + PANEL_X) < 0.02 and PANEL_Z0 < c.z < PANEL_Z1,
        "right": lambda n, c: n.x > 0.9 and abs(c.x - PANEL_X) < 0.02 and PANEL_Z0 < c.z < PANEL_Z1,
    }
    zone_faces = {k: [f.index for f in P if v(fn(f), fc(f))] for k, v in sel.items()}
    for k, v in zone_faces.items():
        assert v, "зона %s не нашлась" % k
        print("зона %s: граней %d, площадь %.2f" % (k, len(v), sum(P[i].area for i in v)))

    ZONES = {
        # axes — оси зоны (вдоль ширины, вдоль высоты); flip — как у гроба, чтобы
        # ta/tb в RankSkull значили то же самое
        "top":   {"faces": zone_faces["top"],   "axes": ("x", "y"), "flipU": False, "flipV": True,  "rot": False},
        "rear":  {"faces": zone_faces["rear"],  "axes": ("x", "z"), "flipU": True,  "flipV": False, "rot": False},
        "left":  {"faces": zone_faces["left"],  "axes": ("y", "z"), "flipU": True,  "flipV": False, "rot": True},
        "right": {"faces": zone_faces["right"], "axes": ("y", "z"), "flipU": False, "flipV": False, "rot": True},
    }
    for name, z in ZONES.items():
        vs = [me.vertices[i].co for fi in z["faces"] for i in me.polygons[fi].vertices]
        lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
        hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
        a, b = z["axes"]
        z["lo"], z["hi"] = lo, hi
        z["w"] = getattr(hi, a) - getattr(lo, a)
        z["h"] = getattr(hi, b) - getattr(lo, b)
        print("зона %s: %.2f x %.2f studs" % (name, z["w"], z["h"]))

    # прямоугольники в атласе (верхняя треть; низ отдан smart project)
    D = 56.0 / ATLAS  # px на stud
    rects = {}
    x = 0.015
    for name in ("top",):
        z = ZONES[name]; rects[name] = (x, 0.615, x + z["w"] * D, 0.615 + z["h"] * D); x += z["w"] * D + 0.03
    z = ZONES["rear"]; rects["rear"] = (x, 0.615, x + z["w"] * D, 0.615 + z["h"] * D)
    xs = 0.63
    for name in ("left", "right"):
        z = ZONES[name]
        rects[name] = (xs, 0.605, xs + z["h"] * D, 0.605 + z["w"] * D)  # повёрнута: длина вдоль V
        xs += z["h"] * D + 0.03
    for name, r in rects.items():
        assert r[2] <= 1.0 and r[3] <= 1.0, (name, r)
        print("RECT %s: u %.3f..%.3f v %.3f..%.3f" % (name, r[0], r[2], r[1], r[3]))

    # smart project на всё, потом ужимаем в нижнюю часть
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True); bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.006)
    bpy.ops.object.mode_set(mode='OBJECT')
    uv = me.uv_layers[0]
    REST_V = 0.58
    for li in range(len(me.loops)):
        u, v = uv.data[li].uv
        uv.data[li].uv = (u, v * REST_V)
    zone_of_face = {fi: name for name, z in ZONES.items() for fi in z["faces"]}
    for poly in me.polygons:
        name = zone_of_face.get(poly.index)
        if name is None:
            continue
        z = ZONES[name]; r = rects[name]
        a, b = z["axes"]
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            ta = (getattr(co, a) - getattr(z["lo"], a)) / z["w"]
            tb = (getattr(co, b) - getattr(z["lo"], b)) / z["h"]
            if z["flipU"]: ta = 1 - ta
            if z["flipV"]: tb = 1 - tb
            if z["rot"]:
                uv.data[li].uv = (r[0] + tb * (r[2] - r[0]), r[1] + ta * (r[3] - r[1]))
            else:
                uv.data[li].uv = (r[0] + ta * (r[2] - r[0]), r[1] + tb * (r[3] - r[1]))
    return ZONES, rects

# ==================================================================== ЗАПЕЧЬ
def bake_and_export(ob, ZONES, rects, name="HearseBody"):
    me = ob.data
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'; scene.cycles.device = 'CPU'
    scene.render.bake.margin = 12; scene.render.bake.margin_type = 'EXTEND'
    scene.render.bake.use_pass_direct = False; scene.render.bake.use_pass_indirect = False
    scene.render.bake.use_pass_color = True
    world = bpy.data.worlds.new("w"); scene.world = world; world.use_nodes = True
    try:
        world.light_settings.distance = 1.4
    except Exception:
        pass
    def target(img):
        for m in me.materials:
            t = m.node_tree.nodes.get("BakeTarget") or m.node_tree.nodes.new("ShaderNodeTexImage")
            t.name = "BakeTarget"; t.image = img; m.node_tree.nodes.active = t
    col_img = bpy.data.images.new(name + "_col", ATLAS, ATLAS, alpha=False)
    target(col_img); scene.cycles.samples = 1
    bpy.ops.object.bake(type='DIFFUSE')
    ao_img = bpy.data.images.new(name + "_ao", ATLAS, ATLAS, alpha=False, float_buffer=True)
    ao_img.colorspace_settings.name = 'Non-Color'
    target(ao_img); scene.cycles.samples = 40
    bpy.ops.object.bake(type='AO')
    pos_img = bpy.data.images.new(name + "_pos", ATLAS, ATLAS, alpha=False, float_buffer=True)
    pos_img.colorspace_settings.name = 'Non-Color'
    target(pos_img); scene.cycles.samples = 1
    bpy.ops.object.bake(type='POSITION')

    col = np.array(col_img.pixels[:], np.float32).reshape(ATLAS, ATLAS, 4)[..., :3]
    ao = np.array(ao_img.pixels[:], np.float32).reshape(ATLAS, ATLAS, 4)[..., 0]
    pos = np.array(pos_img.pixels[:], np.float32).reshape(ATLAS, ATLAS, 4)[..., :3]

    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from texlib import fbm3
    x, y, z = pos[..., 0], pos[..., 1], pos[..., 2]
    # волокно лакированного дерева вдоль длины + крупные потёртости + мелкое зерно
    grain = fbm3(x * 1.1, y * 0.28, z * 1.1, 17, octaves=4)
    wear = fbm3(x * 0.42, y * 0.42, z * 0.42, 31, octaves=3)
    rng = np.random.default_rng(11)
    speck = 0.95 + 0.10 * rng.random((ATLAS, ATLAS)).astype(np.float32)
    shade = (0.88 + 0.24 * grain) * (0.90 + 0.20 * wear) * speck
    aoK = np.clip(ao, 0, 1) ** 1.7
    out = np.clip(col * shade[..., None] * (0.58 + 0.42 * aoK)[..., None], 0, 1)

    final = bpy.data.images.new(name, ATLAS, ATLAS, alpha=False)
    final.pixels[:] = np.concatenate([out, np.ones((ATLAS, ATLAS, 1), np.float32)], axis=2).ravel().tolist()
    png = os.path.join(ROOT, "meshes", "textures", "HearseBody.png")
    final.filepath_raw = png; final.file_format = 'PNG'; final.save()
    print("png ->", png)
    raw = (out[::-1] * 255 + 0.5).astype(np.uint8)
    raw = np.concatenate([raw, np.full((ATLAS, ATLAS, 1), 255, np.uint8)], axis=2)
    open(os.path.join(OUT_DIR, "hearse_tex.raw"), "wb").write(raw.tobytes())

    single = bpy.data.materials.new("HearseBaked"); single.use_nodes = True
    nt = single.node_tree; b = [n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'][0]
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = final
    nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.8
    me.materials.clear(); me.materials.append(single)
    for p in me.polygons:
        p.material_index = 0
    fbx = os.path.join(OUT_DIR, "HearseBody.fbx")
    bpy.ops.object.select_all(action='DESELECT'); ob.select_set(True); bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.fbx(filepath=fbx, use_selection=True, apply_scale_options='FBX_SCALE_ALL',
                             bake_space_transform=True, path_mode='COPY', embed_textures=True,
                             use_tspace=True, object_types={'MESH'})
    import shutil
    shutil.copy(fbx, os.path.join(ROOT, "meshes", "HearseBody.fbx"))
    print("exported", fbx, os.path.getsize(fbx))

    vs = np.array([v.co[:] for v in me.vertices])
    lo, hi = vs.min(0), vs.max(0)
    print("BBOX blender lo=%s hi=%s" % (lo.round(2), hi.round(2)))
    print("ROBLOX size = (%.2f, %.2f, %.2f)  (ширина, высота, длина), тр-ов %d" %
          (hi[0] - lo[0], hi[2] - lo[2], hi[1] - lo[1], len(me.polygons)))
    print("FitPivot = Vector3.new(0, 0, 0)  — начало меша на земле, как у гроба")
    for nm in ("top", "rear", "left", "right"):
        z = ZONES[nm]; r = rects[nm]
        print("ZONE %-5s = { u0 = %.3f, v0 = %.3f, u1 = %.3f, v1 = %.3f, rotated = %s, studsW = %.2f, studsH = %.2f }" %
              (nm, r[0], r[1], r[2], r[3], str(z["rot"]).lower(), z["w"], z["h"]))
    return fbx

# ================================================================== ПРЕДПРОСМОТР
def render_preview(fbx):
    """Катафалк с макетными колёсами — чтобы судить пропорции на шасси."""
    reset()
    bpy.ops.import_scene.fbx(filepath=fbx)
    for sx in (-1, 1):
        for sy in (-1, 1):
            bpy.ops.mesh.primitive_cylinder_add(vertices=28, radius=WHEEL_R, depth=1.6,
                                                location=(sx * WHEEL_X, sy * WHEEL_Y, WHEEL_R),
                                                rotation=(0, math.pi / 2, 0))
            w = bpy.context.active_object
            m = bpy.data.materials.new("tyre"); m.use_nodes = True
            [n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'][0].inputs["Base Color"].default_value = (0.05, 0.05, 0.06, 1)
            w.data.materials.append(m)
    bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, 0))
    gm = bpy.data.materials.new("ground"); gm.use_nodes = True
    [n for n in gm.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'][0].inputs["Base Color"].default_value = (0.10, 0.11, 0.10, 1)
    bpy.context.active_object.data.materials.append(gm)
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in [i.identifier for i in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items] else 'BLENDER_EEVEE'
    scene.render.resolution_x = 1500; scene.render.resolution_y = 900
    world = bpy.data.worlds.new("w"); scene.world = world; world.use_nodes = True
    bg = world.node_tree.nodes["Background"]; bg.inputs[0].default_value = (0.26, 0.30, 0.34, 1); bg.inputs[1].default_value = 1.0
    sun_d = bpy.data.lights.new("sun", 'SUN'); sun_d.energy = 3.2; sun_d.angle = 0.3
    sun = bpy.data.objects.new("sun", sun_d); scene.collection.objects.link(sun); sun.rotation_euler = (0.75, 0.25, 1.05)
    cam_d = bpy.data.cameras.new("cam"); cam = bpy.data.objects.new("cam", cam_d); scene.collection.objects.link(cam)
    scene.camera = cam; cam_d.lens = 52
    def shoot(fname, pos, look):
        cam.location = pos
        cam.rotation_euler = (Vector(look) - Vector(pos)).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = os.path.join(OUT_DIR, fname); bpy.ops.render.render(write_still=True)
    shoot("hearse_side.png", (-40, 0.6, 6.5), (0, 0.6, 3.6))
    shoot("hearse_rear34.png", (-20, 24, 13), (0, 1.5, 3.6))
    shoot("hearse_front34.png", (19, -24, 12), (0, -1.5, 3.4))
    shoot("hearse_top.png", (-3, 1.0, 38), (0, 1.0, 3.0))
    shoot("hearse_chase.png", (-6, 26, 11), (0, 2.0, 4.0))

ob = build()
ZONES, rects = unwrap(ob)
fbx = bake_and_export(ob, ZONES, rects)
render_preview(fbx)
print("DONE")
