"""Derive a playable shop layout from the native tutorial, without its cutscene.

The output is a layout resource. RentLevel installs it before native onready /
ready, so the cloned ordinary level retains furniture and talent extensions.
"""
from pathlib import Path
import re, struct

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT/'FTCModLoader/Mods/ftc.rent_mode/Maps/TutorialShop.tscn'

def native_resource(name):
    with (ROOT/'Feed the Cups.pck').open('rb') as f:
        f.seek(84)
        count = struct.unpack('<I', f.read(4))[0]
        for _ in range(count):
            n = struct.unpack('<I', f.read(4))[0]
            path = f.read(n).rstrip(b'\0').decode('utf8')
            off, size = struct.unpack('<QQ', f.read(16))
            f.read(16)
            if path == name:
                f.seek(off)
                return f.read(size).decode('utf8')
    raise ValueError(name)

source = native_resource('res://TscnAndGd/Main/Level/1_4.tscn')
sections = re.split(r'(?=^\[)', source, flags=re.M)
ext, sub, nodes = {}, {}, []
for block in sections:
    if block.startswith('[ext_resource '):
        ext[int(re.search(r' id=(\d+)', block)[1])] = block
    elif block.startswith('[sub_resource '):
        sub[int(re.search(r' id=(\d+)', block)[1])] = block
    elif block.startswith('[node '):
        nodes.append(block)

def metadata(block):
    head = block.splitlines()[0]
    name = re.search(r'name="([^"]+)"', head)[1]
    p = re.search(r'parent="([^"]+)"', head)
    return name, p[1] if p else ''

def resource(path):
    for i, b in ext.items():
        if 'path="'+path+'"' in b:
            return i
    i = max(ext)+1
    ext[i] = '[ext_resource path="%s" type="PackedScene" id=%d]\n\n' % (path, i)
    return i

def device(name, parent, kind, properties='', index=''):
    return '[node name="%s" parent="%s"%s instance=ExtResource( %d )]\n%s\n\n' % (name, parent, index, resource('res://TscnAndGd/Objects/Devices/'+kind+'.tscn'), properties)

def shape(extents):
    i = max(sub)+1
    sub[i] = '[sub_resource type="RectangleShape2D" id=%d]\nextents = Vector2( %d, %d )\n\n' % (i,*extents)
    return i

layout = ['[node name="TutorialShop" type="Node2D"]\n\n', '[node name="YSort" type="YSort" parent="."]\n\n']
for name in ['Players','NPCs','Items','Devices','Updates','Decorate','Lamp']:
    layout.append('[node name="%s" type="YSort" parent="YSort"]\n\n' % name)

# Preserve the real layout, not animation tracks or tutorial-only prop overrides.
for b in nodes:
    name, parent = metadata(b)
    if parent == 'YSort/Devices':
        ins = re.search(r'instance=ExtResource\( (\d+) \)', b.splitlines()[0])
        if not ins:
            continue
        props = '\n'.join(l for l in b.splitlines()[1:] if l.startswith(('position =','Tex =','CanPutDev =')))
        if name in ['pick1','pick2','pick3']:
            props += '\nCanPutDev = false'
        layout.append(b.splitlines()[0]+'\n'+props+'\n\n')
    elif parent in ['YSort/Devices/Order/ObjNode','YSort/Devices/Order2/ObjNode','YSort/Devices/Order3/ObjNode']:
        layout.append(device('OrderTab',parent,'OrderTab',index=' index="0"'))
    elif parent.startswith('YSort/Devices/') and parent.endswith('/ObjNode') and len(parent.split('/')) == 4:
        ins = re.search(r'instance=ExtResource\( (\d+) \)', b.splitlines()[0])
        if ins:
            layout.append(b.splitlines()[0]+'\n\n')

for table, kind in [('sugar','SugarMachine'),('ice','IceMachine'),('hotwater','HotWaterMachine'),('Coffee','CoffeeMachine'),('incooker','InductionCooker'),('Condi','TeaPort'),('E5','WaterPort'),('E6','TeaPort'),('E7','WaterPort')]:
    layout.append(device(kind,'YSort/Devices/'+table+'/ObjNode',kind,index=' index="0"'))
# The tutorial's tall freezer is a painted prop. Use native saved equipment.
layout.append(device('TallFreezer','YSort/Devices','FreezerBox_Big','position = Vector2( 950, 525 )'))

for b in nodes:
    name, parent = metadata(b)
    if parent == 'YSort' and name in ['Building','Outdoor','Other','WallPaper'] or any(parent == 'YSort/'+p or parent.startswith('YSort/'+p+'/') for p in ['Building','Outdoor','Other','WallPaper']):
        # Drop cinematic mop props while retaining the native sink fixture.
        if name in ['Mop','MopPool','Pool'] or any('/'+x in parent for x in ['Mop','MopPool','Pool']):
            continue
        if name == 'DeviceMopPool' and parent == 'YSort/Other':
            b += '_TEST = true\n\n'
        if name == 'PhoneOnWall' and parent == 'YSort/Other':
            b = re.sub(r'^script = null\n', '', b, flags=re.M)
        if name == 'Trashbin3' and parent == 'YSort/Outdoor':
            b = re.sub(r'^position = .*$', 'position = Vector2( -950, 650 )', b, flags=re.M)
        b = re.sub(r'^material = .*\n', '', b, flags=re.M)
        layout.append(b)
    elif parent == '.' and name == 'MapNode' or parent == 'MapNode' or parent.startswith('MapNode/'):
        if name == 'StreetMain' and parent == 'MapNode':
            b = b.replace('name="StreetMain"','name="StreetVisual"',1)
        layout.append(b)

# The cinematic omitted the door trigger and the painted staff locker's body.
locker_shape = shape((50,50))
door_shape = shape((100,85))
layout += [
    '[node name="SolidBody" type="StaticBody2D" parent="YSort/Other/StaffLocker"]\ncollision_layer = 128\ncollision_mask = 512\n\n',
    '[node name="CollisionShape2D" type="CollisionShape2D" parent="YSort/Other/StaffLocker/SolidBody"]\nshape = SubResource( %d )\n\n' % locker_shape,
    '[node name="AreaNode" type="Node2D" parent="YSort/WallPaper/StaffDoor"]\n\n',
    '[node name="Area2D" type="Area2D" parent="YSort/WallPaper/StaffDoor/AreaNode"]\ncollision_layer = 0\ncollision_mask = 9734\n\n',
    '[node name="CollisionShape2D" type="CollisionShape2D" parent="YSort/WallPaper/StaffDoor/AreaNode/Area2D"]\nposition = Vector2( 75, -50 )\nshape = SubResource( %d )\n\n' % door_shape,
]

# Logical navigation maps are absent in the cinematic. Reuse the native 100px
# tile set and construct separate kitchen, public and street regions.
base = native_resource('res://TscnAndGd/Main/Level/2_2.tscn')
base_subs = {int(re.search(r' id=(\d+)',b)[1]):b for b in re.split(r'(?=^\[)',base,flags=re.M) if b.startswith('[sub_resource ')}
base_exts = {int(re.search(r' id=(\d+)',b)[1]):b for b in re.split(r'(?=^\[)',base,flags=re.M) if b.startswith('[ext_resource ')}
floor_block = next(b for b in re.split(r'(?=^\[node )',base,flags=re.M)[1:] if metadata(b)==('Floor','MapNode'))
base_tile = int(re.search(r'tile_set = SubResource\( (\d+) \)',floor_block)[1])
tile_id = max(sub)+1
tile = base_subs[base_tile].replace(' id=%d]'%base_tile,' id=%d]'%tile_id)
for old in set(map(int,re.findall(r'ExtResource\( (\d+) \)',tile))):
    path = re.search(r'path="([^"]+)"',base_exts[old])[1]
    new = next((i for i,b in ext.items() if 'path="'+path+'"' in b),None)
    if new is None:
        new = max(ext)+1
        ext[new] = base_exts[old].replace(' id=%d]'%old,' id=%d]'%new)
    tile = tile.replace('ExtResource( %d )'%old,'ExtResource( %d )'%new)
assert not re.search(r'SubResource\(',tile), 'Unexpected nested logic tileset'
sub[tile_id]=tile

def logic_map(name,cells):
    values = []
    for x,y in sorted(cells,key=lambda p:(p[1],p[0])):
        word = ((y&65535)<<16)|(x&65535)
        if word >= 2**31: word -= 2**32
        values += [word,0,0]
    return '[node name="%s" type="TileMap" parent="MapNode"]\nvisible = false\nz_index = -5\ntile_set = SubResource( %d )\ncell_size = Vector2( 100, 100 )\nformat = 1\ntile_data = PoolIntArray( %s )\n\n' % (name,tile_id,', '.join(map(str,values)))

kitchen = {(x,y) for y in range(3,9) for x in range(-4,14) if (y<=6 or y==7 and x<=8 or y==8 and x<=2)}
public = {(x,y) for y in range(7,13) for x in range(-4,14)} - kitchen
street = {(x,y) for x in range(-13,22) for y in range(-6,20) if x <= -6 or x >= 15 or y <= 1 or y >= 14 or (y == 13 and 3 <= x <= 6)}
layout += [logic_map('Floor',kitchen),logic_map('NPCFloor',public),logic_map('Street',set()),logic_map('StreetMain',street)]
# Extend the visible pavement as well as navigation/camera bounds.
visual_street = next(b for b in layout if b.startswith('[node name="StreetVisual"'))
visual_tiles = re.search(r'tile_set = SubResource\( (\d+) \)',visual_street)[1]
paving = logic_map('ExteriorPaving',street).replace('visible = false\n','').replace('z_index = -5','z_index = -10').replace('tile_set = SubResource( %d )'%tile_id,'tile_set = SubResource( %s )'%visual_tiles)
layout.append(paving)
for name, points in [('PlayerPos2D',[(-50,450),(50,450),(150,450),(150,550)]),('Pos2DNode',[(-650,250),(1550,250),(-650,1250),(1550,1250)]),('DeliverPos',[(-350,750)]),('CameraPos2D',[(-1300,-600),(2200,2000)])]:
    layout.append('[node name="%s" type="Node2D" parent="."]\n\n'%name)
    for i,(x,y) in enumerate(points):
        child = ['LeftTop','RightBottom'][i] if name=='CameraPos2D' else str(i+1)
        layout.append('[node name="%s" type="Position2D" parent="%s"]\nposition = Vector2( %d, %d )\n\n'%(child,name,x,y))

# Only retain resources reachable from kept nodes. This also excludes megabytes
# of character/cutscene animation data and their script references.
body = ''.join(layout)
used_sub = set(map(int,re.findall(r'SubResource\( (\d+) \)',body)))
pending = list(used_sub)
while pending:
    i = pending.pop()
    for j in map(int,re.findall(r'SubResource\( (\d+) \)',sub[i])):
        if j not in used_sub:
            used_sub.add(j);pending.append(j)
resources = ''.join(sub[i] for i in sorted(used_sub))
used_ext = set(map(int,re.findall(r'ExtResource\( (\d+) \)',body+resources)))
output = '[gd_scene load_steps=%d format=2]\n\n'%(len(used_sub)+len(used_ext)+1)
output += ''.join(ext[i] for i in sorted(used_ext))+resources+body
output += '\n[connection signal="body_entered" from="YSort/WallPaper/StaffDoor/AreaNode/Area2D" to="YSort/WallPaper/StaffDoor" method="_on_player_entered"]\n'
output += '[connection signal="body_exited" from="YSort/WallPaper/StaffDoor/AreaNode/Area2D" to="YSort/WallPaper/StaffDoor" method="_on_player_exited"]\n'
OUT.parent.mkdir(parents=True,exist_ok=True)
OUT.write_text(output,'utf8')
print('Tutorial layout:',len(kitchen),'kitchen cells,',len(public),'public cells,',len(output.encode('utf8')),'bytes')
