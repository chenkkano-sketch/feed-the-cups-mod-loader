from pathlib import Path
import argparse, hashlib, json, re, subprocess, zipfile, sys

ROOT=Path(__file__).resolve().parents[2]
HOME=ROOT/'FTCModLoader'
sys.stdout.reconfigure(encoding='utf8')
parser=argparse.ArgumentParser()
parser.add_argument('--skip-loader-build',action='store_true',help='Package an unchanged, already-built loader with updated modules.')
args=parser.parse_args()
loader_binary=HOME/'Packages/loader-build.exe'
if not args.skip_loader_build:
    loader_binary.parent.mkdir(exist_ok=True)
    subprocess.run(['pwsh','-NoProfile','-File',str(HOME/'src/build_loader.ps1'),'-Output',str(loader_binary)],check=True)
elif not loader_binary.is_file():
    parser.error('The existing loader executable is required with --skip-loader-build.')
packages=HOME/'Packages';packages.mkdir(exist_ok=True)
source=(HOME/'src/Loader.cs').read_text(encoding='utf8')
version=re.search(r'public const string Version = "(\d+\.\d+\.\d+)";',source).group(1)
current_packages=[]
for folder in sorted((HOME/'Mods').iterdir()):
    if not folder.is_dir():continue
    manifest=json.loads((folder/'mod.json').read_text('utf8'))
    output=packages/f"{manifest['id']}-{manifest['version']}.ftcmod"
    current_packages.append(output)
    with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as archive:
        for path in sorted(folder.rglob('*')):
            if path.is_file():archive.write(path,path.relative_to(folder).as_posix())
sample=HOME/'SDK/Example'
sample_package=packages/'example.hello-1.0.0.ftcmod'
current_packages.append(sample_package)
with zipfile.ZipFile(sample_package,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as archive:
    for path in sorted(sample.rglob('*')):
        if path.is_file():archive.write(path,path.relative_to(sample).as_posix())
output=packages/f'FTCModLoader-{version}.zip'
temporary=output.with_name(output.name+'.tmp')
with zipfile.ZipFile(temporary,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as archive:
    archive.writestr('FTCModLoader/release.json',json.dumps({'version':version,'repository':'https://github.com/chenkkano-sketch/feed-the-cups-mod-loader'},ensure_ascii=False))
    archive.write(loader_binary,'杯杯倒满Mod加载器.exe')
    for directory in ['Core','SDK','Profiles']:
        for path in sorted((HOME/directory).rglob('*')):
            if path.is_file():archive.write(path,path.relative_to(ROOT).as_posix())
    for path in [HOME/'使用说明.txt',HOME/'联机安装说明.txt']+sorted(current_packages):
        archive.write(path,path.relative_to(ROOT).as_posix())
with zipfile.ZipFile(temporary) as archive:
    if archive.testzip() is not None:
        raise RuntimeError('Release ZIP verification failed; previous release retained.')
temporary.replace(output)
digest=hashlib.sha256(output.read_bytes()).hexdigest()
output.with_name(output.name+'.sha256').write_text(f'{digest}  {output.name}\n',encoding='ascii')
print(json.dumps({'release':str(output),'bytes':output.stat().st_size,'packages':[{ 'name':p.name,'bytes':p.stat().st_size} for p in sorted(current_packages)]},ensure_ascii=False))
