using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

namespace CupsModLoader {
public sealed class RemoteRelease {
    public string Version, ZipUrl, ZipName, Sha256;
    public long Size;
}

public static class UpdateService {
    public const string Repository = "https://github.com/chenkkano-sketch/feed-the-cups-mod-loader";
    public const string Releases = Repository + "/releases/latest";
    const long MaximumArchive = 256L * 1024 * 1024;

    static HttpWebRequest Request(string url) {
        if (!url.StartsWith("https://", StringComparison.OrdinalIgnoreCase)) throw new Exception("更新地址必须使用 HTTPS。");
        ServicePointManager.SecurityProtocol |= (SecurityProtocolType)3072;
        var request = (HttpWebRequest)WebRequest.Create(url);
        request.UserAgent = "FTCModLoader/" + Data.Version + " (+" + Repository + ")";
        request.Accept = "application/vnd.github+json";
        request.Timeout = 20000;
        request.ReadWriteTimeout = 20000;
        request.AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate;
        return request;
    }

    static string ReadText(string url, int maxBytes) {
        using (var response = Request(url).GetResponse())
        using (var input = response.GetResponseStream())
        using (var output = new MemoryStream()) {
            var buffer = new byte[8192]; int count;
            while ((count = input.Read(buffer, 0, buffer.Length)) > 0) {
                if (output.Length + count > maxBytes) throw new Exception("GitHub 响应过大。");
                output.Write(buffer, 0, count);
            }
            return Encoding.UTF8.GetString(output.ToArray());
        }
    }

    public static RemoteRelease Check() {
        Dictionary<string,object> data;
        try { data = Data.Obj(Data.Json.DeserializeObject(ReadText("https://api.github.com/repos/chenkkano-sketch/feed-the-cups-mod-loader/releases/latest", 1024 * 1024))); }
        catch (WebException error) { throw new Exception("无法获取 GitHub 最新版本。请检查网络或稍后重试。", error); }
        var tag = Data.Str(data, "tag_name").TrimStart('v', 'V');
        Version parsed;
        if (!Version.TryParse(tag, out parsed) || parsed.Build < 0) throw new Exception("GitHub Release 版本号无效。");
        var expectedName = "FTCModLoader-" + tag + ".zip";
        string checksumUrl = null;
        var result = new RemoteRelease { Version = tag, ZipName = expectedName };
        foreach (var item in Data.Arr(Data.Get(data, "assets", new object[0]))) {
            var asset = Data.Obj(item);
            var name = Data.Str(asset, "name");
            if (name == expectedName) {
                result.ZipUrl = Data.Str(asset, "browser_download_url");
                result.Size = Convert.ToInt64(Data.Get(asset, "size", 0));
                var digest = Data.Str(asset, "digest");
                if (Regex.IsMatch(digest, @"^sha256:[0-9a-fA-F]{64}$")) result.Sha256 = digest.Substring(7).ToLowerInvariant();
            } else if (name == expectedName + ".sha256") checksumUrl = Data.Str(asset, "browser_download_url");
        }
        if (String.IsNullOrEmpty(result.ZipUrl) || !result.ZipUrl.StartsWith(Repository + "/releases/download/", StringComparison.OrdinalIgnoreCase)) throw new Exception("Release 缺少完整安装压缩包。");
        if (result.Size <= 0 || result.Size > MaximumArchive) throw new Exception("Release 安装包大小异常。");
        if (checksumUrl != null) {
            var checksum = ReadText(checksumUrl, 4096);
            var match = Regex.Match(checksum, @"\b([0-9a-fA-F]{64})\s+\*?" + Regex.Escape(expectedName) + @"\b");
            if (!match.Success) throw new Exception("Release 校验文件不完整。");
            var expected = match.Groups[1].Value.ToLowerInvariant();
            if (result.Sha256 != null && result.Sha256 != expected) throw new Exception("Release 校验值不一致。");
            result.Sha256 = expected;
        }
        if (result.Sha256 == null) throw new Exception("Release 缺少 SHA-256 校验值。");
        return result;
    }

    public static bool IsNewer(string version) { return new Version(version) > new Version(Data.Version); }

    public static string Download(RemoteRelease release, string cache, Action<int> progress) {
        Directory.CreateDirectory(cache);
        string path = Path.Combine(cache, release.ZipName + ".download-" + Guid.NewGuid().ToString("N"));
        long total = 0;
        try {
            using (var response = Request(release.ZipUrl).GetResponse())
            using (var input = response.GetResponseStream())
            using (var output = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None)) {
                var buffer = new byte[65536]; int count;
                while ((count = input.Read(buffer, 0, buffer.Length)) > 0) {
                    total += count;
                    if (total > MaximumArchive || total > release.Size) throw new Exception("下载大小超过 Release 所声明的大小。");
                    output.Write(buffer, 0, count);
                    if (progress != null) progress((int)(total * 100 / release.Size));
                }
            }
            if (total != release.Size) throw new Exception("下载不完整，请重新尝试。");
            if (Data.HashFile(path) != release.Sha256) throw new Exception("下载文件的 SHA-256 与 GitHub Release 不一致。");
            Validate(path);
            return path;
        } catch { try { File.Delete(path); } catch {} throw; }
    }

    public static string Validate(string archive) {
        if (!File.Exists(archive)) throw new Exception("找不到升级压缩包。");
        if (new FileInfo(archive).Length > MaximumArchive) throw new Exception("升级压缩包过大。");
        string version = null;
        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        using (var zip = ZipFile.OpenRead(archive)) {
            if (zip.Entries.Count > 5000) throw new Exception("升级包文件过多。");
            long total = 0;
            foreach (var entry in zip.Entries) {
                string name = entry.FullName.TrimEnd('/');
                if (name.Length == 0) continue;
                Data.SafePath(Path.GetTempPath(), name);
                if (!names.Add(name)) throw new Exception("升级包包含重复路径：" + name);
                if (((entry.ExternalAttributes >> 16) & 0xF000) == 0xA000) throw new Exception("升级包不能包含符号链接。");
                total += entry.Length;
                if (total > MaximumArchive) throw new Exception("升级包解压后过大。");
                if (name == "FTCModLoader/release.json") {
                    if (entry.Length > 4096) throw new Exception("升级包版本文件异常。");
                    using (var stream = entry.Open()) using (var reader = new StreamReader(stream, Encoding.UTF8))
                        version = Data.Str(Data.Obj(Data.Json.DeserializeObject(reader.ReadToEnd())), "version");
                }
            }
            if (!names.Contains("杯杯倒满Mod加载器.exe") || !names.Any(n => n.StartsWith("FTCModLoader/Packages/ftc.", StringComparison.OrdinalIgnoreCase) && n.EndsWith(".ftcmod", StringComparison.OrdinalIgnoreCase))) throw new Exception("这不是完整的 Mod 加载器安装包。");
            Version parsed;
            if (!Version.TryParse(version, out parsed) || parsed.Build < 0) throw new Exception("升级包缺少有效的 release.json 版本文件。");
            if (parsed < new Version(Data.Version)) throw new Exception("升级包版本低于当前加载器。");
        }
        return version;
    }

    public static void StartApply(string archive, string destination) {
        Validate(archive);
        string directory = Path.Combine(destination, "FTCModLoader", "Cache", "Updates", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        string helper = Path.Combine(directory, "FTCUpdateHelper.exe");
        using (var zip = ZipFile.OpenRead(archive)) {
            var entry = zip.GetEntry("杯杯倒满Mod加载器.exe");
            if (entry == null || entry.Length > 16L * 1024 * 1024) throw new Exception("升级包缺少有效的新版启动器。");
            using (var input = entry.Open()) using (var output = new FileStream(helper, FileMode.CreateNew, FileAccess.Write)) input.CopyTo(output);
        }
        var info = new ProcessStartInfo(helper) {
            Arguments = "--apply-update \"" + Path.GetFullPath(archive) + "\" --destination \"" + Path.GetFullPath(destination) + "\" --wait-pid " + Process.GetCurrentProcess().Id,
            WorkingDirectory = directory,
            UseShellExecute = false
        };
        Process.Start(info);
    }

    public static int Apply(string archive, string destination, string parentPid) {
        string stage = null;
        try {
            int pid;
            if (!Int32.TryParse(parentPid, out pid) || pid <= 0) throw new Exception("更新进程参数无效。");
            try { using (var parent = Process.GetProcessById(pid)) if (!parent.WaitForExit(30000)) throw new Exception("请关闭旧版 Mod 启动器后重试。"); }
            catch (ArgumentException) {}
            Validate(archive);
            stage = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "bundle");
            Directory.CreateDirectory(stage);
            using (var zip = ZipFile.OpenRead(archive)) foreach (var entry in zip.Entries) {
                string relative = entry.FullName.TrimEnd('/');
                if (relative.Length == 0) continue;
                string target = Data.SafePath(stage, relative);
                if (entry.FullName.EndsWith("/")) { Directory.CreateDirectory(target); continue; }
                Directory.CreateDirectory(Path.GetDirectoryName(target));
                using (var input = entry.Open()) using (var output = new FileStream(target, FileMode.CreateNew, FileAccess.Write)) input.CopyTo(output);
            }
            Deployment.Install(stage, destination);
            Process.Start(new ProcessStartInfo(Path.Combine(destination, "杯杯倒满Mod加载器.exe")) { WorkingDirectory = destination, UseShellExecute = false });
            return 0;
        } catch (Exception error) {
            try {
                string log = Path.Combine(destination, "FTCModLoader", "Logs", "update-error.log");
                Directory.CreateDirectory(Path.GetDirectoryName(log));
                File.AppendAllText(log, DateTime.Now.ToString("s") + " " + error + Environment.NewLine, Data.Utf8);
            } catch {}
            MessageBox.Show(error.Message + "\r\n\r\n原压缩包已保留，可重新打开启动器重试。", "Mod 更新未完成", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        } finally {
            if (stage != null && Directory.Exists(stage)) try { Directory.Delete(stage, true); } catch {}
        }
    }
}
}
