param([string]$Bundle, [string]$Output, [string]$HashSource)
$ErrorActionPreference = 'Stop'
$compilerPath = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $compilerPath /nologo /target:winexe /main:CupsModLoader.StandaloneInstaller /platform:x64 /optimize+ /utf8output /reference:System.Core.dll /reference:System.Drawing.dll /reference:System.Windows.Forms.dll /reference:System.Web.Extensions.dll /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll "/resource:$Bundle,FTC.Bundle" "/out:$Output" (Join-Path $PSScriptRoot 'Loader.cs') (Join-Path $PSScriptRoot 'Deployment.cs') (Join-Path $PSScriptRoot 'StandaloneInstaller.cs') $HashSource
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
