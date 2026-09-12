# Текстура гроба: карты позиции/нормали/AO в атлас гроба (развёртка coffin_v2), из них
# numpy'ем рисуем старые доски (тон доски, волокно вдоль, тёмные швы, грязь, двойное AO —
# как в рецепте деталей), пишем PNG и экспортируем FBX со встроенной текстурой.
# Развёртка НЕ трогается — зоны черепов RankSkull остаются на месте.
#
#   blender -b -P tools/blender/coffin_texture.py -- <out_dir> [seed]
#
# Гроб без текстуры был белым холстом: краска ложилась ровным цветом, а режимы наложения
# черепа (Soft Light) на ровном поле теряют смысл (юзер 2026-09-12). Тон подогнан под
# капот багги (149,104,78), чтобы краски красили оба кузова одинаково.
import os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from texlib import bake_maps, hsh, fbm, write_outputs

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_DIR = argv[0] if argv else r"D:/GraveyardRacer/GraveyardRacer/tools/blender/_out"
SEED = int(argv[1]) if len(argv) > 1 else 7
ROOT = r"D:/GraveyardRacer/GraveyardRacer"
ATLAS = 1024

P, N, A, ctx = bake_maps(os.path.join(ROOT, "meshes", "CoffinBody.fbx"), ATLAS)
lo, hi = ctx["lo"], ctx["hi"]

# --- доски ---
x, y, z = P[..., 0], P[..., 1], P[..., 2]
top = np.abs(N[..., 2]) > 0.5          # крышка/дно: доски вдоль Y, поперёк X
side = np.abs(N[..., 0]) > 0.5         # борта: доски вдоль Y, поперёк Z
across = np.where(top, x, z)
along = np.where(top | side, y, x)     # торцы (нос/корма): доски горизонтально, вдоль X
width = hi[0] - lo[0]
PW = width / 4.6                        # ширина доски: ~4–5 досок на крышку
pid = np.floor(across / PW + 0.37)
frac = across / PW + 0.37 - pid
jit = hsh(pid, np.zeros_like(pid), SEED)              # случайность доски
tone = 0.86 + 0.28 * jit
seam = np.minimum(frac, 1 - frac) * PW                # расстояние до шва
seamK = np.clip(seam / (0.045 * width / 6.0), 0, 1)   # шов ~2–3 px тёмный
# волокно: растянуто вдоль доски, мелкое поперёк; фаза своя у каждой доски
g1 = fbm(along * 0.9 + jit * 53.0, across * 14.0 + pid * 7.0, SEED + 11)
g2 = fbm(along * 4.0 + jit * 17.0, across * 55.0, SEED + 29, octaves=3)
grain = 1.0 + 0.30 * (g1 - 0.5) * 2 + 0.10 * (g2 - 0.5) * 2
# грязь/потёртость крупными пятнами
m = fbm(x * 0.35 + z * 0.2, y * 0.35, SEED + 47, octaves=3)
mottle = 0.86 + 0.30 * m
base = np.array([0.70, 0.49, 0.33], np.float32)      # старое дерево, тон под капот багги (149,104,78)
col = base[None, None, :] * (tone * grain * mottle)[..., None]
col *= (0.55 + 0.45 * seamK)[..., None]
aoK = np.clip(A, 0, 1) ** 1.8                        # двойное AO (рецепт деталей)
col *= (0.62 + 0.38 * aoK)[..., None]
print("texture mean rgb", (np.clip(col, 0, 1).reshape(-1, 3).mean(0) * 255).round())

write_outputs(col, ctx, os.path.join(ROOT, "meshes", "textures", "CoffinBody.png"), OUT_DIR, "CoffinBody.fbx", "coffin_rgba.bin")
print("DONE")
