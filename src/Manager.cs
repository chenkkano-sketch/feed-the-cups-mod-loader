using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Data;
using System.Windows.Media;
using System.Windows.Media.Effects;
using Microsoft.Win32;

namespace CupsModLoader {
public sealed class Manager : Window {
    static readonly Brush Page=BrushOf("#F4F7FB"), Paper=BrushOf("#FFFFFF"), Soft=BrushOf("#F8FAFC");
    static readonly Brush Ink=BrushOf("#1E293B"), Muted=BrushOf("#64748B"), Line=BrushOf("#E2E8F0");
    static readonly Brush Teal=BrushOf("#0F766E"), TealHover=BrushOf("#115E59"), TealSoft=BrushOf("#E7F5F2");
    static readonly FontFamily UiFont=new FontFamily("Microsoft YaHei UI");
    readonly Loader loader;
    readonly ComboBox profiles=new ComboBox();
    readonly ListBox list=new ListBox();
    readonly TextBlock modTitle=new TextBlock(),modMeta=new TextBlock(),modDescription=new TextBlock();
    readonly TextBlock releaseStatus=new TextBlock(),status=new TextBlock();
    readonly Button download;
    readonly List<Tuple<Mod,CheckBox>> rows=new List<Tuple<Mod,CheckBox>>();
    List<Mod> mods=new List<Mod>(); RemoteRelease release; bool refreshing,busy;
    readonly KeyValuePair<string,string>[] profileNames={
        new KeyValuePair<string,string>("default","我的配置"),new KeyValuePair<string,string>("rent_coop","房租联机＋实时搬运"),
        new KeyValuePair<string,string>("both","房租＋修改器＋搬运"),new KeyValuePair<string,string>("rent","房租＋搬运"),
        new KeyValuePair<string,string>("rent_only","仅房租模式"),new KeyValuePair<string,string>("trainer","仅修改器"),
        new KeyValuePair<string,string>("furniture","仅自由搬运"),new KeyValuePair<string,string>("talent","人才市场＋自由搬运"),
        new KeyValuePair<string,string>("talent_rent","人才市场＋房租＋搬运"),new KeyValuePair<string,string>("talent_all","全部模块")};

    public Manager(Loader value) {
        loader=value;Title="杯杯倒满 Mod 启动器 "+Data.Version;
        Width=1080;Height=750;MinWidth=980;MinHeight=680;WindowStartupLocation=WindowStartupLocation.CenterScreen;
        Background=Page;Foreground=Ink;FontFamily=UiFont;FontSize=13;UseLayoutRounding=true;AllowDrop=true;
        var root=new Grid();root.RowDefinitions.Add(new RowDefinition{Height=new GridLength(92)});
        root.RowDefinitions.Add(new RowDefinition{Height=new GridLength(1,GridUnitType.Star)});
        root.RowDefinitions.Add(new RowDefinition{Height=new GridLength(98)});Content=root;
        Header(root);
        var middle=new Grid{Margin=new Thickness(24,12,24,12)};
        middle.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(386)});
        middle.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(16)});
        middle.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(1,GridUnitType.Star)});
        Grid.SetRow(middle,1);root.Children.Add(middle);
        ProfilesCard(middle);download=DetailCard(middle);Footer(root);
        DragEnter+=(s,e)=>e.Effects=e.Data.GetDataPresent(DataFormats.FileDrop)?DragDropEffects.Copy:DragDropEffects.None;
        Drop+=(s,e)=>{try{foreach(string path in (string[])e.Data.GetData(DataFormats.FileDrop))ImportFile(path);RefreshMods();}catch(Exception error){Report(error);}};
        RefreshMods();
    }

    static Brush BrushOf(string hex){var value=(SolidColorBrush)new BrushConverter().ConvertFromString(hex);value.Freeze();return value;}
    static TextBlock Text(string value,double size,Brush color,FontWeight weight){return new TextBlock{Text=value,FontSize=size,Foreground=color,FontWeight=weight,VerticalAlignment=VerticalAlignment.Center,TextTrimming=TextTrimming.CharacterEllipsis};}
    static Border Card(){return new Border{Background=Paper,BorderBrush=Line,BorderThickness=new Thickness(1),CornerRadius=new CornerRadius(18),Effect=new DropShadowEffect{Color=Colors.SlateGray,BlurRadius=18,ShadowDepth=3,Opacity=.1}};}
    internal static Style ButtonStyle(bool primary){
        var style=new Style(typeof(Button));
        style.Setters.Add(new Setter(Button.BackgroundProperty,primary?Teal:Soft));
        style.Setters.Add(new Setter(Button.ForegroundProperty,primary?Paper:Ink));
        style.Setters.Add(new Setter(Button.BorderBrushProperty,primary?Teal:Line));
        style.Setters.Add(new Setter(Button.BorderThicknessProperty,new Thickness(1)));
        style.Setters.Add(new Setter(Button.FontWeightProperty,FontWeights.SemiBold));
        style.Setters.Add(new Setter(Button.CursorProperty,System.Windows.Input.Cursors.Hand));
        var frame=new FrameworkElementFactory(typeof(Border));
        frame.SetValue(Border.CornerRadiusProperty,new CornerRadius(10));
        frame.SetBinding(Border.BackgroundProperty,new Binding("Background"){RelativeSource=new RelativeSource(RelativeSourceMode.TemplatedParent)});
        frame.SetBinding(Border.BorderBrushProperty,new Binding("BorderBrush"){RelativeSource=new RelativeSource(RelativeSourceMode.TemplatedParent)});
        frame.SetBinding(Border.BorderThicknessProperty,new Binding("BorderThickness"){RelativeSource=new RelativeSource(RelativeSourceMode.TemplatedParent)});
        var presenter=new FrameworkElementFactory(typeof(ContentPresenter));
        presenter.SetValue(ContentPresenter.HorizontalAlignmentProperty,HorizontalAlignment.Center);
        presenter.SetValue(ContentPresenter.VerticalAlignmentProperty,VerticalAlignment.Center);frame.AppendChild(presenter);
        style.Setters.Add(new Setter(Button.TemplateProperty,new ControlTemplate(typeof(Button)){VisualTree=frame}));
        var hover=new Trigger{Property=Button.IsMouseOverProperty,Value=true};hover.Setters.Add(new Setter(Button.BackgroundProperty,primary?TealHover:TealSoft));style.Triggers.Add(hover);
        var disabled=new Trigger{Property=Button.IsEnabledProperty,Value=false};disabled.Setters.Add(new Setter(Button.OpacityProperty,.45));style.Triggers.Add(disabled);
        return style;
    }
    Button Action(string caption,bool primary,Action callback){
        var button=new Button{Content=caption,Height=40,Style=ButtonStyle(primary),Padding=new Thickness(12,6,12,6)};
        button.Click+=(s,e)=>{try{callback();}catch(Exception error){Report(error);}};return button;
    }

    void Header(Grid root){
        var area=new Border{Background=Paper,BorderBrush=Line,BorderThickness=new Thickness(0,0,0,1)};
        Grid.SetRow(area,0);root.Children.Add(area);
        var grid=new Grid{Margin=new Thickness(27,0,27,0)};
        grid.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(62)});
        grid.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(1,GridUnitType.Star)});
        grid.ColumnDefinitions.Add(new ColumnDefinition{Width=GridLength.Auto});area.Child=grid;
        var badge=new Border{Width=48,Height=48,CornerRadius=new CornerRadius(14),Background=Teal,VerticalAlignment=VerticalAlignment.Center,
            Child=new TextBlock{Text="杯",Foreground=Paper,FontSize=22,FontWeight=FontWeights.Bold,HorizontalAlignment=HorizontalAlignment.Center,VerticalAlignment=VerticalAlignment.Center}};
        Grid.SetColumn(badge,0);grid.Children.Add(badge);
        var title=new StackPanel{VerticalAlignment=VerticalAlignment.Center};
        title.Children.Add(Text("杯杯倒满 Mod 启动器",21,Ink,FontWeights.Bold));
        title.Children.Add(Text("管理模块、配置与更新，一处完成",12,Muted,FontWeights.Normal));
        Grid.SetColumn(title,1);grid.Children.Add(title);
        var chip=new Border{Background=TealSoft,CornerRadius=new CornerRadius(15),Padding=new Thickness(14,7,14,7),VerticalAlignment=VerticalAlignment.Center,
            Child=Text("版本  "+Data.Version,12,Teal,FontWeights.SemiBold)};
        Grid.SetColumn(chip,2);grid.Children.Add(chip);
    }

    void ProfilesCard(Grid middle){
        var card=Card();Grid.SetColumn(card,0);middle.Children.Add(card);
        var grid=new Grid{Margin=new Thickness(22)};card.Child=grid;
        grid.RowDefinitions.Add(new RowDefinition{Height=GridLength.Auto});grid.RowDefinitions.Add(new RowDefinition{Height=GridLength.Auto});
        grid.RowDefinitions.Add(new RowDefinition{Height=new GridLength(1,GridUnitType.Star)});grid.RowDefinitions.Add(new RowDefinition{Height=GridLength.Auto});
        var heading=new StackPanel();heading.Children.Add(Text("游戏配置",18,Ink,FontWeights.Bold));
        heading.Children.Add(new TextBlock{Text="选择一个方案，再勾选需要的 Mod",Foreground=Muted,FontSize=12,Margin=new Thickness(0,4,0,0)});
        Grid.SetRow(heading,0);grid.Children.Add(heading);
        profiles.Height=38;profiles.Margin=new Thickness(0,20,0,15);profiles.Background=Paper;profiles.Foreground=Ink;
        profiles.BorderBrush=Line;profiles.FontFamily=UiFont;profiles.FontSize=13;
        foreach(var pair in profileNames)profiles.Items.Add(new ComboBoxItem{Content=pair.Value,Tag=pair.Key});
        profiles.SelectedIndex=0;profiles.SelectionChanged+=(s,e)=>RefreshMods();Grid.SetRow(profiles,1);grid.Children.Add(profiles);
        list.Background=Paper;list.BorderThickness=new Thickness(0);list.SelectionChanged+=(s,e)=>ShowDetail();
        Grid.SetRow(list,2);grid.Children.Add(list);
        var actions=new UniformGrid{Columns=3,Margin=new Thickness(0,18,0,0)};
        var import=Action("导入 Mod",true,Import);import.Margin=new Thickness(0,0,8,0);actions.Children.Add(import);
        var folder=Action("打开目录",false,()=>Open(loader.Mods));folder.Margin=new Thickness(4,0,4,0);actions.Children.Add(folder);
        var refresh=Action("刷新列表",false,RefreshMods);refresh.Margin=new Thickness(8,0,0,0);actions.Children.Add(refresh);
        Grid.SetRow(actions,3);grid.Children.Add(actions);
    }

    Button DetailCard(Grid middle){
        var card=Card();Grid.SetColumn(card,2);middle.Children.Add(card);
        var content=new StackPanel{Margin=new Thickness(24)};card.Child=content;
        content.Children.Add(Text("模块详情",18,Ink,FontWeights.Bold));
        var details=new Border{Background=Soft,CornerRadius=new CornerRadius(12),Padding=new Thickness(17),Height=160,Margin=new Thickness(0,15,0,19)};
        var detailStack=new StackPanel();details.Child=detailStack;
        modTitle.FontSize=16;modTitle.FontWeight=FontWeights.SemiBold;modTitle.Foreground=Ink;
        modMeta.FontSize=11;modMeta.Foreground=Muted;modMeta.Margin=new Thickness(0,4,0,10);
        modDescription.FontSize=12;modDescription.Foreground=Muted;modDescription.TextWrapping=TextWrapping.Wrap;
        detailStack.Children.Add(modTitle);detailStack.Children.Add(modMeta);
        detailStack.Children.Add(new ScrollViewer{Content=modDescription,VerticalScrollBarVisibility=ScrollBarVisibility.Auto,Height=76});
        content.Children.Add(details);content.Children.Add(Text("启动器更新",18,Ink,FontWeights.Bold));
        var banner=new Border{Background=TealSoft,CornerRadius=new CornerRadius(12),Padding=new Thickness(16,12,16,12),Margin=new Thickness(0,15,0,16)};
        releaseStatus.Text="当前版本 v"+Data.Version+"  ·  可检查 GitHub 最新版本";
        releaseStatus.Foreground=Teal;releaseStatus.FontSize=12;releaseStatus.TextWrapping=TextWrapping.Wrap;
        banner.Child=releaseStatus;content.Children.Add(banner);
        var actions=new UniformGrid{Columns=2,Rows=2};
        var check=Action("检查更新",false,CheckUpdate);check.Margin=new Thickness(0,0,6,8);actions.Children.Add(check);
        var downloadButton=Action("从 GitHub 升级",true,DownloadUpdate);downloadButton.Margin=new Thickness(6,0,0,8);downloadButton.IsEnabled=false;actions.Children.Add(downloadButton);
        var local=Action("选择压缩包",false,LocalUpdate);local.Margin=new Thickness(0,6,6,0);actions.Children.Add(local);
        var github=Action("打开 GitHub",false,()=>Open(UpdateService.Repository));github.Margin=new Thickness(6,6,0,0);actions.Children.Add(github);
        content.Children.Add(actions);
        content.Children.Add(new TextBlock{Text="更新前先退出游戏。已有配置与第三方 Mod 会保留。",Foreground=Muted,FontSize=11,Margin=new Thickness(0,18,0,0),TextWrapping=TextWrapping.Wrap});
        return downloadButton;
    }

    void Footer(Grid root){
        var card=Card();card.Margin=new Thickness(24,0,24,18);Grid.SetRow(card,2);root.Children.Add(card);
        var grid=new Grid{Margin=new Thickness(16)};card.Child=grid;
        foreach(var width in new[]{150.0,112.0,142.0,76.0})grid.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(width)});
        grid.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(1,GridUnitType.Star)});
        var play=Action("启动游戏",true,()=>Launch(false));play.Margin=new Thickness(0,0,8,0);Grid.SetColumn(play,0);grid.Children.Add(play);
        var vanilla=Action("启动原版",false,()=>Launch(true));vanilla.Margin=new Thickness(0,0,8,0);Grid.SetColumn(vanilla,1);grid.Children.Add(vanilla);
        var bundled=Action("更新内置 Mod",false,UpdateBundled);bundled.Margin=new Thickness(0,0,8,0);Grid.SetColumn(bundled,2);grid.Children.Add(bundled);
        var logs=Action("日志",false,()=>{string path=Path.Combine(loader.Home,"Logs");Directory.CreateDirectory(path);Open(path);});logs.Margin=new Thickness(0,0,8,0);Grid.SetColumn(logs,3);grid.Children.Add(logs);
        status.Text="就绪";status.Foreground=Muted;status.FontSize=11;status.TextWrapping=TextWrapping.Wrap;status.VerticalAlignment=VerticalAlignment.Center;status.Margin=new Thickness(12,0,0,0);
        Grid.SetColumn(status,4);grid.Children.Add(status);
    }

    string Profile{get{return Convert.ToString(((ComboBoxItem)profiles.SelectedItem).Tag);}}
    void RefreshMods(){
        refreshing=true;
        try{
            mods=loader.Discover();var active=new HashSet<string>(loader.Enabled(Profile));rows.Clear();list.Items.Clear();
            foreach(var mod in mods){
                var box=new CheckBox{IsChecked=active.Contains(mod.Id),VerticalAlignment=VerticalAlignment.Center,Margin=new Thickness(0,0,12,0)};
                var labels=new StackPanel();labels.Children.Add(Text(mod.Name,13,Ink,FontWeights.SemiBold));labels.Children.Add(Text(mod.Id+"  ·  v"+mod.Version,10,Muted,FontWeights.Normal));
                var panel=new StackPanel{Orientation=Orientation.Horizontal,Margin=new Thickness(6,7,6,7)};panel.Children.Add(box);panel.Children.Add(labels);
                var item=new ListBoxItem{Content=panel,Tag=mod,Margin=new Thickness(0,2,0,2),Background=Soft,BorderBrush=Line,BorderThickness=new Thickness(1),Padding=new Thickness(8)};
                box.Click+=(s,e)=>{list.SelectedItem=item;SaveSelection();status.Text="配置已保存，下次启动生效。";};
                rows.Add(Tuple.Create(mod,box));list.Items.Add(item);
            }
        }finally{refreshing=false;}
        status.Text=loader.Errors.Count==0?"已安装 "+mods.Count+" 个 Mod":String.Join("；",loader.Errors);
        if(mods.Count>0)list.SelectedIndex=0;else{modTitle.Text="暂无模块";modMeta.Text="";modDescription.Text="可以导入 .ftcmod，或安装内置 Mod。";}
    }
    void SaveSelection(){if(!refreshing)loader.SaveProfile(Profile,rows.Where(r=>r.Item2.IsChecked==true).Select(r=>r.Item1.Id));}
    void ShowDetail(){
        var item=list.SelectedItem as ListBoxItem;if(item==null)return;var mod=item.Tag as Mod;if(mod==null)return;
        var deps=Data.Obj(Data.Get(mod.Manifest,"dependencies",new Dictionary<string,object>()));
        modTitle.Text=mod.Name+"  v"+mod.Version;modMeta.Text=mod.Id+"  ·  API "+Data.Api+"  ·  游戏 1.0.2.0";
        modDescription.Text=Data.Str(mod.Manifest,"description")+"\n\n依赖："+(deps.Count==0?"无":String.Join("，",deps.Select(p=>p.Key+" "+p.Value)));
    }
    void Import(){var picker=new OpenFileDialog{Filter="Mod 包 (*.ftcmod;*.zip)|*.ftcmod;*.zip",Multiselect=true};if(picker.ShowDialog(this)==true){foreach(var path in picker.FileNames)ImportFile(path);RefreshMods();}}
    void ImportFile(string path){var mod=loader.Install(path);status.Text="已安装 "+mod.Name+"；勾选后启动。";}
    void Open(string target){Process.Start(new ProcessStartInfo(target){UseShellExecute=true});}
    void Report(Exception error){loader.Log("ERROR "+error);status.Text=error.Message;System.Windows.MessageBox.Show(this,error.Message,"Mod 启动器",MessageBoxButton.OK,MessageBoxImage.Error);}
    void Work(string message,Func<object> task,Action<object> done){
        if(busy)return;busy=true;status.Text=message;
        var worker=new BackgroundWorker();worker.DoWork+=(s,e)=>e.Result=task();
        worker.RunWorkerCompleted+=(s,e)=>{busy=false;if(e.Error!=null)Report(e.Error);else try{done(e.Result);}catch(Exception error){Report(error);}};
        worker.RunWorkerAsync();
    }
    void Launch(bool vanilla){SaveSelection();string profile=Profile;Work("正在准备游戏…",()=>{loader.Launch(profile,vanilla);return null;},_=>status.Text="游戏已启动。请先保存退出游戏，再切换 Mod。");}
    void UpdateBundled(){SaveSelection();Work("正在校验内置 Mod…",()=>loader.UpdateBundled(),result=>{var changed=(List<Mod>)result;RefreshMods();status.Text=changed.Count==0?"内置 Mod 已是最新版本。":"已更新 "+String.Join("、",changed.Select(m=>m.Name+" "+m.Version));});}
    void CheckUpdate(){Work("正在连接 GitHub Release…",()=>UpdateService.Check(),result=>{
        release=(RemoteRelease)result;bool newer=UpdateService.IsNewer(release.Version);download.IsEnabled=newer;
        releaseStatus.Text=newer?"发现新版 v"+release.Version+(release.Size>0?"  ·  "+Math.Round(release.Size/1048576.0,1)+" MB":"")+"  ·  已读取 SHA-256":"当前已是最新版本 v"+Data.Version;
        status.Text=newer?"可从 GitHub 下载升级。":"已是最新版本。";});}
    void DownloadUpdate(){if(release==null||!UpdateService.IsNewer(release.Version))return;var selected=release;
        Work("正在下载新版…",()=>UpdateService.Download(selected,Path.Combine(loader.Home,"Cache","Updates"),percent=>{
            try{Dispatcher.BeginInvoke(new Action(()=>status.Text=percent<0?"正在下载新版…":"正在下载新版… "+percent+"%"));}catch(InvalidOperationException){}
        }),result=>BeginUpdate((string)result));}
    void LocalUpdate(){var picker=new OpenFileDialog{Filter="完整安装压缩包 (*.zip)|*.zip",Title="选择 FTCModLoader 完整安装包"};if(picker.ShowDialog(this)==true){string path=picker.FileName;Work("正在校验压缩包…",()=>UpdateService.Validate(path),_=>BeginUpdate(path));}}
    void BeginUpdate(string path){SaveSelection();UpdateService.StartApply(path,loader.Root);status.Text="正在关闭旧版启动器并安装新版…";Close();}
}
}
