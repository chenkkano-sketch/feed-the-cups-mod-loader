using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;
using Microsoft.Win32;

namespace CupsModLoader {
public static class StandaloneInstaller {
    static string Value(string[] args,string key) {int i=Array.IndexOf(args,key);return i>=0&&i+1<args.Length?args[i+1]:null;}
    public static bool IsGame(string path) {return Directory.Exists(path)&&File.Exists(Path.Combine(path,"Feed the Cups.exe"))&&File.Exists(Path.Combine(path,"Feed the Cups.pck"));}
    public static string[] FindGames(string[] explicitRoots=null) {
        var roots=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if(explicitRoots!=null) {foreach(var path in explicitRoots)if(!String.IsNullOrWhiteSpace(path))roots.Add(path);}
        else {
            foreach(var item in new[]{new[]{@"HKEY_CURRENT_USER\Software\Valve\Steam","SteamPath"},new[]{@"HKEY_LOCAL_MACHINE\SOFTWARE\Valve\Steam","InstallPath"},new[]{@"HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Valve\Steam","InstallPath"}}) {
                try {string path=Registry.GetValue(item[0],item[1],null) as string;if(!String.IsNullOrEmpty(path))roots.Add(path);}catch{}
            }
            foreach(var drive in DriveInfo.GetDrives())foreach(var relative in new[]{"SteamLibrary","Steam",@"Games\Steam",@"Program Files (x86)\Steam",@"Program Files\Steam"}) {
                string path=Path.Combine(drive.Name,relative);if(Directory.Exists(Path.Combine(path,"steamapps")))roots.Add(path);
            }
        }
        var libraries=new HashSet<string>(roots,StringComparer.OrdinalIgnoreCase);
        foreach(var root in roots)foreach(var relative in new[]{@"steamapps\libraryfolders.vdf",@"config\libraryfolders.vdf"}) {
            string vdf=Path.Combine(root,relative);if(!File.Exists(vdf))continue;
            try {foreach(Match match in Regex.Matches(File.ReadAllText(vdf),"\"(?:path|[0-9]+)\"\\s+\"((?:\\\\.|[^\"\\\\])*)\"")) {
                string path=match.Groups[1].Value.Replace(@"\\",@"\").Replace("\\\"","\"");
                if(Path.IsPathRooted(path))libraries.Add(Path.GetFullPath(path));
            }}catch{}
        }
        var games=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach(var library in libraries) {
            if(!Directory.Exists(library))continue;
            string apps=Path.Combine(library,"steamapps");var folders=new List<string>{"Feed The Cups"};
            string manifest=Path.Combine(apps,"appmanifest_2336220.acf");
            if(File.Exists(manifest))try {
                string text=File.ReadAllText(manifest);var folder=Regex.Match(text,"\"installdir\"\\s+\"([^\"\\\\/]+)\"");
                if(Regex.IsMatch(text,"\"appid\"\\s+\"2336220\"")&&folder.Success&&folder.Groups[1].Value!="."&&folder.Groups[1].Value!="..")folders.Add(folder.Groups[1].Value);
            }catch{}
            foreach(var folder in folders) {string path=Path.Combine(apps,"common",folder);if(IsGame(path))games.Add(Path.GetFullPath(path));}
        }
        return games.OrderBy(p=>p,StringComparer.OrdinalIgnoreCase).ToArray();
    }
    public static void Extract(string folder) {
        if(Directory.Exists(folder)||File.Exists(folder))throw new Exception("解包目标已存在，请选择新的空目录。");
        using(var resource=typeof(StandaloneInstaller).Assembly.GetManifestResourceStream("FTC.Bundle")) {
            if(resource==null)throw new Exception("安装器缺少内置数据，请重新下载完整安装器。");
            using(var memory=new MemoryStream()) {
                resource.CopyTo(memory);
                if(Data.Hash(memory.ToArray())!=InstallerBundle.Hash)throw new Exception("安装器数据校验失败，请重新下载。");
                memory.Position=0;
                using(var zip=new ZipArchive(memory,ZipArchiveMode.Read,true)) {
                    if(zip.Entries.Count>5000||zip.Entries.Sum(e=>e.Length)>256L*1024*1024)throw new Exception("内置安装包大小异常。");
                    Directory.CreateDirectory(folder);
                    foreach(var entry in zip.Entries) {
                        string relative=entry.FullName.TrimEnd('/');if(relative=="")continue;
                        string path=Data.SafePath(folder,relative);
                        if(entry.FullName.EndsWith("/")){Directory.CreateDirectory(path);continue;}
                        Directory.CreateDirectory(Path.GetDirectoryName(path));
                        using(var input=entry.Open())using(var output=new FileStream(path,FileMode.CreateNew,FileAccess.Write))input.CopyTo(output);
                    }
                }
            }
        }
    }
    static void CopyTree(string source,string destination) {
        foreach(var file in Data.Files(source)) {
            string relative=file.Substring(source.TrimEnd(Path.DirectorySeparatorChar).Length+1).Replace('\\','/');
            string target=Data.SafePath(destination,relative);Directory.CreateDirectory(Path.GetDirectoryName(target));File.Copy(file,target,true);
        }
    }
    static void CopyLoader(string source,string target) {
        if(File.Exists(target)&&Data.HashFile(source)==Data.HashFile(target))return;
        foreach(var process in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(target)))using(process) {
            try {
                if(!String.Equals(process.MainModule.FileName,target,StringComparison.OrdinalIgnoreCase))continue;
                if(process.MainWindowHandle!=IntPtr.Zero){process.CloseMainWindow();process.WaitForExit(8000);}
            }catch{}
        }
        try {File.Copy(source,target,true);}
        catch(IOException){throw new Exception("加载器文件仍被占用。请关闭“杯杯倒满Mod加载器”窗口后重试；游戏不会被强制结束。");}
    }
    public static void Install(string bundle,string destination) {
        Deployment.Install(bundle,destination);
    }
    static void RunInstall(string destination) {
        string boundary=Path.GetFullPath(Path.Combine(Path.GetTempPath(),"FTCModLoaderInstaller"));
        string stage=Path.Combine(boundary,Guid.NewGuid().ToString("N"));
        try {Extract(stage);Install(stage,destination);}
        finally {if(Data.Under(stage,boundary)&&Directory.Exists(stage))try{Directory.Delete(stage,true);}catch{}}
    }
    [STAThread] public static int Main(string[] args) {
        Console.SetOut(new StreamWriter(Console.OpenStandardOutput(),Data.Utf8){AutoFlush=true});
        Console.SetError(new StreamWriter(Console.OpenStandardError(),Data.Utf8){AutoFlush=true});
        bool cli=args.Length>0;
        try {
            if(args.Contains("--extract-to")){Extract(Path.GetFullPath(Value(args,"--extract-to")));Console.WriteLine("EXTRACT_OK");return 0;}
            if(args.Contains("--find-games")){string root=Value(args,"--steam-root");Console.WriteLine(Data.Json.Serialize(FindGames(root==null?null:new[]{root})));return 0;}
            string destination=Value(args,"--install-to");
            if(destination!=null){RunInstall(destination);Console.WriteLine("INSTALL_OK");return 0;}
            Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
            var found=FindGames();
            if(found.Length==1)destination=found[0];
            else using(var picker=new FolderBrowserDialog{Description=found.Length==0?"未找到游戏，请选择 Feed the Cups.exe 所在目录":"发现多个游戏位置，请选择本次安装目录",ShowNewFolderButton=false}) {
                if(found.Length>0)picker.SelectedPath=found[0];if(picker.ShowDialog()!=DialogResult.OK)return 0;destination=picker.SelectedPath;
            }
            using(var form=new Form{Text="杯杯倒满 Mod 安装 · 1.0.3",Width=570,Height=190,StartPosition=FormStartPosition.CenterScreen,FormBorderStyle=FormBorderStyle.FixedDialog,MaximizeBox=false,MinimizeBox=false}) {
                var label=new Label{Left=20,Top=20,Width=510,Height=70,Text="正在校验并安装，请稍候…\r\n"+destination};form.Controls.Add(label);
                form.Controls.Add(new ProgressBar{Left=20,Top=100,Width=510,Height=22,Style=ProgressBarStyle.Marquee});
                bool running=true;form.FormClosing+=(s,e)=>{if(running)e.Cancel=true;};
                var worker=new BackgroundWorker();worker.DoWork+=(s,e)=>RunInstall(destination);
                worker.RunWorkerCompleted+=(s,e)=>{running=false;if(e.Error!=null)MessageBox.Show(form,e.Error.Message,"安装未完成",MessageBoxButtons.OK,MessageBoxIcon.Error);else MessageBox.Show(form,"安装完成！\r\n请打开游戏目录中的“杯杯倒满Mod加载器.exe”。\r\n"+destination,"房租联机",MessageBoxButtons.OK,MessageBoxIcon.Information);form.Close();};
                form.Shown+=(s,e)=>worker.RunWorkerAsync();Application.Run(form);
            }
            return 0;
        }catch(Exception error){Console.Error.WriteLine(error.Message);if(!cli)MessageBox.Show(error.Message,"安装未完成",MessageBoxButtons.OK,MessageBoxIcon.Error);return 1;}
    }
}
}
