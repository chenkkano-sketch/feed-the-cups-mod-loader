"""Create the native compatibility declarations from this game's pack index."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[2]
HOME = ROOT / 'FTCModLoader'
extensions = [
    {'scene':'res://TscnAndGd/Logics/GameLogic/GameLogic.tscn','base_script':'res://TscnAndGd/Logics/GameLogic/GameLogic.gd','script':'TalentGameLogic.gd'},
    {'scene':'res://TscnAndGd/Logics/GameLogic/GameLogic.tscn','base_script':'res://TscnAndGd/Logics/GameLogic/AStarLogic.gd','script':'TalentAstar.gd'},
    {'scene':'res://TscnAndGd/UI/InGame/DayEndUI.tscn','base_script':'res://TscnAndGd/UI/InGame/DayEndUI.gd','script':'TalentDayEnd.gd'},
]
targets = {
    'res://TscnAndGd/Main/Level/NewLevel.gd':'TalentLevel.gd',
    'res://TscnAndGd/Objects/Devices/Con_Liquid.gd':'Helpers/CoffeeReceiver.gd',
}
with (ROOT/'Feed the Cups.pck').open('rb') as pack:
    for path, offset, size in json.loads((ROOT/'mods/trainer_work/index.json').read_text('utf8')):
        if not path.endswith('.tscn'):continue
        pack.seek(offset)
        content = pack.read(size)
        for base, script in targets.items():
            if base.encode() in content:
                extensions.append({'scene':path,'base_script':base,'script':script})
manifest = dict(schema_version=1, id='ftc.talent_market', name='人才市场', version='1.1.0', api_version='1.0',game_versions=['1.0.1.2'],loader_version='>=1.0.2',entry='Entry.gd',
    description='F3 招聘统一店员，每日五位候选、最多四位在职，六星稀有度与四格独立随机主动技能、被动技能及被动减益；原生角色皮肤衣装和动态形象卡。技能决定点单、制饮、冲煮、整理、补杯、清洁、维修及高级丢垃圾，付费刷新100元起翻倍、次日重置；基薪保留，日薪与离职金随天数上涨，真实库存兼容正式关卡、自由搬运和房租模式。',
    capabilities=['gameplay','input','ui','config','save'],dependencies={},conflicts=[],load_after=['ftc.furniture_carry','ftc.trainer'],script_extensions=extensions)
(HOME/'Mods/ftc.talent_market/mod.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
rent=HOME/'Mods/ftc.rent_mode/mod.json'
data=json.loads(rent.read_text('utf8'))
if 'ftc.talent_market' not in data.setdefault('load_after',[]):data['load_after'].append('ftc.talent_market')
data['version']='0.9.0'
rent.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
for name, mods in [('talent',['ftc.furniture_carry','ftc.talent_market']),('talent_rent',['ftc.furniture_carry','ftc.talent_market','ftc.rent_mode']),('talent_all',['ftc.furniture_carry','ftc.talent_market','ftc.rent_mode','ftc.trainer'])]:
    (HOME/'Profiles'/(name+'.json')).write_text(json.dumps({'enabled':mods},indent=2)+'\n',encoding='utf8')
default=HOME/'Profiles/default.json'
data=json.loads(default.read_text('utf8'))
if 'ftc.talent_market' not in data['enabled']:data['enabled'].append('ftc.talent_market')
default.write_text(json.dumps(data,indent=2)+'\n',encoding='utf8')
print('Talent native extensions:',len(extensions))
