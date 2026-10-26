using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using Microsoft.Win32;

namespace CupsModLoader {
public static class Deployment {
    sealed class ChangedFile {public string Target,Backup;public bool Existed;}
    public static bool IsGame(string path) {return Directory.Exists(path)&&File.Exists(Path.Combine(path,"Feed the Cups.exe"))&&File.Exists(Path.Combine(path,"Feed the Cups.pck"));}
    public static bool IsBundle(string path) {return File.Exists(Path.Combine(path,"杯杯倒满Mod加载器.exe"))&&Directory.Exists(Path.Combine(path,"FTCModLoader","Core"))&&Directory.Exists(Path.Combine(path,"FTCModLoader","Packages"));}
    public static string[] FindGames() {
        var roots=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach(var item in new[]{new[]{@"HKEY_CURRENT_USER\Software\Valve\Steam","SteamPath"},new[]{@"HKEY_LOCAL_MACHINE\SOFTWARE\Valve\Steam","InstallPath"},new[]{@"HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Valve\Steam","InstallPath"}})
            try {string value=Registry.GetValue(item[0],item[1],null) as string;if(!String.IsNullOrEmpty(value))roots.Add(value);}catch{}
        foreach(var drive in DriveInfo.GetDrives())try {
            if(!drive.IsReady)continue;
            foreach(var relative in new[]{"SteamLibrary","Steam",@"Games\Steam",@"Program Files (x86)\Steam",@"Program Files\Steam"}) {
                string path=Path.Combine(drive.Name,relative);if(Directory.Exists(Path.Combine(path,"steamapps")))roots.Add(path);
            }
        }catch{}
        var libraries=new HashSet<string>(roots,StringComparer.OrdinalIgnoreCase);
        foreach(var root in roots)foreach(var relative in new[]{@"steamapps\libraryfolders.vdf",@"config\libraryfolders.vdf"})try {
            string vdf=Path.Combine(root,relative);if(!File.Exists(vdf))continue;
            foreach(Match match in Regex.Matches(File.ReadAllText(vdf),"\"(?:path|[0-9]+)\"\\s+\"((?:\\\\.|[^\"\\\\])*)\"")) {
                string path=match.Groups[1].Value.Replace(@"\\",@"\").Replace("\\\"","\"");
                if(Path.IsPathRooted(path))libraries.Add(Path.GetFullPath(path));
            }
        }catch{}
        var games=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach(var library in libraries)try {
            string apps=Path.Combine(library,"steamapps");if(!Directory.Exists(apps))continue;
            var folders=new List<string>{"Feed The Cups"};string manifest=Path.Combine(apps,"appmanifest_2336220.acf");
            if(File.Exists(manifest)) {
                string content=File.ReadAllText(manifest);var found=Regex.Match(content,"\"installdir\"\\s+\"([^\"\\\\/]+)\"");
                if(Regex.IsMatch(content,"\"appid\"\\s+\"2336220\"")&&found.Success&&found.Groups[1].Value!="."&&found.Groups[1].Value!="..")folders.Add(found.Groups[1].Value);
            }
            foreach(var folder in folders){string path=Path.Combine(apps,"common",folder);if(IsGame(path))games.Add(Path.GetFullPath(path));}
        }catch{}
        return games.OrderBy(p=>p,StringComparer.OrdinalIgnoreCase).ToArray();
    }
    static void CloseOldLoader(string target) {
        foreach(var process in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(target)))using(process) {
            string actual;try{actual=process.MainModule.FileName;}catch{continue;}
            if(!String.Equals(actual,target,StringComparison.OrdinalIgnoreCase))continue;
            if(process.MainWindowHandle!=IntPtr.Zero){process.CloseMainWindow();process.WaitForExit(8000);}
            if(!process.HasExited)throw new Exception("旧加载器仍在运行，请关闭窗口后重试。");
        }
    }
    static void CopyAtomic(string source,string target,List<ChangedFile> changed) {
        if(File.Exists(target)&&Data.HashFile(source)==Data.HashFile(target))return;
        Directory.CreateDirectory(Path.GetDirectoryName(target));
        string temp=target+".ftc-new-"+Guid.NewGuid().ToString("N");
        string backup=target+".ftc-backup-"+Guid.NewGuid().ToString("N");
        bool existed=File.Exists(target);
        try {
            File.Copy(source,temp);
            if(Data.HashFile(source)!=Data.HashFile(temp))throw new Exception("文件复制校验失败："+Path.GetFileName(source));
            if(existed)File.Replace(temp,target,backup);else File.Move(temp,target);
            changed.Add(new ChangedFile{Target=target,Backup=existed?backup:null,Existed=existed});
        } finally {if(File.Exists(temp))File.Delete(temp);}
    }
    public static void Install(string sourceRoot,string destination) {
        sourceRoot=Path.GetFullPath(sourceRoot);destination=Path.GetFullPath(destination);
        if(!IsBundle(sourceRoot))throw new Exception("安装包不完整：请完整解压后双击 Mod 加载器。");
        if(!IsGame(destination))throw new Exception("所选目录没有 Feed the Cups.exe 和游戏 PCK。");
        if(Data.HashFile(Path.Combine(destination,"Feed the Cups.pck"))!=Data.GameHash||Data.HashFile(Path.Combine(destination,"Feed the Cups.exe"))!=Data.ExeHash)throw new Exception("游戏版本不匹配；此加载器适配游戏 1.0.2.0。");
        if(String.Equals(sourceRoot,destination,StringComparison.OrdinalIgnoreCase)){new Loader(destination).UpdateBundled();return;}
        var targetLoader=new Loader(destination);targetLoader.GuardGame();
        using(new InstallLock(destination)) {
        string sourceHome=Path.Combine(sourceRoot,"FTCModLoader"),targetHome=targetLoader.Home;
        string sourcePackages=Path.Combine(sourceHome,"Packages");
        if(!Directory.GetFiles(sourcePackages,"ftc.*.ftcmod").Any())throw new Exception("安装包缺少内置 Mod，请重新解压完整安装包。");
        var changed=new List<ChangedFile>();
        try {
            string exeTarget=Path.Combine(destination,"杯杯倒满Mod加载器.exe");
            string exeSource=Path.Combine(sourceRoot,"杯杯倒满Mod加载器.exe");
            if(!File.Exists(exeTarget)||Data.HashFile(exeSource)!=Data.HashFile(exeTarget)) {
                CloseOldLoader(exeTarget);
                CopyAtomic(exeSource,exeTarget,changed);
            }
            foreach(var directory in new[]{"Core","SDK","Packages","Profiles"}) {
                string from=Path.Combine(sourceHome,directory);if(!Directory.Exists(from))continue;
                foreach(var file in Data.Files(from)) {
                    string relative=file.Substring(from.Length+1).Replace('\\','/');
                    string target=Data.SafePath(Path.Combine(targetHome,directory),relative);
                    if(directory=="Profiles"&&File.Exists(target))continue;
                    CopyAtomic(file,target,changed);
                }
            }
            foreach(var name in new[]{"使用说明.txt","联机安装说明.txt"}) {
                string from=Path.Combine(sourceHome,name);
                if(File.Exists(from))CopyAtomic(from,Path.Combine(targetHome,name),changed);
            }
            targetLoader.UpdateBundled();
        } catch(Exception error) {
            var failed=new List<string>();
            for(int i=changed.Count-1;i>=0;i--)try {
                var item=changed[i];if(!Data.Under(item.Target,destination))throw new Exception("回滚路径异常");
                if(item.Existed)File.Replace(item.Backup,item.Target,null);else if(File.Exists(item.Target))File.Delete(item.Target);
            }catch(Exception restore){failed.Add(Path.GetFileName(changed[i].Target)+"："+restore.Message);}
            if(failed.Count>0)throw new Exception("安装失败，部分文件保留了 .ftc-backup 备份："+String.Join("；",failed),error);
            throw;
        }
        foreach(var item in changed)if(item.Existed&&File.Exists(item.Backup))try{File.Delete(item.Backup);}catch{}
        }
    }
}

}
