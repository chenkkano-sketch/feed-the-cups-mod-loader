# 杯杯倒满 Mod 启动器

适配《Feed the Cups》Windows 64 位游戏版本 `1.0.2.0` 的 Mod 启动器和模块集合。启动器采用浅色 WPF 界面。

## 安装

1. 从 [最新 Release](https://github.com/chenkkano-sketch/feed-the-cups-mod-loader/releases/latest) 下载 `FTCModLoader-版本号.zip`。
2. 完整解压到任意文件夹，运行其中的 `杯杯倒满Mod加载器.exe`。
3. 选择游戏目录并点击安装。之后从游戏目录的同一个启动器管理、启动和更新 Mod。

不用运行命令脚本。安装器会检查游戏版本，保留已有配置和第三方 Mod；游戏本体、游戏存档和运行缓存不包含在本仓库与 Release 中。

## 更新

启动器右侧可以检查 GitHub 最新版本、下载并升级，也可以打开仓库或选择已下载的完整 ZIP。更新检查读取公开 Release，避免 GitHub 匿名 API 的请求额度限制。GitHub 下载会核对 Release 的 SHA-256，文件大小可读取时也会核对大小。更新时请先退出游戏。更新失败时会保留原压缩包，并记录在 `FTCModLoader/Logs/update-error.log`。

只更新内置模块时，可使用启动器底部的“更新内置 Mod”。

## 目录

- `src`：启动器、安装器和发布脚本
- `Core`：Mod API 与兼容层
- `Mods`：内置模块源码
- `SDK`：开发资料和示例
- `Design`：项目设计素材
- `Profiles`：预设配置

运行时产生的 `Cache`、`Logs`、`Backups`、`Packages` 和本地测试文件不提交到仓库。Release 提供完整安装 ZIP 及同名 `.sha256` 校验文件。
