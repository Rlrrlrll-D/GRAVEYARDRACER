# skull_range.json -> ReplicatedStorage/SkullShapes.lua: пять силуэтов по рангам,
# нормировано как SkullOutline (ширина 1, центр в нуле, Y вверх), контуры упрощены RDP.
import json, sys, math

paths = json.load(open(sys.argv[1]))
out = sys.argv[2]
TOL = 0.0012  # допуск упрощения в долях ширины (как у SkullOutline)

paths = [p for p in paths if p["op"] in ("f", "f*", "F", "B", "b") and sum(len(s) for s in p["subs"]) > 100]
assert len(paths) == 5, len(paths)

def center(p):
    pts = [pt for s in p["subs"] for pt in s]
    return (sum(a[0] for a in pts) / len(pts), sum(a[1] for a in pts) / len(pts))

# раскладка по листу (PDF: Y вверх): верх-лево GRAVEDIGGER, верх-право PALLBEARER,
# центр GRAVE ROBBER, низ-лево REAPER, низ-право BONE KING
cs = [center(p) for p in paths]
xs = sorted(c[0] for c in cs); ys = sorted(c[1] for c in cs)
midx, midy = (xs[0] + xs[-1]) / 2, (ys[0] + ys[-1]) / 2
def slot(c):
    if abs(c[0] - midx) < 60 and abs(c[1] - midy) < 60:
        return "GRAVE ROBBER"
    if c[1] > midy:
        return "GRAVEDIGGER" if c[0] < midx else "PALLBEARER"
    return "REAPER" if c[0] < midx else "BONE KING"
names = [slot(c) for c in cs]
assert len(set(names)) == 5, names

def rdp(pts, eps):
    if len(pts) < 3:
        return pts
    # итеративно
    keep = [False] * len(pts)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        i, j = stack.pop()
        ax, ay = pts[i]; bx, by = pts[j]
        dx, dy = bx - ax, by - ay
        L = math.hypot(dx, dy)
        best, bi = 0.0, -1
        for k in range(i + 1, j):
            px, py = pts[k]
            d = abs(dx * (ay - py) - dy * (ax - px)) / L if L > 1e-12 else math.hypot(px - ax, py - ay)
            if d > best:
                best, bi = d, k
        if best > eps:
            keep[bi] = True
            stack.append((i, bi)); stack.append((bi, j))
    return [p for p, k in zip(pts, keep) if k]

lines = ["--!strict", "-- ModuleScript: ReplicatedStorage.SkullShapes",
         "-- ЧЕРЕПА ПО РАНГАМ ИЗ ВЕКТОРА ЮЗЕРА (D:\\VECTOR\\skull_range.ai, 2026-09-12): пять силуэтов с",
         "-- лентой и именем ранга. Ранг теперь отличается формой, а не цветом (цвет у всех bone).",
         "-- Формат — как у SkullOutline: Loops[i] = список {x, y}, ширина рисунка = 1, центр в",
         "-- нуле, Y вверх; контуры разомкнуты (замыкает потребитель), заливка по чётности —",
         "-- глазницы, буквы на ленте и просветы вырезаны насквозь. Сгенерировано",
         "-- scratchpad/ai_to_lua.py (разбор PDF-стримов .ai, Безье дроблены, RDP %.4f)." % TOL,
         "local SkullShapes = {", "\tShapes = {"]
total = 0
for p, name in zip(paths, names):
    pts = [pt for s in p["subs"] for pt in s]
    minx = min(a[0] for a in pts); maxx = max(a[0] for a in pts)
    miny = min(a[1] for a in pts); maxy = max(a[1] for a in pts)
    w = maxx - minx
    cx, cy = (minx + maxx) / 2, (miny + maxy) / 2
    loops = []
    for s in p["subs"]:
        if len(s) < 3:
            continue
        # замкнутый контур: дубликат стартовой точки в конце убрать
        if math.hypot(s[0][0] - s[-1][0], s[0][1] - s[-1][1]) < 1e-6:
            s = s[:-1]
        norm = [((a[0] - cx) / w, (a[1] - cy) / w) for a in s]
        simp = rdp(norm + [norm[0]], TOL)[:-1]
        if len(simp) >= 3:
            loops.append(simp)
    total += sum(len(l) for l in loops)
    lines.append('\t\t["%s"] = {' % name)
    for l in loops:
        lines.append("\t\t\t{" + ",".join("{%.5f,%.5f}" % (a[0], a[1]) for a in l) + "},")
    lines.append("\t\t},")
    print(f"{name}: loops={len(loops)} pts={sum(len(l) for l in loops)} aspect={(maxy-miny)/w:.3f}", file=sys.stderr)
lines += ["\t},", "}", "return SkullShapes", ""]
open(out, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
print("total pts", total, file=sys.stderr)
