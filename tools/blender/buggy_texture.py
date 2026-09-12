# Текстура багги: ржавый металл с РЕЗКИМИ краями (юзер 2026-09-12: прежняя печёная
# текстура — размытая мутная рябь; «порезче края, по аналогии с гробовой»). Карты
# позиции/нормали/AO в атлас багги (развёртка reunwrap_buggy), дальше numpy: краска-охра
# с крупными пятнами, ржавые островки по жёсткому порогу шума, сколы-крапинки, царапины,
# зерно, двойное AO. Средний тон капота держим (149,104,78) — краски и черепа подобраны
# под него.
#
#   blender -b -P tools/blender/buggy_texture.py -- <out_dir> [seed]
import os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from texlib import bake_maps, hsh, fbm, vnoise, smoothstep, write_outputs

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_DIR = argv[0] if argv else r"D:/GraveyardRacer/GraveyardRacer/tools/blender/_out"
SEED = int(argv[1]) if len(argv) > 1 else 3
ROOT = r"D:/GraveyardRacer/GraveyardRacer"
ATLAS = 1024

P, N, A, ctx = bake_maps(os.path.join(ROOT, "meshes", "BuggyBody.fbx"), ATLAS, ao_distance=1.2)
x, y, z = P[..., 0], P[..., 1], P[..., 2]
# две координаты «по поверхности» для царапин: вдоль длины кузова на крышке/бортах
top = np.abs(N[..., 2]) > 0.5
side = np.abs(N[..., 0]) > 0.5
u = np.where(top, x, np.where(side, y, x))
v = np.where(top, y, z)

# краска: охра, крупные спокойные пятна (не размытые — амплитуда мала, зерно сверху)
paint = np.array([0.71, 0.50, 0.37], np.float32)
m = fbm(x * 0.45 + z * 0.3, y * 0.45, SEED + 5, octaves=3)
col = paint[None, None, :] * (0.90 + 0.22 * m)[..., None]
# ржавые островки: жёсткий порог по многооктавному шуму → рваный чёткий край; островки
# мелкие и не слишком контрастные, иначе с дистанции выходит «корова» (проверено 12.09)
r = fbm(x * 3.2 + z * 2.0, y * 3.2, SEED + 17, octaves=5)
rustK = smoothstep(0.585, 0.61, r)                    # переход ~1 px, ржавчины ~12–15 %
rustDetail = fbm(x * 9.0 + z * 6.0, y * 9.0, SEED + 23, octaves=3)
rust = np.array([0.50, 0.31, 0.21], np.float32)[None, None, :] * (0.82 + 0.36 * rustDetail)[..., None]
col = col * (1 - rustK)[..., None] + rust * rustK[..., None]
# мелкая сыпь-питтинг тёмных точек
pit = fbm(x * 11 + z * 7, y * 11, SEED + 31, octaves=2)
pitK = smoothstep(0.745, 0.775, pit)
col = col * (1 - pitK)[..., None] + np.array([0.42, 0.25, 0.16], np.float32)[None, None, :] * pitK[..., None]
# ободок вокруг ржавчины — лёгкое потемнение краски у края островка
rim = smoothstep(0.53, 0.575, r) * (1 - rustK)
col *= (1 - 0.12 * rim)[..., None]
# сколы: мелкие светлые крапины (голый металл) по порогу мелкого шума
c = fbm(x * 13 + z * 8, y * 13, SEED + 41, octaves=2)
chipK = smoothstep(0.75, 0.78, c) * (1 - rustK)
col = col * (1 - chipK)[..., None] + np.array([0.78, 0.64, 0.50], np.float32)[None, None, :] * chipK[..., None]
# царапины: сильно вытянутый шум, узкий порог → тонкие тёмные линии вдоль кузова
s = vnoise(u * 1.3, v * 45.0, SEED + 61)
scratch = smoothstep(0.86, 0.90, s) * smoothstep(0.35, 0.55, fbm(x * 0.8, y * 0.8, SEED + 67, octaves=2))
col *= (1 - 0.35 * scratch)[..., None]
# зерно на каждый тексель
g = hsh(np.arange(ATLAS)[None, :].repeat(ATLAS, 0), np.arange(ATLAS)[:, None].repeat(ATLAS, 1), SEED + 71)
col *= (0.95 + 0.10 * g)[..., None]
# двойное AO
aoK = np.clip(A, 0, 1) ** 1.8
col *= (0.62 + 0.38 * aoK)[..., None]
print("texture mean rgb", (np.clip(col, 0, 1).reshape(-1, 3).mean(0) * 255).round(), "rust share %.3f" % rustK.mean())

write_outputs(col, ctx, os.path.join(ROOT, "meshes", "textures", "BuggyBody.png"), OUT_DIR, "BuggyBody.fbx", "buggy_rgba.bin")
print("DONE")
