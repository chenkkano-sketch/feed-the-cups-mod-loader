"""Developer-only migration. Installed modules are self-contained; launch needs no Python."""
from pathlib import Path
import json, re, sys

ROOT = Path(__file__).resolve().parents[2]
HOME = ROOT / 'FTCModLoader'
sys.stdout.reconfigure(encoding='utf8')
if (HOME / 'Mods/ftc.furniture_carry/mod.json').exists():
    raise SystemExit('Legacy migration is retired: edit canonical FTCModLoader/Mods sources; rebuilding old sources would undo the furniture module extraction.')

def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n', 'utf8')

def migrate(source, module, names):
    target = HOME / 'Mods' / module
    target.mkdir(parents=True, exist_ok=True)
    for name in names:
        text = (ROOT / 'mods' / source / name).read_text('utf8')
        text = text.replace('res://mods/'+source+'/', 'res://ftc_mods/'+module+'/')
        (target / name).write_text(text, 'utf8')
    return target

trainer = migrate('single_player_trainer', 'ftc.trainer', ['Trainer.gd', 'OrderAssistant.gd'])
text = (trainer/'Trainer.gd').read_text('utf8')
text = text.replace('const SETTINGS = "res://ftc_mods/ftc.trainer/settings.cfg"', 'var SETTINGS = "user://ftc_mods/ftc.trainer/settings.cfg"\nvar mod_api')
def replace_function(text, name, body):
    pattern = r'^func '+re.escape(name)+r'\([^\n]*\):\n.*?(?=^func |\Z)'
    replacement = 'func '+name+'():\n'+body+'\n\n'
    text, count = re.subn(pattern, lambda _: replacement, text, count=1, flags=re.S|re.M)
    assert count == 1, name
    return text
text = replace_function(text, '_movement_tick', '\tvar context = _game_and_player()\n\tmod_api.set_movement_multiplier(MOVEMENT_SPEEDS[movement_speed_index] if not context.empty() else 1.0)')
text = replace_function(text, '_restore_movement', '\tif mod_api != null:\n\t\tmod_api.set_movement_multiplier(1.0)')
text = replace_function(text, '_apply_scale', '\tmod_api.set_game_speed(SPEEDS[speed_index])')
text = replace_function(text, '_restore_scale', '\tif mod_api != null:\n\t\tmod_api.set_game_speed(1.0)')
(trainer/'Trainer.gd').write_text(text,'utf8')
(trainer/'Entry.gd').write_text('''extends Reference
var api
var trainer
func on_load(context):
    api = context
    trainer = preload("res://ftc_mods/ftc.trainer/Trainer.gd").new()
    trainer.mod_api = api
    trainer.SETTINGS = api.config_path()
    # Import preferences once; existing loose trainer files remain usable.
    var previous = OS.get_executable_path().get_base_dir().plus_file("mods/single_player_trainer/settings.cfg")
    var file = File.new()
    if not file.file_exists(trainer.SETTINGS) and file.file_exists(previous):
        Directory.new().copy(previous, trainer.SETTINGS)
    if api.add_root("FtcSinglePlayerTrainer", trainer) == null:
        return false
    api.provide_service("trainer", trainer)
    return true
func on_unload():
    if is_instance_valid(trainer):
        trainer.reset_all()
''', 'utf8')
write_json(trainer/'mod.json', {
    'schema_version':1,'id':'ftc.trainer','name':'单机修改器','version':'3.0.0','api_version':'1.0',
    'game_versions':['1.0.1.2'],'entry':'Entry.gd','description':'I 装填当前订单；F7 自动配料；F8 自动点单并取杯；F5 移动倍率；F6 游戏倍率；F9 显隐；F10 重置。使用公共 API 叠加移动和游戏速度。',
    'capabilities':['gameplay','ui','config','save'],'dependencies':{},'conflicts':[]
})

rent = migrate('rent_mode','ftc.rent_mode',[p.name for p in (ROOT/'mods/rent_mode').glob('*.gd') if p.name != 'RentPlayerControl.gd'])
rent_source = rent/'RentMode.gd'
rent_source.write_text(rent_source.read_text('utf8').replace('房租模式 v0.6.1','房租模式 v0.7.0'), 'utf8')
(rent/'Entry.gd').write_text('''extends Reference
var api
var rent
func on_load(context):
    api = context
    rent = preload("res://ftc_mods/ftc.rent_mode/RentMode.gd").new()
    if api.add_root("RentMode", rent) == null:
        return false
    api.provide_service("mode", rent)
    api.register_control_hook(self, "_control", 100)
    api.register_movement_provider(rent.sprint, "factor_for")
    return true
func _control(actor, button, value, type):
    if rent.sprint.reserves_shift(actor, button, type):
        return true
    return rent.carry.handle_control(actor, button, value)
''', 'utf8')
extension_specs = [
 ('res://TscnAndGd/Logics/GameLogic/GameLogic.tscn','res://TscnAndGd/Logics/SystemLogic/ConfigLogic.gd','RentConfig.gd'),
 ('res://TscnAndGd/Logics/GameLogic/GameLogic.tscn','res://TscnAndGd/Logics/GameLogic/GameLogic.gd','RentGameLogic.gd')
]
for scene,script in [('DayEndUI','RentDayEnd'),('DayControl','RentDayControl'),('GameUI','RentGameUI'),('RewardUI','RentReward'),('MenuUI','RentProductMenu')]:
    extension_specs.append((f'res://TscnAndGd/UI/InGame/{scene}.tscn',f'res://TscnAndGd/UI/InGame/{scene}.gd',script+'.gd'))
write_json(rent/'mod.json', {
 'schema_version':1,'id':'ftc.rent_mode','name':'房租模式','version':'0.7.0','api_version':'1.0','game_versions':['1.0.1.2'],
 'entry':'Entry.gd','description':'三张实景地图、自选开局、无尽付租、三日上新、每天卡片升级、不限时准备、完整设施搬运和 Shift 残影冲刺。兼容原有独立房租存档。',
 'capabilities':['gameplay','input','ui','config','save','levels'],'save_profile':'rent_mode','dependencies':{},'conflicts':[],
 'script_extensions':[dict(scene=a,base_script=b,script=c) for a,b,c in extension_specs],
 'scene_clones':[{'source':f'res://TscnAndGd/Main/Level/{mid}.tscn','destination':f'res://TscnAndGd/Main/Level/RentRoom_{mid}.tscn','base_script':'res://TscnAndGd/Main/Level/NewLevel.gd','script':'RentLevel.gd'} for mid in ['2_1','2_2','2_3']],
 'animation_aliases':[{'resource':'res://TscnAndGd/Logics/SystemLogic/AudioLogic.tscn','from':'美食街2','to':'房租模式'}],
 'levels':[{'name':'房租模式','base':'美食街2','values':{
  'TSCN':'RentRoom_2_2','Name':'RentRoom','Info':'房租模式：无尽经营','Rent':'0','Menu':['橙汁S'],'Funds':'1500','Popular':'1',
  'GamePlay':[],'Difficult':['无'],'DevilList':[],'Mission_1':'-1','Mission_2':'-1','MenuMax':'3',
  'Type':['FRUIT','MILKTEA','MILK','TEA'],'Tag':['初始','混合','红豆'],'DrinkTypeList':['FRUIT','MILKTEA','MILK','TEA'],
  'CustomersList':['LittleCup'],'M':'','L':'','ExtraMax':'1','MenuList':[],'DevilMax':'0'
 }}]
})
for profile,enabled in [('default',['ftc.rent_mode','ftc.trainer']),('both',['ftc.rent_mode','ftc.trainer']),('rent',['ftc.rent_mode']),('trainer',['ftc.trainer'])]:
    path=HOME/'Profiles'/f'{profile}.json'
    if not path.exists(): write_json(path,{'enabled':enabled})
print('Migrated self-contained modules:',trainer,rent)
