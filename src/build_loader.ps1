param([string]$Output)
$ErrorActionPreference = 'Stop'
$loaderRoot = Split-Path $PSScriptRoot -Parent
$gameRoot = Split-Path $loaderRoot -Parent
if (-not $Output) { $Output = Join-Path $gameRoot '杯杯倒满Mod加载器.exe' }
$compilerPath = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $compilerPath /nologo /target:winexe /platform:x64 /optimize+ /utf8output /reference:System.Core.dll /reference:System.Drawing.dll /reference:System.Windows.Forms.dll /reference:System.Web.Extensions.dll /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll /out:$Output "$PSScriptRoot\Loader.cs" "$PSScriptRoot\Deployment.cs" "$PSScriptRoot\UpdateService.cs" "$PSScriptRoot\Manager.cs"
if ($LASTEXITCODE -ne 0) { throw '加载器编译失败。' }
