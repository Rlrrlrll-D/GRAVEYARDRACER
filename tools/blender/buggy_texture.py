# Текстура багги: ржавый металл с РЕЗКИМИ краями (юзер 2026-09-12: прежняя печёная
# текстура — размытая мутная рябь; «порезче края, по аналогии с гробовой»). Карты
# позиции/нормали/AO в атлас багги (развёртка reunwrap_buggy), дальше numpy: краска-охра
# с крупными пятнами, ржавые островки по жёсткому порогу шума, сколы-крапинки, зерно,
# двойное AO. Средний тон капота держим (149,104,78) — краски и черепа подобраны под него.
# Царапин НЕТ: на скошенных гранях они читались косыми полосами «как доски гроба» (юзер
# 2026-09-12: «только пятна ржавчины»).
#
# ДУГА (задние стойки, бампер): в первой печёной текстуре (ref/BuggyBody_v1.png) у них
# был свой металл — юзер просит вернуть. Грани классифицируем по цвету старой текстуры
# в центре грани (металл = холодный/ненасыщенный), печём маску EMIT и в этих местах
# берём пиксели старой текстуры как есть.
#
#   blender -b -P tools/blender/buggy_texture.py -- <out_dir> [seed]
import os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from texlib import bake_maps, hsh, fbm3, smoothstep, write_outputs

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_DIR = argv[0] if argv else r"D:/GraveyardRacer/GraveyardRacer/tools/blender/_out"
SEED = int(argv[1]) if len(argv) > 1 else 3
ROOT = r"D:/GraveyardRacer/GraveyardRacer"
ATLAS = 1024

P, N, A, ctx = bake_maps(os.path.join(ROOT, "meshes", "BuggyBody.fbx"), ATLAS, ao_distance=1.2)
x, y, z = P[..., 0], P[..., 1], P[..., 2]

# --- маска металла по старой текстуре ---
import bpy
old_img = bpy.data.images.load(os.path.join(os.path.dirname(os.path.abspath(__file__)), "ref", "BuggyBody_v1.png"))
old = np.array(old_img.pixels[:], dtype=np.float32).reshape(ATLAS, ATLAS, 4)[..., :3]
me = ctx["me"]
uvl = me.uv_layers[0].data
metal_faces = 0
for poly in me.polygons:
    us = [uvl[li].uv for li in poly.loop_indices]
    u = sum(p.x for p in us) / len(us); v = sum(p.y for p in us) / len(us)
    px = old[min(ATLAS - 1, max(0, int(v * ATLAS))), min(ATLAS - 1, max(0, int(u * ATLAS)))]
    mx, mn = px.max(), px.min()
    is_metal = mx > 0.1 and (px[2] >= px[0] - 0.02 or (mx - mn) < 0.11)
    poly.material_index = 1 if is_metal else 0
    metal_faces += int(is_metal)
print("metal faces", metal_faces, "of", len(me.polygons))
mat_metal = bpy.data.materials.new("MetalMask"); mat_metal.use_nodes = True
mb = [n for n in mat_metal.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'][0]
mb.inputs["Emission Color"].default_value = (1, 1, 1, 1); mb.inputs["Emission Strength"].default_value = 1.0
mb.inputs["Base Color"].default_value = (0, 0, 0, 1)
rb = ctx["bsdf"]
rb.inputs["Emission Color"].default_value = (0, 0, 0, 1); rb.inputs["Emission Strength"].default_value = 0.0
me.materials.append(mat_metal)
# целевая картинка в обоих материалах: bake пишет в активный TEX_IMAGE каждого материала
mimg = bpy.data.images.new("mask", ATLAS, ATLAS, alpha=False, float_buffer=True)
mimg.colorspace_settings.name = 'Non-Color'
ctx["tgt"].image = mimg
t2 = mat_metal.node_tree.nodes.new("ShaderNodeTexImage"); t2.image = mimg; mat_metal.node_tree.nodes.active = t2
bpy.context.scene.cycles.samples = 1
bpy.ops.object.bake(type='EMIT')
metalK = np.clip(np.array(mimg.pixels[:], dtype=np.float32).reshape(ATLAS, ATLAS, 4)[..., 0], 0, 1)
print("metal texels", (metalK > 0.5).sum())
# краска: охра, крупные спокойные пятна (не размытые — амплитуда мала, зерно сверху)
paint = np.array([0.69, 0.485, 0.36], np.float32)  # ×0.97: с объёмным шумом ржавчины меньше, тон капота держим ~ (163,112,82)
m = fbm3(x * 0.45, y * 0.45, z * 0.45, SEED + 5, octaves=3)
col = paint[None, None, :] * (0.90 + 0.22 * m)[..., None]
# ржавые островки: жёсткий порог по многооктавному шуму → рваный чёткий край; островки
# мелкие и не слишком контрастные, иначе с дистанции выходит «корова» (проверено 12.09)
r = fbm3(x * 3.2, y * 3.2, z * 3.2, SEED + 17, octaves=5)
rustK = smoothstep(0.585, 0.61, r)                    # переход ~1 px, ржавчины ~12–15 %
rustDetail = fbm3(x * 9.0, y * 9.0, z * 9.0, SEED + 23, octaves=3)
rust = np.array([0.50, 0.31, 0.21], np.float32)[None, None, :] * (0.82 + 0.36 * rustDetail)[..., None]
col = col * (1 - rustK)[..., None] + rust * rustK[..., None]
# мелкая сыпь-питтинг тёмных точек
pit = fbm3(x * 11, y * 11, z * 11, SEED + 31, octaves=2)
pitK = smoothstep(0.745, 0.775, pit)
col = col * (1 - pitK)[..., None] + np.array([0.42, 0.25, 0.16], np.float32)[None, None, :] * pitK[..., None]
# ободок вокруг ржавчины — лёгкое потемнение краски у края островка
rim = smoothstep(0.53, 0.575, r) * (1 - rustK)
col *= (1 - 0.12 * rim)[..., None]
# сколы: мелкие светлые крапины (голый металл) по порогу мелкого шума
c = fbm3(x * 13, y * 13, z * 13, SEED + 41, octaves=2)
chipK = smoothstep(0.75, 0.78, c) * (1 - rustK)
col = col * (1 - chipK)[..., None] + np.array([0.78, 0.64, 0.50], np.float32)[None, None, :] * chipK[..., None]
# зерно на каждый тексель
g = hsh(np.arange(ATLAS)[None, :].repeat(ATLAS, 0), np.arange(ATLAS)[:, None].repeat(ATLAS, 1), SEED + 71)
col *= (0.95 + 0.10 * g)[..., None]
# двойное AO
aoK = np.clip(A, 0, 1) ** 1.8
col *= (0.62 + 0.38 * aoK)[..., None]
# дуга и бампер — металл старой текстуры как был; там, где маска шире старого острова
# (поля запекания), старая текстура чёрная — подставляем средний металл
oldOk = (old.max(2) > 0.1)
metalMean = old[(metalK > 0.5) & oldOk].mean(0)
print("metal mean rgb", (metalMean * 255).round())
metalCol = np.where(oldOk[..., None], old, metalMean[None, None, :])
col = col * (1 - metalK)[..., None] + metalCol * metalK[..., None]
print("texture mean rgb", (np.clip(col, 0, 1).reshape(-1, 3).mean(0) * 255).round(), "rust share %.3f" % rustK.mean())

# перед экспортом — один материал на весь меш (второй был только для маски),
# иначе импортёр Roblox порежет кузов по материалам
for poly in me.polygons:
    poly.material_index = 0
me.materials.pop(index=1)
write_outputs(col, ctx, os.path.join(ROOT, "meshes", "textures", "BuggyBody.png"), OUT_DIR, "BuggyBody.fbx", "buggy_rgba.bin")
print("DONE")
