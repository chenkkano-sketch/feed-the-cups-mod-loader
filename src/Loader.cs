using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Web.Script.Serialization;

namespace CupsModLoader {
public static class Data {
    public const string Version = "1.1.1";
    public const string Api = "1.0";
    public const string GameHash = "6bd9534ba18c2b8ed17db98b3080c85176d3d9c1cd80ead2ae3a9884b773b109";
    public const string ExeHash = "c52fb468fa1cb9c0fb048cd23c680023a16ad47e056fbf7b8e454340c924a745";
    public static readonly JavaScriptSerializer Json = new JavaScriptSerializer { MaxJsonLength = 16 * 1024 * 1024 };
    public static readonly UTF8Encoding Utf8 = new UTF8Encoding(false);
    public static Dictionary<string,object> Obj(object value) { var d = value as Dictionary<string,object>; if (d == null) throw new Exception("应为 JSON 对象。"); return d; }
    public static object[] Arr(object value) { return value as object[] ?? (value as ArrayList ?? new ArrayList()).ToArray(); }
    public static object Get(Dictionary<string,object> d, string key, object fallback) { object v; return d.TryGetValue(key, out v) ? v : fallback; }
    public static string Str(Dictionary<string,object> d, string key, string fallback = "") { return Convert.ToString(Get(d,key,fallback)); }
    public static Dictionary<string,object> Read(string path) { return Obj(Json.DeserializeObject(File.ReadAllText(path,Encoding.UTF8))); }
    public static void Write(string path, object value) { Directory.CreateDirectory(Path.GetDirectoryName(path)); string tmp = path + ".tmp"; File.WriteAllText(tmp,Json.Serialize(value),Utf8); if (File.Exists(path)) File.Replace(tmp,path,null); else File.Move(tmp,path); }
    public static string Hash(byte[] data) { using (var sha = SHA256.Create()) return Hex(sha.ComputeHash(data)); }
    public static string HashFile(string path) { using (var f=File.OpenRead(path)) using(var sha=SHA256.Create()) return Hex(sha.ComputeHash(f)); }
    public static string Hex(byte[] value) { return BitConverter.ToString(value).Replace("-", "").ToLowerInvariant(); }
    public static bool Id(string value) { return Regex.IsMatch(value, @"^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$") && value.Length <= 80; }
    public static bool Under(string path,string root) { return Path.GetFullPath(path).StartsWith(Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar)+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase); }
    public static string SafePath(string root, string relative) {
        if (String.IsNullOrWhiteSpace(relative) || relative.Contains(":") || relative.Contains("\\") || relative.StartsWith("/") || relative.Split('/').Any(s=>s==".." || s=="." || s=="")) throw new Exception("非法相对路径："+relative);
        foreach(var segment in relative.Split('/')) if(segment.TrimEnd(' ','.')!=segment || segment.IndexOfAny(Path.GetInvalidFileNameChars())>=0 || Regex.IsMatch(segment,@"^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)",RegexOptions.IgnoreCase)) throw new Exception("非法 Windows 路径："+relative);
        var path=Path.GetFullPath(Path.Combine(root,relative.Replace('/',Path.DirectorySeparatorChar)));
        if (!Under(path,root)) throw new Exception("路径超出模块目录："+relative);
        return path;
    }
    public static IEnumerable<string> Files(string root) {
        foreach(var entry in Directory.EnumerateFileSystemEntries(root).OrderBy(p=>p,StringComparer.Ordinal)) {
            if ((File.GetAttributes(entry)&FileAttributes.ReparsePoint)!=0) throw new Exception("Mod 不允许包含链接或联接："+entry);
            if (Directory.Exists(entry)) { foreach(var f in Files(entry)) yield return f; } else yield return entry;
        }
    }
    public static string Resource(string name) {
        if (!name.StartsWith("res://",StringComparison.Ordinal) || name.Substring(6).Split('/').Any(s=>s==".." || s=="." || s=="") || name.Contains("\\")) throw new Exception("非法资源路径："+name);
        return name;
    }
    public static bool Satisfies(string version,string requirement) {
        if (requirement=="*" || requirement=="") return true;
        Match m=Regex.Match(requirement,@"^(>=|\^|=)?(\d+)\.(\d+)\.(\d+)$");
        if(!m.Success) throw new Exception("不支持的版本范围："+requirement+"；可用精确版本、>=、^ 或 *。");
        var actual=new System.Version(version); var expected=new System.Version(m.Groups[2].Value+"."+m.Groups[3].Value+"."+m.Groups[4].Value);
        if(m.Groups[1].Value==">=") return actual>=expected;
        if(m.Groups[1].Value=="^") return actual>=expected && actual.Major==expected.Major;
        return actual==expected;
    }
}

public sealed class Mod {
    public string Id,Name,Version,Directory,Entry;
    public Dictionary<string,object> Manifest;
    public Mod(string directory) {
        Directory=directory; Manifest=Data.Read(Path.Combine(directory,"mod.json"));
        var allowed=new HashSet<string>(new[]{"schema_version","id","name","version","api_version","game_versions","entry","description","capabilities","dependencies","conflicts","load_after","save_profile","script_extensions","scene_clones","text_patches","animation_aliases","levels","author","website","license","loader_version"});
        foreach(var key in Manifest.Keys)if(!allowed.Contains(key))throw new Exception("未知清单字段："+key);
        foreach(var key in new[]{"game_versions","capabilities","conflicts","load_after","script_extensions","scene_clones","text_patches","animation_aliases","levels"})if(Manifest.ContainsKey(key)&&!(Manifest[key] is object[])&&!(Manifest[key] is ArrayList))throw new Exception("清单字段必须是数组："+key);
        Id=Data.Str(Manifest,"id"); Name=Data.Str(Manifest,"name",Id); Version=Data.Str(Manifest,"version"); Entry=Data.Str(Manifest,"entry");
        if(!Data.Id(Id) || !Regex.IsMatch(Version,@"^\d+\.\d+\.\d+$")) throw new Exception("Mod ID 或版本无效："+directory);
        if(Convert.ToInt32(Data.Get(Manifest,"schema_version",0))!=1 || Data.Str(Manifest,"api_version")!=Data.Api) throw new Exception(Name+" 使用了不兼容的清单/API 版本。");
        if(!Data.Satisfies(Data.Version,Data.Str(Manifest,"loader_version","*")))throw new Exception(Name+" 需要其他版本的加载器。");
        if(Data.Str(Manifest,"save_profile")!=""&&!Data.Id(Data.Str(Manifest,"save_profile")))throw new Exception("独立存档标识无效。");
        if(!Data.Arr(Data.Get(Manifest,"game_versions",new object[0])).Select(Convert.ToString).Contains("1.0.2.0")) throw new Exception(Name+" 未声明支持游戏 1.0.2.0。");
        if(!File.Exists(Data.SafePath(directory,Entry)) || !Entry.EndsWith(".gd",StringComparison.OrdinalIgnoreCase)) throw new Exception(Name+" 入口脚本缺失。");
        var capabilities=new HashSet<string>(new[]{"gameplay","input","ui","config","save","recipes","levels"});
        foreach(var cap in Data.Arr(Data.Get(Manifest,"capabilities",new object[0]))) if(!capabilities.Contains(Convert.ToString(cap))) throw new Exception("未知能力声明："+cap);
        Data.Obj(Data.Get(Manifest,"dependencies",new Dictionary<string,object>()));
        foreach(var file in Data.Files(directory)) { if(new FileInfo(file).Length>256L*1024*1024) throw new Exception("Mod 单文件过大："+file); }
    }
    public string Prefix { get { return "res://ftc_mods/"+Id+"/"; } }
    public string Resource(string relative) { Data.SafePath(Directory,relative); return Prefix+relative; }
}

public sealed class PackEntry {
    public string Name;
    public long Offset,Length;
    public byte[] Md5,Bytes;
}

public sealed class Pack {
    public Dictionary<string,PackEntry> Entries=new Dictionary<string,PackEntry>(StringComparer.Ordinal);
    public string Source;
    public Pack(string source) {
        Source=source;
        using(var f=File.OpenRead(source)) using(var r=new BinaryReader(f)) {
            if(r.ReadUInt32()!=0x43504447 || r.ReadUInt32()!=1) throw new Exception("不支持的游戏 PCK 格式。");
            f.Position=84; uint count=r.ReadUInt32(); if(count>200000) throw new Exception("PCK 索引异常。");
            for(uint i=0;i<count;i++) { int n=r.ReadInt32(); if(n<1||n>4096) throw new Exception("PCK 路径长度异常。"); string name=Encoding.UTF8.GetString(r.ReadBytes(n)).TrimEnd('\0'); long o=r.ReadInt64(),l=r.ReadInt64(); var hash=r.ReadBytes(16); if(o<0||l<0||o>f.Length-l) throw new Exception("PCK 资源偏移异常。"); Entries.Add(name,new PackEntry{Name=name,Offset=o,Length=l,Md5=hash}); }
        }
    }
    public byte[] Get(string name) {
        PackEntry e; if(!Entries.TryGetValue(name,out e)) throw new Exception("找不到基础资源："+name);
        if(e.Bytes!=null) return e.Bytes;
        if(e.Length>32*1024*1024) throw new Exception("不支持对超大资源进行文本补丁："+name);
        using(var f=File.OpenRead(Source)) using(var r=new BinaryReader(f)) { f.Position=e.Offset; return r.ReadBytes((int)e.Length); }
    }
    public string Text(string name) { return Encoding.UTF8.GetString(Get(name)); }
    public void Put(string name,byte[] data) { Data.Resource(name); using(var md5=MD5.Create()) Entries[name]=new PackEntry{Name=name,Length=data.Length,Bytes=data,Md5=md5.ComputeHash(data)}; }
    public void PutText(string name,string text) { Put(name,Data.Utf8.GetBytes(text)); }
    static long Align(long n) { return (n+15)/16*16; }
    public void Save(string path) {
        var entries=Entries.Values.OrderBy(e=>e.Name,StringComparer.Ordinal).ToList();
        var names=entries.Select(e=> { var raw=Data.Utf8.GetBytes(e.Name); var padded=new byte[(raw.Length+3)/4*4]; Buffer.BlockCopy(raw,0,padded,0,raw.Length); return padded; }).ToList();
        long offset=Align(88+names.Sum(n=>36L+n.Length));
        var offsets=new List<long>(); foreach(var e in entries){offsets.Add(offset);offset=Align(offset+e.Length);}
        using(var input=File.OpenRead(Source)) using(var output=new FileStream(path,FileMode.CreateNew,FileAccess.Write,FileShare.None,1024*1024)) using(var w=new BinaryWriter(output)) {
            w.Write((uint)0x43504447);w.Write((uint)1);w.Write((uint)3);w.Write((uint)6);w.Write((uint)1);w.Write(new byte[64]);w.Write((uint)entries.Count);
            for(int i=0;i<entries.Count;i++){w.Write(names[i].Length);w.Write(names[i]);w.Write(offsets[i]);w.Write(entries[i].Length);w.Write(entries[i].Md5);}
            byte[] buffer=new byte[1024*1024];
            for(int i=0;i<entries.Count;i++) {
                var e=entries[i]; while(output.Position<offsets[i]) w.Write((byte)0);
                if(e.Bytes!=null) { w.Write(e.Bytes); continue; }
                input.Position=e.Offset; long remaining=e.Length;
                while(remaining>0) {int n=input.Read(buffer,0,(int)Math.Min(buffer.Length,remaining)); if(n==0)throw new EndOfStreamException();output.Write(buffer,0,n);remaining-=n;}
            }
        }
    }
    public void Settings(Dictionary<string,byte[]> updates) {
        byte[] data=Get("res://project.binary");
        var items=new Dictionary<string,byte[]>();
        using(var f=new MemoryStream(data)) using(var r=new BinaryReader(f)) {
            if(r.ReadUInt32()!=0x47464345) throw new Exception("游戏项目设置格式异常。");
            int count=r.ReadInt32(); for(int i=0;i<count;i++){string key=Encoding.UTF8.GetString(r.ReadBytes(r.ReadInt32()));items.Add(key,r.ReadBytes(r.ReadInt32()));}
        }
        foreach(var pair in updates) items[pair.Key]=pair.Value;
        using(var f=new MemoryStream()) using(var w=new BinaryWriter(f)) { w.Write((uint)0x47464345);w.Write(items.Count);foreach(var item in items){var key=Data.Utf8.GetBytes(item.Key);w.Write(key.Length);w.Write(key);w.Write(item.Value.Length);w.Write(item.Value);}Put("res://project.binary",f.ToArray()); }
    }
    public static byte[] Variant(string value) { using(var f=new MemoryStream()) using(var w=new BinaryWriter(f)){var b=Data.Utf8.GetBytes(value);w.Write(4);w.Write(b.Length);w.Write(b);while(f.Position%4!=0)w.Write((byte)0);return f.ToArray();} }
}

public sealed class BuildResult {
    public string pack,profile,save_directory;
    public bool cache_hit;
    public string[] mods;
    public int resources;
    public long elapsed_ms;
}

public sealed class PendingInstall {
    public string Stage,Target,Backup;
    public Mod Mod;
}

public sealed class InstallLock : IDisposable {
    readonly Mutex mutex;
    public InstallLock(string root) {
        string key=Data.Hash(Data.Utf8.GetBytes(Path.GetFullPath(root).ToLowerInvariant())).Substring(0,24);
        mutex=new Mutex(false,@"Local\FTCModInstall-"+key);
        bool acquired;
        try {acquired=mutex.WaitOne(0);}catch(AbandonedMutexException){acquired=true;}
        if(!acquired) {mutex.Dispose();throw new Exception("另一个 Mod 安装或更新正在进行，请完成后重试。");}
    }
    public void Dispose(){mutex.ReleaseMutex();mutex.Dispose();}
}

public sealed class Loader {
    public readonly string Root,Home,Mods,Cache;
    public readonly List<string> Errors=new List<string>();
    public Loader(string root) {Root=Path.GetFullPath(root);Home=Path.Combine(Root,"FTCModLoader");Mods=Path.Combine(Home,"Mods");Cache=Path.Combine(Home,"Cache");Directory.CreateDirectory(Mods);Directory.CreateDirectory(Cache);}
    public void Log(string value) {Directory.CreateDirectory(Path.Combine(Home,"Logs")); File.AppendAllText(Path.Combine(Home,"Logs/launcher.log"),DateTime.Now.ToString("s")+" "+value+Environment.NewLine,Data.Utf8);}
    public List<Mod> Discover() {
        Errors.Clear();var result=new List<Mod>();var seen=new HashSet<string>();
        foreach(var dir in Directory.GetDirectories(Mods).OrderBy(p=>p,StringComparer.Ordinal)) {
            try {if((File.GetAttributes(dir)&FileAttributes.ReparsePoint)!=0)throw new Exception("Mod 目录不允许是链接。"); var mod=new Mod(dir);if(Path.GetFileName(dir)!=mod.Id)throw new Exception("目录名称必须等于 Mod ID："+mod.Id);if(!seen.Add(mod.Id))throw new Exception("重复 Mod ID："+mod.Id);result.Add(mod);}catch(Exception e){Errors.Add(Path.GetFileName(dir)+"："+e.Message);}
        }
        return result;
    }
    public string[] Enabled(string profile) {
        if(!Data.Id(profile)) throw new Exception("配置名称无效。");
        string path=Path.Combine(Home,"Profiles",profile+".json");
        return File.Exists(path) ? Data.Arr(Data.Get(Data.Read(path),"enabled",new object[0])).Select(Convert.ToString).ToArray() : new string[0];
    }
    public void SaveProfile(string profile,IEnumerable<string> ids) { if(!Data.Id(profile))throw new Exception("配置名称无效。"); Data.Write(Path.Combine(Home,"Profiles",profile+".json"),new {enabled=ids.ToArray()}); }
    public List<Mod> Resolve(string profile) {
        var all=Discover().ToDictionary(m=>m.Id,StringComparer.Ordinal);var selected=new HashSet<string>(Enabled(profile));var sorted=new List<Mod>();var visiting=new HashSet<string>();var done=new HashSet<string>();
        foreach(var id in selected.OrderBy(v=>v,StringComparer.Ordinal)) Visit(id,all,selected,visiting,done,sorted);
        foreach(var mod in sorted) foreach(var conflict in Data.Arr(Data.Get(mod.Manifest,"conflicts",new object[0]))) if(selected.Contains(Convert.ToString(conflict)))throw new Exception(mod.Name+" 与 "+conflict+" 冲突，请停用其中一个。");
        return sorted;
    }
    static void Visit(string id,Dictionary<string,Mod> all,HashSet<string> selected,HashSet<string> visiting,HashSet<string> done,List<Mod> sorted) {
        if(done.Contains(id))return;Mod mod;if(!all.TryGetValue(id,out mod))throw new Exception("找不到已启用的 Mod："+id);
        if(!visiting.Add(id))throw new Exception("Mod 依赖存在循环："+id);
        foreach(var dep in Data.Obj(Data.Get(mod.Manifest,"dependencies",new Dictionary<string,object>())).OrderBy(p=>p.Key,StringComparer.Ordinal)) {
            if(!selected.Contains(dep.Key))throw new Exception(mod.Name+" 需要启用依赖 "+dep.Key);
            Mod required;if(!all.TryGetValue(dep.Key,out required)||!Data.Satisfies(required.Version,Convert.ToString(dep.Value)))throw new Exception(mod.Name+" 的依赖版本不满足："+dep.Key+" "+dep.Value);
            Visit(dep.Key,all,selected,visiting,done,sorted);
        }
        foreach(var after in Data.Arr(Data.Get(mod.Manifest,"load_after",new object[0]))) if(selected.Contains(Convert.ToString(after)))Visit(Convert.ToString(after),all,selected,visiting,done,sorted);
        visiting.Remove(id);done.Add(id);sorted.Add(mod);
    }
    string VerifyGame() {
        string pck=Path.Combine(Root,"Feed the Cups.pck"),exe=Path.Combine(Root,"Feed the Cups.exe");
        if(!File.Exists(pck)||!File.Exists(exe))throw new Exception("请将加载器安装到 Feed the Cups.exe 所在目录。");
        string hash=Data.HashFile(pck);if(hash!=Data.GameHash||Data.HashFile(exe)!=Data.ExeHash)throw new Exception("此加载器适配杯杯倒满 1.0.2.0；检测到游戏资源已变化，请更新兼容层。");return hash;
    }
    static void Replace(Pack pack,string path,string oldValue,string newValue,int count) {
        if(String.IsNullOrEmpty(oldValue)||count<1)throw new Exception("文本补丁必须指定非空 find 和正数 count。");
        string text=pack.Text(path);int actual=0,start=0;while((start=text.IndexOf(oldValue,start,StringComparison.Ordinal))>=0){actual++;start+=oldValue.Length;}
        if(actual!=count)throw new Exception("资源补丁不匹配或冲突："+path+"；预期 "+count+" 处，实际 "+actual+" 处。");pack.PutText(path,text.Replace(oldValue,newValue));
    }
    public BuildResult Build(string profile,bool qa) {
        var watch=Stopwatch.StartNew();var mods=Resolve(profile);string originalHash=VerifyGame();
        var saves=mods.Select(m=>Data.Str(m.Manifest,"save_profile")).Where(v=>v!="").Distinct().ToArray();if(saves.Length>1)throw new Exception("启用的 Mod 要求不同的独立存档空间，不能组合启动。");
        string save=mods.Any(m=>m.Id=="ftc.rent_mode") ? "Feed The Cups" : "Feed The Cups Modded"+(saves.Length==1?" "+saves[0]:"");if(qa)save+=" QA";
        var fingerprint=new StringBuilder(Data.Version+"|"+Data.HashFile(System.Reflection.Assembly.GetExecutingAssembly().Location)+"|"+originalHash+"|"+save);
        foreach(var f in Data.Files(Path.Combine(Home,"Core")))fingerprint.Append("|core/"+Path.GetFileName(f)+":"+Data.HashFile(f));
        foreach(var mod in mods)foreach(var f in Data.Files(mod.Directory))fingerprint.Append("|"+mod.Id+"/"+f.Substring(mod.Directory.Length+1)+":"+Data.HashFile(f));
        if(qa && Directory.Exists(Path.Combine(Home,"tests/runtime")))foreach(var f in Data.Files(Path.Combine(Home,"tests/runtime")))fingerprint.Append("|test:"+Data.HashFile(f));
        string key=Data.Hash(Data.Utf8.GetBytes(fingerprint.ToString()));string path=Path.Combine(Cache,(qa?"qa-":"runtime-")+key.Substring(0,24)+".pck");
        string info=path+".json";
        if(CacheValid(path,info,key)) {var meta=Data.Read(info);Log("cache hit "+key);return new BuildResult{pack=path,profile=profile,save_directory=save,cache_hit=true,mods=mods.Select(m=>m.Id).ToArray(),resources=Convert.ToInt32(Data.Get(meta,"resources",0)),elapsed_ms=watch.ElapsedMilliseconds};}
        using(var mutex=new System.Threading.Mutex(false,"Local\\FTCModBuild_"+Data.Hash(Data.Utf8.GetBytes(Root)).Substring(0,16))) {
            bool entered=false; try {
                entered=mutex.WaitOne(30000);if(!entered)throw new Exception("另一个加载器正在构建，请稍后重试。");
                if(CacheValid(path,info,key)) {var meta=Data.Read(info);return new BuildResult{pack=path,profile=profile,save_directory=save,cache_hit=true,mods=mods.Select(m=>m.Id).ToArray(),resources=Convert.ToInt32(Data.Get(meta,"resources",0)),elapsed_ms=watch.ElapsedMilliseconds};}
                var pack=new Pack(Path.Combine(Root,"Feed the Cups.pck"));
                foreach(var f in Data.Files(Path.Combine(Home,"Core")))pack.Put("res://ftc_loader/"+f.Substring(Path.Combine(Home,"Core").Length+1).Replace('\\','/'),File.ReadAllBytes(f));
                var chains=new Dictionary<string,string>();
                Extend(pack,chains,"res://TscnAndGd/Logics/GameLogic/GameLogic.tscn","res://TscnAndGd/Logics/SystemLogic/ConfigLogic.gd","res://ftc_loader/ConfigBridge.gd",false);
                foreach(string scene in new[]{"NewPlayer","Player","Player1P"}) {
                    string resource="res://TscnAndGd/Main/Player/"+scene+".tscn";
                    if(pack.Entries.ContainsKey(resource))Extend(pack,chains,resource,"res://TscnAndGd/Main/Player/Control.gd","res://ftc_loader/PlayerControlBridge.gd",false);
                }
                var definitions=new List<object>();var levelOwners=new Dictionary<string,string>();
                foreach(var mod in mods) {
                    var capabilities=new HashSet<string>(Data.Arr(Data.Get(mod.Manifest,"capabilities",new object[0])).Select(Convert.ToString));
                    if((Data.Arr(Data.Get(mod.Manifest,"script_extensions",new object[0])).Length>0||Data.Arr(Data.Get(mod.Manifest,"text_patches",new object[0])).Length>0)&&!capabilities.Contains("gameplay"))throw new Exception(mod.Name+" 使用资源补丁，必须声明 gameplay 能力。");
                    foreach(var raw in Data.Arr(Data.Get(mod.Manifest,"levels",new object[0]))) {
                        var spec=Data.Obj(raw);string name=Data.Str(spec,"name");
                        if(!capabilities.Contains("levels")||(!name.StartsWith(mod.Id+".",StringComparison.Ordinal)&&!(mod.Id=="ftc.rent_mode"&&name=="房租模式")))throw new Exception("自定义关卡必须声明 levels 能力并以 Mod ID 加点作为名称前缀："+name);
                        if(levelOwners.ContainsKey(name))throw new Exception("关卡名称冲突："+name);levelOwners[name]=mod.Id;
                    }
                    foreach(var f in Data.Files(mod.Directory))if(Path.GetFileName(f)!="mod.json") pack.Put(mod.Prefix+f.Substring(mod.Directory.Length+1).Replace('\\','/'),File.ReadAllBytes(f));
                    foreach(var raw in Data.Arr(Data.Get(mod.Manifest,"scene_clones",new object[0]))) {
                        var spec=Data.Obj(raw);string source=Data.Resource(Data.Str(spec,"source")),destination=Data.Resource(Data.Str(spec,"destination"));
                        bool privateScene=destination.StartsWith(mod.Prefix,StringComparison.Ordinal)||destination.StartsWith("res://TscnAndGd/Main/Level/"+mod.Id+".",StringComparison.Ordinal)||(mod.Id=="ftc.rent_mode"&&Regex.IsMatch(destination,@"^res://TscnAndGd/Main/Level/RentRoom_2_[123]\.tscn$"));
                        if(!capabilities.Contains("levels")||!privateScene)throw new Exception("克隆场景必须声明 levels 能力并位于本 Mod 的命名空间："+destination);
                        if(pack.Entries.ContainsKey(destination))throw new Exception("场景资源冲突："+destination);
                        string original=Data.Resource(Data.Str(spec,"base_script")),replacement=mod.Resource(Data.Str(spec,"script"));
                        pack.PutText(destination,pack.Text(source));
                        // A clone starts from the source's composed scene, including all
                        // previously installed script chains. Its own extension is the next
                        // layer, rather than a replacement that drops those earlier hooks.
                        foreach(var chain in chains.Where(p=>p.Key.StartsWith(source+"|",StringComparison.Ordinal)).ToArray())
                            chains.Add(destination+chain.Key.Substring(source.Length),chain.Value);
                        Extend(pack,chains,destination,original,replacement,true);
                    }
                    foreach(var raw in Data.Arr(Data.Get(mod.Manifest,"script_extensions",new object[0]))) {
                        var spec=Data.Obj(raw);Extend(pack,chains,Data.Resource(Data.Str(spec,"scene")),Data.Resource(Data.Str(spec,"base_script")),mod.Resource(Data.Str(spec,"script")),true);
                    }
                    foreach(var raw in Data.Arr(Data.Get(mod.Manifest,"text_patches",new object[0]))) {var spec=Data.Obj(raw);Replace(pack,Data.Resource(Data.Str(spec,"resource")),Data.Str(spec,"find"),Data.Str(spec,"replace"),Convert.ToInt32(Data.Get(spec,"count",1)));}
                    foreach(var raw in Data.Arr(Data.Get(mod.Manifest,"animation_aliases",new object[0]))) {
                        var spec=Data.Obj(raw);string resource=Data.Resource(Data.Str(spec,"resource")),from=Data.Str(spec,"from"),to=Data.Str(spec,"to");
                        if(!Regex.IsMatch(from,@"^[^""\r\n]+$")||!Regex.IsMatch(to,@"^[^""\r\n]+$"))throw new Exception("动画别名格式无效。");
                        var text=pack.Text(resource);var match=Regex.Match(text,"^\"anims/"+Regex.Escape(from)+"\" = (.+)$",RegexOptions.Multiline);if(!match.Success||text.Contains("\"anims/"+to+"\""))throw new Exception("动画别名冲突："+to);
                        pack.PutText(resource,text.Replace(match.Value,match.Value+"\n\"anims/"+to+"\" = "+match.Groups[1].Value));
                    }
                    var definition=new Dictionary<string,object>(mod.Manifest);definition["entry"]=mod.Resource(mod.Entry);definitions.Add(definition);
                }
                pack.PutText("res://ftc_loader/active_mods.json",Data.Json.Serialize(new {loader_version=Data.Version,api_version=Data.Api,mods=definitions}));
                if(qa&&Directory.Exists(Path.Combine(Home,"tests/runtime")))foreach(var f in Data.Files(Path.Combine(Home,"tests/runtime")))pack.Put("res://ftc_loader/tests/"+f.Substring(Path.Combine(Home,"tests/runtime").Length+1).Replace('\\','/'),File.ReadAllBytes(f));
                pack.Settings(new Dictionary<string,byte[]>{{"application/config/use_custom_user_dir",new byte[]{1,0,0,0,1,0,0,0}},{"application/config/custom_user_dir_name",Pack.Variant(save)},{"autoload/FtcModAPI",Pack.Variant("*res://ftc_loader/ModAPI.gd")}});
                string temporary=Path.Combine(Cache,"building-"+Guid.NewGuid().ToString("N")+".pck");pack.Save(temporary);
                if(File.Exists(path)){string quarantine=Path.Combine(Cache,"Corrupt");Directory.CreateDirectory(quarantine);string backup=Path.Combine(quarantine,Path.GetFileName(path)+"-"+DateTime.Now.ToString("yyyyMMddHHmmssfff"));if(!Data.Under(backup,Cache))throw new Exception("缓存备份路径异常。");File.Move(path,backup);}
                File.Move(temporary,path);Data.Write(info,new {key=key,length=new FileInfo(path).Length,sha256=Data.HashFile(path),resources=pack.Entries.Count});Log("built "+key+" mods="+String.Join(",",mods.Select(m=>m.Id)));PruneCache(path,qa);
                return new BuildResult{pack=path,profile=profile,save_directory=save,cache_hit=false,mods=mods.Select(m=>m.Id).ToArray(),resources=pack.Entries.Count,elapsed_ms=watch.ElapsedMilliseconds};
            } finally {if(entered)mutex.ReleaseMutex();}
        }
    }
    static bool CacheValid(string path,string info,string key) {
        if(!File.Exists(path)||!File.Exists(info))return false;
        try{var meta=Data.Read(info);return Data.Str(meta,"key")==key&&new FileInfo(path).Length==Convert.ToInt64(Data.Get(meta,"length",0))&&Data.Str(meta,"sha256")==Data.HashFile(path);}catch(Exception){return false;}
    }
    static void Extend(Pack pack,Dictionary<string,string> chains,string scene,string original,string replacement,bool rewrite) {
        string key=scene+"|"+original;string current; if(!chains.TryGetValue(key,out current))current=original;
        if(current==replacement)throw new Exception("脚本扩展不能重复继承自身："+replacement);
        if(rewrite) {
            string script=pack.Text(replacement);var match=Regex.Match(script,@"\A(?:\uFEFF)?extends\s+""([^""]+)""");
            if(!match.Success||(match.Groups[1].Value!=original&&match.Groups[1].Value!=current))throw new Exception("脚本扩展必须继承声明的原脚本，且同一扩展在各场景中的继承链必须兼容："+replacement);
            if(current!=match.Groups[1].Value)pack.PutText(replacement,script.Substring(0,match.Groups[1].Index)+current+script.Substring(match.Groups[1].Index+match.Groups[1].Length));
        }
        Replace(pack,scene,current,replacement,1);chains[key]=replacement;
    }
    void PruneCache(string keep,bool qa) {
        // Only bounded, generated caches are expendable. In-use packs stay locked
        // on Windows and are retained; installed modules and profiles are untouched.
        int retained=0;foreach(var file in Directory.GetFiles(Cache,(qa?"qa-":"runtime-")+"*.pck").Select(p=>new FileInfo(p)).OrderByDescending(f=>f.LastWriteTimeUtc)) {
            if(file.FullName==keep){retained++;continue;}if(retained++<(qa?1:2))continue;
            if(!Data.Under(file.FullName,Cache))continue;
            try{file.Delete();if(File.Exists(file.FullName+".json"))File.Delete(file.FullName+".json");}catch(IOException){}catch(UnauthorizedAccessException){}
        }
    }
    public void GuardGame() {
        var live=new List<int>();foreach(var process in Process.GetProcessesByName("Feed the Cups"))using(process) {
            try {process.Refresh();if(process.HasExited)continue;bool same=String.Equals(process.MainModule.FileName,Path.Combine(Root,"Feed the Cups.exe"),StringComparison.OrdinalIgnoreCase);if(!same)continue;if(process.Threads.Count==0&&process.MainWindowHandle==IntPtr.Zero&&(DateTime.Now-process.StartTime).TotalSeconds>10)continue;live.Add(process.Id);}catch{live.Add(process.Id);}
        }
        if(live.Count>0)throw new Exception("请先保存并退出正在运行的游戏（PID："+String.Join(", ",live)+"）。");
    }
    public void Launch(string profile,bool vanilla) {
        GuardGame();string arguments="";
        if(!vanilla){var result=Build(profile,false);arguments="--main-pack \""+result.pack+"\"";}
        Process.Start(new ProcessStartInfo(Path.Combine(Root,"Feed the Cups.exe"),arguments){WorkingDirectory=Root,UseShellExecute=false});Log("launched "+(vanilla?"vanilla":profile));
    }
    PendingInstall Prepare(string archive) {
        if(!File.Exists(archive))throw new Exception("找不到 Mod 安装包："+archive);
        string stage=Path.Combine(Cache,"install-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(stage);
        try {
            using(var zip=ZipFile.OpenRead(archive)) {
                if(zip.Entries.Count>10000)throw new Exception("Mod 包文件数量超过上限。");
                long bytes=0;var paths=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                foreach(var entry in zip.Entries) {
                    if(entry.FullName.EndsWith("/"))continue;
                    string destination=Data.SafePath(stage,entry.FullName);if(!paths.Add(destination))throw new Exception("Mod 包含重复路径。");
                    if(((entry.ExternalAttributes>>16)&0xf000)==0xa000)throw new Exception("Mod 包不允许包含符号链接。");
                    bytes+=entry.Length;if(bytes>256L*1024*1024)throw new Exception("Mod 包展开后超过 256 MB。");
                    Directory.CreateDirectory(Path.GetDirectoryName(destination));entry.ExtractToFile(destination);
                }
            }
            if(!File.Exists(Path.Combine(stage,"mod.json")))throw new Exception("Mod 包根目录缺少 mod.json。");
            var mod=new Mod(stage);
            return new PendingInstall{Stage=stage,Target=Data.SafePath(Mods,mod.Id),Mod=mod};
        } catch {if(Data.Under(stage,Cache)&&Directory.Exists(stage))Directory.Delete(stage,true);throw;}
    }
    public List<Mod> InstallMany(IEnumerable<string> archives) {
        GuardGame();
        using(new InstallLock(Root)) {
        var pending=new List<PendingInstall>();var applied=new List<PendingInstall>();
        try {
            foreach(var archive in archives)pending.Add(Prepare(archive));
            if(pending.Select(p=>p.Mod.Id).Distinct(StringComparer.Ordinal).Count()!=pending.Count)throw new Exception("安装包中包含重复的 Mod ID。");
            foreach(var item in pending) {
                if(Directory.Exists(item.Target)) {
                    item.Backup=Path.Combine(Home,"Backups",item.Mod.Id+"-"+DateTime.Now.ToString("yyyyMMddHHmmssfff")+"-"+Guid.NewGuid().ToString("N"));
                    Directory.CreateDirectory(Path.GetDirectoryName(item.Backup));
                    Directory.Move(item.Target,item.Backup);
                }
                try {Directory.Move(item.Stage,item.Target);applied.Add(item);}
                catch(Exception updateError) {
                    try {if(item.Backup!=null&&Directory.Exists(item.Backup))Directory.Move(item.Backup,item.Target);}
                    catch(Exception restoreError){throw new Exception("新版本写入失败，旧版保留在 "+item.Backup+"；自动恢复失败："+restoreError.Message,updateError);}
                    throw;
                }
            }
            var installed=applied.Select(p=>new Mod(p.Target)).ToList();
            foreach(var mod in installed)Log("installed "+mod.Id+" "+mod.Version);
            return installed;
        } catch(Exception error) {
            var rollback=new List<string>();
            for(int i=applied.Count-1;i>=0;i--)try {
                var item=applied[i];if(!Data.Under(item.Target,Mods))throw new Exception("回滚路径异常");
                if(Directory.Exists(item.Target))Directory.Delete(item.Target,true);
                if(item.Backup!=null&&Directory.Exists(item.Backup))Directory.Move(item.Backup,item.Target);
            }catch(Exception restore){rollback.Add(applied[i].Mod.Id+"："+restore.Message);}
            if(rollback.Count>0)throw new Exception("安装失败，自动恢复未完成；旧版保留在 Backups："+String.Join("；",rollback),error);
            throw;
        } finally {
            foreach(var item in pending)if(Directory.Exists(item.Stage)&&Data.Under(item.Stage,Cache))try{Directory.Delete(item.Stage,true);}catch{}
        }
        }
    }
    public Mod Install(string archive) {return InstallMany(new[]{archive})[0];}
    public List<Mod> UpdateBundled(string packageDirectory=null) {
        GuardGame();
        string folder=packageDirectory??Path.Combine(Home,"Packages");
        if(!Directory.Exists(folder))throw new Exception("找不到内置 Mod 包目录，请重新解压完整安装包。");
        var latest=new Dictionary<string,Tuple<System.Version,string>>(StringComparer.Ordinal);
        foreach(var archive in Directory.GetFiles(folder,"ftc.*.ftcmod")) {
            var match=Regex.Match(Path.GetFileNameWithoutExtension(archive),@"^(ftc\.[a-z0-9._-]+)-(\d+\.\d+\.\d+)$");
            if(!match.Success||!Data.Id(match.Groups[1].Value))continue;
            string id=match.Groups[1].Value;var parsed=new System.Version(match.Groups[2].Value);Tuple<System.Version,string> previous;
            if(!latest.TryGetValue(id,out previous)||parsed>previous.Item1)latest[id]=Tuple.Create(parsed,archive);
        }
        var installed=Discover().ToDictionary(m=>m.Id,StringComparer.Ordinal);
        var upgrades=latest.OrderBy(p=>p.Key,StringComparer.Ordinal).Where(p=>!installed.ContainsKey(p.Key)||p.Value.Item1>new System.Version(installed[p.Key].Version)).Select(p=>p.Value.Item2).ToArray();
        foreach(var archive in upgrades)using(var zip=ZipFile.OpenRead(archive)) {
            var entry=zip.GetEntry("mod.json");if(entry==null)throw new Exception("安装包缺少 mod.json："+Path.GetFileName(archive));
            Dictionary<string,object> manifest;using(var input=entry.Open())using(var reader=new StreamReader(input,Encoding.UTF8))manifest=Data.Obj(Data.Json.DeserializeObject(reader.ReadToEnd()));
            var match=Regex.Match(Path.GetFileNameWithoutExtension(archive),@"^(ftc\.[a-z0-9._-]+)-(\d+\.\d+\.\d+)$");
            if(Data.Str(manifest,"id")!=match.Groups[1].Value||Data.Str(manifest,"version")!=match.Groups[2].Value)throw new Exception("内置包文件名与清单不一致："+Path.GetFileName(archive));
        }
        return upgrades.Length==0?new List<Mod>():InstallMany(upgrades);
    }
    public void Export(string id,string output) {
        if(!Data.Id(id))throw new Exception("Mod ID 无效。");var mod=new Mod(Data.SafePath(Mods,id));
        using(var zip=ZipFile.Open(output,ZipArchiveMode.Create))foreach(var f in Data.Files(mod.Directory))zip.CreateEntryFromFile(f,f.Substring(mod.Directory.Length+1).Replace('\\','/'),CompressionLevel.Optimal);
    }
}

public static class Program {
    static string Value(string[] args,string key,string fallback){int n=Array.IndexOf(args,key);return n>=0&&n+1<args.Length?args[n+1]:fallback;}
    [STAThread] public static int Main(string[] args) {
        Console.SetOut(new StreamWriter(Console.OpenStandardOutput(),Data.Utf8){AutoFlush=true});
        Console.SetError(new StreamWriter(Console.OpenStandardError(),Data.Utf8){AutoFlush=true});
        string root=Value(args,"--root",AppDomain.CurrentDomain.BaseDirectory);
        Loader loader=null;
        try {
            if(args.Contains("--apply-update"))return UpdateService.Apply(Value(args,"--apply-update",""),Value(args,"--destination",""),Value(args,"--wait-pid","0"));
            if(args.Length==0&&!Deployment.IsGame(root)) {
                if(!Deployment.IsBundle(root))throw new Exception("安装包不完整，请完整解压压缩包后运行加载器。");
                new System.Windows.Application().Run(new SetupWindow(root));return 0;
            }
            loader=new Loader(root);
            string profile=Value(args,"--profile","default");
            if(args.Contains("--help")){Console.WriteLine("FTC ModLoader "+Data.Version+"\n--list [--profile NAME]\n--build [--profile NAME] [--qa]\n--launch [--profile NAME] [--vanilla]\n--install FILE.ftcmod\n--update-bundled\n--export MOD.ID --out FILE.ftcmod");return 0;}
            if(args.Contains("--build")){Console.WriteLine(Data.Json.Serialize(loader.Build(profile,args.Contains("--qa"))));return 0;}
            if(args.Contains("--list")){var mods=loader.Discover();Console.WriteLine(Data.Json.Serialize(new {mods=mods.Select(m=>new{id=m.Id,name=m.Name,version=m.Version}).ToArray(),errors=loader.Errors,enabled=loader.Enabled(profile)}));return 0;}
            if(args.Contains("--install")){var mod=loader.Install(Value(args,"--install",""));Console.WriteLine(Data.Json.Serialize(new {installed=mod.Id,version=mod.Version}));return 0;}
            if(args.Contains("--update-bundled")){var changed=loader.UpdateBundled();Console.WriteLine(Data.Json.Serialize(new {updated=changed.Select(m=>m.Id+"@"+m.Version).ToArray()}));return 0;}
            if(args.Contains("--export")){loader.Export(Value(args,"--export",""),Value(args,"--out","module.ftcmod"));return 0;}
            if(args.Contains("--launch")){loader.Launch(profile,args.Contains("--vanilla"));return 0;}
            new System.Windows.Application().Run(new Manager(loader));return 0;
        } catch(Exception e){try{if(loader!=null)loader.Log("ERROR "+e.Message);}catch{} Console.Error.WriteLine(e.Message);if(args.Length==0)System.Windows.MessageBox.Show(e.Message,"杯杯倒满 Mod 加载器");return 1;}
    }
}
}
