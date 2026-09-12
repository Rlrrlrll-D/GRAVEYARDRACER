# Разбор .ai (PDF-совместимый Illustrator): контуры из content-стримов страницы.
import re, sys, zlib, json, math

path = sys.argv[1]
data = open(path, "rb").read()

# --- все стримы объектов ---
objs = re.finditer(rb"(\d+)\s+(\d+)\s+obj(.*?)endobj", data, re.S)
streams = []
for m in objs:
    body = m.group(3)
    sm = re.search(rb"stream\r?\n", body)
    if not sm:
        continue
    head = body[:sm.start()]
    raw = body[sm.end():]
    em = raw.rfind(b"endstream")
    raw = raw[:em]
    if b"FlateDecode" in head:
        try:
            raw = zlib.decompress(raw)
        except Exception as e:
            try:
                raw = zlib.decompressobj().decompress(raw)
            except Exception:
                continue
    streams.append((int(m.group(1)), head, raw))

# content streams: содержат операторы путей
tok_re = re.compile(rb"/?[A-Za-z_][A-Za-z0-9_*]*|[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?|\[|\]|<<|>>|\(|\)")
paths_all = []
for num, head, raw in streams:
    if b" cm" not in raw and b" c\n" not in raw and b" l\n" not in raw and b"\nm" not in raw and b" m\n" not in raw:
        continue
    # простой токенизатор
    toks = tok_re.findall(raw)
    stack = []
    ctm = [1, 0, 0, 1, 0, 0]
    gs = []
    cur = None  # текущий путь: список подпутей, каждый — список точек
    sub = None
    start = None
    def apply(pt):
        a, b, c, d, e, f = ctm
        x, y = pt
        return (a * x + c * y + e, b * x + d * y + f)
    def bez(p0, p1, p2, p3, n=24):
        out = []
        for i in range(1, n + 1):
            t = i / n
            mt = 1 - t
            x = mt**3 * p0[0] + 3 * mt**2 * t * p1[0] + 3 * mt * t**2 * p2[0] + t**3 * p3[0]
            y = mt**3 * p0[1] + 3 * mt**2 * t * p1[1] + 3 * mt * t**2 * p2[1] + t**3 * p3[1]
            out.append((x, y))
        return out
    npaths = 0
    for t in toks:
        s = t.decode("latin1")
        if re.fullmatch(r"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?", s):
            stack.append(float(s))
            continue
        op = s
        if op == "q":
            gs.append(list(ctm))
        elif op == "Q":
            if gs:
                ctm = gs.pop()
        elif op == "cm" and len(stack) >= 6:
            a, b, c, d, e, f = stack[-6:]
            A, B, C, D, E, F = ctm
            ctm = [a * A + b * C, a * B + b * D, c * A + d * C, c * B + d * D, e * A + f * C + E, e * B + f * D + F]
        elif op == "m" and len(stack) >= 2:
            if cur is None:
                cur = []
            sub = [apply((stack[-2], stack[-1]))]
            start = sub[0]
            cur.append(sub)
        elif op == "l" and len(stack) >= 2 and sub is not None:
            sub.append(apply((stack[-2], stack[-1])))
        elif op == "c" and len(stack) >= 6 and sub is not None:
            p0 = sub[-1]
            p1, p2, p3 = apply((stack[-6], stack[-5])), apply((stack[-4], stack[-3])), apply((stack[-2], stack[-1]))
            sub.extend(bez(p0, p1, p2, p3))
        elif op == "v" and len(stack) >= 4 and sub is not None:
            p0 = sub[-1]
            p2, p3 = apply((stack[-4], stack[-3])), apply((stack[-2], stack[-1]))
            sub.extend(bez(p0, p0, p2, p3))
        elif op == "y" and len(stack) >= 4 and sub is not None:
            p0 = sub[-1]
            p1, p3 = apply((stack[-4], stack[-3])), apply((stack[-2], stack[-1]))
            sub.extend(bez(p0, p1, p3, p3))
        elif op == "h":
            pass
        elif op == "re" and len(stack) >= 4:
            x, y, w, h = stack[-4:]
            if cur is None:
                cur = []
            sub = [apply((x, y)), apply((x + w, y)), apply((x + w, y + h)), apply((x, y + h))]
            cur.append(sub)
        elif op in ("f", "f*", "F", "B", "B*", "b", "b*", "S", "s", "n"):
            if cur:
                npaths += 1
                paths_all.append({"op": op, "subs": cur, "stream": num})
            cur = None
            sub = None
        if op not in ("cm",):
            stack = [] if not re.fullmatch(r"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?", s) else stack
        else:
            stack = []
    print(f"stream {num}: {len(raw)} bytes, paths {npaths}", file=sys.stderr)

# сводка
def bbox(pts):
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)
print(f"total paths: {len(paths_all)}", file=sys.stderr)
for i, p in enumerate(paths_all):
    allpts = [pt for s in p["subs"] for pt in s]
    b = bbox(allpts)
    print(f"path {i}: op={p['op']} subs={len(p['subs'])} pts={len(allpts)} bbox=({b[0]:.1f},{b[1]:.1f})-({b[2]:.1f},{b[3]:.1f})", file=sys.stderr)
json.dump(paths_all, open(sys.argv[2], "w"))
