# Общее для процедурных текстур кузовов (coffin_texture.py, buggy_texture.py):
# импорт FBX → карты позиции/нормали/AO в атлас развёртки → numpy-шум → PNG + сырой RGBA
# для предпросмотра в Studio → FBX со встроенной текстурой. Развёртка не трогается.
import bpy, os
import numpy as np


def bake_maps(src_fbx, atlas, ao_samples=48, ao_distance=1.6):
    """Импортирует FBX, применяет поворот узла в меш (object space == world space) и печёт
    POSITION / NORMAL(object) / AO в атлас. Возвращает (P, N, A, ctx): массивы atlas×atlas
    (строки снизу вверх, как в Blender) и контекст для экспорта."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=src_fbx)
    ob = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
    me = ob.data
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True); bpy.context.view_layer.objects.active = ob
    # поворот узла — в данные меша (см. coffin_v2.py), иначе Roblox ставит кузов на нос
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    vs = np.array([v.co[:] for v in me.vertices])
    lo, hi = vs.min(0), vs.max(0)
    print("bbox lo", lo.round(2), "hi", hi.round(2))

    mat = bpy.data.materials.new("BodyMat"); mat.use_nodes = True
    nt = mat.node_tree
    bsdf = [n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'][0]
    tgt = nt.nodes.new("ShaderNodeTexImage")
    nt.nodes.active = tgt
    me.materials.clear(); me.materials.append(mat)

    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.render.bake.margin = 24
    scene.render.bake.margin_type = 'EXTEND'
    scene.render.bake.use_selected_to_active = False
    scene.render.bake.normal_space = 'OBJECT'
    world = bpy.data.worlds.new("w"); scene.world = world
    world.use_nodes = True
    try:
        world.light_settings.distance = ao_distance
    except Exception as e:
        print("ao distance:", e)

    def bake(kind, samples, name):
        img = bpy.data.images.new(name, atlas, atlas, alpha=False, float_buffer=True)
        img.colorspace_settings.name = 'Non-Color'
        tgt.image = img
        scene.cycles.samples = samples
        bpy.ops.object.bake(type=kind)
        return np.array(img.pixels[:], dtype=np.float32).reshape(atlas, atlas, 4)

    P = bake('POSITION', 1, "pos")[..., :3]
    N = bake('NORMAL', 1, "nrm")[..., :3] * 2.0 - 1.0
    A = bake('AO', ao_samples, "ao")[..., 0]
    print("pos range", P.reshape(-1, 3).min(0).round(2), P.reshape(-1, 3).max(0).round(2), "ao mean %.3f" % A.mean())
    ctx = {"ob": ob, "me": me, "nt": nt, "tgt": tgt, "bsdf": bsdf, "lo": lo, "hi": hi, "atlas": atlas}
    return P, N, A, ctx


# --- шум (value noise + fBm), детерминированный по seed ---
def hsh(ix, iy, seed):
    n = (np.asarray(ix).astype(np.int64) * 374761393 + np.asarray(iy).astype(np.int64) * 668265263 + seed * 1442695041) & 0x7fffffff
    n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
    return ((n ^ (n >> 16)) & 0xffff) / 65535.0


def vnoise(x, y, seed):
    xi = np.floor(x); yi = np.floor(y)
    xf = x - xi; yf = y - yi
    u = xf * xf * (3 - 2 * xf); v = yf * yf * (3 - 2 * yf)
    a = hsh(xi, yi, seed); b = hsh(xi + 1, yi, seed); c = hsh(xi, yi + 1, seed); d = hsh(xi + 1, yi + 1, seed)
    return (a * (1 - u) + b * u) * (1 - v) + (c * (1 - u) + d * u) * v


def fbm(x, y, seed, octaves=4):
    s = np.zeros_like(x); amp = 0.5; f = 1.0; tot = 0.0
    for k in range(octaves):
        s += amp * vnoise(x * f, y * f, seed + k * 101); tot += amp; amp *= 0.5; f *= 2.0
    return s / tot


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


# --- вывод ---
def write_outputs(col, ctx, out_png, out_dir, out_fbx_name, raw_name):
    """PNG в репо, сырой RGBA (строки сверху) для EditableImage, FBX со встроенной текстурой."""
    atlas = ctx["atlas"]
    col = np.clip(col, 0, 1).astype(np.float32)
    out = bpy.data.images.new(os.path.splitext(os.path.basename(out_png))[0], atlas, atlas, alpha=False)
    out.pixels[:] = np.concatenate([col, np.ones((atlas, atlas, 1), np.float32)], axis=2).ravel().tolist()
    out.filepath_raw = out_png; out.file_format = 'PNG'; out.save()
    print("png ->", out_png)
    raw = (col[::-1] * 255 + 0.5).astype(np.uint8)
    raw = np.concatenate([raw, np.full((atlas, atlas, 1), 255, np.uint8)], axis=2)
    os.makedirs(out_dir, exist_ok=True)
    open(os.path.join(out_dir, raw_name), "wb").write(raw.tobytes())
    ctx["tgt"].image = out
    out.colorspace_settings.name = 'sRGB'
    ctx["nt"].links.new(ctx["tgt"].outputs["Color"], ctx["bsdf"].inputs["Base Color"])
    out_fbx = os.path.join(out_dir, out_fbx_name)
    bpy.ops.export_scene.fbx(filepath=out_fbx, use_selection=True, apply_scale_options='FBX_SCALE_ALL',
                             bake_space_transform=True, path_mode='COPY', embed_textures=True,
                             use_tspace=True, object_types={'MESH'})
    print("exported", out_fbx, os.path.getsize(out_fbx))
