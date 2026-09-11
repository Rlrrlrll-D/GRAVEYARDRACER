import bpy, bmesh, os
from mathutils import Vector

SP = r"D:/GraveyardRacer/GraveyardRacer/tools/blender/_out"  # выход: сюда, потом руками в meshes/
SRC = r"D:/GraveyardRacer/GraveyardRacer/meshes/CoffinBody.fbx"
OUT_FBX = os.path.join(SP, "out", "CoffinBody.fbx")

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=SRC)
ob = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
me = ob.data
before = (len(me.vertices), len(me.polygons))

bm = bmesh.new()
bm.from_mesh(me)
bm.verts.ensure_lookup_table()
seen = set()
islands = []
for v in bm.verts:
    if v.index in seen:
        continue
    stack = [v]
    comp = []
    seen.add(v.index)
    while stack:
        cur = stack.pop()
        comp.append(cur)
        for e in cur.link_edges:
            o = e.other_vert(cur)
            if o.index not in seen:
                seen.add(o.index)
                stack.append(o)
    islands.append(comp)

# Ручки: кубики 8 вершин на высоте 2.66..2.96 у бортов (|x| >= 1.85): скоба + два уха, по три на борт.
kill = []
for comp in islands:
    lo_y = min(v.co.y for v in comp)
    hi_y = max(v.co.y for v in comp)
    min_ax = min(abs(v.co.x) for v in comp)
    if len(comp) == 8 and lo_y >= 2.6 and hi_y <= 3.0 and min_ax >= 1.8:
        kill.append(comp)
print("handle islands to delete:", len(kill))
verts = [v for comp in kill for v in comp]
bmesh.ops.delete(bm, geom=verts, context='VERTS')
bm.to_mesh(me)
bm.free()
me.update()
after = (len(me.vertices), len(me.polygons))
print("verts/faces before", before, "after", after)

bpy.ops.object.select_all(action='DESELECT')
ob.select_set(True)
bpy.context.view_layer.objects.active = ob
bpy.ops.export_scene.fbx(filepath=OUT_FBX, use_selection=True, apply_scale_options='FBX_SCALE_ALL',
                         bake_space_transform=True, path_mode='COPY', embed_textures=True,
                         use_tspace=True, object_types={'MESH'})
print("exported", OUT_FBX, os.path.getsize(OUT_FBX))

# Контрольный рендер: до/после рядом
bpy.ops.import_scene.fbx(filepath=SRC)
orig = [o for o in bpy.context.scene.objects if o.type == 'MESH' and o != ob][0]
orig.location.x -= 8
ob.location.x += 0
scene = bpy.context.scene
scene.render.engine = 'BLENDER_WORKBENCH'
scene.display.shading.light = 'STUDIO'
scene.display.shading.color_type = 'MATERIAL'
scene.render.resolution_x = 1000
scene.render.resolution_y = 500
world = bpy.data.worlds.new("w"); scene.world = world; world.color = (0.12, 0.12, 0.14)
cam_data = bpy.data.cameras.new("cam"); cam = bpy.data.objects.new("cam", cam_data); scene.collection.objects.link(cam)
scene.camera = cam
cam_data.lens = 35
center = Vector((-4, 0, 3))
pos = center + Vector((6, -20, 9))
cam.location = pos
cam.rotation_euler = (center - pos).to_track_quat('-Z', 'Y').to_euler()
scene.render.filepath = os.path.join(SP, "coffin_before_after.png")
bpy.ops.render.render(write_still=True)
print("DONE")
