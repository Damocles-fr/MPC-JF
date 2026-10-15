# PlayBridge Core: setup and settings window, folder assistant, install and uninstall.
# Don't start this file yourself: double-click Install.cmd (or Start menu > PlayBridge Settings).
# https://github.com/Damocles-fr/MPC-JF
param(
    [string]$MapUrl,
    [switch]$Uninstall,
    [switch]$NoGui
)

$ErrorActionPreference = 'Continue'
$SetupDir = $PSScriptRoot
$InstallDir = Join-Path ([string]$env:LOCALAPPDATA) 'PlayBridge'
$OldTestDir = Join-Path ([string]$env:LOCALAPPDATA) 'MPC-JF'        # MPC-JF 12.2 test builds
$OldHiddenDir = Join-Path ([string]$env:LOCALAPPDATA) 'MPCJF'       # Install-MPCJF-HiddenProtocol.ps1 (MPC-JF 12.1 and older)
$OldManualDir = Join-Path ([string]$env:ProgramData) 'MPC-JF'       # manual installation (MPC-JF 12.1 and older)
$ProtocolSubKey = 'Software\Classes\playbridge'
$LegacyProtocolSubKey = 'Software\Classes\MPCJF'                     # links of older browser scripts keep working
$RepoUrl = 'https://github.com/Damocles-fr/MPC-JF'
$ReadmeUrl = $RepoUrl + '#readme'
$RawUrl = 'https://raw.githubusercontent.com/Damocles-fr/MPC-JF/refs/heads/main/'
$InjectorUrl = 'https://github.com/n00bcodr/Jellyfin-JavaScript-Injector'
$VMStore = @{
    chromium = 'https://chrome.google.com/webstore/detail/violent-monkey/jinjaccalgkegednnccohejagnlnfdag'
    edge     = 'https://microsoftedge.microsoft.com/addons/detail/eeagobfjdenkkddmbclomhiblgggliao'
    firefox  = 'https://addons.mozilla.org/firefox/addon/violentmonkey/'
    other    = 'https://violentmonkey.github.io/get-it/'
}
$DefaultJellyfin = 'http://localhost:8096'
$ScriptFiles = @{ A = 'PlayBridge.user.js'; B = 'PlayBridgeIcon.user.js' }
$ArrowChar = [string][char]0x2192

# Shared logic: the same file your browser starts
. (Join-Path $SetupDir 'PlayBridge.ps1') -LoadOnly

# ---------------------------------------------------------------------------
# Video players
# ---------------------------------------------------------------------------

# Fs = fullscreen option. Http = opens http links (stream and download modes): yes / untested.
$PlayBridge_PlayerTable = @(
    @{ Name = 'MPC-BE'; Exe = @('mpc-be64.exe', 'mpc-be.exe'); Fs = '/fullscreen'; Http = 'yes'; Dirs = @('MPC-BE', 'MPC-BE x64'); Match = 'MPC-BE' },
    @{ Name = 'MPC-HC'; Exe = @('mpc-hc64.exe', 'mpc-hc.exe'); Fs = '/fullscreen'; Http = 'yes'; Dirs = @('MPC-HC', 'MPC-HC x64', 'K-Lite Codec Pack\MPC-HC64', 'K-Lite Codec Pack\MPC-HC'); Match = 'MPC-HC|Media Player Classic - Home' },
    @{ Name = 'PotPlayer'; Exe = @('PotPlayerMini64.exe', 'PotPlayerMini.exe'); Fs = $null; Http = 'yes'; Dirs = @('DAUM\PotPlayer', 'PotPlayer', 'Kakao\PotPlayer'); Match = 'PotPlayer' },
    @{ Name = 'VLC'; Exe = @('vlc.exe'); Fs = '--fullscreen'; Http = 'yes'; Dirs = @('VideoLAN\VLC'); Match = '^VLC\b' },
    @{ Name = 'mpv.net'; Exe = @('mpvnet.exe'); Fs = '--fs'; Http = 'yes'; Dirs = @('mpv.net'); Match = 'mpv\.net' },
    @{ Name = 'mpv'; Exe = @('mpv.exe'); Fs = '--fs'; Http = 'yes'; Dirs = @('mpv'); Match = '^mpv\b(?!\.net)' },
    @{ Name = 'SMPlayer'; Exe = @('smplayer.exe'); Fs = '-fullscreen'; Http = 'yes'; Dirs = @('SMPlayer'); Match = 'SMPlayer' },
    @{ Name = 'MPC-QT'; Exe = @('mpc-qt.exe'); Fs = $null; Http = 'untested'; Dirs = @('mpc-qt', 'Media Player Classic Qute Theater'); Match = 'mpc-qt|Qute Theater' },
    @{ Name = 'KMPlayer'; Exe = @('KMPlayer64.exe', 'KMPlayer.exe'); Fs = $null; Http = 'untested'; Dirs = @('KMPlayer 64X', 'The KMPlayer', 'KMPlayer'); Match = 'KMPlayer' },
    @{ Name = 'GOM Player'; Exe = @('GOM64.exe', 'GOM.exe'); Fs = $null; Http = 'untested'; Dirs = @('GRETECH\GomPlayer', 'GOM\GOMPlayer', 'GOMPlayer'); Match = 'GOM Player' }
)
# launchers that only start another exe: never shown
$PlayBridge_LauncherExes = @('potplayer64.exe', 'potplayer.exe')

function Get-PlayBridgePlayerInfo([string]$Exe) {
    $file = (([string]$Exe).Trim().Trim('"') -split '[\\/]')[-1]
    if (-not $file) { return @{ Name = ''; Fullscreen = $null; Note = ''; Known = $false; Http = 'unknown' } }
    foreach ($p in $PlayBridge_PlayerTable) {
        if ($p.Exe -contains $file) {
            $note = ''
            if (-not $p.Fs) {
                if ($p.Name -eq 'PotPlayer') { $note = 'PotPlayer: set fullscreen in PotPlayer > Preferences > General > Startup > Window size.' }
                else { $note = $p.Name + ": set fullscreen in the player's own settings." }
            }
            return @{ Name = $p.Name; Fullscreen = $p.Fs; Note = $note; Known = $true; Http = $p.Http }
        }
    }
    return @{ Name = [System.IO.Path]::GetFileNameWithoutExtension($file); Fullscreen = $null; Note = 'Other player: type its fullscreen option below, if it has one.'; Known = $false; Http = 'unknown' }
}

function Get-PlayBridgeExeFromCommand([string]$Command) {
    $c = [Environment]::ExpandEnvironmentVariables([string]$Command).Trim()
    if ($c -match '^"([^"]+\.exe)"') { return $Matches[1] }
    if ($c -match '^(.+?\.exe)(\s|$)') { return $Matches[1] }
    return ''
}

# The program Windows opens .mkv files with (Explorer's "Open with" choice)
function Get-PlayBridgeDefaultVideoPlayer {
    foreach ($ext in '.mkv', '.mp4') {
        try {
            $prog = [string][Microsoft.Win32.Registry]::GetValue("HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$ext\UserChoice", 'ProgId', $null)
            if (-not $prog) { $prog = [string][Microsoft.Win32.Registry]::GetValue("HKEY_CLASSES_ROOT\$ext", '', $null) }
            if (-not $prog -or $prog -match '^AppX') { continue }
            $cmd = [string][Microsoft.Win32.Registry]::GetValue("HKEY_CLASSES_ROOT\$prog\shell\open\command", '', $null)
            $exe = Get-PlayBridgeExeFromCommand $cmd
            if ($exe -and (Test-Path -LiteralPath $exe -PathType Leaf)) { return $exe }
        } catch { }
    }
    return ''
}

# Installed players: usual folders, uninstall entries, App Paths, Scoop, PATH. Registry and folders only (fast).
function Find-PlayBridgePlayers {
    $paths = New-Object System.Collections.Generic.List[string]
    $roots = @($env:ProgramW6432, $env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ } | Select-Object -Unique
    if ($env:LOCALAPPDATA) { $roots = @($roots) + (Join-Path $env:LOCALAPPDATA 'Programs') }
    foreach ($r in @($roots)) { foreach ($p in $PlayBridge_PlayerTable) { foreach ($d in $p.Dirs) { foreach ($e in $p.Exe) { $paths.Add(('{0}\{1}\{2}' -f $r.TrimEnd('\'), $d, $e)) } } } }
    if ($env:USERPROFILE) {
        foreach ($app in 'mpc-be', 'mpc-hc', 'potplayer', 'vlc', 'mpv', 'mpv.net', 'smplayer', 'mpc-qt') {
            foreach ($p in $PlayBridge_PlayerTable) { foreach ($e in $p.Exe) { $paths.Add(('{0}\scoop\apps\{1}\current\{2}' -f $env:USERPROFILE, $app, $e)) } }
        }
    }
    # uninstall entries: finds players installed in other folders
    foreach ($hive in [Microsoft.Win32.Registry]::LocalMachine, [Microsoft.Win32.Registry]::CurrentUser) {
        foreach ($sub in 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall') {
            try {
                $k = $hive.OpenSubKey($sub)
                if (-not $k) { continue }
                foreach ($n in $k.GetSubKeyNames()) {
                    $e = $k.OpenSubKey($n)
                    if (-not $e) { continue }
                    $dn = [string]$e.GetValue('DisplayName')
                    if ($dn) {
                        foreach ($p in $PlayBridge_PlayerTable) {
                            if ($dn -notmatch $p.Match) { continue }
                            $icon = (([string]$e.GetValue('DisplayIcon')) -replace ',\s*-?\d+\s*$', '').Trim().Trim('"')
                            if ($icon -match '\.exe$') { $paths.Add($icon) }
                            $loc = ([string]$e.GetValue('InstallLocation')).Trim().Trim('"')
                            if ($loc) { foreach ($x in $p.Exe) { $paths.Add($loc.TrimEnd('\') + '\' + $x) } }
                        }
                    }
                    $e.Close()
                }
                $k.Close()
            } catch { }
        }
    }
    foreach ($hint in @(
            @('HKEY_CURRENT_USER\Software\MPC-BE', 'ExePath'),
            @('HKEY_CURRENT_USER\Software\MPC-HC\MPC-HC', 'ExePath'),
            @('HKEY_CURRENT_USER\Software\DAUM\PotPlayer64', 'ProgramPath'),
            @('HKEY_CURRENT_USER\Software\DAUM\PotPlayer', 'ProgramPath'),
            @('HKEY_LOCAL_MACHINE\SOFTWARE\VideoLAN\VLC', ''),
            @('HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\VideoLAN\VLC', ''))) {
        try { $v = [Microsoft.Win32.Registry]::GetValue($hint[0], $hint[1], $null); if ($v) { $paths.Add(([string]$v).Trim('"')) } } catch { }
    }
    foreach ($p in $PlayBridge_PlayerTable) {
        foreach ($exe in $p.Exe) {
            foreach ($hive in 'HKEY_LOCAL_MACHINE', 'HKEY_CURRENT_USER') {
                try {
                    $v = [Microsoft.Win32.Registry]::GetValue("$hive\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$exe", '', $null)
                    if ($v) { $paths.Add(([string]$v).Trim('"')) }
                } catch { }
            }
            $cmd = Get-Command $exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($cmd) { $paths.Add([string]$cmd.Path) }
        }
    }
    $default = Get-PlayBridgeDefaultVideoPlayer
    if ($default) { $paths.Add($default) }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $found = New-Object System.Collections.Generic.List[object]
    foreach ($p in $paths) {
        if (-not $p -or $p -notmatch '\.exe$') { continue }
        $full = [Environment]::ExpandEnvironmentVariables($p)
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
        try { $full = (Get-Item -LiteralPath $full).FullName } catch { }
        if (-not $seen.Add($full)) { continue }
        $name = ([System.IO.Path]::GetFileName($full)).ToLowerInvariant()
        if ($PlayBridge_LauncherExes -contains $name) { continue }
        $info = Get-PlayBridgePlayerInfo $full
        $isDefault = $default -and [string]::Equals($full, $default, [System.StringComparison]::OrdinalIgnoreCase)
        if ($info.Known -or $isDefault) { $found.Add(@{ Name = $info.Name; Path = $full; Default = [bool]$isDefault }) }
    }
    # Windows default player first, then the order of the table (MPC-BE first)
    $order = @{}; $i = 0
    foreach ($p in $PlayBridge_PlayerTable) { $order[$p.Name] = $i++ }
    $found | Sort-Object @{ Expression = { -not $_.Default } }, @{ Expression = { if ($order.ContainsKey($_.Name)) { $order[$_.Name] } else { 99 } } }
}

# ---------------------------------------------------------------------------
# Web browsers
# ---------------------------------------------------------------------------

function Get-PlayBridgeBrowserKind([string]$Exe) {
    $n = ((([string]$Exe) -split '[\\/]')[-1]).ToLowerInvariant()
    if ($n -eq 'msedge.exe') { return 'edge' }
    if ($n -match '^(firefox|librewolf|waterfox|floorp|zen|palemoon|mercury)\.exe$') { return 'firefox' }
    if ($n -match '^(chrome|brave|vivaldi|chromium|thorium|opera|launcher|yandex|browser)\.exe$') { return 'chromium' }
    return 'other'
}

# Browsers registered in Windows, the default one first
function Find-PlayBridgeBrowsers {
    $list = New-Object System.Collections.Generic.List[object]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($hive in [Microsoft.Win32.Registry]::CurrentUser, [Microsoft.Win32.Registry]::LocalMachine) {
        foreach ($sub in 'SOFTWARE\Clients\StartMenuInternet', 'SOFTWARE\WOW6432Node\Clients\StartMenuInternet') {
            try {
                $k = $hive.OpenSubKey($sub)
                if (-not $k) { continue }
                foreach ($n in $k.GetSubKeyNames()) {
                    $e = $k.OpenSubKey($n)
                    if (-not $e) { continue }
                    $name = [string]$e.GetValue('')
                    if (-not $name) { $name = $n }
                    $c = $e.OpenSubKey('shell\open\command')
                    $exe = ''
                    if ($c) { $exe = Get-PlayBridgeExeFromCommand ([string]$c.GetValue('')); $c.Close() }
                    $e.Close()
                    if ($exe -and (Test-Path -LiteralPath $exe -PathType Leaf) -and $seen.Add($exe)) {
                        $list.Add(@{ Name = $name; Path = $exe; Kind = (Get-PlayBridgeBrowserKind $exe); Default = $false })
                    }
                }
                $k.Close()
            } catch { }
        }
    }
    $defaultExe = ''
    foreach ($proto in 'https', 'http') {
        try {
            $prog = [string][Microsoft.Win32.Registry]::GetValue("HKEY_CURRENT_USER\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\$proto\UserChoice", 'ProgId', $null)
            if (-not $prog) { continue }
            $cmd = [string][Microsoft.Win32.Registry]::GetValue("HKEY_CLASSES_ROOT\$prog\shell\open\command", '', $null)
            $defaultExe = Get-PlayBridgeExeFromCommand $cmd
            if ($defaultExe) { break }
        } catch { }
    }
    if ($defaultExe -and (Test-Path -LiteralPath $defaultExe -PathType Leaf)) {
        $hit = @($list | Where-Object { [string]::Equals($_.Path, $defaultExe, [System.StringComparison]::OrdinalIgnoreCase) })
        if ($hit.Count) { $hit[0].Default = $true }
        else { $list.Add(@{ Name = [System.IO.Path]::GetFileNameWithoutExtension($defaultExe); Path = $defaultExe; Kind = (Get-PlayBridgeBrowserKind $defaultExe); Default = $true }) }
    }
    $list | Sort-Object @{ Expression = { -not $_.Default } }, @{ Expression = { $_.Name } }
    # Jellyfin Media Player / Jellyfin Desktop: always offered, with its exe when installed
    $exe = ''
    foreach ($base in @($env:LOCALAPPDATA, $env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }) {
        foreach ($rel in 'Programs\Jellyfin Media Player\JellyfinMediaPlayer.exe', 'Jellyfin Media Player\JellyfinMediaPlayer.exe', 'Programs\jellyfin-desktop\Jellyfin Desktop.exe', 'Programs\Jellyfin Desktop\Jellyfin Desktop.exe', 'Programs\jellyfin-desktop\jellyfin-desktop.exe') {
            $c = Join-Path $base $rel
            if (-not $exe -and (Test-Path -LiteralPath $c -PathType Leaf)) { $exe = $c }
        }
    }
    @{ Name = 'Jellyfin Media Player / Jellyfin Desktop app (experimental)'; Path = $exe; Kind = 'desktop'; Default = $false }
}

function Add-PlayBridgeBrowserItem($Browser, [bool]$Select) {
    $ui = $script:UI
    $item = New-Object System.Windows.Controls.ComboBoxItem
    $label = $Browser.Name
    if ($Browser.Default) { $label += '   (default browser)' }
    $item.Content = $label
    $item.Tag = $Browser
    [void]$ui.BrowserCombo.Items.Add($item)
    if ($Select) { $ui.BrowserCombo.SelectedItem = $item }
    return $item
}

# ---------------------------------------------------------------------------
# Browser scripts: copies made for this PC, served to the browser by a tiny local web server
# ---------------------------------------------------------------------------

# "192.168.1.24:8096/web/index.html" => @{ Base = 'http://192.168.1.24:8096'; Match = 'http://192.168.1.24:8096/*' }
function Get-PlayBridgeJellyfinAddress([string]$Text) {
    $t = ([string]$Text).Trim()
    if (-not $t) { $t = $DefaultJellyfin }
    if ($t -notmatch '^[a-z][a-z0-9+.-]*://') { $t = 'http://' + $t }
    try {
        $u = New-Object System.Uri $t
        $path = ($u.AbsolutePath -replace '/web(/.*)?$', '').TrimEnd('/')
        $origin = $u.Scheme + '://' + $u.Authority
        return @{ Base = $origin + $path; Match = $origin + '/*'; Ok = $true }
    } catch {
        return @{ Base = $t.TrimEnd('/'); Match = $t.TrimEnd('/') + '/*'; Ok = $false }
    }
}

function Get-PlayBridgeScriptSource([string]$Name) {
    foreach ($d in $SetupDir, $InstallDir) {
        $f = Join-Path $d $Name
        if ([System.IO.File]::Exists($f)) { return [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8) }
    }
    return $null
}

# Copy of a browser script with your Jellyfin address, the stream setting and, if wanted, no auto-update
function New-PlayBridgeCustomScript([string]$Name, [string]$Match, [bool]$Stream, [bool]$AutoUpdate) {
    $text = Get-PlayBridgeScriptSource $Name
    if (-not $text) { return $null }
    $defaultMatch = '// @match        http://localhost:8096/*'
    $isDefault = [string]::Equals($Match, 'http://localhost:8096/*', [System.StringComparison]::OrdinalIgnoreCase)
    if ($Match -and -not $isDefault) {
        $text = $text.Replace($defaultMatch, $defaultMatch + "`n// @match        " + $Match)
    }
    if (-not $AutoUpdate) {
        $text = [regex]::Replace($text, '(?m)^// @(updateURL|downloadURL)[^\r\n]*\r?\n', '')
        $text = $text.Replace('// ==/UserScript==', "// ==/UserScript==`n// No auto-update: this copy was prepared for this PC by PlayBridge Setup. After a PlayBridge update, install it again from PlayBridge Settings.")
    }
    if ($Stream) { $text = $text.Replace('const STREAM_LINKS = false;', 'const STREAM_LINKS = true;') }
    return $text
}

function Get-PlayBridgeInjectorScript([bool]$Stream) {
    $text = Get-PlayBridgeScriptSource 'PlayBridge-JSinjector-deviceID.js'
    if ($text -and $Stream) { $text = $text.Replace('const STREAM_LINKS = false;', 'const STREAM_LINKS = true;') }
    return $text
}

# Tiny web server on 127.0.0.1 (random port): the browser opens http://127.0.0.1:PORT/PlayBridge.user.js and
# Violentmonkey shows its install page. Plain sockets: no admin rights, nothing to configure.
$LocalServerScript = @'
param($files, $state)
$listener = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Loopback, 0)
$listener.Start()
$state.Port = $listener.LocalEndpoint.Port
while (-not $state.Stop) {
    if (-not $listener.Pending()) { Start-Sleep -Milliseconds 50; continue }
    $client = $null
    try {
        $client = $listener.AcceptTcpClient()
        $client.ReceiveTimeout = 3000
        $stream = $client.GetStream()
        $buf = New-Object byte[] 8192
        $n = $stream.Read($buf, 0, $buf.Length)
        $req = [System.Text.Encoding]::ASCII.GetString($buf, 0, [Math]::Max($n, 0))
        $name = ''
        $m = [regex]::Match($req, '^GET\s+/([^\s?]*)')
        if ($m.Success) { $name = [System.Uri]::UnescapeDataString($m.Groups[1].Value) }
        if ($name -and $files.ContainsKey($name)) {
            $body = [System.Text.Encoding]::UTF8.GetBytes([string]$files[$name])
            $type = 'text/javascript'
            if ($name -match '\.html?$') { $type = 'text/html' }
            $head = "HTTP/1.1 200 OK`r`nContent-Type: $type; charset=utf-8`r`nContent-Length: $($body.Length)`r`nCache-Control: no-store`r`nConnection: close`r`n`r`n"
        } else {
            $body = [System.Text.Encoding]::UTF8.GetBytes('PlayBridge Setup: not found')
            $head = "HTTP/1.1 404 Not Found`r`nContent-Type: text/plain`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
        }
        $hb = [System.Text.Encoding]::ASCII.GetBytes($head)
        $stream.Write($hb, 0, $hb.Length)
        $stream.Write($body, 0, $body.Length)
        $stream.Flush()
        $state.Served++
    } catch { }
    finally { if ($client) { try { $client.Close() } catch { } } }
}
try { $listener.Stop() } catch { }
'@

$script:LocalServer = $null
function Start-PlayBridgeLocalServer {
    if ($script:LocalServer) { return $script:LocalServer }
    $files = [hashtable]::Synchronized(@{})
    $state = [hashtable]::Synchronized(@{ Stop = $false; Port = 0; Served = 0 })
    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.Open()
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($LocalServerScript).AddArgument($files).AddArgument($state)
    $async = $ps.BeginInvoke()
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    while ($state.Port -eq 0 -and $clock.ElapsedMilliseconds -lt 3000 -and -not $async.IsCompleted) { Start-Sleep -Milliseconds 20 }
    if ($state.Port -eq 0) { try { $ps.Dispose(); $rs.Dispose() } catch { }; return $null }
    $script:LocalServer = @{ Files = $files; State = $state; PS = $ps; Async = $async; Port = $state.Port }
    return $script:LocalServer
}

function Stop-PlayBridgeLocalServer {
    $s = $script:LocalServer
    if (-not $s) { return }
    $s.State.Stop = $true
    try { [void]$s.PS.BeginStop($null, $null) } catch { }
    $script:LocalServer = $null
}

# ---------------------------------------------------------------------------
# NAS and network shares (setup only)
# ---------------------------------------------------------------------------

# Shares opened before in File Explorer, and their servers. Registry only (no network access).
function Get-PlayBridgeHistoryShares {
    try {
        $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Explorer\MountPoints2')
        if (-not $k) { return }
        foreach ($n in $k.GetSubKeyNames()) {
            if ($n -match '^##([^#]+)#([^#]+)$' -and $Matches[2] -notmatch '\$$') { '\\{0}\{1}' -f $Matches[1], $Matches[2] }
        }
        $k.Close()
    } catch { }
}

function Get-PlayBridgeServers($Shares) {
    $seen = @{}
    foreach ($u in @(@(Get-PlayBridgeNetworkDrives | ForEach-Object { $_.Unc }) + @($Shares))) {
        $s = (([string]$u).TrimStart('\').Split('\'))[0]
        if ($s -and $s -notmatch '^(localhost|127\.0\.0\.1|\.)$' -and -not $seen[$s.ToLowerInvariant()]) {
            $seen[$s.ToLowerInvariant()] = $true
            $s
        }
    }
}

# Lists the shares of a server, with a time limit (offline servers can make Windows wait 20 s and more)
$NetSharesCode = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;
namespace PlayBridge {
    public static class NetShares {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct SHARE_INFO_1 { public string netname; public uint type; public string remark; }
        [DllImport("Netapi32.dll", CharSet = CharSet.Unicode)]
        static extern int NetShareEnum(string server, int level, out IntPtr buf, int prefmaxlen, out int read, out int total, ref int resume);
        [DllImport("Netapi32.dll")]
        static extern int NetApiBufferFree(IntPtr buf);
        static string[] List(string server) {
            var names = new List<string>();
            IntPtr buf; int read, total, resume = 0;
            if (NetShareEnum(server, 1, out buf, -1, out read, out total, ref resume) == 0 && buf != IntPtr.Zero) {
                try {
                    int size = Marshal.SizeOf(typeof(SHARE_INFO_1));
                    for (int i = 0; i < read; i++) {
                        var si = (SHARE_INFO_1)Marshal.PtrToStructure(new IntPtr(buf.ToInt64() + (long)i * size), typeof(SHARE_INFO_1));
                        bool disk = (si.type & 0xFFFF) == 0 && (si.type & 0x80000000) == 0;
                        if (disk && !string.IsNullOrEmpty(si.netname) && !si.netname.EndsWith("$")) names.Add(si.netname);
                    }
                } finally { NetApiBufferFree(buf); }
            }
            return names.ToArray();
        }
        public static string[] Get(string server, int timeoutMs) {
            string[] result = null;
            var t = new Thread(() => { try { result = List(server); } catch { } });
            t.IsBackground = true;
            t.Start();
            return t.Join(timeoutMs) ? (result ?? new string[0]) : new string[0];
        }
    }
}
'@

$SharesJobScript = @'
param($code, $servers)
$out = New-Object System.Collections.Generic.List[string]
try {
    foreach ($c in @(Get-CimInstance -ClassName Win32_NetworkConnection -ErrorAction Stop)) {
        $r = ([string]$c.RemoteName).TrimEnd('\')
        if ($r -match '^\\\\[^\\]+\\[^\\]+$') { $out.Add($r) }
    }
} catch { }
try { if (-not ('PlayBridge.NetShares' -as [type])) { Add-Type -TypeDefinition $code -ErrorAction Stop } } catch { }
$seen = @{}
foreach ($s in @(@($servers) + @($out | ForEach-Object { $_.Split('\')[2] }))) {
    if (-not $s -or $seen[$s.ToLowerInvariant()]) { continue }
    $seen[$s.ToLowerInvariant()] = $true
    try { foreach ($n in @([PlayBridge.NetShares]::Get('\\' + $s, 4000))) { $out.Add('\\' + $s + '\' + $n) } } catch { }
}
$out
'@

# Jellyfin servers that answer on port 8096 (this PC and your NAS)
$JellyfinJobScript = @'
param($hosts)
$tasks = @{}
foreach ($h in @($hosts)) {
    $base = 'http://{0}:8096' -f $h
    try { $r = [System.Net.WebRequest]::Create($base + '/System/Info/Public'); $r.Timeout = 2500; $tasks[$base] = $r.GetResponseAsync() } catch { }
}
if ($tasks.Count) { try { [void][System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]@($tasks.Values), 3000) } catch { } }
foreach ($kv in $tasks.GetEnumerator()) {
    if ($kv.Value.Status -ne 'RanToCompletion') { continue }
    try {
        $resp = $kv.Value.Result
        $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $o = $sr.ReadToEnd() | ConvertFrom-Json
        $resp.Close()
        if ($o.Id -or $o.ServerName) { '{0}|{1}|{2}' -f $kv.Key, $o.ServerName, $o.Version }
    } catch { }
}
'@

# ---------------------------------------------------------------------------
# Settings of an older installation (MPC-JF)
# ---------------------------------------------------------------------------

# Reads the player line and the "YOUR NAS CONFIG" lines of an old MPCJF.ps1 (MPC-JF 12.1 and older).
# Simple lines ($path = $path -replace "\\share\\X\\", "D:") become folder links,
# anything else is kept as is in PlayBridge-custom.ps1.
function Read-PlayBridgeLegacyScript([string]$File) {
    if (-not $File -or -not [System.IO.File]::Exists($File)) { return $null }
    $lines = @(Read-PlayBridgeTextFile $File)
    if (($lines -join "`n") -match '(MPCJF|PlayBridge)_Version') { return $null }   # not a hand-edited old script
    $res = @{ Player = ''; Fullscreen = $false; Paths = @(); Custom = @() }
    $paths = New-Object System.Collections.Generic.List[object]
    $custom = New-Object System.Collections.Generic.List[string]
    $inNas = $false
    foreach ($line in $lines) {
        $t = $line.Trim()
        if ($t -match '^&\s*["'']([^"'']+?\.exe)["''](.*)$') {
            $res.Player = $Matches[1]
            $res.Fullscreen = ($Matches[2] -match '(/|--)(fullscreen|fs)\b')
            continue
        }
        if ($t -match 'YOUR NAS CONFIG') { $inNas = $true; continue }
        if (-not $inNas -or $t -eq '' -or $t.StartsWith('#')) { continue }
        if ($t -match '^(echo|Write-Host|Write-Output)\b') { continue }
        if ($t -match '^\$path\s*=\s*\$path\s+-i?replace\s*(["''])(.+?)\1\s*,\s*(["''])(.*?)\3\s*(#.*)?$') {
            $pattern = $Matches[2]
            $to = $Matches[4]
            if (($pattern -replace '\\.', '') -notmatch '[\^\$\*\+\?\(\)\[\]\{\}\|]' -and $to -notmatch '\$' -and $to) {
                try {
                    $from = [regex]::Unescape($pattern)
                    if ($from -notmatch '^(\\|[A-Za-z]:)') { $from = '\' + $from }
                    $paths.Add(@{ From = (Format-PlayBridgePath $from); To = (Format-PlayBridgePath $to) })
                    continue
                } catch { }
            }
        }
        $custom.Add($line)
    }
    $res.Paths = $paths.ToArray()
    $res.Custom = $custom.ToArray()
    return $res
}

function Get-PlayBridgeProtocolCommand([string]$SubKey = $ProtocolSubKey) {
    try {
        $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($SubKey + '\shell\open\command')
        if ($k) { $v = [string]$k.GetValue(''); $k.Close(); return $v }
    } catch { }
    return ''
}

# What the setup shows first: the current settings, else those of an older installation
function Get-PlayBridgeStartSettings {
    $s = New-PlayBridgeConfig
    $s.Custom = @()
    $s.Source = ''
    $ini = Join-Path $InstallDir 'PlayBridge.ini'
    if ([System.IO.File]::Exists($ini)) {
        $c = Read-PlayBridgeConfig $ini
        foreach ($k in @($c.Keys)) { $s[$k] = $c[$k] }
        $s.Source = 'current'
        return $s
    }
    # MPC-JF 12.2 test builds: same settings file
    $testIni = Join-Path $OldTestDir 'MPCJF.ini'
    if ([System.IO.File]::Exists($testIni)) {
        $c = Read-PlayBridgeConfig $testIni
        foreach ($k in @($c.Keys)) { $s[$k] = $c[$k] }
        $customOld = Join-Path $OldTestDir 'MPCJF-custom.ps1'
        if ([System.IO.File]::Exists($customOld)) { $s.Custom = @(Read-PlayBridgeTextFile $customOld | Where-Object { $_ -notmatch '^\s*#' }) }
        $s.Source = $testIni
        return $s
    }
    $cmd = Get-PlayBridgeProtocolCommand $LegacyProtocolSubKey
    $files = @()
    if ($cmd -match 'wscript') { $files += (Join-Path $OldHiddenDir 'MPCJF.ps1') }   # the copy really used by the link
    $files += (Join-Path $OldManualDir 'MPCJF.ps1'), (Join-Path $OldHiddenDir 'MPCJF.ps1')
    foreach ($f in $files) {
        $old = Read-PlayBridgeLegacyScript $f
        if (-not $old) { continue }
        $s.Player = $old.Player
        $info = Get-PlayBridgePlayerInfo $old.Player
        if ($old.Fullscreen -and $info.Fullscreen) { $s.Arguments = $info.Fullscreen }
        elseif ($old.Fullscreen) { $s.Arguments = '/fullscreen' }
        else { $s.Arguments = '' }
        if ($cmd -match 'wscript') { $s.HideWindow = $true }
        $s.Paths = $old.Paths
        $s.Custom = $old.Custom
        $s.Source = $f
        return $s
    }
    # new installation: Jellyfin stream links, nothing else to set up
    $s.Mode = 'stream'
    return $s
}

# ---------------------------------------------------------------------------
# Install / uninstall
# ---------------------------------------------------------------------------

function Test-PlayBridgeSameFolder([string]$A, [string]$B) {
    try {
        $x = [System.IO.Path]::GetFullPath($A).TrimEnd('\')
        $y = [System.IO.Path]::GetFullPath($B).TrimEnd('\')
        return [string]::Equals($x, $y, [System.StringComparison]::OrdinalIgnoreCase)
    } catch { return $false }
}

function Test-PlayBridgeVBScript {
    $sys = Join-Path ([string]$env:SystemRoot) 'System32'
    return ((Test-Path -LiteralPath (Join-Path $sys 'wscript.exe')) -and (Test-Path -LiteralPath (Join-Path $sys 'vbscript.dll')))
}

function Write-PlayBridgeHiddenLauncher([string]$Dir) {
    $vbs = @'
' PlayBridge: starts PlayBridge.ps1 without showing a PowerShell window (created by PlayBridge Setup)
Option Explicit
Dim fso, sh, ps1, arg, cmd
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
ps1 = fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "PlayBridge.ps1")
' the link goes to PlayBridge.ps1 through an environment variable (no quoting or % expansion issues)
arg = ""
If WScript.Arguments.Count > 0 Then arg = WScript.Arguments(0)
sh.Environment("PROCESS")("PLAYBRIDGE_URL") = arg
cmd = """" & sh.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File """ & ps1 & """"
sh.Run cmd, 0, False
'@
    [System.IO.File]::WriteAllText((Join-Path $Dir 'PlayBridge-launch.vbs'), ($vbs -replace "`r?`n", "`r`n"), [System.Text.Encoding]::ASCII)
}

# The playbridge:// link, for this Windows user only (no admin rights). Same job as the old MPCJF.reg.
function Get-PlayBridgeProtocolCommandFor([string]$Dir, [bool]$Hidden) {
    $sys = ([string]$env:SystemRoot).TrimEnd('\') + '\System32\'
    $Dir = $Dir.TrimEnd('\')
    if ($Hidden) { return '"{0}wscript.exe" "{1}\PlayBridge-launch.vbs" "%1"' -f $sys, $Dir }
    return '"{0}WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "{1}\PlayBridge.ps1" "%1"' -f $sys, $Dir
}

function Register-PlayBridgeProtocol([string]$Dir, [bool]$Hidden) {
    $cmd = Get-PlayBridgeProtocolCommandFor $Dir $Hidden
    # playbridge:// for the new scripts, mpcjf:// for scripts installed before the rename
    foreach ($sub in $ProtocolSubKey, $LegacyProtocolSubKey) {
        $k = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($sub)
        $k.SetValue('', 'URL:PlayBridge Protocol')
        $k.SetValue('URL Protocol', '')
        $k.Close()
        $c = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($sub + '\shell\open\command')
        $c.SetValue('', $cmd)
        $c.Close()
    }
}

function Get-PlayBridgeShortcutFile([string]$Name = 'PlayBridge Settings.lnk') {
    $programs = [Environment]::GetFolderPath('Programs')
    if (-not $programs) { return $null }
    return (Join-Path $programs $Name)
}

function New-PlayBridgeShortcut {
    try {
        $file = Get-PlayBridgeShortcutFile
        if (-not $file) { return }
        $sh = New-Object -ComObject WScript.Shell
        $s = $sh.CreateShortcut($file)
        $s.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $s.Arguments = '-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "{0}"' -f (Join-Path $InstallDir 'PlayBridge-Core.ps1')
        $s.WorkingDirectory = $env:USERPROFILE   # not the PlayBridge folder, so that it can be deleted
        $s.Description = 'PlayBridge: video player, NAS folders, browser steps, uninstall'
        $ico = Join-Path $InstallDir 'PlayBridge.ico'
        if (Test-Path -LiteralPath $ico) { $s.IconLocation = "$ico,0" }
        $s.Save()
    } catch { }
}

# Older installations replaced by this one (MPC-JF 12.2 test builds, Install-MPCJF-HiddenProtocol.ps1)
function Remove-PlayBridgeOldInstalls {
    try {
        $old = Get-PlayBridgeShortcutFile 'MPC-JF Settings.lnk'
        if ($old) { Remove-Item -LiteralPath $old -Force -ErrorAction SilentlyContinue }
        if ((Test-Path -LiteralPath $OldTestDir) -and (Test-Path -LiteralPath (Join-Path $OldTestDir 'MPCJF.ini'))) {
            Remove-Item -LiteralPath $OldTestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $OldHiddenDir) {
            $oldPs1 = Join-Path $OldHiddenDir 'MPCJF.ps1'
            $backup = Join-Path $InstallDir 'MPCJF.ps1.old'
            if ((Test-Path -LiteralPath $oldPs1) -and (Test-Path -LiteralPath $InstallDir) -and -not (Test-Path -LiteralPath $backup)) { Copy-Item -LiteralPath $oldPs1 -Destination $backup }
            foreach ($n in 'MPCJF.ps1', 'MPCJF-launch.vbs') { Remove-Item -LiteralPath (Join-Path $OldHiddenDir $n) -Force -ErrorAction SilentlyContinue }
            if (-not @(Get-ChildItem -LiteralPath $OldHiddenDir -Force -ErrorAction SilentlyContinue).Count) { Remove-Item -LiteralPath $OldHiddenDir -Force -ErrorAction SilentlyContinue }
        }
    } catch { }
}

function Install-PlayBridge($Settings) {
    if (-not (Test-Path -LiteralPath $InstallDir)) { New-Item -ItemType Directory -Path $InstallDir -Force -ErrorAction Stop | Out-Null }
    if (-not (Test-PlayBridgeSameFolder $SetupDir $InstallDir)) {
        $skip = '^(PlayBridge\.ini|PlayBridge\.log|PlayBridge-custom\.ps1|PlayBridge-launch\.vbs|(?!README\.md$).*\.md|MPCJF.*|Install-MPCJF.*|\..*|.*\.old|.*\.zip)$'
        foreach ($f in @(Get-ChildItem -LiteralPath $SetupDir -File -ErrorAction Stop)) {
            if ($f.Name -match $skip) { continue }
            Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $InstallDir $f.Name) -Force -ErrorAction Stop
        }
    }
    Write-PlayBridgeConfig (Join-Path $InstallDir 'PlayBridge.ini') $Settings
    $customFile = Join-Path $InstallDir 'PlayBridge-custom.ps1'
    if (@($Settings.Custom).Count -and -not (Test-Path -LiteralPath $customFile)) {
        $content = @('# Your own lines, imported from an older installation ("YOUR NAS CONFIG" section).',
            '# PlayBridge runs them on $path before looking for the video. This file is kept when PlayBridge is updated.') + @($Settings.Custom)
        [System.IO.File]::WriteAllLines($customFile, [string[]]$content, (New-Object System.Text.UTF8Encoding $true))
    }
    if ($Settings.HideWindow) { Write-PlayBridgeHiddenLauncher $InstallDir }
    else { Remove-Item -LiteralPath (Join-Path $InstallDir 'PlayBridge-launch.vbs') -Force -ErrorAction SilentlyContinue }
    Register-PlayBridgeProtocol $InstallDir ([bool]$Settings.HideWindow)
    try { Get-ChildItem -LiteralPath $InstallDir -File | Unblock-File -ErrorAction SilentlyContinue } catch { }
    New-PlayBridgeShortcut
    Remove-PlayBridgeOldInstalls
}

function Test-PlayBridgeMachineProtocol {
    try { $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE\Classes\MPCJF'); if ($k) { $k.Close(); return $true } } catch { }
    return $false
}

function Uninstall-PlayBridge {
    foreach ($sub in $ProtocolSubKey, $LegacyProtocolSubKey) { try { [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($sub, $false) } catch { } }
    foreach ($n in 'PlayBridge Settings.lnk', 'MPC-JF Settings.lnk') {
        $lnk = Get-PlayBridgeShortcutFile $n
        if ($lnk) { Remove-Item -LiteralPath $lnk -Force -ErrorAction SilentlyContinue }
    }
    Remove-PlayBridgeOldInstalls
    if (Test-Path -LiteralPath $InstallDir) { Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction SilentlyContinue }
}

# ---------------------------------------------------------------------------
# Finding videos (setup side: deeper than at play time)
# ---------------------------------------------------------------------------

function Get-PlayBridgeCandidates([string]$Path, $Rules, $Shares) {
    $kind = Get-PlayBridgePathKind $Path
    foreach ($c in @(Get-PlayBridgeRuleMatches $Path $Rules)) { @{ Path = $c; How = 'through your folder link' } }
    if ($kind -eq 'drive' -or $kind -eq 'unc') { @{ Path = $Path; How = 'same path as Jellyfin' } }
    if ($kind -ne 'other') {
        foreach ($c in @(Get-PlayBridgeShareMatches $Path @(Get-PlayBridgeShareRoots $Shares))) { @{ Path = $c; How = 'found automatically by its share name' } }
    }
}

function Get-PlayBridgeSearchRoots($Shares) {
    $roots = New-Object System.Collections.Generic.List[string]
    try {
        foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
            $t = [string]$d.DriveType
            if ($t -eq 'Fixed' -or $t -eq 'Removable' -or $t -eq 'Network' -or $t -eq 'Ram') { $roots.Add($d.Name) }
        }
    } catch { }
    foreach ($n in @(Get-PlayBridgeShareRoots $Shares)) { if (-not $roots.Contains($n.Root)) { $roots.Add($n.Root) } }
    return $roots.ToArray()
}

# Quick checks first (links, Jellyfin path, share names), then every drive and share, two folder levels deep.
# $OnStatus: shows a message ($null = just keep the window alive). $IsCancelled: returns $true to stop.
function Find-PlayBridgeVideo([string]$Path, $Rules, $Shares, [scriptblock]$OnStatus, [scriptblock]$IsCancelled) {
    $res = @{ Found = $null; How = ''; Maybe = $null; Deep = @() }
    $p = Format-PlayBridgePath $Path
    & $OnStatus 'Checking...'
    foreach ($c in @(Get-PlayBridgeCandidates $p $Rules $Shares)) {
        $r = Test-PlayBridgePath $c.Path 20000 { & $OnStatus $null; & $IsCancelled }
        if ($r -eq $true) { $res.Found = $c.Path; $res.How = $c.How; return $res }
        if ($null -eq $r -and -not $res.Maybe) { $res.Maybe = $c }
        if (& $IsCancelled) { return $res }
    }
    $searchRoots = @(Get-PlayBridgeSearchRoots $Shares)
    $searchClock = [System.Diagnostics.Stopwatch]::StartNew()
    $res.Deep = @(Find-PlayBridgeOnDrives $p $searchRoots 90000 {
            & $OnStatus ('Searching {0} drives and shares... {1} s  (sleeping NAS disks can take a minute to wake up)' -f $searchRoots.Count, [int]$searchClock.Elapsed.TotalSeconds)
            & $IsCancelled
        })
    return $res
}

# ---------------------------------------------------------------------------
# Background jobs (window stays responsive)
# ---------------------------------------------------------------------------

$script:Jobs = New-Object System.Collections.ArrayList
$script:JobTimer = $null

function Start-PlayBridgeJob([string]$Script, [object[]]$Arguments, [scriptblock]$Done, [int]$TimeoutMs = 15000) {
    try {
        $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
        $rs.Open()
        $ps = [System.Management.Automation.PowerShell]::Create()
        $ps.Runspace = $rs
        [void]$ps.AddScript($Script)
        foreach ($a in $Arguments) { [void]$ps.AddArgument($a) }
        [void]$script:Jobs.Add(@{ PS = $ps; Async = $ps.BeginInvoke(); Done = $Done; Clock = [System.Diagnostics.Stopwatch]::StartNew(); Timeout = $TimeoutMs })
        if ($script:JobTimer -and -not $script:JobTimer.IsEnabled) { $script:JobTimer.Start() }
    } catch {
        & $Done @()
    }
}

function Update-PlayBridgeJobs {
    foreach ($j in @($script:Jobs)) {
        $result = $null
        if ($j.Async.IsCompleted) {
            try { $result = @($j.PS.EndInvoke($j.Async)) } catch { $result = @() }
            try { $j.PS.Runspace.Dispose(); $j.PS.Dispose() } catch { }
        } elseif ($j.Clock.ElapsedMilliseconds -gt $j.Timeout) {
            $result = @()
            try { [void]$j.PS.BeginStop($null, $null) } catch { }
        } else { continue }
        $script:Jobs.Remove($j)
        try { & $j.Done $result } catch { }
    }
    if ($script:Jobs.Count -eq 0 -and $script:JobTimer) { $script:JobTimer.Stop() }
}

# ---------------------------------------------------------------------------
# Windows (WPF). Only plain ASCII in this file: special characters are XML entities.
# ---------------------------------------------------------------------------

$StylesXaml = @'
    <SolidColorBrush x:Key="Accent" Color="#E89B00"/>
    <SolidColorBrush x:Key="Muted" Color="#5F6368"/>
    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="White"/>
      <Setter Property="BorderBrush" Value="#DADCE0"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="8"/>
      <Setter Property="Padding" Value="16,12,16,14"/>
      <Setter Property="Margin" Value="0,0,0,10"/>
    </Style>
    <Style x:Key="Option" TargetType="Border">
      <Setter Property="Background" Value="#F8FAFB"/>
      <Setter Property="BorderBrush" Value="#C9D3DA"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="6"/>
      <Setter Property="Padding" Value="12,10"/>
    </Style>
    <Style x:Key="H2" TargetType="TextBlock">
      <Setter Property="FontSize" Value="15"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
    </Style>
    <Style x:Key="Hint" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#5F6368"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
    </Style>
    <Style x:Key="Num" TargetType="Border">
      <Setter Property="Width" Value="26"/>
      <Setter Property="Height" Value="26"/>
      <Setter Property="CornerRadius" Value="13"/>
      <Setter Property="Background" Value="#1E293B"/>
      <Setter Property="Margin" Value="0,0,10,0"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
    <Style x:Key="NumText" TargetType="TextBlock">
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="HorizontalAlignment" Value="Center"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
    <Style x:Key="Required" TargetType="Border">
      <Setter Property="Background" Value="#FCE8E6"/>
      <Setter Property="CornerRadius" Value="9"/>
      <Setter Property="Padding" Value="8,1"/>
      <Setter Property="Margin" Value="10,0,0,0"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
    <Style x:Key="Auto" TargetType="Border" BasedOn="{StaticResource Required}">
      <Setter Property="Background" Value="#E6F4EA"/>
    </Style>
    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Background" Value="White"/>
      <Setter Property="Foreground" Value="#202124"/>
      <Setter Property="BorderBrush" Value="#BDC1C6"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="14,6"/>
      <Setter Property="MinHeight" Value="32"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="5" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.85"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.7"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="Bd" Property="Opacity" Value="0.45"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="#1E293B"/>
      <Setter Property="BorderBrush" Value="#0F172A"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
    <Style x:Key="Action" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="#FFAA00"/>
      <Setter Property="BorderBrush" Value="#E89B00"/>
      <Setter Property="Foreground" Value="#1E293B"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
    <Style TargetType="Button" BasedOn="{StaticResource Btn}"/>
    <Style TargetType="TextBox">
      <Setter Property="Padding" Value="4,3"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
      <Setter Property="MinHeight" Value="30"/>
    </Style>
    <Style TargetType="ComboBox">
      <Setter Property="MinHeight" Value="30"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
      <Setter Property="Padding" Value="6,3"/>
    </Style>
'@

$MainXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PlayBridge Setup" Width="820" Height="860" MinWidth="680" MinHeight="480"
        WindowStartupLocation="CenterScreen" FontFamily="Segoe UI" FontSize="13" Background="#F1F3F4">
  <Window.Resources>
__STYLES__
  </Window.Resources>
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <Border Grid.Row="0" Background="White" BorderBrush="#DADCE0" BorderThickness="0,0,0,1" Padding="20,12">
      <DockPanel>
        <Image x:Name="Logo" Width="46" Height="46" Margin="0,0,14,0" DockPanel.Dock="Left"/>
        <TextBlock x:Name="VersionText" DockPanel.Dock="Right" Style="{StaticResource Hint}" VerticalAlignment="Top"/>
        <StackPanel VerticalAlignment="Center">
          <TextBlock Text="PlayBridge Setup" FontSize="21" FontWeight="SemiBold"/>
          <TextBlock x:Name="HeaderSub" Style="{StaticResource Hint}" FontSize="13" Text="External player launcher for Jellyfin (Windows)"/>
        </StackPanel>
      </DockPanel>
    </Border>

    <!-- ============================== PAGE 1: settings ============================== -->
    <ScrollViewer x:Name="Page1" Grid.Row="1" VerticalScrollBarVisibility="Auto">
      <StackPanel Margin="20,14,20,6">

        <Border Style="{StaticResource Card}">
          <StackPanel>
            <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
              <Border Style="{StaticResource Num}"><TextBlock Style="{StaticResource NumText}" Text="1"/></Border>
              <TextBlock Style="{StaticResource H2}" Text="Video player"/>
            </StackPanel>
            <DockPanel>
              <Button x:Name="BrowsePlayer" Content="Browse..." DockPanel.Dock="Right" Margin="8,0,0,0"/>
              <ComboBox x:Name="PlayerCombo"/>
            </DockPanel>
            <TextBox x:Name="PlayerPath" Margin="0,6,0,0" FontSize="12" Foreground="#3C4043"
                     ToolTip="Path of the player .exe. Choose 'Other player' or Browse... for any other player."/>
            <TextBlock Style="{StaticResource Hint}" Margin="0,6,0,0"
                       Text="Detected automatically: MPC-BE, MPC-HC, PotPlayer, VLC, mpv, mpv.net, SMPlayer, MPC-QT, KMPlayer, GOM Player. Any other player: Browse..."/>
            <TextBlock x:Name="PlayerWarn" TextWrapping="Wrap" Foreground="#C5221F" Visibility="Collapsed" Margin="0,6,0,0"/>
            <DockPanel Margin="0,10,0,0">
              <CheckBox x:Name="Fullscreen" Content="Fullscreen" VerticalAlignment="Center" Margin="0,0,18,0"/>
              <TextBlock Text="Options" VerticalAlignment="Center" Margin="0,0,8,0" Foreground="#5F6368"/>
              <TextBox x:Name="PlayerArgs" FontFamily="Consolas"
                       ToolTip="Command-line options of the player. Put %1 where the video must go, if the player needs it."/>
            </DockPanel>
            <TextBlock x:Name="FullscreenNote" Style="{StaticResource Hint}" Foreground="#9A5B00" Visibility="Collapsed" Margin="0,6,0,0"/>
          </StackPanel>
        </Border>

        <Border Style="{StaticResource Card}">
          <StackPanel>
            <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
              <Border Style="{StaticResource Num}"><TextBlock Style="{StaticResource NumText}" Text="2"/></Border>
              <TextBlock Style="{StaticResource H2}" Text="How videos open"/>
            </StackPanel>
            <ComboBox x:Name="ModeCombo"/>
            <TextBlock x:Name="ModeHint" Style="{StaticResource Hint}" Margin="0,6,0,0"/>
            <TextBlock x:Name="ModeWarn" TextWrapping="Wrap" Foreground="#9A5B00" Visibility="Collapsed" Margin="0,6,0,0"/>
          </StackPanel>
        </Border>

        <Border x:Name="NasCard" Style="{StaticResource Card}">
          <StackPanel>
            <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
              <Border Style="{StaticResource Num}"><TextBlock Style="{StaticResource NumText}" Text="3"/></Border>
              <TextBlock Style="{StaticResource H2}" Text="NAS and network folders"/>
              <Border Style="{StaticResource Auto}"><TextBlock Text="Automatic" Foreground="#137333" FontSize="11.5" FontWeight="SemiBold"/></Border>
            </StackPanel>
            <TextBlock Style="{StaticResource Hint}" Text="Nothing to do in most cases: your network drives and shares are used automatically."/>
            <WrapPanel x:Name="DrivesPanel" Margin="0,8,0,0"/>
            <TextBlock x:Name="SharesText" Style="{StaticResource Hint}" Margin="0,2,0,0"/>
            <TextBlock Text="A video doesn't open? Paste its path from Jellyfin (Media info) and check it:" Margin="0,12,0,4" TextWrapping="Wrap"/>
            <DockPanel>
              <Button x:Name="CheckBtn" Content="Check" DockPanel.Dock="Right" Width="90" Margin="8,0,0,0"/>
              <TextBox x:Name="TestPath" FontFamily="Consolas" ToolTip="Example: /share/CACHEDEV1_DATA/Movies/Film (2020)/Film.mkv"/>
            </DockPanel>
            <TextBlock x:Name="TestResult" TextWrapping="Wrap" Margin="0,8,0,0" Visibility="Collapsed"/>
            <ListBox x:Name="TestMatches" MaxHeight="90" Margin="0,6,0,0" Visibility="Collapsed"/>
            <WrapPanel x:Name="TestActions" Margin="0,6,0,0" Visibility="Collapsed">
              <Button x:Name="SaveLinkBtn" Content="Save this folder link" Style="{StaticResource Action}" Margin="0,0,8,6"/>
              <Button x:Name="PickFileBtn" Content="Pick the file myself..." Margin="0,0,8,6"/>
              <Button x:Name="PickFolderBtn" Content="Pick the folder..." Margin="0,0,8,6"/>
            </WrapPanel>
            <StackPanel x:Name="LinksPanel" Margin="0,10,0,0" Visibility="Collapsed">
              <TextBlock Style="{StaticResource Hint}" Text="Folder links (Jellyfin folder &#x2192; Windows folder):"/>
              <DockPanel Margin="0,4,0,0">
                <Button x:Name="RemoveMap" Content="Remove" DockPanel.Dock="Right" VerticalAlignment="Top" Margin="8,0,0,0"/>
                <ListBox x:Name="MapList" MaxHeight="110" FontFamily="Consolas"/>
              </DockPanel>
            </StackPanel>
          </StackPanel>
        </Border>

        <Border Style="{StaticResource Card}">
          <StackPanel>
            <CheckBox x:Name="HideWindow" Content="Hide the PowerShell window when a video starts (recommended)"/>
            <TextBlock x:Name="HideNote" Style="{StaticResource Hint}" Foreground="#9A5B00" Visibility="Collapsed" Margin="20,4,0,0"/>
          </StackPanel>
        </Border>

        <TextBlock x:Name="InstallInfo" Style="{StaticResource Hint}" Margin="4,0,4,8"/>
      </StackPanel>
    </ScrollViewer>

    <!-- ============================== PAGE 2: browser steps ============================== -->
    <ScrollViewer x:Name="Page2" Grid.Row="1" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
      <StackPanel Margin="20,14,20,6">

        <Border Style="{StaticResource Card}" BorderBrush="#A8DAB5" Background="#F3FAF5">
          <StackPanel>
            <TextBlock x:Name="StatusTitle" Text="&#x2714;  PlayBridge is installed on this PC" FontSize="18" FontWeight="SemiBold" Foreground="#137333"/>
            <TextBlock x:Name="IntroReq" TextWrapping="Wrap" Margin="0,6,0,0" FontSize="13.5" FontWeight="SemiBold"
                       Text="Required last step: install the PlayBridge script in your browser."/>
            <TextBlock x:Name="IntroText" TextWrapping="Wrap" Margin="0,2,0,0" FontSize="13"
                       Text="It is this script that makes Jellyfin's Play button open your player. A browser never lets a program install a script by itself, so these two clicks are yours."/>
          </StackPanel>
        </Border>

        <Border Style="{StaticResource Card}">
          <StackPanel>
            <DockPanel>
              <Button x:Name="BrowseBrowser" Content="Browse..." DockPanel.Dock="Right" Margin="8,0,0,0" ToolTip="Your browser is not in the list? Pick its .exe"/>
              <TextBlock Text="You open Jellyfin with" FontWeight="SemiBold" VerticalAlignment="Center" Margin="0,0,10,0"/>
              <ComboBox x:Name="BrowserCombo" ToolTip="Your web browser, or the Jellyfin desktop app. The steps below adapt to it, and its buttons open in it."/>
            </DockPanel>
          </StackPanel>
        </Border>

        <Border x:Name="VMCard" Style="{StaticResource Card}">
          <StackPanel>
            <DockPanel>
              <Button x:Name="VMBtn" Content="Install Violentmonkey" Style="{StaticResource Action}" DockPanel.Dock="Right" VerticalAlignment="Center"/>
              <StackPanel Orientation="Horizontal">
                <Border Style="{StaticResource Num}"><TextBlock Style="{StaticResource NumText}" Text="1"/></Border>
                <TextBlock Style="{StaticResource H2}" Text="Install the Violentmonkey extension"/>
                <Border Style="{StaticResource Required}"><TextBlock Text="Required" Foreground="#C5221F" FontSize="11.5" FontWeight="SemiBold"/></Border>
              </StackPanel>
            </DockPanel>
            <TextBlock Style="{StaticResource Hint}" Margin="36,6,0,0"
                       Text="Already have Violentmonkey (or Tampermonkey) in this browser? Go to step 2."/>
            <TextBlock x:Name="VMChromeHint" Style="{StaticResource Hint}" Foreground="#9A5B00" Margin="36,4,0,0"
                       Text="Then right-click the extension icon &#x2192; Manage extension &#x2192; turn on 'Allow User Scripts'."/>
          </StackPanel>
        </Border>

        <Border x:Name="AddrCard" Style="{StaticResource Card}">
          <StackPanel>
            <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
              <Border Style="{StaticResource Num}"><TextBlock Style="{StaticResource NumText}" Text="2"/></Border>
              <TextBlock Style="{StaticResource H2}" Text="Your Jellyfin address"/>
              <Border Style="{StaticResource Required}"><TextBlock Text="Required" Foreground="#C5221F" FontSize="11.5" FontWeight="SemiBold"/></Border>
            </StackPanel>
            <TextBlock Style="{StaticResource Hint}" Margin="36,0,0,4" Text="The address you type in the browser to open Jellyfin. It is written into the script of step 3."/>
            <ComboBox x:Name="JfCombo" IsEditable="True" Margin="36,0,0,0"/>
            <TextBlock x:Name="JfHint" Style="{StaticResource Hint}" Margin="36,4,0,0"/>
            <CheckBox x:Name="AutoUpdate" Content="Let the script update itself from GitHub (advanced)" Margin="36,12,0,0"/>
            <TextBlock x:Name="AutoUpdateHint" Style="{StaticResource Hint}" Margin="56,2,0,0"/>
          </StackPanel>
        </Border>

        <Border x:Name="ScriptCard" Style="{StaticResource Card}">
          <StackPanel>
            <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
              <Border Style="{StaticResource Num}"><TextBlock Style="{StaticResource NumText}" Text="3"/></Border>
              <TextBlock Style="{StaticResource H2}" Text="Install ONE of these two scripts"/>
              <Border Style="{StaticResource Required}"><TextBlock Text="Required" Foreground="#C5221F" FontSize="11.5" FontWeight="SemiBold"/></Border>
            </StackPanel>
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="12"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <Border Grid.Column="0" Style="{StaticResource Option}">
                <DockPanel>
                  <Button x:Name="ScriptABtn" Content="Install A" Style="{StaticResource Action}" DockPanel.Dock="Bottom" HorizontalAlignment="Left" Margin="0,10,0,0"/>
                  <StackPanel>
                    <TextBlock Text="A.  Jellyfin's Play buttons" FontWeight="SemiBold" FontSize="14"/>
                    <TextBlock Style="{StaticResource Hint}" Margin="0,4,0,0" Text="Every Play and Resume button of Jellyfin opens your player."/>
                  </StackPanel>
                </DockPanel>
              </Border>
              <Border Grid.Column="2" Style="{StaticResource Option}">
                <DockPanel>
                  <Button x:Name="ScriptBBtn" Content="Install B" Style="{StaticResource Action}" DockPanel.Dock="Bottom" HorizontalAlignment="Left" Margin="0,10,0,0"/>
                  <StackPanel>
                    <TextBlock Text="B.  A new yellow button" FontWeight="SemiBold" FontSize="14"/>
                    <TextBlock Style="{StaticResource Hint}" Margin="0,4,0,0" Text="Play stays in Jellyfin. The yellow button opens your player."/>
                    <Image x:Name="IconPreview" Margin="0,6,0,0" MaxWidth="330" HorizontalAlignment="Left" Stretch="Uniform"/>
                  </StackPanel>
                </DockPanel>
              </Border>
            </Grid>
            <TextBlock x:Name="ScriptHint" Style="{StaticResource Hint}" Margin="0,8,0,0"
                       Text="The script is made for this PC (address of step 2). Violentmonkey opens its page: click Install. Choose A or B, not both."/>
            <TextBlock x:Name="ScriptWarn" TextWrapping="Wrap" FontWeight="SemiBold" Foreground="#C5221F" Margin="0,8,0,0" Visibility="Collapsed"/>
          </StackPanel>
        </Border>

        <Border x:Name="MatchCard" Style="{StaticResource Card}" Visibility="Collapsed">
          <StackPanel>
            <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
              <Border Style="{StaticResource Num}"><TextBlock x:Name="NumMatch" Style="{StaticResource NumText}" Text="4"/></Border>
              <TextBlock Style="{StaticResource H2}" Text="Add your Jellyfin address in Violentmonkey (kept through auto-updates)"/>
              <Border Style="{StaticResource Required}"><TextBlock Text="Required" Foreground="#C5221F" FontSize="11.5" FontWeight="SemiBold"/></Border>
            </StackPanel>
            <TextBlock Style="{StaticResource Hint}" Margin="36,0,0,6"
                       Text="Violentmonkey &#x2192; Dashboard &#x2192; PlayBridge &#x2192; &lt;/&gt; &#x2192; Settings tab &#x2192; @match rules: add this line, then Save."/>
            <DockPanel Margin="36,0,0,0">
              <Button x:Name="CopyMatchBtn" Content="Copy" DockPanel.Dock="Right" Margin="8,0,0,0"/>
              <TextBox x:Name="MatchText" IsReadOnly="True" FontFamily="Consolas"/>
            </DockPanel>
          </StackPanel>
        </Border>

        <Border x:Name="StreamCard" Style="{StaticResource Card}" Visibility="Collapsed">
          <StackPanel>
            <DockPanel>
              <Button x:Name="StreamBtn" Content="Turn on" Style="{StaticResource Action}" DockPanel.Dock="Right" VerticalAlignment="Center"/>
              <StackPanel Orientation="Horizontal">
                <Border Style="{StaticResource Num}"><TextBlock x:Name="NumStream" Style="{StaticResource NumText}" Text="5"/></Border>
                <TextBlock Style="{StaticResource H2}" Text="Turn on stream links in this browser"/>
                <Border Style="{StaticResource Required}"><TextBlock Text="Required" Foreground="#C5221F" FontSize="11.5" FontWeight="SemiBold"/></Border>
              </StackPanel>
            </DockPanel>
            <TextBlock Style="{StaticResource Hint}" Margin="36,6,0,0"
                       Text="Needed with auto-update when PlayBridge uses Jellyfin links. Opens Jellyfin once: a message says 'stream links are ON'."/>
            <TextBlock Style="{StaticResource Hint}" Margin="36,4,0,0"
                       Text="No message? In Jellyfin press F12 &#x2192; Console and type:  localStorage.setItem('playbridge-stream', 'on')"/>
          </StackPanel>
        </Border>

        <Border x:Name="DesktopCard" Style="{StaticResource Card}" Visibility="Collapsed">
          <StackPanel>
            <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
              <Border Style="{StaticResource Num}"><TextBlock Style="{StaticResource NumText}" Text="1"/></Border>
              <TextBlock Style="{StaticResource H2}" Text="Jellyfin Media Player / Jellyfin Desktop app"/>
              <Border Style="{StaticResource Required}"><TextBlock Text="Experimental" Foreground="#9A5B00" FontSize="11.5" FontWeight="SemiBold"/></Border>
            </StackPanel>
            <TextBlock Style="{StaticResource Hint}" Margin="36,0,0,10"
                       Text="The app has no extension system: the PlayBridge script is added on your Jellyfin server, for this app only (identified by its DeviceId)."/>
            <DockPanel Margin="36,0,0,8">
              <Button x:Name="InjectorBtn" Content="Plugin page" DockPanel.Dock="Right" VerticalAlignment="Top" Margin="8,0,0,0"/>
              <TextBlock TextWrapping="Wrap" Text="a.  On your Jellyfin server, install the JavaScript Injector plugin (restart the server if asked)."/>
            </DockPanel>
            <DockPanel Margin="36,0,0,8">
              <Button x:Name="CopyInjectorBtn" Content="Copy the script" DockPanel.Dock="Right" VerticalAlignment="Top" Margin="8,0,0,0"/>
              <TextBlock TextWrapping="Wrap" Text="b.  Jellyfin Dashboard &#x2192; JS Injector &#x2192; Add Script: paste the script, tick 'Requires Authentication' and 'Enabled', Save."/>
            </DockPanel>
            <TextBlock TextWrapping="Wrap" Margin="36,0,0,0" Text="c.  Open the app and log in: a box shows its DeviceId. Copy it into the script in place of PUT_DEVICE_ID_HERE, Save, restart the app."/>
            <TextBlock x:Name="InjectorStreamHint" Style="{StaticResource Hint}" Margin="36,6,0,0" Visibility="Collapsed"
                       Text="The copied script has stream links turned on (STREAM_LINKS = true), for your Jellyfin link mode."/>
          </StackPanel>
        </Border>

        <Border Style="{StaticResource Card}">
          <StackPanel>
            <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
              <Border Style="{StaticResource Num}"><TextBlock x:Name="NumTest" Style="{StaticResource NumText}" Text="4"/></Border>
              <TextBlock x:Name="TestTitle" Style="{StaticResource H2}" Text="Restart the browser, then test"/>
            </StackPanel>
            <TextBlock x:Name="TestText" TextWrapping="Wrap" Margin="36,0,0,6"
                       Text="Close ALL the windows of your browser and open it again: a browser learns the new playbridge:// link only when it starts."/>
            <WrapPanel Margin="36,0,0,0">
              <Button x:Name="TestBrowserBtn" Content="Test from the browser" Style="{StaticResource Action}" Margin="0,0,8,6" ToolTip="Opens a small page in the browser with a button that starts PlayBridge, like Jellyfin would"/>
              <Button x:Name="TestFileBtn" Content="Test with a video file..." Margin="0,0,8,6"/>
              <Button x:Name="OpenJfBtn" Content="Open Jellyfin" Margin="0,0,8,6"/>
            </WrapPanel>
            <TextBlock x:Name="TestHint" Style="{StaticResource Hint}" Margin="36,2,0,0"
                       Text="Then in Jellyfin, press Play. The first time, the browser asks to open PlayBridge: tick 'Always allow', then open."/>
          </StackPanel>
        </Border>
      </StackPanel>
    </ScrollViewer>

    <Border Grid.Row="2" Background="White" BorderBrush="#DADCE0" BorderThickness="0,1,0,0" Padding="20,10">
      <DockPanel LastChildFill="False">
        <Button x:Name="HelpBtn" Content="Help" DockPanel.Dock="Left" Margin="0,0,8,0" ToolTip="Full guide (GitHub)"/>
        <Button x:Name="UninstallBtn" Content="Uninstall..." DockPanel.Dock="Left" Margin="0,0,8,0" Visibility="Collapsed"/>
        <Button x:Name="OpenFolderBtn" Content="Open folder" DockPanel.Dock="Left" Visibility="Collapsed"/>
        <Button x:Name="NextBtn" Content="Next  &#x25B8;" Style="{StaticResource Primary}" DockPanel.Dock="Right" MinWidth="130"/>
        <Button x:Name="BackBtn" Content="&#x25C2;  Back" DockPanel.Dock="Right" Margin="0,0,8,0" MinWidth="90" Visibility="Collapsed"/>
        <Button x:Name="CloseBtn" Content="Close" DockPanel.Dock="Right" Margin="0,0,8,0" MinWidth="90"/>
      </DockPanel>
    </Border>
  </Grid>
</Window>
'@

$MapXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PlayBridge - Find a video" Width="720" SizeToContent="Height"
        WindowStartupLocation="CenterScreen" ResizeMode="CanMinimize" FontFamily="Segoe UI" FontSize="13" Background="#F1F3F4" Topmost="True">
  <Window.Resources>
__STYLES__
  </Window.Resources>
  <StackPanel>
    <Border Background="White" BorderBrush="#DADCE0" BorderThickness="0,0,0,1" Padding="20,12">
      <DockPanel>
        <Image x:Name="MapLogo" Width="40" Height="40" Margin="0,0,12,0"/>
        <StackPanel VerticalAlignment="Center">
          <TextBlock Text="Link this video's folder to Windows" FontSize="18" FontWeight="SemiBold"/>
          <TextBlock Style="{StaticResource Hint}" FontSize="13" Text="Once per folder: every video in it will then open directly."/>
        </StackPanel>
      </DockPanel>
    </Border>
    <StackPanel Margin="20,14,20,0">
      <Border Style="{StaticResource Card}">
        <StackPanel>
          <TextBlock Text="Path from Jellyfin" FontWeight="SemiBold" Margin="0,0,0,4"/>
          <TextBox x:Name="JfPath" FontFamily="Consolas"/>
          <WrapPanel Margin="0,10,0,0">
            <Button x:Name="SearchBtn" Content="Search automatically" Style="{StaticResource Action}" Margin="0,0,8,6"/>
            <Button x:Name="LocateFileBtn" Content="Pick the file myself..." Margin="0,0,8,6"/>
            <Button x:Name="LocateFolderBtn" Content="Pick the folder..." Margin="0,0,8,6"/>
            <Button x:Name="StopBtn" Content="Stop" Margin="0,0,8,6" Visibility="Collapsed"/>
          </WrapPanel>
          <TextBlock x:Name="Status" TextWrapping="Wrap" Margin="0,4,0,0"/>
          <ListBox x:Name="Matches" MaxHeight="90" Visibility="Collapsed" Margin="0,6,0,0"/>
        </StackPanel>
      </Border>
      <Border Style="{StaticResource Card}">
        <StackPanel>
          <TextBlock Text="Folder link to save" FontWeight="SemiBold"/>
          <TextBlock x:Name="RuleText" TextWrapping="Wrap" Margin="0,6,0,0" FontFamily="Consolas" Text="(nothing yet)"/>
        </StackPanel>
      </Border>
    </StackPanel>
    <Border Background="White" BorderBrush="#DADCE0" BorderThickness="0,1,0,0" Padding="20,10" Margin="0,4,0,0">
      <DockPanel LastChildFill="False">
        <Button x:Name="SavePlayBtn" Content="Save and play" Style="{StaticResource Primary}" DockPanel.Dock="Right" MinWidth="130" IsEnabled="False" Visibility="Collapsed"/>
        <Button x:Name="SaveBtn" Content="Save" DockPanel.Dock="Right" MinWidth="90" Margin="0,0,8,0" IsEnabled="False"/>
        <Button x:Name="MapCancel" Content="Cancel" DockPanel.Dock="Right" MinWidth="90" Margin="0,0,8,0" IsCancel="True"/>
      </DockPanel>
    </Border>
  </StackPanel>
</Window>
'@

function Get-PlayBridgeImage([string]$Name) {
    foreach ($d in $SetupDir, $InstallDir) {
        $f = Join-Path $d $Name
        if (-not [System.IO.File]::Exists($f)) { continue }
        try {
            # loaded in memory: the file stays free (update, uninstall)
            $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
            $bmp.BeginInit()
            $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bmp.StreamSource = New-Object System.IO.MemoryStream (, [System.IO.File]::ReadAllBytes($f))
            $bmp.EndInit()
            $bmp.Freeze()
            return $bmp
        } catch { }
    }
    return $null
}

function New-PlayBridgeWindow([string]$Xaml) {
    $xml = [xml]($Xaml.Replace('__STYLES__', $StylesXaml))
    $win = [System.Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xml))
    $ui = @{ Window = $win }
    foreach ($node in $xml.SelectNodes('//*[@*[local-name()="Name"]][not(ancestor::*[local-name()="ControlTemplate"])]')) {
        $name = $node.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
        if ($name) { $ui[$name] = $win.FindName($name) }
    }
    $logo = Get-PlayBridgeImage 'PlayBridge-logo.png'
    if ($logo) { $win.Icon = $logo }
    try {
        $max = [System.Windows.SystemParameters]::WorkArea.Height - 20
        $win.MaxHeight = $max
        if (-not [double]::IsNaN($win.Height) -and $win.Height -gt $max) { $win.Height = $max }
    } catch { }
    return $ui
}

function Invoke-PlayBridgeUiRefresh {
    try { [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action] { }, [System.Windows.Threading.DispatcherPriority]::Background) } catch { }
}

function Show-PlayBridgeBox([string]$Text, [string]$Buttons = 'OK', [string]$Icon = 'Information', $Owner = $null) {
    if ($Owner) { return [string][System.Windows.MessageBox]::Show($Owner, $Text, 'PlayBridge', $Buttons, $Icon) }
    return [string][System.Windows.MessageBox]::Show($Text, 'PlayBridge', $Buttons, $Icon)
}

function Invoke-PlayBridgeSafe([scriptblock]$Action) {
    try { & $Action } catch {
        try { [void][System.Windows.MessageBox]::Show("Something went wrong:`n`n" + $_.Exception.Message, 'PlayBridge', 'OK', 'Warning') } catch { }
    }
}

function Set-PlayBridgeText($Block, [string]$Text, [string]$Color = '#202124') {
    $Block.Text = $Text
    $Block.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($Color))
    $Block.Visibility = 'Visible'
}

function Show-PlayBridge($Element, [bool]$Visible) {
    if ($Visible) { $Element.Visibility = 'Visible' } else { $Element.Visibility = 'Collapsed' }
}

function Get-PlayBridgeSelectedBrowser {
    if (-not $script:UI -or -not $script:UI.BrowserCombo) { return $null }
    $item = $script:UI.BrowserCombo.SelectedItem
    if ($item) { return $item.Tag }
    return $null
}

function Open-PlayBridgeUrl([string]$Url) {
    $b = Get-PlayBridgeSelectedBrowser
    if ($b -and $b.Kind -ne 'desktop' -and $b.Path -and (Test-Path -LiteralPath $b.Path)) {
        try { Start-Process -FilePath $b.Path -ArgumentList ('"{0}"' -f $Url); return } catch { }
    }
    Start-Process -FilePath $Url
}

# --- Folder assistant (opened by PlayBridge when a video isn't found) -------------

function Show-PlayBridgeMapWindow([string]$JellyfinPath) {
    $ui = New-PlayBridgeWindow $MapXaml
    $script:Map = @{ UI = $ui; Rule = $null; Cancel = $false; Saved = $null }
    $logo = Get-PlayBridgeImage 'PlayBridge-logo.png'
    if ($logo) { $ui.MapLogo.Source = $logo }
    if ($JellyfinPath -match '^(playbridge|mpcjf):') { $JellyfinPath = ConvertFrom-PlayBridgeUrl $JellyfinPath }
    if ($JellyfinPath) { $ui.JfPath.Text = ConvertTo-PlayBridgeDisplayPath (Format-PlayBridgePath $JellyfinPath) }
    if ($MapUrl) { $ui.SavePlayBtn.Visibility = 'Visible' }

    $ui.SearchBtn.Add_Click({ Invoke-PlayBridgeSafe { Invoke-PlayBridgeMapSearch } })
    $ui.LocateFileBtn.Add_Click({ Invoke-PlayBridgeSafe { Invoke-PlayBridgeMapLocate $true } })
    $ui.LocateFolderBtn.Add_Click({ Invoke-PlayBridgeSafe { Invoke-PlayBridgeMapLocate $false } })
    $ui.StopBtn.Add_Click({ $script:Map.Cancel = $true })
    $ui.Matches.Add_SelectionChanged({ Invoke-PlayBridgeSafe {
                $sel = [string]$script:Map.UI.Matches.SelectedItem
                if ($sel) { Set-PlayBridgeMapResult $sel }
            } })
    $ui.SaveBtn.Add_Click({ Invoke-PlayBridgeSafe { Save-PlayBridgeMapRule $false } })
    $ui.SavePlayBtn.Add_Click({ Invoke-PlayBridgeSafe { Save-PlayBridgeMapRule $true } })
    $ui.MapCancel.Add_Click({ $script:Map.Cancel = $true; $script:Map.UI.Window.Close() })
    $ui.Window.Add_Closing({ $script:Map.Cancel = $true })
    $ui.Window.Add_ContentRendered({ Invoke-PlayBridgeSafe { if ($script:Map.UI.JfPath.Text) { Invoke-PlayBridgeMapSearch } } })
    [void]$ui.Window.ShowDialog()
    return $script:Map.Saved
}

function Set-PlayBridgeMapBusy([bool]$Busy) {
    $ui = $script:Map.UI
    foreach ($b in $ui.SearchBtn, $ui.LocateFileBtn, $ui.LocateFolderBtn) { $b.IsEnabled = -not $Busy }
    Show-PlayBridge $ui.StopBtn $Busy
}

function Invoke-PlayBridgeMapSearch {
    $ui = $script:Map.UI
    $j = Format-PlayBridgePath $ui.JfPath.Text
    if (-not $j -or (Get-PlayBridgePathKind $j) -eq 'other') {
        Set-PlayBridgeText $ui.Status 'Paste the path shown by Jellyfin first, for example /share/Movies/Film.mkv' '#9A5B00'
        return
    }
    $script:Map.Cancel = $false
    $script:Map.Rule = $null
    $ui.SaveBtn.IsEnabled = $false; $ui.SavePlayBtn.IsEnabled = $false
    $ui.RuleText.Text = '(nothing yet)'
    $ui.Matches.Items.Clear(); Show-PlayBridge $ui.Matches $false
    Set-PlayBridgeMapBusy $true
    try {
        $res = Find-PlayBridgeVideo $j @($script:State.Paths) @($script:State.Shares) {
            param($msg)
            if ($null -ne $msg) { $script:Map.UI.Status.Text = $msg }
            Invoke-PlayBridgeUiRefresh
        } { $script:Map.Cancel }
    } finally { Set-PlayBridgeMapBusy $false }
    $results = @()
    if ($res.Found) { $results = @($res.Found) } else { $results = @($res.Deep) }
    if ($results.Count -eq 0) {
        if ($script:Map.Cancel) { Set-PlayBridgeText $ui.Status 'Search stopped.' '#9A5B00' }
        else { Set-PlayBridgeText $ui.Status "Not found automatically. Click 'Pick the file myself...' and choose the same video in Windows." '#C5221F' }
        return
    }
    if ($results.Count -eq 1) {
        Set-PlayBridgeText $ui.Status ('Found: ' + $results[0]) '#137333'
        Set-PlayBridgeMapResult $results[0]
        return
    }
    Set-PlayBridgeText $ui.Status 'Found in several places, choose the right one:' '#9A5B00'
    foreach ($f in $results) { [void]$ui.Matches.Items.Add($f) }
    Show-PlayBridge $ui.Matches $true
    $ui.Matches.SelectedIndex = 0
}

# File or folder dialog over a window; returns the picked path or $null
function Select-PlayBridgeWindowsPath($Window, [bool]$File, [string]$JellyfinPath) {
    $leaf = @(@((Split-PlayBridgePath $JellyfinPath).Parts) | Select-Object -Last 1)[0]
    $topmost = $Window.Topmost
    $Window.Topmost = $false   # the dialog must not open behind the window
    try {
        if ($File) {
            $dlg = New-Object Microsoft.Win32.OpenFileDialog
            $dlg.Title = 'Pick the same video in Windows'
            $dlg.Filter = 'All files (*.*)|*.*'
            if ($leaf) { $dlg.FileName = $leaf }
            if ($dlg.ShowDialog($Window) -eq $true) { return $dlg.FileName }
        } else {
            $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
            $dlg.Description = 'Pick the Windows folder that matches: ' + (ConvertTo-PlayBridgeDisplayPath $JellyfinPath)
            $dlg.ShowNewFolderButton = $false
            $owner = New-Object System.Windows.Forms.NativeWindow
            $owner.AssignHandle((New-Object System.Windows.Interop.WindowInteropHelper $Window).Handle)
            try { if ([string]$dlg.ShowDialog($owner) -eq 'OK') { return $dlg.SelectedPath } } finally { $owner.ReleaseHandle() }
        }
    } finally {
        $Window.Topmost = $topmost
    }
    return $null
}

function Invoke-PlayBridgeMapLocate([bool]$File) {
    $ui = $script:Map.UI
    $j = Format-PlayBridgePath $ui.JfPath.Text
    if (-not $j -or (Get-PlayBridgePathKind $j) -eq 'other') {
        Set-PlayBridgeText $ui.Status 'Paste the path shown by Jellyfin first, then pick the same video in Windows.' '#9A5B00'
        return
    }
    $w = Select-PlayBridgeWindowsPath $ui.Window $File $j
    if (-not $w) { return }
    Set-PlayBridgeText $ui.Status ('Picked: ' + $w) '#137333'
    Set-PlayBridgeMapResult $w
}

function Set-PlayBridgeMapResult([string]$WindowsPath) {
    $ui = $script:Map.UI
    $r = New-PlayBridgeRule (Format-PlayBridgePath $ui.JfPath.Text) $WindowsPath
    $script:Map.Rule = $r
    $ui.RuleText.Text = ("Jellyfin  {0}`nWindows   {1}" -f (ConvertTo-PlayBridgeDisplayPath $r.From), $r.To)
    $ui.SaveBtn.IsEnabled = $true
    $ui.SavePlayBtn.IsEnabled = $true
}

function Save-PlayBridgeMapRule([bool]$Play) {
    $r = $script:Map.Rule
    if (-not $r) { return }
    # saved at once, next to the PlayBridge that asked
    $ini = Join-Path $SetupDir 'PlayBridge.ini'
    $cfg = Read-PlayBridgeConfig $ini
    if (-not $cfg.Player) {
        $cfg.Player = $PlayBridge_DefaultPlayer
        if ($null -eq $cfg.Arguments) { $cfg.Arguments = $PlayBridge_DefaultArguments }
    }
    if ($null -eq $cfg.HideWindow) { $cfg.HideWindow = ((Get-PlayBridgeProtocolCommand) -match 'wscript') }
    $cfg.Paths = @(@($cfg.Paths) | Where-Object { -not [string]::Equals($_.From, $r.From, [System.StringComparison]::OrdinalIgnoreCase) }) + @($r)
    Write-PlayBridgeConfig $ini $cfg
    $script:Map.Saved = $r
    $script:Map.UI.Window.Close()
    if ($Play -and $MapUrl) { Start-Process -FilePath $MapUrl }
}

# --- Main window: page 1 (settings) ---------------------------------------------

function Select-PlayBridgePlayerItem {
    $ui = $script:UI
    $target = ([string]$ui.PlayerPath.Text).Trim().Trim('"')
    foreach ($item in $ui.PlayerCombo.Items) {
        if ($item.Tag -and [string]::Equals([string]$item.Tag, $target, [System.StringComparison]::OrdinalIgnoreCase)) { $ui.PlayerCombo.SelectedItem = $item; return }
    }
    $ui.PlayerCombo.SelectedItem = $script:State.OtherItem
}

function Set-PlayBridgeFullscreenArg([bool]$On) {
    $ui = $script:UI
    $flag = (Get-PlayBridgePlayerInfo $ui.PlayerPath.Text).Fullscreen
    $tokens = @(([string]$ui.PlayerArgs.Text) -split '\s+' | Where-Object { $_ -and $_ -notmatch '^(/fullscreen|--fullscreen|--fs|-fullscreen)$' })
    if ($On -and $flag) { $tokens = @($flag) + $tokens }
    $ui.PlayerArgs.Text = ($tokens -join ' ')
}

function Update-PlayBridgePlayerUi([bool]$Resync) {
    $ui = $script:UI
    $path = ([string]$ui.PlayerPath.Text).Trim().Trim('"')
    $info = Get-PlayBridgePlayerInfo $path
    $ui.Fullscreen.IsEnabled = [bool]$info.Fullscreen
    $ui.FullscreenNote.Text = $info.Note
    Show-PlayBridge $ui.FullscreenNote ([bool]$info.Note -and -not $info.Fullscreen)
    if (-not $path) {
        Set-PlayBridgeText $ui.PlayerWarn 'No player found on this PC. Install MPC-BE, PotPlayer, VLC... or choose one with Browse...' '#C5221F'
    } elseif (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Set-PlayBridgeText $ui.PlayerWarn 'This file does not exist. Choose your player with Browse...' '#C5221F'
    } else {
        Show-PlayBridge $ui.PlayerWarn $false
    }
    if ($Resync) { Set-PlayBridgeFullscreenArg ($ui.Fullscreen.IsChecked -eq $true) }
    Update-PlayBridgeModeUi
}

function Invoke-PlayBridgeBrowsePlayer {
    $ui = $script:UI
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title = 'Choose your video player (.exe)'
    $dlg.Filter = 'Programs (*.exe)|*.exe'
    try {
        $dir = Split-Path ([string]$ui.PlayerPath.Text) -Parent
        if ($dir -and (Test-Path -LiteralPath $dir)) { $dlg.InitialDirectory = $dir }
    } catch { }
    if ($dlg.ShowDialog($ui.Window) -eq $true) {
        $ui.PlayerPath.Text = $dlg.FileName      # TextChanged does the rest
    } else {
        $script:State.Updating = $true
        Select-PlayBridgePlayerItem
        $script:State.Updating = $false
    }
}

$ModeTexts = @{
    'path'        = 'Opens the file itself from Windows: fast seeking, subtitle files next to the video are loaded. The file must be reachable from this PC (local disk, NAS share).'
    'path+stream' = 'Opens the file itself, and streams it from Jellyfin when it isn''t found on this PC (instead of asking).'
    'stream'      = 'Plays the original file through Jellyfin (no conversion). Works wherever Jellyfin opens, even remotely: no NAS share, mapped drive or folder setup needed. Embedded subtitles work; separate subtitle files (.srt...) aren''t loaded.'
    'download'    = 'Like stream, through Jellyfin''s Download link: no NAS or mapped drive needed. Your Jellyfin user needs the download permission.'
}

function Get-PlayBridgeSelectedMode {
    $item = $script:UI.ModeCombo.SelectedItem
    if ($item -and $item.Tag) { return [string]$item.Tag }
    return 'path'
}

function Update-PlayBridgeModeUi {
    $ui = $script:UI
    if (-not $ui.ModeCombo) { return }
    $mode = Get-PlayBridgeSelectedMode
    $ui.ModeHint.Text = $ModeTexts[$mode]
    $info = Get-PlayBridgePlayerInfo $ui.PlayerPath.Text
    if ($mode -ne 'path' -and $info.Http -eq 'untested') { Set-PlayBridgeText $ui.ModeWarn ($info.Name + ' should open http links, but this was not tested with PlayBridge. Use the test button of the next page.') '#9A5B00' }
    elseif ($mode -ne 'path' -and $info.Http -eq 'unknown') { Set-PlayBridgeText $ui.ModeWarn 'Your player must be able to open http links for this mode (MPC-BE, MPC-HC, PotPlayer, VLC, mpv and SMPlayer do).' '#9A5B00' }
    else { Show-PlayBridge $ui.ModeWarn $false }
    Show-PlayBridge $ui.NasCard ($mode -eq 'path' -or $mode -eq 'path+stream')
}

function Update-PlayBridgeDrivesUi {
    $ui = $script:UI
    $ui.DrivesPanel.Children.Clear()
    $drives = @(Get-PlayBridgeNetworkDrives)
    $mapped = @{}
    foreach ($d in $drives) {
        $mapped[$d.Unc.ToLowerInvariant()] = $true
        $chip = New-Object System.Windows.Controls.Border
        $chip.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#E8F0FE'))
        $chip.CornerRadius = New-Object System.Windows.CornerRadius 12
        $chip.Padding = New-Object System.Windows.Thickness 10, 3, 10, 3
        $chip.Margin = New-Object System.Windows.Thickness 0, 0, 6, 6
        $chip.ToolTip = $d.Unc
        $tb = New-Object System.Windows.Controls.TextBlock
        $label = $d.Root.TrimEnd('\') + '  ' + ($d.Parts -join '\')
        if ($d.Source -eq 'saved drive') { $label += '  (not connected)' }
        $tb.Text = $label
        $tb.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#174EA6'))
        $chip.Child = $tb
        [void]$ui.DrivesPanel.Children.Add($chip)
    }
    $extra = @($script:State.Shares | Where-Object { -not $mapped[([string]$_).ToLowerInvariant()] })
    $text = ''
    if ($extra.Count) {
        $shown = @($extra | Select-Object -First 3) -join ',  '
        if ($extra.Count -gt 3) { $shown += ('  (+{0})' -f ($extra.Count - 3)) }
        $text = ('Shares without a drive letter, used too: ' + $shown)
    } elseif (-not $drives.Count) {
        $text = 'No network drive found. Map your NAS shares to drive letters (File Explorer > This PC > Map network drive), or check a path below.'
    }
    if ($script:State.ScanningShares) { if ($text) { $text += '   ' }; $text += 'Looking for other network shares...' }
    $ui.SharesText.Text = $text
    Show-PlayBridge $ui.SharesText ([bool]$text)
}

function Update-PlayBridgeMapList {
    $ui = $script:UI
    $ui.MapList.Items.Clear()
    foreach ($r in $script:State.Paths) { [void]$ui.MapList.Items.Add(('{0}  {2}  {1}' -f (ConvertTo-PlayBridgeDisplayPath $r.From), $r.To, $ArrowChar)) }
    Show-PlayBridge $ui.LinksPanel ($script:State.Paths.Count -gt 0)
}

function Add-PlayBridgeRule($Rule) {
    for ($i = $script:State.Paths.Count - 1; $i -ge 0; $i--) {
        if ([string]::Equals($script:State.Paths[$i].From, $Rule.From, [System.StringComparison]::OrdinalIgnoreCase)) { $script:State.Paths.RemoveAt($i) }
    }
    [void]$script:State.Paths.Add($Rule)
}

function Add-PlayBridgeShares($List) {
    foreach ($s in @($List)) {
        $u = ([string]$s).Trim().TrimEnd('\')
        if ($u -notmatch '^\\\\[^\\]+\\[^\\]+$') { continue }
        $known = @($script:State.Shares | Where-Object { [string]::Equals([string]$_, $u, [System.StringComparison]::OrdinalIgnoreCase) })
        if (-not $known.Count) { [void]$script:State.Shares.Add($u) }
    }
}

function Reset-PlayBridgeCheckUi {
    $ui = $script:UI
    Show-PlayBridge $ui.TestActions $false
    Show-PlayBridge $ui.TestMatches $false
    $ui.TestMatches.Items.Clear()
    $script:State.PendingRule = $null
}

function Show-PlayBridgeCheckRule([string]$JellyfinPath, [string]$WindowsPath) {
    $ui = $script:UI
    $r = New-PlayBridgeRule $JellyfinPath $WindowsPath
    $script:State.PendingRule = $r
    Set-PlayBridgeText $ui.TestResult ("Found: {0}`nFolder link:  {1}  {3}  {2}" -f $WindowsPath, (ConvertTo-PlayBridgeDisplayPath $r.From), $r.To, $ArrowChar) '#137333'
    Show-PlayBridge $ui.TestActions $true
    Show-PlayBridge $ui.SaveLinkBtn $true
}

function Invoke-PlayBridgePathTest {
    $ui = $script:UI
    if ($script:State.Busy) { $script:State.Cancel = $true; return }   # the button is "Stop" while searching
    $raw = ([string]$ui.TestPath.Text).Trim().Trim('"')
    Reset-PlayBridgeCheckUi
    if (-not $raw) { Set-PlayBridgeText $ui.TestResult 'Paste a path from Jellyfin first.' '#9A5B00'; return }
    if ($raw -match '^(playbridge|mpcjf):') { $raw = ConvertFrom-PlayBridgeUrl $raw }
    $p = Format-PlayBridgePath $raw
    if ((Get-PlayBridgePathKind $p) -eq 'other') { Set-PlayBridgeText $ui.TestResult 'This is not a full path. Example: /share/Movies/Film.mkv' '#9A5B00'; return }
    $script:State.Busy = $true
    $script:State.Cancel = $false
    $ui.CheckBtn.Content = 'Stop'
    $ui.NextBtn.IsEnabled = $false
    try {
        $res = Find-PlayBridgeVideo $p @($script:State.Paths) @($script:State.Shares) {
            param($msg)
            if ($null -ne $msg) { Set-PlayBridgeText $script:UI.TestResult $msg '#202124' }
            Invoke-PlayBridgeUiRefresh
        } { $script:State.Cancel }
    } finally {
        $script:State.Busy = $false
        $ui.CheckBtn.Content = 'Check'
        $ui.NextBtn.IsEnabled = $true
    }
    if ($res.Found) {
        Set-PlayBridgeText $ui.TestResult ("OK, nothing to do. PlayBridge opens:  {0}`n({1})" -f $res.Found, $res.How) '#137333'
        return
    }
    $deep = @($res.Deep)
    if ($deep.Count -ge 1) {
        Show-PlayBridgeCheckRule $p $deep[0]
        if ($deep.Count -gt 1) {
            foreach ($d in $deep) { [void]$ui.TestMatches.Items.Add($d) }
            $ui.TestMatches.SelectedIndex = 0
            Show-PlayBridge $ui.TestMatches $true
        }
        return
    }
    if ($res.Maybe) {
        Set-PlayBridgeText $ui.TestResult ("Probably {0}, but the drive did not answer in time (sleeping disks?). Check again in a minute." -f $res.Maybe.Path) '#9A5B00'
        return
    }
    if ($script:State.Cancel) { Set-PlayBridgeText $ui.TestResult 'Search stopped.' '#9A5B00' }
    else { Set-PlayBridgeText $ui.TestResult 'Not found on this PC. Pick the same video (or its folder) in Windows:' '#C5221F' }
    Show-PlayBridge $ui.TestActions $true
    Show-PlayBridge $ui.SaveLinkBtn $false
}

function Invoke-PlayBridgePickForCheck([bool]$File) {
    $ui = $script:UI
    $p = Format-PlayBridgePath ([string]$ui.TestPath.Text).Trim().Trim('"')
    if ((Get-PlayBridgePathKind $p) -eq 'other') { Set-PlayBridgeText $ui.TestResult 'Paste the path from Jellyfin first.' '#9A5B00'; return }
    $w = Select-PlayBridgeWindowsPath $ui.Window $File $p
    if ($w) { Show-PlayBridgeCheckRule $p $w }
}

function Get-PlayBridgeSettingsFromUi {
    $ui = $script:UI
    $mapped = @{}
    foreach ($d in @(Get-PlayBridgeNetworkDrives)) { $mapped[$d.Unc.ToLowerInvariant()] = $true }
    $b = Get-PlayBridgeSelectedBrowser
    return @{
        Player     = ([string]$ui.PlayerPath.Text).Trim().Trim('"')
        Arguments  = ([string]$ui.PlayerArgs.Text).Trim()
        HideWindow = ($ui.HideWindow.IsEnabled -and $ui.HideWindow.IsChecked -eq $true)
        Mode       = (Get-PlayBridgeSelectedMode)
        Jellyfin   = $script:State.Jellyfin
        Browser    = $(if ($b -and $b.Kind -eq 'desktop') { 'desktop' } elseif ($b) { [string]$b.Path } else { '' })
        AutoUpdate = ($ui.AutoUpdate.IsChecked -eq $true)
        Script     = [string]$script:State.Script
        ScriptStream = $script:State.ScriptStream
        ScriptMatch  = [string]$script:State.ScriptMatch
        Paths      = @($script:State.Paths)
        Shares     = @($script:State.Shares | Where-Object { -not $mapped[([string]$_).ToLowerInvariant()] })
        Custom     = @($script:State.Custom)
    }
}

function Invoke-PlayBridgeInstall {
    $ui = $script:UI
    $player = ([string]$ui.PlayerPath.Text).Trim().Trim('"')
    if (-not $player) { [void](Show-PlayBridgeBox 'Choose your video player first (Browse...).' 'OK' 'Warning' $ui.Window); return }
    if (-not (Test-Path -LiteralPath $player -PathType Leaf)) {
        if ((Show-PlayBridgeBox ("This player was not found:`n{0}`n`nInstall anyway?" -f $player) 'YesNo' 'Warning' $ui.Window) -ne 'Yes') { return }
    }
    $settings = Get-PlayBridgeSettingsFromUi
    try { Install-PlayBridge $settings }
    catch { [void](Show-PlayBridgeBox ("The installation failed:`n`n{0}" -f $_.Exception.Message) 'OK' 'Error' $ui.Window); return }
    $script:State.Settings = $settings
    $script:State.Installed = $true
    if ($script:State.InPlace -or $script:State.WasInstalled) { $ui.StatusTitle.Text = [string][char]0x2714 + '  Settings saved' }
    else { $ui.StatusTitle.Text = [string][char]0x2714 + '  PlayBridge is installed on this PC' }
    Show-PlayBridgePage 2
}

# Page 2 choices (browser, address, auto-update, script) are saved as soon as they change
function Save-PlayBridgePage2Settings {
    if (-not $script:State.Installed -and -not $script:State.WasInstalled) { return }
    try {
        $ini = Join-Path $InstallDir 'PlayBridge.ini'
        if (-not [System.IO.File]::Exists($ini)) { return }
        $cfg = Read-PlayBridgeConfig $ini
        $b = Get-PlayBridgeSelectedBrowser
        $cfg.Jellyfin = $script:State.Jellyfin
        $cfg.Browser = $(if ($b -and $b.Kind -eq 'desktop') { 'desktop' } elseif ($b) { [string]$b.Path } else { '' })
        $cfg.AutoUpdate = ($script:UI.AutoUpdate.IsChecked -eq $true)
        $cfg.Script = [string]$script:State.Script
        $cfg.ScriptStream = $script:State.ScriptStream
        $cfg.ScriptMatch = [string]$script:State.ScriptMatch
        Write-PlayBridgeConfig $ini $cfg
        if ($script:State.Settings) { $script:State.Settings.Jellyfin = $cfg.Jellyfin }
    } catch { }
}

function Invoke-PlayBridgeUninstall($Owner) {
    $msg = ("Remove PlayBridge from this Windows account?`n`n- the playbridge:// link is removed`n- the folder {0} and your settings are deleted`n`nThe script stays in your browser: remove it in Violentmonkey if you want." -f $InstallDir)
    if ((Show-PlayBridgeBox $msg 'YesNo' 'Question' $Owner) -ne 'Yes') { return $false }
    Uninstall-PlayBridge
    if (Test-PlayBridgeMachineProtocol) {
        $q = "An older MPC-JF installation (MPCJF.reg) is also registered for all users of this PC.`n`nRemove it too? Windows will ask for administrator rights."
        if ((Show-PlayBridgeBox $q 'YesNo' 'Question' $Owner) -eq 'Yes') {
            try { Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\reg.exe') -ArgumentList 'delete "HKLM\SOFTWARE\Classes\MPCJF" /f' -Verb RunAs -Wait -WindowStyle Hidden } catch { }
        }
    }
    $end = 'PlayBridge has been removed.'
    if (Test-Path -LiteralPath $OldManualDir) { $end += ("`n`nThe old folder {0} was left as it is: you can delete it." -f $OldManualDir) }
    [void](Show-PlayBridgeBox $end 'OK' 'Information' $Owner)
    return $true
}

# --- Main window: page 2 (browser steps) ------------------------------------------

function Update-PlayBridgePage2 {
    $ui = $script:UI
    $b = Get-PlayBridgeSelectedBrowser
    $kind = 'other'
    if ($b) { $kind = $b.Kind }
    Show-PlayBridge $ui.VMChromeHint ($kind -eq 'chromium' -or $kind -eq 'edge')
    $addr = Get-PlayBridgeJellyfinAddress ([string]$ui.JfCombo.Text)
    $script:State.Jellyfin = $addr.Base
    $ui.MatchText.Text = $addr.Match
    $isDefault = [string]::Equals($addr.Match, 'http://localhost:8096/*', [System.StringComparison]::OrdinalIgnoreCase)
    $auto = ($ui.AutoUpdate.IsChecked -eq $true)
    $mode = 'path'
    if ($script:State.Settings) { $mode = [string]$script:State.Settings.Mode }
    $streamMode = ($mode -ne 'path')
    if ($auto) {
        $ui.AutoUpdateHint.Text = 'On: the script comes from GitHub and updates itself. Required extra steps appear below.'
    } else {
        $ui.AutoUpdateHint.Text = 'Off (recommended): the script of step 3 is made for this PC, with your address and your stream setting inside. To update it later: PlayBridge Settings, this page, Install A or B again.'
    }
    $ui.ScriptHint.Text = $(if ($auto) { 'Violentmonkey opens its page: click Install. Choose A or B, not both.' } else { 'The script is made for this PC (address of step 2). Violentmonkey opens its page: click Install. Choose A or B, not both.' })
    $desktop = ($kind -eq 'desktop')
    # the script installed from this PC no longer matches the settings: it must be installed again
    $warn = ''
    if (-not $auto -and -not $desktop -and $null -ne $script:State.ScriptStream) {
        if ([bool]$script:State.ScriptStream -ne $streamMode) { $warn = 'How videos open was changed since the script was installed: click Install A or B again.' }
        elseif ($script:State.ScriptMatch -and -not [string]::Equals([string]$script:State.ScriptMatch, $addr.Match, [System.StringComparison]::OrdinalIgnoreCase)) { $warn = 'The Jellyfin address was changed since the script was installed: click Install A or B again.' }
    }
    if ($warn) { Set-PlayBridgeText $ui.ScriptWarn ([string][char]0x26A0 + '  ' + $warn) '#C5221F' } else { Show-PlayBridge $ui.ScriptWarn $false }
    $needMatch = (-not $desktop -and $auto -and -not $isDefault)
    $needStream = (-not $desktop -and $auto -and $streamMode)
    foreach ($c in $ui.VMCard, $ui.AddrCard, $ui.ScriptCard) { Show-PlayBridge $c (-not $desktop) }
    Show-PlayBridge $ui.DesktopCard $desktop
    Show-PlayBridge $ui.MatchCard $needMatch
    Show-PlayBridge $ui.StreamCard $needStream
    Show-PlayBridge $ui.InjectorStreamHint $streamMode
    Show-PlayBridge $ui.TestBrowserBtn (-not $desktop)
    if ($desktop) {
        $ui.IntroReq.Text = 'Required last step: add the PlayBridge script to your Jellyfin server, for the app.'
        $ui.IntroText.Text = 'The Jellyfin desktop app has no extensions, so the script is injected by the JavaScript Injector plugin of your server. Experimental: tested with Jellyfin Media Player and Jellyfin Desktop on Windows.'
        $ui.TestTitle.Text = 'Restart the app, then test'
        $ui.TestText.Text = 'Close the app completely and open it again, so that it loads the script.'
        $ui.TestHint.Text = 'In the app, press Play: your player opens. Nothing happens? Check the DeviceId pasted in the script, then save and restart the app again.'
        $ui.NumTest.Text = '2'
    } else {
        $ui.IntroReq.Text = 'Required last step: install the PlayBridge script in your browser.'
        $ui.IntroText.Text = "It is this script that makes Jellyfin's Play button open your player. A browser never lets a program install a script by itself, so these two clicks are yours."
        $ui.TestTitle.Text = 'Restart the browser, then test'
        $ui.TestText.Text = 'Close ALL the windows of your browser and open it again: a browser learns the new playbridge:// link only when it starts.'
        $ui.TestHint.Text = "Then in Jellyfin, press Play. The first time, the browser asks to open PlayBridge: tick 'Always allow', then open."
        $n = 4
        if ($needMatch) { $ui.NumMatch.Text = [string]$n; $n++ }
        if ($needStream) { $ui.NumStream.Text = [string]$n; $n++ }
        $ui.NumTest.Text = [string]$n
    }
}

# Small page served to the browser: a button that starts PlayBridge exactly like Jellyfin would
function Get-PlayBridgeBrowserTestPage {
    return @'
<!doctype html><html><head><meta charset="utf-8"><title>PlayBridge test</title>
<style>body{font-family:Segoe UI,sans-serif;background:#1E293B;color:#fff;display:flex;flex-direction:column;align-items:center;justify-content:center;min-height:100vh;margin:0;text-align:center}
button{font-size:22px;padding:18px 36px;border:0;border-radius:10px;background:#FFAA00;color:#1E293B;font-weight:600;cursor:pointer}p{max-width:560px;line-height:1.5;color:#cbd5e1}</style></head>
<body><h1>PlayBridge test</h1><p>Click the button: your browser must ask to open PlayBridge (tick "Always allow"), then a PlayBridge message confirms that it was started.</p>
<button onclick="location.replace('playbridge://playbridge-test')">Start PlayBridge</button>
<p>Nothing happens? Restart the browser (all windows) and try again. If the browser says it has no application for this link, run Install.cmd again.</p></body></html>
'@
}

function Show-PlayBridgePage([int]$Page) {
    $ui = $script:UI
    $one = ($Page -eq 1)
    Show-PlayBridge $ui.Page1 $one
    Show-PlayBridge $ui.Page2 (-not $one)
    Show-PlayBridge $ui.BackBtn (-not $one)
    Show-PlayBridge $ui.CloseBtn $one
    Show-PlayBridge $ui.UninstallBtn ($one -and ($script:State.WasInstalled -or $script:State.Installed -or [bool](Get-PlayBridgeProtocolCommand)))
    Show-PlayBridge $ui.OpenFolderBtn ($one -and (Test-Path -LiteralPath (Join-Path $InstallDir 'PlayBridge.ini')))
    if ($one) {
        $ui.NextBtn.Content = 'Next  ' + [string][char]0x25B8
        $ui.HeaderSub.Text = 'External player launcher for Jellyfin (Windows)'
    } else {
        $ui.NextBtn.Content = 'Finish'
        $ui.HeaderSub.Text = 'Last step: your browser'
        Update-PlayBridgePage2
    }
    $ui.Page1.ScrollToTop(); $ui.Page2.ScrollToTop()
}

# Opens the chosen script in the browser (Violentmonkey shows its install page)
function Install-PlayBridgeScript([string]$Which) {
    $ui = $script:UI
    $script:State.Script = $Which
    $name = $ScriptFiles[$Which]
    $auto = ($ui.AutoUpdate.IsChecked -eq $true)
    $mode = 'path'
    if ($script:State.Settings) { $mode = [string]$script:State.Settings.Mode }
    $addr = Get-PlayBridgeJellyfinAddress ([string]$ui.JfCombo.Text)
    if ($auto) {
        # GitHub copy: the address and the stream setting are handled by the extra steps
        Update-PlayBridgePage2
        Save-PlayBridgePage2Settings
        Open-PlayBridgeUrl ($RawUrl + $name)
        return
    }
    $text = New-PlayBridgeCustomScript $name $addr.Match ($mode -ne 'path') $false
    if (-not $text) { [void](Show-PlayBridgeBox ("File not found: {0}`n`nExtract the whole PlayBridge.zip and run Install.cmd again." -f $name) 'OK' 'Error' $ui.Window); return }
    # remembered in PlayBridge.ini: this page warns when the mode or the address changes later
    $script:State.ScriptStream = ($mode -ne 'path')
    $script:State.ScriptMatch = $addr.Match
    Update-PlayBridgePage2
    Save-PlayBridgePage2Settings
    $server = Start-PlayBridgeLocalServer
    if (-not $server) {
        # last resort: a file next to the installation, opened as a file:// address
        $file = Join-Path $InstallDir $name
        [System.IO.File]::WriteAllText($file, $text, (New-Object System.Text.UTF8Encoding $false))
        Open-PlayBridgeUrl ('file:///' + ($file -replace '\\', '/'))
        return
    }
    $server.Files[$name] = $text
    Open-PlayBridgeUrl ('http://127.0.0.1:{0}/{1}' -f $server.Port, $name)
}

function Start-PlayBridgeDiscovery {
    # shares on your NAS (no drive letter needed) and Jellyfin servers, in the background
    $servers = @(Get-PlayBridgeServers @($script:State.Shares))
    if ($servers.Count) {
        $script:State.ScanningShares = $true
        Update-PlayBridgeDrivesUi
        Start-PlayBridgeJob $SharesJobScript @($NetSharesCode, [string[]]$servers) {
            param($r)
            $script:State.ScanningShares = $false
            Add-PlayBridgeShares @($r)
            Update-PlayBridgeDrivesUi
        } 20000
    }
    $hosts = @('localhost') + $servers
    Start-PlayBridgeJob $JellyfinJobScript @(, [string[]]$hosts) {
        param($r)
        $ui = $script:UI
        $found = @(@($r) | ForEach-Object { $a = ([string]$_).Split('|'); @{ Url = $a[0]; Name = $a[1]; Version = $a[2] } })
        foreach ($f in $found) { if (-not ($ui.JfCombo.Items -contains $f.Url)) { [void]$ui.JfCombo.Items.Add($f.Url) } }
        if (-not $found.Count) { return }
        if (-not $script:State.JellyfinSaved) {
            $pick = @($found | Where-Object { $_.Url -match 'localhost' }) + @($found)
            $ui.JfCombo.Text = $pick[0].Url
        }
        $ui.JfHint.Text = 'Found: ' + (($found | ForEach-Object { '{0} ({1}, {2})' -f $_.Name, $_.Url, $_.Version }) -join ',  ')
        Update-PlayBridgePage2
    } 8000
}

function Show-PlayBridgeMainWindow {
    $ui = New-PlayBridgeWindow $MainXaml
    $script:UI = $ui
    $script:JobTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:JobTimer.Interval = [TimeSpan]::FromMilliseconds(150)
    $script:JobTimer.Add_Tick({ Update-PlayBridgeJobs })

    $start = Get-PlayBridgeStartSettings
    $script:State = @{
        Paths          = New-Object System.Collections.ArrayList
        Shares         = New-Object System.Collections.ArrayList
        Custom         = @($start.Custom)
        Updating       = $true
        InPlace        = (Test-PlayBridgeSameFolder $SetupDir $InstallDir)
        WasInstalled   = [System.IO.File]::Exists((Join-Path $InstallDir 'PlayBridge.ini'))
        Installed      = $false
        Settings       = $null
        OtherItem      = $null
        Busy           = $false
        Cancel         = $false
        PendingRule    = $null
        ScanningShares = $false
        Jellyfin       = ''
        JellyfinSaved  = [bool]$start.Jellyfin
        Script         = [string]$start.Script
        ScriptStream   = $start.ScriptStream
        ScriptMatch    = [string]$start.ScriptMatch
    }
    foreach ($r in @($start.Paths)) { if ($r) { [void]$script:State.Paths.Add($r) } }
    Add-PlayBridgeShares @($start.Shares)
    Add-PlayBridgeShares @(Get-PlayBridgeHistoryShares)
    if ($script:State.InPlace -or $script:State.WasInstalled) {
        # opened to change settings: page 2 is available right away with the saved settings
        $script:State.Settings = @{ Mode = $start.Mode; Jellyfin = $start.Jellyfin }
    }

    $logo = Get-PlayBridgeImage 'PlayBridge-logo.png'
    if ($logo) { $ui.Logo.Source = $logo }
    $preview = Get-PlayBridgeImage 'PlayBridgeIcon.png'
    if ($preview) { $ui.IconPreview.Source = $preview } else { $ui.IconPreview.Visibility = 'Collapsed' }
    $ui.VersionText.Text = 'v' + $PlayBridge_Version

    # 1. player
    $players = @(Find-PlayBridgePlayers)
    foreach ($p in $players) {
        $item = New-Object System.Windows.Controls.ComboBoxItem
        $label = '{0}      {1}' -f $p.Name, $p.Path
        if ($p.Default) { $label = '{0}  (Windows default for videos)      {1}' -f $p.Name, $p.Path }
        $item.Content = $label
        $item.Tag = $p.Path
        [void]$ui.PlayerCombo.Items.Add($item)
    }
    $other = New-Object System.Windows.Controls.ComboBoxItem
    $other.Content = 'Other player or custom path (Browse...)'
    $other.Tag = ''
    [void]$ui.PlayerCombo.Items.Add($other)
    $script:State.OtherItem = $other
    $player = $start.Player
    if (-not $player -and $players.Count) { $player = $players[0].Path }   # Windows default player first
    $ui.PlayerPath.Text = [string]$player
    Select-PlayBridgePlayerItem
    $info = Get-PlayBridgePlayerInfo $player
    if ($null -ne $start.Arguments) { $ui.PlayerArgs.Text = [string]$start.Arguments }
    elseif ($info.Fullscreen) { $ui.PlayerArgs.Text = $info.Fullscreen }
    $ui.Fullscreen.IsChecked = (([string]$ui.PlayerArgs.Text) -match '(^|\s)(/fullscreen|--fullscreen|--fs|-fullscreen)(\s|$)')

    # 2. mode
    foreach ($m in @(@('path', 'Windows file path'), @('path+stream', 'Windows file path, or Jellyfin stream when not found'),
            @('stream', 'Jellyfin stream link'), @('download', 'Jellyfin download link'))) {
        $item = New-Object System.Windows.Controls.ComboBoxItem
        $item.Content = $m[1]
        $item.Tag = $m[0]
        [void]$ui.ModeCombo.Items.Add($item)
        if ($m[0] -eq $start.Mode) { $ui.ModeCombo.SelectedItem = $item }
    }
    if (-not $ui.ModeCombo.SelectedItem) { $ui.ModeCombo.SelectedIndex = 0 }
    Update-PlayBridgePlayerUi $false

    # 3. NAS
    Update-PlayBridgeDrivesUi
    Update-PlayBridgeMapList

    # options
    if (Test-PlayBridgeVBScript) {
        $ui.HideWindow.IsChecked = ($start.HideWindow -ne $false)
    } else {
        $ui.HideWindow.IsChecked = $false
        $ui.HideWindow.IsEnabled = $false
        Set-PlayBridgeText $ui.HideNote 'Not available: VBScript is missing on this Windows (Settings > System > Optional features > VBSCRIPT). A PowerShell window flashes briefly when a video starts.' '#9A5B00'
    }

    $infoLines = @('Next saves these settings and installs PlayBridge for your Windows account only (no admin rights) in ' + $InstallDir)
    if ($start.Source -and $start.Source -ne 'current') {
        $infoLines += ('Imported from your previous installation ({0}). The old files are not changed.' -f $start.Source)
        if (@($start.Custom).Count) { $infoLines += ('{0} line(s) of your own will be kept in PlayBridge-custom.ps1.' -f @($start.Custom).Count) }
    }
    $ui.InstallInfo.Text = $infoLines -join "`n"

    # page 2: browsers, Jellyfin address, last choices
    $browsers = @(Find-PlayBridgeBrowsers)
    $saved = [string]$start.Browser
    foreach ($b in $browsers) {
        $sel = ($saved -eq 'desktop' -and $b.Kind -eq 'desktop') -or ($saved -and $b.Kind -ne 'desktop' -and [string]::Equals($b.Path, $saved, [System.StringComparison]::OrdinalIgnoreCase))
        [void](Add-PlayBridgeBrowserItem $b $sel)
    }
    if (-not $ui.BrowserCombo.SelectedItem -and $saved -and $saved -ne 'desktop' -and (Test-Path -LiteralPath $saved -PathType Leaf)) {
        # browser picked with Browse... last time
        [void](Add-PlayBridgeBrowserItem @{ Name = ([System.IO.Path]::GetFileNameWithoutExtension($saved) + '   (' + $saved + ')'); Path = $saved; Kind = (Get-PlayBridgeBrowserKind $saved); Default = $false } $true)
    }
    if (-not $ui.BrowserCombo.SelectedItem) { $ui.BrowserCombo.SelectedIndex = 0 }
    $jf = [string]$start.Jellyfin
    if (-not $jf) { $jf = $DefaultJellyfin }
    [void]$ui.JfCombo.Items.Add($DefaultJellyfin)
    $ui.JfCombo.Text = $jf
    $script:State.Jellyfin = (Get-PlayBridgeJellyfinAddress $jf).Base
    $ui.AutoUpdate.IsChecked = ($start.AutoUpdate -eq $true)
    $script:State.Updating = $false

    # --- events: page 1
    $ui.PlayerCombo.Add_SelectionChanged({ Invoke-PlayBridgeSafe {
                if ($script:State.Updating) { return }
                $item = $script:UI.PlayerCombo.SelectedItem
                if (-not $item) { return }
                if ($item.Tag) {
                    $script:State.Updating = $true
                    $script:UI.PlayerPath.Text = [string]$item.Tag
                    $script:State.Updating = $false
                    Update-PlayBridgePlayerUi $true
                } else {
                    Invoke-PlayBridgeBrowsePlayer
                }
            } })
    $ui.PlayerPath.Add_TextChanged({ Invoke-PlayBridgeSafe {
                if ($script:State.Updating) { return }
                $script:State.Updating = $true
                Select-PlayBridgePlayerItem
                $script:State.Updating = $false
                Update-PlayBridgePlayerUi $true
            } })
    $ui.BrowsePlayer.Add_Click({ Invoke-PlayBridgeSafe { Invoke-PlayBridgeBrowsePlayer } })
    $ui.Fullscreen.Add_Checked({ Invoke-PlayBridgeSafe { if (-not $script:State.Updating) { Set-PlayBridgeFullscreenArg $true } } })
    $ui.Fullscreen.Add_Unchecked({ Invoke-PlayBridgeSafe { if (-not $script:State.Updating) { Set-PlayBridgeFullscreenArg $false } } })
    $ui.ModeCombo.Add_SelectionChanged({ Invoke-PlayBridgeSafe { Update-PlayBridgeModeUi } })
    $ui.CheckBtn.Add_Click({ Invoke-PlayBridgeSafe { Invoke-PlayBridgePathTest } })
    $ui.TestPath.Add_KeyDown({ param($s, $e) if ($e.Key -eq [System.Windows.Input.Key]::Return) { Invoke-PlayBridgeSafe { Invoke-PlayBridgePathTest } } })
    $ui.TestMatches.Add_SelectionChanged({ Invoke-PlayBridgeSafe {
                $sel = [string]$script:UI.TestMatches.SelectedItem
                if ($sel) { Show-PlayBridgeCheckRule (Format-PlayBridgePath ([string]$script:UI.TestPath.Text).Trim().Trim('"')) $sel }
            } })
    $ui.SaveLinkBtn.Add_Click({ Invoke-PlayBridgeSafe {
                if (-not $script:State.PendingRule) { return }
                Add-PlayBridgeRule $script:State.PendingRule
                Update-PlayBridgeMapList
                Reset-PlayBridgeCheckUi
                Set-PlayBridgeText $script:UI.TestResult 'Folder link added. It is saved when you click Next.' '#137333'
            } })
    $ui.PickFileBtn.Add_Click({ Invoke-PlayBridgeSafe { Invoke-PlayBridgePickForCheck $true } })
    $ui.PickFolderBtn.Add_Click({ Invoke-PlayBridgeSafe { Invoke-PlayBridgePickForCheck $false } })
    $ui.RemoveMap.Add_Click({ Invoke-PlayBridgeSafe {
                $i = $script:UI.MapList.SelectedIndex
                if ($i -ge 0 -and $i -lt $script:State.Paths.Count) { $script:State.Paths.RemoveAt($i); Update-PlayBridgeMapList }
            } })

    # --- events: page 2
    $ui.BrowserCombo.Add_SelectionChanged({ Invoke-PlayBridgeSafe { if (-not $script:State.Updating) { Update-PlayBridgePage2; Save-PlayBridgePage2Settings } } })
    $ui.JfCombo.Add_LostFocus({ Invoke-PlayBridgeSafe { Update-PlayBridgePage2; Save-PlayBridgePage2Settings } })
    $ui.JfCombo.Add_SelectionChanged({ Invoke-PlayBridgeSafe {
                $sel = [string]$script:UI.JfCombo.SelectedItem
                if ($sel) { $script:UI.JfCombo.Text = $sel }
                Update-PlayBridgePage2; Save-PlayBridgePage2Settings
            } })
    $ui.AutoUpdate.Add_Checked({ Invoke-PlayBridgeSafe { if (-not $script:State.Updating) { Update-PlayBridgePage2; Save-PlayBridgePage2Settings } } })
    $ui.AutoUpdate.Add_Unchecked({ Invoke-PlayBridgeSafe { if (-not $script:State.Updating) { Update-PlayBridgePage2; Save-PlayBridgePage2Settings } } })
    $ui.VMBtn.Add_Click({ Invoke-PlayBridgeSafe {
                $b = Get-PlayBridgeSelectedBrowser
                $kind = 'other'
                if ($b) { $kind = $b.Kind }
                Open-PlayBridgeUrl $VMStore[$kind]
            } })
    $ui.BrowseBrowser.Add_Click({ Invoke-PlayBridgeSafe {
                $dlg = New-Object Microsoft.Win32.OpenFileDialog
                $dlg.Title = 'Choose your browser (.exe)'
                $dlg.Filter = 'Programs (*.exe)|*.exe'
                if ($dlg.ShowDialog($script:UI.Window) -ne $true) { return }
                $exe = $dlg.FileName
                [void](Add-PlayBridgeBrowserItem @{ Name = ([System.IO.Path]::GetFileNameWithoutExtension($exe) + '   (' + $exe + ')'); Path = $exe; Kind = (Get-PlayBridgeBrowserKind $exe); Default = $false } $true)
            } })
    $ui.TestBrowserBtn.Add_Click({ Invoke-PlayBridgeSafe {
                $server = Start-PlayBridgeLocalServer
                if (-not $server) { [void](Show-PlayBridgeBox 'The local test page could not be started. Use "Test with a video file..." instead.' 'OK' 'Warning' $script:UI.Window); return }
                $server.Files['playbridge-test.html'] = Get-PlayBridgeBrowserTestPage
                Open-PlayBridgeUrl ('http://127.0.0.1:{0}/playbridge-test.html' -f $server.Port)
            } })
    $ui.ScriptABtn.Add_Click({ Invoke-PlayBridgeSafe { Install-PlayBridgeScript 'A' } })
    $ui.ScriptBBtn.Add_Click({ Invoke-PlayBridgeSafe { Install-PlayBridgeScript 'B' } })
    $ui.CopyMatchBtn.Add_Click({ Invoke-PlayBridgeSafe { [System.Windows.Clipboard]::SetText($script:UI.MatchText.Text); $script:UI.CopyMatchBtn.Content = 'Copied' } })
    $ui.StreamBtn.Add_Click({ Invoke-PlayBridgeSafe { Update-PlayBridgePage2; Save-PlayBridgePage2Settings; Open-PlayBridgeUrl ($script:State.Jellyfin + '/web/index.html?playbridge-stream=on#/home?playbridge-stream=on') } })
    $ui.OpenJfBtn.Add_Click({ Invoke-PlayBridgeSafe {
                Update-PlayBridgePage2; Save-PlayBridgePage2Settings
                $b = Get-PlayBridgeSelectedBrowser
                if ($b -and $b.Kind -eq 'desktop') {
                    if ($b.Path -and (Test-Path -LiteralPath $b.Path)) { Start-Process -FilePath $b.Path } else { [void](Show-PlayBridgeBox 'The Jellyfin app was not found on this PC: open it yourself.' 'OK' 'Information' $script:UI.Window) }
                    return
                }
                Open-PlayBridgeUrl ($script:State.Jellyfin + '/web/')
            } })
    $ui.TestFileBtn.Add_Click({ Invoke-PlayBridgeSafe {
                $dlg = New-Object Microsoft.Win32.OpenFileDialog
                $dlg.Title = 'Choose a video to test PlayBridge'
                $dlg.Filter = 'Videos|*.mkv;*.mp4;*.m4v;*.avi;*.m2ts;*.ts;*.mov;*.wmv;*.webm;*.iso;*.mpg|All files (*.*)|*.*'
                if ($dlg.ShowDialog($script:UI.Window) -eq $true) { Start-Process -FilePath (ConvertTo-PlayBridgeUrl $dlg.FileName) }
            } })
    $ui.InjectorBtn.Add_Click({ Invoke-PlayBridgeSafe { Open-PlayBridgeUrl $InjectorUrl } })
    $ui.CopyInjectorBtn.Add_Click({ Invoke-PlayBridgeSafe {
                $mode = 'path'
                if ($script:State.Settings) { $mode = [string]$script:State.Settings.Mode }
                $text = Get-PlayBridgeInjectorScript ($mode -ne 'path')
                if ($text) { [System.Windows.Clipboard]::SetText($text); $script:UI.CopyInjectorBtn.Content = 'Copied: paste it in JS Injector' }
            } })

    # --- events: footer
    $ui.HelpBtn.Add_Click({ Invoke-PlayBridgeSafe { Open-PlayBridgeUrl $ReadmeUrl } })
    $ui.BackBtn.Add_Click({ Invoke-PlayBridgeSafe { Save-PlayBridgePage2Settings; Show-PlayBridgePage 1 } })
    $ui.NextBtn.Add_Click({ Invoke-PlayBridgeSafe {
                if ($script:UI.Page1.Visibility -eq 'Visible') { Invoke-PlayBridgeInstall }
                else { Save-PlayBridgePage2Settings; $script:UI.Window.Close() }
            } })
    $ui.CloseBtn.Add_Click({ $script:UI.Window.Close() })
    $ui.OpenFolderBtn.Add_Click({ Invoke-PlayBridgeSafe { Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f $InstallDir) } })
    $ui.UninstallBtn.Add_Click({ Invoke-PlayBridgeSafe { if (Invoke-PlayBridgeUninstall $script:UI.Window) { $script:UI.Window.Close() } } })
    $ui.Window.Add_ContentRendered({ Invoke-PlayBridgeSafe { Start-PlayBridgeDiscovery } })
    $ui.Window.Add_Closing({ $script:State.Cancel = $true; Stop-PlayBridgeLocalServer })

    Show-PlayBridgePage 1
    [void]$ui.Window.ShowDialog()
}

# ---------------------------------------------------------------------------

if ($NoGui) { return }

try {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms -ErrorAction Stop
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $script:State = @{ Paths = New-Object System.Collections.ArrayList; Shares = New-Object System.Collections.ArrayList; Custom = @() }
    if ($MapUrl) {
        $cfg = Read-PlayBridgeConfig (Join-Path $SetupDir 'PlayBridge.ini')
        foreach ($r in @($cfg.Paths)) { if ($r) { [void]$script:State.Paths.Add($r) } }
        Add-PlayBridgeShares @($cfg.Shares)
        Add-PlayBridgeShares @(Get-PlayBridgeHistoryShares)
        [void](Show-PlayBridgeMapWindow $MapUrl)
    } elseif ($Uninstall) {
        [void](Invoke-PlayBridgeUninstall $null)
    } else {
        Show-PlayBridgeMainWindow
    }
    Stop-PlayBridgeLocalServer
    [Environment]::Exit(0)
} catch {
    $err = ($_ | Out-String)
    try { [System.IO.File]::WriteAllText((Join-Path $env:TEMP 'PlayBridge-Setup-error.txt'), $err) } catch { }
    try { [void][System.Windows.MessageBox]::Show("PlayBridge Setup stopped because of an error:`n`n" + $_.Exception.Message, 'PlayBridge', 'OK', 'Error') }
    catch { Write-Host $err }
    [Environment]::Exit(1)
}
