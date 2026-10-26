using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Windows.Forms;

namespace CupsModLoader {
public sealed class Manager : Form {
    static readonly Color Background = Color.FromArgb(15, 22, 33);
    static readonly Color PanelColor = Color.FromArgb(26, 37, 53);
    static readonly Color Muted = Color.FromArgb(166, 185, 205);
    static readonly Color Accent = Color.FromArgb(71, 216, 181);
    static readonly Color White = Color.FromArgb(238, 247, 252);
    readonly Loader loader;
    readonly CheckedListBox list = new CheckedListBox();
    readonly TextBox detail = new TextBox();
    readonly ComboBox profiles = new ComboBox();
    readonly Label status = new Label();
    readonly Label releaseStatus = new Label();
    readonly Button download;
    List<Mod> mods = new List<Mod>();
    RemoteRelease release;
    bool refreshing, busy;
    readonly Dictionary<string,string> names = new Dictionary<string,string> {
        {"default","我的配置"},{"rent_coop","房租联机＋实时搬运"},{"both","房租＋修改器＋搬运"},
        {"rent","房租＋搬运"},{"rent_only","仅房租模式"},{"trainer","仅修改器"},
        {"furniture","仅自由搬运"},{"talent","人才市场＋自由搬运"},
        {"talent_rent","人才市场＋房租＋搬运"},{"talent_all","全部模块"}
    };

    public Manager(Loader value) {
        loader = value;
        Text = "杯杯倒满 Mod 启动器 " + Data.Version;
        Font = new Font("Microsoft YaHei UI", 9);
        BackColor = Background; ForeColor = White;
        ClientSize = new Size(1040, 690); MinimumSize = new Size(1056, 729);
        StartPosition = FormStartPosition.CenterScreen;
        AllowDrop = true;

        LabelAt(this, "杯杯倒满", 30, 21, 420, 42, 24, true, White);
        LabelAt(this, "MOD LAUNCHER  /  v" + Data.Version, 32, 66, 430, 24, 9, true, Accent);
        LabelAt(this, "选择配置、管理模块，然后进入游戏", 650, 42, 360, 24, 10, false, Muted, ContentAlignment.MiddleRight);

        var left = Card(24, 111, 410, 463);
        LabelAt(left, "游戏配置", 21, 17, 350, 28, 14, true, White);
        LabelAt(left, "勾选的模块在下一次启动时生效", 21, 49, 350, 23, 9, false, Muted);
        profiles.SetBounds(21, 83, 368, 32);
        profiles.BackColor = Color.FromArgb(37, 51, 69); profiles.ForeColor = White;
        profiles.FlatStyle = FlatStyle.Flat; profiles.DropDownStyle = ComboBoxStyle.DropDownList;
        profiles.DisplayMember = "Value"; profiles.ValueMember = "Key";
        foreach (var pair in names) profiles.Items.Add(pair);
        profiles.SelectedIndex = 0; left.Controls.Add(profiles);
        profiles.SelectedIndexChanged += (s,e) => RefreshMods();
        list.SetBounds(21, 132, 368, 258);
        list.BackColor = Color.FromArgb(19, 29, 43); list.ForeColor = White;
        list.BorderStyle = BorderStyle.None; list.CheckOnClick = true;
        list.Font = new Font(Font.FontFamily, 10); list.ItemHeight = 28;
        left.Controls.Add(list);
        list.SelectedIndexChanged += (s,e) => ShowDetail();
        list.ItemCheck += (s,e) => {
            if (refreshing || busy) return;
            var selected = new HashSet<int>(list.CheckedIndices.Cast<int>());
            if (e.NewValue == CheckState.Checked) selected.Add(e.Index); else selected.Remove(e.Index);
            loader.SaveProfile(Profile, selected.Select(i => mods[i].Id));
            status.Text = "配置已保存，下次启动生效。";
        };
        ButtonAt(left, "导入 Mod", 21, 408, 113, 35, Accent, Background, () => Import());
        ButtonAt(left, "打开目录", 143, 408, 114, 35, Color.FromArgb(52, 70, 90), White, () => Open(loader.Mods));
        ButtonAt(left, "刷新列表", 266, 408, 123, 35, Color.FromArgb(52, 70, 90), White, () => RefreshMods());

        var right = Card(448, 111, 568, 463);
        LabelAt(right, "模块详情", 22, 17, 400, 28, 14, true, White);
        detail.SetBounds(22, 57, 524, 194); detail.Multiline = true;
        detail.ReadOnly = true; detail.ScrollBars = ScrollBars.Vertical;
        detail.BorderStyle = BorderStyle.None; detail.BackColor = Color.FromArgb(19, 29, 43);
        detail.ForeColor = Muted; detail.Font = new Font(Font.FontFamily, 9.5f); right.Controls.Add(detail);
        LabelAt(right, "启动器更新", 22, 271, 400, 28, 14, true, White);
        releaseStatus = LabelAt(right, "当前版本 v" + Data.Version + " · 可从 GitHub 检查新版", 22, 301, 520, 43, 9, false, Muted);
        ButtonAt(right, "检查更新", 22, 363, 116, 37, Color.FromArgb(52, 70, 90), White, () => CheckUpdate());
        download = ButtonAt(right, "从 GitHub 升级", 148, 363, 144, 37, Accent, Background, () => DownloadUpdate());
        download.Enabled = false;
        ButtonAt(right, "选择压缩包", 302, 363, 119, 37, Color.FromArgb(52, 70, 90), White, () => LocalUpdate());
        ButtonAt(right, "打开 GitHub", 431, 363, 115, 37, Color.FromArgb(52, 70, 90), White, () => Open(UpdateService.Repository));
        LabelAt(right, "更新前先退出游戏；现有配置与第三方 Mod 会保留。", 22, 417, 520, 23, 9, false, Muted);

        var footer = Card(24, 590, 992, 71);
        ButtonAt(footer, "启动游戏", 16, 14, 168, 43, Accent, Background, () => Launch(false), 12);
        ButtonAt(footer, "启动原版", 195, 14, 120, 43, Color.FromArgb(52, 70, 90), White, () => Launch(true));
        ButtonAt(footer, "更新内置 Mod", 326, 14, 144, 43, Color.FromArgb(52, 70, 90), White, () => UpdateBundled());
        ButtonAt(footer, "日志", 481, 14, 75, 43, Color.FromArgb(52, 70, 90), White, () => {
            string path = Path.Combine(loader.Home, "Logs"); Directory.CreateDirectory(path); Open(path);
        });
        status = LabelAt(footer, "就绪", 571, 17, 401, 39, 9, false, Muted, ContentAlignment.MiddleLeft);

        DragEnter += (s,e) => e.Effect = e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None;
        DragDrop += (s,e) => { try { foreach (string path in (string[])e.Data.GetData(DataFormats.FileDrop)) ImportFile(path); RefreshMods(); } catch (Exception error) { Report(error); } };
        RefreshMods();
    }

    Panel Card(int x, int y, int width, int height) {
        var panel = new Panel { Left=x, Top=y, Width=width, Height=height, BackColor=PanelColor };
        Controls.Add(panel); return panel;
    }
    static Label LabelAt(Control parent, string text, int x, int y, int width, int height, float size, bool bold, Color color, ContentAlignment align=ContentAlignment.MiddleLeft) {
        var label = new Label { Text=text, Left=x, Top=y, Width=width, Height=height, ForeColor=color,
            TextAlign=align, Font=new Font("Microsoft YaHei UI", size, bold?FontStyle.Bold:FontStyle.Regular) };
        parent.Controls.Add(label); return label;
    }
    Button ButtonAt(Control parent, string text, int x, int y, int width, int height, Color background, Color foreground, Action action, float size=9) {
        var button = new Button { Text=text, Left=x, Top=y, Width=width, Height=height, BackColor=background,
            ForeColor=foreground, FlatStyle=FlatStyle.Flat, Cursor=Cursors.Hand,
            Font=new Font("Microsoft YaHei UI", size, FontStyle.Bold) };
        button.FlatAppearance.BorderSize=0;
        button.Click += (s,e) => { try { action(); } catch (Exception error) { Report(error); } };
        parent.Controls.Add(button); return button;
    }
    string Profile { get { return ((KeyValuePair<string,string>)profiles.SelectedItem).Key; } }
    void RefreshMods() {
        refreshing=true;
        try {
            mods=loader.Discover(); var active=new HashSet<string>(loader.Enabled(Profile)); list.Items.Clear();
            foreach (var mod in mods) list.Items.Add(mod.Name + "  v" + mod.Version, active.Contains(mod.Id));
        } finally { refreshing=false; }
        status.Text=loader.Errors.Count==0 ? "已安装 " + mods.Count + " 个 Mod" : String.Join("；",loader.Errors);
        if (mods.Count>0) list.SelectedIndex=0; else detail.Text="暂无已安装模块。";
    }
    void SaveSelection() { loader.SaveProfile(Profile,list.CheckedIndices.Cast<int>().Select(i=>mods[i].Id)); }
    void ShowDetail() {
        if (list.SelectedIndex<0) return;
        var mod=mods[list.SelectedIndex];
        var dependencies=Data.Obj(Data.Get(mod.Manifest,"dependencies",new Dictionary<string,object>()));
        detail.Text=mod.Name+"  v"+mod.Version+"\r\n"+mod.Id+"\r\n\r\n"+Data.Str(mod.Manifest,"description")+
            "\r\n\r\n依赖："+(dependencies.Count==0?"无":String.Join("，",dependencies.Select(p=>p.Key+" "+p.Value)))+
            "\r\n路径："+mod.Directory;
    }
    void Import() {
        using (var picker=new OpenFileDialog { Filter="Mod 包 (*.ftcmod;*.zip)|*.ftcmod;*.zip", Multiselect=true })
            if (picker.ShowDialog(this)==DialogResult.OK) { foreach (var path in picker.FileNames) ImportFile(path); RefreshMods(); }
    }
    void ImportFile(string path) { var mod=loader.Install(path); status.Text="已安装 " + mod.Name + "；勾选后启动。"; }
    void Open(string target) { Process.Start(new ProcessStartInfo(target) { UseShellExecute=true }); }
    void Report(Exception error) {
        loader.Log("ERROR " + error); status.Text=error.Message;
        MessageBox.Show(this,error.Message,"Mod 启动器",MessageBoxButtons.OK,MessageBoxIcon.Error);
    }
    void Work(string message, Func<object> task, Action<object> completed) {
        if (busy) return;
        busy=true; status.Text=message;
        var worker=new BackgroundWorker();
        worker.DoWork+=(s,e)=>e.Result=task();
        worker.RunWorkerCompleted+=(s,e)=>{
            busy=false;
            if (e.Error!=null) Report(e.Error); else completed(e.Result);
        };
        worker.RunWorkerAsync();
    }
    void Launch(bool vanilla) {
        SaveSelection(); string profile=Profile;
        Work("正在准备游戏…",()=>{loader.Launch(profile,vanilla);return null;},_=>status.Text="游戏已启动。请先保存退出游戏，再切换 Mod。");
    }
    void UpdateBundled() {
        SaveSelection();
        Work("正在校验内置 Mod…",()=>loader.UpdateBundled(),result=>{
            var changed=(List<Mod>)result; RefreshMods();
            status.Text=changed.Count==0?"内置 Mod 已是最新版本。":"已更新 "+String.Join("、",changed.Select(m=>m.Name+" "+m.Version));
        });
    }
    void CheckUpdate() {
        Work("正在连接 GitHub…",()=>UpdateService.Check(),result=>{
            release=(RemoteRelease)result;
            bool newer=UpdateService.IsNewer(release.Version);
            download.Enabled=newer;
            releaseStatus.Text=newer?"发现新版 v"+release.Version+" · "+Math.Round(release.Size/1048576.0,1)+" MB · SHA-256 已验证":"当前已是最新版本 v"+Data.Version;
            status.Text=newer?"可以从 GitHub 下载升级。":"已是最新版本。";
        });
    }
    void DownloadUpdate() {
        if (release==null || !UpdateService.IsNewer(release.Version)) return;
        var selected=release;
        Work("正在下载新版…",()=>UpdateService.Download(selected,Path.Combine(loader.Home,"Cache","Updates"),percent=>{
            try { BeginInvoke((Action)(()=>status.Text="正在下载新版… "+percent+"%")); } catch (InvalidOperationException) {}
        }),result=>BeginUpdate((string)result));
    }
    void LocalUpdate() {
        using (var picker=new OpenFileDialog { Filter="完整安装压缩包 (*.zip)|*.zip", Title="选择 FTCModLoader 完整安装包" })
            if (picker.ShowDialog(this)==DialogResult.OK) {
                string path=picker.FileName;
                Work("正在校验压缩包…",()=>UpdateService.Validate(path),_=>BeginUpdate(path));
            }
    }
    void BeginUpdate(string path) {
        SaveSelection();
        UpdateService.StartApply(path,loader.Root);
        status.Text="正在关闭旧版启动器并安装新版…";
        Close();
    }
}
}
