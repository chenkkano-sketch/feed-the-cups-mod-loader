using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace CupsModLoader {
public sealed class SetupWindow : Window {
    readonly string source;
    readonly TextBox path=new TextBox();
    readonly TextBlock status=new TextBlock();
    readonly Button install=new Button();
    static Brush Color(string hex){return (Brush)new BrushConverter().ConvertFromString(hex);}

    public SetupWindow(string root){
        source=root;Title="安装杯杯倒满 Mod 启动器";
        Width=680;Height=365;ResizeMode=ResizeMode.NoResize;WindowStartupLocation=WindowStartupLocation.CenterScreen;
        Background=Color("#F4F7FB");Foreground=Color("#1E293B");FontFamily=new FontFamily("Microsoft YaHei UI");FontSize=13;
        var grid=new Grid{Margin=new Thickness(26)};Content=grid;
        grid.RowDefinitions.Add(new RowDefinition{Height=GridLength.Auto});
        grid.RowDefinitions.Add(new RowDefinition{Height=new GridLength(1,GridUnitType.Star)});
        var header=new StackPanel{Margin=new Thickness(0,0,0,18)};
        header.Children.Add(new TextBlock{Text="安装 Mod 启动器",FontSize=23,FontWeight=FontWeights.Bold});
        header.Children.Add(new TextBlock{Text="选择游戏目录，安装器会校验版本并保留现有配置。",Foreground=Color("#64748B"),Margin=new Thickness(0,6,0,0)});
        Grid.SetRow(header,0);grid.Children.Add(header);
        var card=new Border{Background=Brushes.White,BorderBrush=Color("#E2E8F0"),BorderThickness=new Thickness(1),CornerRadius=new CornerRadius(16),Padding=new Thickness(22)};
        Grid.SetRow(card,1);grid.Children.Add(card);
        var body=new StackPanel();card.Child=body;
        body.Children.Add(new TextBlock{Text="游戏安装位置",FontWeight=FontWeights.SemiBold,FontSize=15});
        var pick=new Grid{Margin=new Thickness(0,14,0,10)};
        pick.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(1,GridUnitType.Star)});
        pick.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(94)});
        path.Height=39;path.VerticalContentAlignment=VerticalAlignment.Center;path.Padding=new Thickness(9,0,9,0);
        path.BorderBrush=Color("#CBD5E1");path.Margin=new Thickness(0,0,10,0);
        var found=Deployment.FindGames();path.Text=found.Length==1?found[0]:"";
        Grid.SetColumn(path,0);pick.Children.Add(path);
        var browse=new Button{Content="浏览…",Height=39,Style=Manager.ButtonStyle(false)};
        browse.Click+=(s,e)=>Browse();Grid.SetColumn(browse,1);pick.Children.Add(browse);body.Children.Add(pick);
        body.Children.Add(new TextBlock{Text="请选择 Feed the Cups.exe 所在目录。不会修改原版游戏 EXE 和 PCK。",Foreground=Color("#64748B"),FontSize=11,TextWrapping=TextWrapping.Wrap});
        var bottom=new Grid{Margin=new Thickness(0,24,0,0)};
        bottom.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(1,GridUnitType.Star)});
        bottom.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(150)});
        status.Text=found.Length>1?"发现多个游戏位置，请确认目录。":"就绪";
        status.Foreground=Color("#64748B");status.TextWrapping=TextWrapping.Wrap;status.VerticalAlignment=VerticalAlignment.Center;
        Grid.SetColumn(status,0);bottom.Children.Add(status);
        install.Content="安装 / 更新";install.Height=42;install.Style=Manager.ButtonStyle(true);
        install.Click+=(s,e)=>Install();Grid.SetColumn(install,1);bottom.Children.Add(install);body.Children.Add(bottom);
    }
    void Browse(){
        using(var picker=new System.Windows.Forms.FolderBrowserDialog{Description="选择 Feed the Cups.exe 所在目录",ShowNewFolderButton=false}){
            if(Directory.Exists(path.Text))picker.SelectedPath=path.Text;
            if(picker.ShowDialog()==System.Windows.Forms.DialogResult.OK)path.Text=picker.SelectedPath;
        }
    }
    void Install(){
        string destination=path.Text.Trim();
        if(!Deployment.IsGame(destination)){System.Windows.MessageBox.Show(this,"请选择 Feed the Cups.exe 所在目录。","安装未开始",MessageBoxButton.OK,MessageBoxImage.Information);return;}
        install.IsEnabled=false;status.Text="正在校验并安装，请稍候…";
        var worker=new BackgroundWorker();worker.DoWork+=(s,e)=>Deployment.Install(source,destination);
        worker.RunWorkerCompleted+=(s,e)=>{
            install.IsEnabled=true;
            if(e.Error!=null){status.Text="安装未完成："+e.Error.Message;System.Windows.MessageBox.Show(this,e.Error.Message,"安装未完成",MessageBoxButton.OK,MessageBoxImage.Error);}
            else{status.Text="安装完成，正在打开启动器…";Process.Start(new ProcessStartInfo(Path.Combine(destination,"杯杯倒满Mod加载器.exe")){WorkingDirectory=destination,UseShellExecute=false});Close();}
        };
        worker.RunWorkerAsync();
    }
}
}
