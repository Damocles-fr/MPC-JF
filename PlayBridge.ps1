# PlayBridge launcher: opens Jellyfin videos in your own video player (Windows).
# Started by your browser through playbridge:// links (registered by Install.cmd).
# Settings: PlayBridge.ini next to this file. Change them with Start menu > PlayBridge Settings
# (or Install.cmd). Started without a link, this file opens PlayBridge Settings.
# https://github.com/Damocles-fr/MPC-JF
param(
    [string]$Url,
    [switch]$LoadOnly
)

$PlayBridge_Version = '13.0.0'
$PlayBridge_DefaultPlayer = 'C:\Program Files\MPC-BE\mpc-be64.exe'
$PlayBridge_DefaultArguments = '/fullscreen'
# Longest wait for one "is the file there?" check. Past that (NAS disks waking up, slow network),
# the player is started anyway and waits for the disk itself.
$PlayBridge_CheckTimeoutMs = 2000
# Longest total time spent checking before the player is started.
$PlayBridge_CheckBudgetMs = 5000
# Jellyfin links: longest wait for Jellyfin's first answer before the player starts anyway. Jellyfin answers
# in a few ms when its disks are awake; sleeping NAS disks can take half a minute, longer than some players wait.
$PlayBridge_ServerWaitMs = 60000
# A small "Waiting for Jellyfin" window (with Cancel) appears when the answer takes longer than this.
$PlayBridge_WaitWindowMs = 1500
# How videos are opened (PlayBridge.ini [Options] Mode=)
$PlayBridge_Modes = @('path', 'path+stream', 'stream', 'download')

# ---------------------------------------------------------------------------
# playbridge:// links (and mpcjf:// links of older scripts)
# ---------------------------------------------------------------------------

# "playbridge://D%3A/Films/x.mkv?server=...&id=...&token=..." => Path "D:/Films/x.mkv" + Info (stream data, if any).
# Stream data is only sent by the browser scripts when stream links are turned on.
function Split-PlayBridgeUrl([string]$Url) {
    $u = ([string]$Url).Trim().Trim('"')
    $u = $u -replace '^(playbridge|mpcjf):(//)?', ''
    $info = @{}
    $q = $u.IndexOf('?')    # a "?" inside the path is always encoded (%3F) by the scripts
    if ($q -ge 0) {
        $pairs = @{}
        foreach ($kv in $u.Substring($q + 1).Split('&')) {
            $i = $kv.IndexOf('=')
            if ($i -lt 1) { continue }
            $v = $kv.Substring($i + 1).Replace('+', ' ')
            try { $v = [System.Uri]::UnescapeDataString($v) } catch { }
            $pairs[$kv.Substring(0, $i).ToLowerInvariant()] = $v
        }
        if ($pairs.ContainsKey('id') -and $pairs.ContainsKey('server')) {
            $info = $pairs
            $u = $u.Substring(0, $q)
        }
    }
    try { $u = [System.Uri]::UnescapeDataString($u) } catch { }
    return @{ Path = $u; Info = $info }
}

function ConvertFrom-PlayBridgeUrl([string]$Url) { return (Split-PlayBridgeUrl $Url).Path }

# Same encoding as the browser scripts (toPlayBridgeUrl), used by the setup "Test" button
function ConvertTo-PlayBridgeUrl([string]$Path) {
    $forward = ([string]$Path) -replace '\\', '/'
    return 'playbridge://' + ([System.Uri]::EscapeDataString($forward) -replace '%2F', '/')
}

# Jellyfin link of the video: original file, no conversion.
# ApiKey works since Jellyfin 10.8 (api_key, kept for older servers, is off by default since Jellyfin 12).
function Get-PlayBridgeStreamUrl($Info, [string]$Mode) {
    if (-not $Info -or -not $Info.Count) { return $null }
    $server = ([string]$Info.server).Trim().TrimEnd('/')
    $id = [string]$Info.id
    $token = [string]$Info.token
    if ($server -notmatch '^https?://[^\s/?#]+' -or $id -notmatch '^[0-9A-Fa-f-]{16,40}$' -or -not $token) { return $null }
    $key = [System.Uri]::EscapeDataString($token)
    if ($Mode -eq 'download') { return '{0}/Items/{1}/Download?ApiKey={2}&api_key={2}' -f $server, $id, $key }
    $ext = (([string]$Info.c).Split(',')[0]).Trim().ToLowerInvariant()
    if ($ext -match '^[a-z0-9]{1,8}$') { $ext = '.' + $ext } else { $ext = '' }
    $link = '{0}/Videos/{1}/stream{2}?static=true' -f $server, $id, $ext
    if ([string]$Info.ms -match '^[0-9A-Fa-f-]{16,40}$') { $link += '&mediaSourceId=' + $Info.ms }
    return $link + ('&ApiKey={0}&api_key={0}' -f $key)
}

# Never write the Jellyfin access token in the log
function Hide-PlayBridgeToken([string]$Text) {
    return ([string]$Text) -replace '((?:token|ApiKey|api_key)=)[^&\s]+', '$1***'
}

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

# Normalizes any path to the Windows style: backslashes, no doubled separators
function Format-PlayBridgePath([string]$Path) {
    $p = ([string]$Path).Trim() -replace '/', '\'
    $p = $p -replace '^\\\\\?\\UNC\\', '\\'       # \\?\UNC\server\... => \\server\...
    $p = $p -replace '^\\\\\?\\', ''              # \\?\X:\...         => X:\...
    if ($p -match '^\\\\[^\\]') {                 # UNC path: keep the leading \\
        $p = '\\' + ($p.Substring(2) -replace '\\{2,}', '\')
    } else {
        $p = $p -replace '\\{2,}', '\'
    }
    $p = $p -replace '^\\([A-Za-z]:)', '$1'         # "\D:\..." => "D:\..."
    $p = $p -replace '^([A-Za-z])\\', '$1:\'        # "D\..." (colon lost) => "D:\..."
    $p = $p -replace '^([A-Za-z]):(?!\\)', '$1:\'   # "D:..." => "D:\..."
    if ($p.Length -gt 1 -and $p.EndsWith('\') -and $p -notmatch '^[A-Za-z]:\\$') { $p = $p.TrimEnd('\') }
    return $p
}

# drive = "D:\...", unc = "\\server\share\...", linux = path seen by a NAS / Linux / Docker server
function Get-PlayBridgePathKind([string]$Path) {
    if ($Path -match '^[A-Za-z]:\\') { return 'drive' }
    if ($Path -match '^\\\\[^\\]+\\[^\\]+') { return 'unc' }
    if ($Path -match '^\\[^\\]') { return 'linux' }
    return 'other'
}

# Splits a normalized path into its root ("D:\", "\\server\share", "\") and its folder/file names
function Split-PlayBridgePath([string]$Path) {
    $kind = Get-PlayBridgePathKind $Path
    $all = @($Path.Split('\') | Where-Object { $_ -ne '' })
    if ($kind -eq 'drive') { return @{ Kind = $kind; Root = $all[0] + '\'; Parts = @($all | Select-Object -Skip 1) } }
    if ($kind -eq 'unc') { return @{ Kind = $kind; Root = '\\' + $all[0] + '\' + $all[1]; Parts = @($all | Select-Object -Skip 2) } }
    if ($kind -eq 'linux') { return @{ Kind = $kind; Root = '\'; Parts = $all } }
    return @{ Kind = $kind; Root = ''; Parts = $all }
}

function Join-PlayBridgePath([string]$Root, $Parts) {
    $rest = (@($Parts) | Where-Object { $_ }) -join '\'
    if (-not $rest) { return $Root }
    if ($Root.EndsWith('\')) { return $Root + $rest }
    return $Root + '\' + $rest
}

# How a path is shown to people: Jellyfin style (/share/...) for NAS paths
function ConvertTo-PlayBridgeDisplayPath([string]$Path) {
    if ((Get-PlayBridgePathKind $Path) -eq 'linux') { return ($Path -replace '\\', '/') }
    return $Path
}

# ---------------------------------------------------------------------------
# Settings (PlayBridge.ini)
# ---------------------------------------------------------------------------

function Read-PlayBridgeTextFile([string]$File) {
    # UTF-8 first, then the Windows ANSI code page for files saved by old editors
    $lines = [System.IO.File]::ReadAllLines($File, [System.Text.Encoding]::UTF8)
    if (($lines -join "`n").Contains([string][char]0xFFFD)) { $lines = [System.IO.File]::ReadAllLines($File, [System.Text.Encoding]::Default) }
    return $lines
}

function New-PlayBridgeConfig {
    return @{ Player = ''; Arguments = $null; HideWindow = $null; Mode = 'path'; Jellyfin = ''; Paths = @(); Shares = @();
        Browser = ''; AutoUpdate = $null; Script = ''; ScriptStream = $null; ScriptMatch = '' }
}

function Read-PlayBridgeConfig([string]$File) {
    $cfg = New-PlayBridgeConfig
    if (-not $File -or -not [System.IO.File]::Exists($File)) { return $cfg }
    $section = ''
    $paths = New-Object System.Collections.Generic.List[object]
    $shares = New-Object System.Collections.Generic.List[string]
    foreach ($raw in (Read-PlayBridgeTextFile $File)) {
        $line = $raw.Trim()
        if ($line -eq '' -or $line.StartsWith(';') -or $line.StartsWith('#')) { continue }
        if ($line -match '^\[(.+)\]$') { $section = $Matches[1].Trim().ToLowerInvariant(); continue }
        if ($section -eq 'shares') {
            $s = Format-PlayBridgePath $line.Trim('"')
            if ((Get-PlayBridgePathKind $s) -eq 'unc') { $shares.Add($s) }
            continue
        }
        $i = $line.IndexOf('=')
        if ($i -lt 1) { continue }
        $key = $line.Substring(0, $i).Trim()
        $val = $line.Substring($i + 1).Trim()
        if ($section -eq 'player') {
            if ($key -eq 'Path') { $cfg.Player = $val.Trim('"') }
            elseif ($key -eq 'Arguments') { $cfg.Arguments = $val }
        } elseif ($section -eq 'options') {
            if ($key -eq 'HideWindow') { $cfg.HideWindow = ($val -match '^(1|true|yes|on)$') }
            elseif ($key -eq 'Mode' -and $PlayBridge_Modes -contains $val.ToLowerInvariant()) { $cfg.Mode = $val.ToLowerInvariant() }
            elseif ($key -eq 'Jellyfin') { $cfg.Jellyfin = $val }
        } elseif ($section -eq 'setup') {
            if ($key -eq 'Browser') { $cfg.Browser = $val.Trim('"') }
            elseif ($key -eq 'AutoUpdate') { $cfg.AutoUpdate = ($val -match '^(1|true|yes|on)$') }
            elseif ($key -eq 'Script') { $cfg.Script = $val.ToUpperInvariant() }
            elseif ($key -eq 'ScriptStream' -and $val) { $cfg.ScriptStream = ($val -match '^(1|true|yes|on)$') }
            elseif ($key -eq 'ScriptMatch') { $cfg.ScriptMatch = $val }
        } elseif ($section -eq 'paths') {
            $to = $val.Trim('"')
            if ($to) { $paths.Add(@{ From = (Format-PlayBridgePath $key.Trim('"')); To = (Format-PlayBridgePath $to) }) }
        }
    }
    $cfg.Paths = $paths.ToArray()
    $cfg.Shares = $shares.ToArray()
    return $cfg
}

function Write-PlayBridgeConfig([string]$File, $Config) {
    $mode = [string]$Config.Mode
    if ($PlayBridge_Modes -notcontains $mode) { $mode = 'path' }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('; PlayBridge settings, written by PlayBridge Setup.')
    $lines.Add('; Change them with Start menu > PlayBridge Settings (or Install.cmd). Lines starting with ; are comments.')
    $lines.Add('')
    $lines.Add('[Player]')
    $lines.Add('Path=' + $Config.Player)
    $lines.Add('Arguments=' + $Config.Arguments)
    $lines.Add('')
    $lines.Add('[Options]')
    $lines.Add('; Mode: path, path+stream, stream or download')
    $lines.Add('Mode=' + $mode)
    $lines.Add('HideWindow=' + $(if ($Config.HideWindow) { '1' } else { '0' }))
    $lines.Add('Jellyfin=' + [string]$Config.Jellyfin)
    $lines.Add('')
    $lines.Add('[Setup]')
    $lines.Add('; Last choices of the setup window')
    $lines.Add('Browser=' + [string]$Config.Browser)
    $lines.Add('AutoUpdate=' + $(if ($Config.AutoUpdate) { '1' } else { '0' }))
    $lines.Add('Script=' + [string]$Config.Script)
    $lines.Add('; Made for: stream links and address of the script last installed from this PC (A or B)')
    $lines.Add('ScriptStream=' + $(if ($null -eq $Config.ScriptStream) { '' } elseif ($Config.ScriptStream) { '1' } else { '0' }))
    $lines.Add('ScriptMatch=' + [string]$Config.ScriptMatch)
    $lines.Add('')
    $lines.Add('[Paths]')
    $lines.Add('; Folder links: Jellyfin folder = Windows folder. Only needed when PlayBridge cannot find a folder by itself.')
    $lines.Add('; Example: /share/CACHEDEV1_DATA/Movies = M:\')
    foreach ($r in @($Config.Paths)) {
        if ($r -and $r.From -and $r.To) { $lines.Add((ConvertTo-PlayBridgeDisplayPath $r.From) + ' = ' + $r.To) }
    }
    $lines.Add('')
    $lines.Add('[Shares]')
    $lines.Add('; Network shares without a drive letter, found by PlayBridge Setup. Used like mapped drives.')
    foreach ($s in @($Config.Shares)) { if ($s) { $lines.Add([string]$s) } }
    [System.IO.File]::WriteAllLines($File, $lines.ToArray(), (New-Object System.Text.UTF8Encoding $true))
}

# ---------------------------------------------------------------------------
# Finding the Windows path of a Jellyfin path
# ---------------------------------------------------------------------------

# 1. Folder links from PlayBridge.ini, most specific first: "/share/external/DEV3502_1 = U:\"
function Get-PlayBridgeRuleMatches([string]$Path, $Rules) {
    foreach ($r in @(@($Rules) | Where-Object { $_ -and $_.From -and $_.To } | Sort-Object { $_.From.Length } -Descending)) {
        $from = [string]$r.From
        if (-not $Path.StartsWith($from, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $rest = $Path.Substring($from.Length)
        # "\Movies" must not match "\Movies2\..."
        if ($rest -ne '' -and -not $rest.StartsWith('\') -and -not $from.EndsWith('\')) { continue }
        Join-PlayBridgePath $r.To @($rest.Split('\'))
    }
}

function New-PlayBridgeShareEntry([string]$Root, [string]$Unc, [string]$Source) {
    $Unc = ([string]$Unc).TrimEnd('\')
    return @{
        Root   = $Root
        Unc    = $Unc
        Parts  = @($Unc.Split('\') | Where-Object { $_ -ne '' } | Select-Object -Skip 1)  # share (and subfolders), without the server
        Source = $Source
    }
}

# Mapped network drives (M: = \\server\share), read locally: no disk or network access.
# Includes drives that Windows reconnects at sign-in but has not reconnected yet.
function Get-PlayBridgeNetworkDrives {
    $seen = @{}
    foreach ($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        $unc = [string]$d.DisplayRoot
        if ($d.Name.Length -ne 1 -or $unc -notmatch '^\\\\[^\\]+\\[^\\]') { continue }
        $root = $d.Name.ToUpperInvariant() + ':\'
        $seen[$root] = $true
        New-PlayBridgeShareEntry $root $unc 'drive'
    }
    try {
        $net = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Network')
        if ($net) {
            foreach ($letter in $net.GetSubKeyNames()) {
                $root = $letter.ToUpperInvariant() + ':\'
                if ($letter.Length -ne 1 -or $seen[$root]) { continue }
                $k = $net.OpenSubKey($letter)
                $unc = [string]$k.GetValue('RemotePath')
                $k.Close()
                if ($unc -match '^\\\\[^\\]+\\[^\\]') { $seen[$root] = $true; New-PlayBridgeShareEntry $root $unc 'saved drive' }
            }
            $net.Close()
        }
    } catch { }
}

# Mapped drives + shares without a letter found by the setup ([Shares] in PlayBridge.ini)
function Get-PlayBridgeShareRoots($Shares) {
    $list = @(Get-PlayBridgeNetworkDrives)
    $mapped = @{}
    foreach ($d in $list) { $mapped[$d.Unc.ToLowerInvariant()] = $true }
    foreach ($s in @($Shares)) {
        $u = ([string]$s).TrimEnd('\')
        if ($u -and -not $mapped[$u.ToLowerInvariant()]) { $list += New-PlayBridgeShareEntry $u $u 'share' }
    }
    return $list
}

# 2. Share names: "/share/CACHEDEV3_DATA/SSD2TB/Films/x.mkv" + "M: = \\nas\SSD2TB" => "M:\Films\x.mkv"
#    Text matching only, best matches first.
function Get-PlayBridgeShareMatches([string]$Path, $Drives) {
    $sp = Split-PlayBridgePath $Path
    $parts = @($sp.Parts)
    if ($sp.Kind -eq 'unc') { $parts = @(([string]$sp.Root).TrimStart('\').Split('\')[1]) + $parts }
    $found = New-Object System.Collections.Generic.List[object]
    foreach ($d in @($Drives)) {
        $dp = @($d.Parts)
        for ($s = 0; $s -lt $dp.Count; $s++) {
            # whole share path first ("Media\Films"), then its last folders only ("Films")
            $want = @($dp[$s..($dp.Count - 1)])
            $n = $want.Count
            for ($i = 0; $i -le $parts.Count - $n - 1; $i++) {   # at least one name must remain after the share
                $same = $true
                for ($j = 0; $j -lt $n; $j++) { if ($parts[$i + $j] -ne $want[$j]) { $same = $false; break } }
                if ($same) {
                    $found.Add(@{ Path = (Join-PlayBridgePath $d.Root @($parts[($i + $n)..($parts.Count - 1)])); Score = $n; Index = $i })
                }
            }
        }
    }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $found | Sort-Object @{ Expression = { $_.Score }; Descending = $true }, @{ Expression = { $_.Index }; Descending = $false } |
        Where-Object { $seen.Add($_.Path) } | ForEach-Object { $_.Path }
}

# Does the file (or folder) exist? $true / $false, or $null when there is no answer in time
# (NAS disks waking up, offline network drive) or the path is too long to be checked.
# The check runs in a tiny separate runspace so that a stuck network drive can never block PlayBridge.
$script:PlayBridgeChecker = $null
function Test-PlayBridgePath([string]$Path, [int]$TimeoutMs = $PlayBridge_CheckTimeoutMs, [scriptblock]$OnWait) {
    if (-not $Path -or $Path.Length -ge 250) { return $null }
    try {
        if (-not $script:PlayBridgeChecker) {
            $iss = [System.Management.Automation.Runspaces.InitialSessionState]::Create()
            $iss.LanguageMode = 'FullLanguage'
            $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($iss)
            $rs.Open()
            $ps = [System.Management.Automation.PowerShell]::Create()
            $ps.Runspace = $rs
            $script:PlayBridgeChecker = $ps
        }
        $ps = $script:PlayBridgeChecker
        $ps.Commands.Clear()
        [void]$ps.AddScript('param($p) [System.IO.File]::Exists($p) -or [System.IO.Directory]::Exists($p)').AddArgument($Path)
        $async = $ps.BeginInvoke()
        if ($OnWait) {
            # setup window: keep it responsive, $OnWait returns $true to stop waiting
            $wait = [System.Diagnostics.Stopwatch]::StartNew()
            while (-not ($answered = $async.AsyncWaitHandle.WaitOne(100))) {
                if ($wait.ElapsedMilliseconds -ge $TimeoutMs -or (& $OnWait)) { break }
            }
        } else {
            $answered = $async.AsyncWaitHandle.WaitOne($TimeoutMs)
        }
        if ($answered) {
            $r = $ps.EndInvoke($async)
            return [bool]($r -and $r[0])
        }
        $script:PlayBridgeChecker = $null   # still waiting for the drive: never reuse it
        return $null
    } catch {
        $script:PlayBridgeChecker = $null
        return $null
    }
}

# Looks for the end of a Jellyfin path on every drive and share at the same time (setup and folder
# assistant only, never when a video starts). "/share/external/DEV3502_1/Films/x.mkv" tries, on each root:
# U:\share\external\DEV3502_1\Films\x.mkv, U:\external\DEV3502_1\Films\x.mkv, ..., U:\Films\x.mkv, U:\x.mkv,
# then the same names inside its first two levels of folders (U:\Media\Films\x.mkv...).
# Returns the matches that keep the longest end of the path.
function Find-PlayBridgeOnDrives([string]$Path, [string[]]$Roots, [int]$TimeoutMs = 60000, [scriptblock]$OnWait) {
    $parts = @((Split-PlayBridgePath (Format-PlayBridgePath $Path)).Parts)
    if ($parts.Count -eq 0 -or -not $Roots) { return }
    # no cmdlets in this tiny runspace: .NET only
    $probe = @'
param($root, $parts)
$n = $parts.Count
function J($a, $b) { if ($a.EndsWith('\')) { return $a + $b } return $a + '\' + $b }
function Has($c) { try { return ([System.IO.File]::Exists($c) -or [System.IO.Directory]::Exists($c)) } catch { return $false } }
$best = $null; $bestK = $n
for ($k = 0; $k -lt $n; $k++) {
    $c = J $root ($parts[$k..($n - 1)] -join '\')
    if (Has $c) { $best = $c; $bestK = $k; break }
}
if ($bestK -gt 0 -and $n -gt 1) {
    $skip = '^(\$.*|System Volume Information|Windows|Program Files.*|ProgramData|Recovery|PerfLogs|AppData|@.*|#.*|\..*)$'
    $dirs = [System.Collections.Generic.List[string]]::new()
    try { foreach ($d in [System.IO.Directory]::GetDirectories($root)) { if ([System.IO.Path]::GetFileName($d) -notmatch $skip) { $dirs.Add($d) } } } catch { }
    $first = $dirs.ToArray()
    if ($first.Count -gt 300) { $first = $first[0..299] }
    foreach ($d in $first) {
        if ($dirs.Count -ge 800) { break }
        try { foreach ($e in [System.IO.Directory]::GetDirectories($d)) { if ([System.IO.Path]::GetFileName($e) -notmatch $skip) { $dirs.Add($e) } } } catch { }
    }
    foreach ($d in $dirs) {
        $name = [System.IO.Path]::GetFileName($d)
        $max = [Math]::Min($bestK, $n - 1)
        for ($k = 0; $k -lt $max; $k++) {
            if ($parts[$k] -eq $name) {
                $c = J $d ($parts[($k + 1)..($n - 1)] -join '\')
                if (Has $c) { $best = $c; $bestK = $k; break }
            }
        }
    }
}
if ($best) { "$bestK|$best" }
'@
    $jobs = New-Object System.Collections.Generic.List[object]
    foreach ($root in $Roots) {
        $iss = [System.Management.Automation.Runspaces.InitialSessionState]::Create()
        $iss.LanguageMode = 'FullLanguage'
        $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($iss)
        $rs.Open()
        $ps = [System.Management.Automation.PowerShell]::Create()
        $ps.Runspace = $rs
        [void]$ps.AddScript($probe).AddArgument($root).AddArgument($parts)
        $jobs.Add(@{ PS = $ps; Async = $ps.BeginInvoke(); Done = $false; Hit = $null })
    }
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        $pending = 0
        foreach ($j in $jobs) {
            if ($j.Done) { continue }
            if ($j.Async.IsCompleted) {
                $j.Done = $true
                try { $o = $j.PS.EndInvoke($j.Async); if ($o.Count) { $j.Hit = [string]$o[0] } } catch { }
                try { $j.PS.Runspace.Dispose(); $j.PS.Dispose() } catch { }
            } else { $pending++ }
        }
        if ($pending -eq 0 -or $watch.ElapsedMilliseconds -ge $TimeoutMs) { break }
        if ($OnWait -and (& $OnWait)) { break }   # $OnWait returns $true to stop
        Start-Sleep -Milliseconds 100
    }
    $hits = @($jobs | Where-Object { $_.Hit } | ForEach-Object {
        $k, $p = $_.Hit.Split('|', 2)
        @{ K = [int]$k; Path = $p }
    })
    if ($hits.Count -eq 0) { return }
    $best = @($hits | ForEach-Object { $_.K } | Sort-Object)[0]
    $hits | Where-Object { $_.K -eq $best } | ForEach-Object { $_.Path }
}

# Folder link deduced from a Jellyfin path and the same file seen by Windows:
# "/share/external/DEV3502_1/Films/x.mkv" + "U:\Films\x.mkv" => From "\share\external\DEV3502_1", To "U:\"
function New-PlayBridgeRule([string]$JellyfinPath, [string]$WindowsPath) {
    $j = Split-PlayBridgePath (Format-PlayBridgePath $JellyfinPath)
    $w = Split-PlayBridgePath (Format-PlayBridgePath $WindowsPath)
    $jp = @($j.Parts); $wp = @($w.Parts)
    $same = 0
    while ($same -lt $jp.Count -and $same -lt $wp.Count -and $jp[$jp.Count - 1 - $same] -eq $wp[$wp.Count - 1 - $same]) { $same++ }
    # keep at least one folder on the Jellyfin side: "/" alone would catch every path
    if ($same -gt 0 -and $same -eq $jp.Count -and $j.Kind -eq 'linux') { $same-- }
    $from = Join-PlayBridgePath $j.Root @($jp | Select-Object -First ($jp.Count - $same))
    $to = Join-PlayBridgePath $w.Root @($wp | Select-Object -First ($wp.Count - $same))
    return @{ From = (Format-PlayBridgePath $from); To = (Format-PlayBridgePath $to) }
}

# ---------------------------------------------------------------------------
# Player, messages, log
# ---------------------------------------------------------------------------

function Get-PlayBridgeArgumentList([string]$Arguments, [string]$Target) {
    # The video goes first, unless the options contain %1 to place it
    $list = New-Object System.Collections.Generic.List[string]
    $placed = $false
    foreach ($m in [regex]::Matches([string]$Arguments, '"([^"]*)"|(\S+)')) {
        if ($m.Groups[1].Success) { $a = $m.Groups[1].Value } else { $a = $m.Groups[2].Value }
        if ($a -eq '%1') { $a = $Target; $placed = $true }
        $list.Add($a)
    }
    if (-not $placed) { $list.Insert(0, $Target) }
    return , $list.ToArray()
}

# Player and options from PlayBridge.ini, or the defaults of the old MPC-JF script
function Get-PlayBridgePlayer($Config) {
    $player = [string]$Config.Player
    $playerArgs = $Config.Arguments
    if (-not $player) {
        $player = $PlayBridge_DefaultPlayer
        if ($null -eq $playerArgs) { $playerArgs = $PlayBridge_DefaultArguments }
    }
    if ($null -eq $playerArgs) { $playerArgs = '' }
    return @{ Path = $player; Arguments = [string]$playerArgs }
}

function Start-PlayBridgePlayer($Config, [string]$Target) {
    $p = Get-PlayBridgePlayer $Config
    $argv = Get-PlayBridgeArgumentList $p.Arguments $Target
    # Start-Process: the player is fully detached from this hidden PowerShell
    Start-Process -FilePath $p.Path -ArgumentList @($argv | ForEach-Object { '"' + ($_ -replace '"', '""') + '"' }) -ErrorAction Stop
}

function Show-PlayBridgeMessage([string]$Text, [string]$Buttons = 'OK', [string]$Icon = 'Information') {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $owner = New-Object System.Windows.Forms.Form
        $owner.TopMost = $true
        $answer = [System.Windows.Forms.MessageBox]::Show($owner, $Text, 'PlayBridge', $Buttons, $Icon)
        $owner.Dispose()
        return [string]$answer
    } catch {
        return 'None'
    }
}

# Opens PlayBridge Settings, or its folder assistant for one video (-MapUrl)
function Start-PlayBridgeSetup([string]$Dir, [string]$Url) {
    $core = Join-Path $Dir 'PlayBridge-Core.ps1'
    if (-not [System.IO.File]::Exists($core)) { return }
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $argLine = '-NoProfile -ExecutionPolicy Bypass -STA -File "{0}"' -f $core
    if ($Url) { $argLine += (' -MapUrl "{0}"' -f (([string]$Url) -replace '"', '%22')) }
    Start-Process -FilePath $ps -WindowStyle Hidden -ArgumentList $argLine
}

function Write-PlayBridgeLog([string]$Dir, $Lines) {
    try {
        $file = Join-Path $Dir 'PlayBridge.log'
        if ([System.IO.File]::Exists($file) -and (New-Object System.IO.FileInfo $file).Length -gt 262144) { [System.IO.File]::Delete($file) }
        [System.IO.File]::AppendAllText($file, ((Hide-PlayBridgeToken ($Lines -join "`r`n")) + "`r`n"), (New-Object System.Text.UTF8Encoding $false))
    } catch { }
}

# ---------------------------------------------------------------------------
# Jellyfin links: wait for the server before the player starts
# ---------------------------------------------------------------------------

# Small window shown while Jellyfin wakes up its disks. $null when it can't be shown.
function New-PlayBridgeWaitWindow {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $form = New-Object System.Windows.Forms.Form
        $form.Text = 'PlayBridge'
        $form.FormBorderStyle = 'FixedDialog'
        $form.MaximizeBox = $false
        $form.MinimizeBox = $false
        $form.StartPosition = 'CenterScreen'
        $form.TopMost = $true
        $form.Font = New-Object System.Drawing.Font 'Segoe UI', 9.5
        $form.ClientSize = New-Object System.Drawing.Size 400, 112
        $label = New-Object System.Windows.Forms.Label
        $label.Text = "Waiting for Jellyfin to send the video...`r`nSleeping NAS disks can take up to a minute to wake up."
        $label.Location = New-Object System.Drawing.Point 16, 16
        $label.Size = New-Object System.Drawing.Size 372, 46
        $button = New-Object System.Windows.Forms.Button
        $button.Text = 'Cancel'
        $button.Location = New-Object System.Drawing.Point 300, 72
        $button.Size = New-Object System.Drawing.Size 88, 28
        $button.Add_Click({ $script:PlayBridgeWaitCancelled = $true })
        $form.Add_FormClosing({ $script:PlayBridgeWaitCancelled = $true })
        $form.CancelButton = $button
        $form.Controls.Add($label)
        $form.Controls.Add($button)
        $form.Show()
        $form.Activate()
        return $form
    } catch {
        return $null
    }
}

# The wait window stays open until the player is started: while PlayBridge owns the active window,
# Windows lets the player come to the front.
function Close-PlayBridgeWaitWindow {
    if ($script:PlayBridgeWaitWindow) { try { $script:PlayBridgeWaitWindow.Dispose() } catch { } }
    $script:PlayBridgeWaitWindow = $null
}

# Asks Jellyfin for the first byte of the video, so that the player starts once Jellyfin can send it.
# Code: HTTP status (206, 200, 404...), 0 when there was no answer (timeout, server unreachable).
function Wait-PlayBridgeServer([string]$Link, [int]$TimeoutMs = $PlayBridge_ServerWaitMs) {
    $result = @{ Code = 0; Ms = 0; Cancelled = $false; Error = '' }
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $script:PlayBridgeWaitCancelled = $false
    $script:PlayBridgeWaitWindow = $null
    $windowTried = $false
    $request = $null
    try {
        try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12 } catch { }
        $request = [System.Net.HttpWebRequest]([System.Net.WebRequest]::Create($Link))
        $request.Method = 'GET'
        $request.AddRange(0, 0)          # first byte only
        $request.KeepAlive = $false
        $request.UserAgent = 'PlayBridge/' + $PlayBridge_Version
        # server on the local network: no proxy (the automatic proxy lookup of Windows can take seconds)
        $server = $request.RequestUri.Host.Trim('[', ']')
        if ($server -notmatch '\.' -or $server -match '^(127\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|169\.254\.|::1$|f[cde][0-9a-f]{2}:)' -or $server -match '\.(local|lan|home|internal)$') {
            $request.Proxy = $null
        }
        $async = $request.BeginGetResponse($null, $null)
        while (-not $async.AsyncWaitHandle.WaitOne(50)) {
            if ($watch.ElapsedMilliseconds -ge $TimeoutMs) { break }
            if (-not $windowTried -and $watch.ElapsedMilliseconds -ge $PlayBridge_WaitWindowMs) {
                $windowTried = $true
                $script:PlayBridgeWaitWindow = New-PlayBridgeWaitWindow
            }
            if ($script:PlayBridgeWaitWindow) { [System.Windows.Forms.Application]::DoEvents() }
            if ($script:PlayBridgeWaitCancelled) { $result.Cancelled = $true; break }
        }
        if ($async.IsCompleted) {
            try {
                $response = $request.EndGetResponse($async)
                $result.Code = [int]$response.StatusCode
                $response.Close()
            } catch {
                # PowerShell wraps the WebException: look for it
                $e = $_.Exception
                while ($e -and -not ($e -is [System.Net.WebException])) { $e = $e.InnerException }
                if ($e -and $e.Response) {
                    $result.Code = [int]$e.Response.StatusCode
                    try { $e.Response.Close() } catch { }
                } elseif ($e) {
                    $result.Error = [string]$e.Status
                } else {
                    $result.Error = $_.Exception.Message
                }
            }
        } elseif (-not $result.Cancelled) {
            $result.Error = 'timeout'
        }
    } catch {
        $result.Error = $_.Exception.Message
    } finally {
        if ($request) { try { $request.Abort() } catch { } }
        if ($result.Cancelled) { Close-PlayBridgeWaitWindow }
    }
    $result.Ms = $watch.ElapsedMilliseconds
    return $result
}

# One wait per video: a second click on the same video while PlayBridge waits for Jellyfin does nothing.
# Returns the mutex (keep it until the end), $false when another PlayBridge waits for this video, $null on error.
function Enter-PlayBridgeWait([string]$Key) {
    try {
        $mutex = New-Object System.Threading.Mutex($false, ('Local\PlayBridge-' + $Key))
        try { $mine = $mutex.WaitOne(0) } catch { $mine = $true }   # abandoned by a closed PlayBridge: ours now
        if ($mine) { return $mutex }
        $mutex.Dispose()
        return $false
    } catch {
        return $null
    }
}

function Exit-PlayBridgeWait {
    if ($script:PlayBridgeMutex) {
        try { $script:PlayBridgeMutex.ReleaseMutex() } catch { }
        try { $script:PlayBridgeMutex.Dispose() } catch { }
    }
    $script:PlayBridgeMutex = $null
}

if ($LoadOnly) { return }

# ---------------------------------------------------------------------------
# Main: find the video, start the player
# ---------------------------------------------------------------------------

$here = $PSScriptRoot
# PlayBridge-launch.vbs hands the link over in an environment variable: no quoting or %-expansion issues
if (-not $Url -and $env:PLAYBRIDGE_URL) { $Url = $env:PLAYBRIDGE_URL }
if (-not $Url) {
    # double-clicked or started from a shortcut: open PlayBridge Settings
    Start-PlayBridgeSetup $here ''
    [Environment]::Exit(0)
}
if ($Url -match '^(playbridge|mpcjf):(//)?playbridge-test/?$') {
    # "Test from the browser" button of the setup: the browser did start PlayBridge
    Write-PlayBridgeLog $here @('', ('{0}  PlayBridge {1}  browser test link received' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $PlayBridge_Version))
    [void](Show-PlayBridgeMessage "Success: your browser started PlayBridge.`n`nThe browser side works. If Jellyfin's Play button still does nothing, the browser script is the thing to check (PlayBridge Settings, browser page)." 'OK' 'Information')
    [Environment]::Exit(0)
}

# first line written at once: if it is missing, the browser never started PlayBridge
Write-PlayBridgeLog $here @('', ('{0}  PlayBridge {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $PlayBridge_Version), ('  link     : ' + $Url))
$log = New-Object System.Collections.Generic.List[string]
$watch = [System.Diagnostics.Stopwatch]::StartNew()
$config = $null

function Invoke-PlayBridgePlay([string]$Target, [string]$Label) {
    $log.Add(('  play     : {0}  ({1}, {2} ms)' -f $Target, $Label, $watch.ElapsedMilliseconds))
    $p = Get-PlayBridgePlayer $config
    try {
        Start-PlayBridgePlayer $config $Target
        $log.Add('  player   : ' + $p.Path + ' ' + $p.Arguments)
        Close-PlayBridgeWaitWindow
    } catch {
        $log.Add('  player   : ERROR ' + $_)
        Write-PlayBridgeLog $here $log
        Close-PlayBridgeWaitWindow
        Exit-PlayBridgeWait
        [void](Show-PlayBridgeMessage ("PlayBridge can't start your video player:`n`n{0}`n`n{1}`n`nOpen Start menu > PlayBridge Settings to choose your player." -f $p.Path, $_.Exception.Message) 'OK' 'Error')
        [Environment]::Exit(1)
    }
    Write-PlayBridgeLog $here $log
    [Environment]::Exit(0)
}

# Jellyfin link (stream / download): waits until Jellyfin can send the video, then starts the player
function Invoke-PlayBridgeStream([string]$Label) {
    $script:PlayBridgeMutex = Enter-PlayBridgeWait (([string]$info.id) -replace '[^0-9A-Za-z]', '')
    if ($script:PlayBridgeMutex -is [bool]) {
        $log.Add('  server   : this video is already starting (other click), nothing more to do')
        Write-PlayBridgeLog $here $log
        [Environment]::Exit(0)
    }
    $w = Wait-PlayBridgeServer $streamUrl
    if ($w.Cancelled) { $state = 'cancelled' }
    elseif ($w.Code -gt 0) { $state = 'HTTP ' + $w.Code }
    else { $state = 'no answer (' + $w.Error + '), the player starts anyway' }
    $log.Add(('  server   : {0} after {1} ms' -f $state, $w.Ms))
    if ($w.Cancelled) {
        Write-PlayBridgeLog $here $log
        [Environment]::Exit(0)
    }
    if (401, 403, 404 -contains $w.Code) {
        Close-PlayBridgeWaitWindow
        Exit-PlayBridgeWait
        Write-PlayBridgeLog $here $log
        $log.Clear()
        if ($w.Code -eq 401) { $why = 'The browser session may have expired: sign in to Jellyfin again, then retry.' }
        elseif ($w.Code -eq 404) { $why = "Jellyfin can't find the file: it may have been moved or deleted. Refresh the library in Jellyfin, then retry." }
        elseif ($mode -eq 'download') { $why = 'This Jellyfin user may not be allowed to download. Allow it in Jellyfin (Dashboard > Users), or choose the Jellyfin stream mode in PlayBridge Settings.' }
        else { $why = 'This Jellyfin user may not be allowed to play this video.' }
        $text = "Jellyfin refused this video (HTTP {0}).`n`n{1}`n`nStart the player anyway?" -f $w.Code, $why
        if ((Show-PlayBridgeMessage $text 'YesNo' 'Warning') -ne 'Yes') { [Environment]::Exit(0) }
        $Label += ', started anyway'
    }
    Invoke-PlayBridgePlay $streamUrl $Label
}

try {
    $config = Read-PlayBridgeConfig (Join-Path $here 'PlayBridge.ini')
    $mode = $config.Mode
    $link = Split-PlayBridgeUrl $Url
    $info = $link.Info
    $streamUrl = $null
    if ($info.Count) {
        $streamMode = 'stream'
        if ($mode -eq 'download') { $streamMode = 'download' }
        $streamUrl = Get-PlayBridgeStreamUrl $info $streamMode
    }
    $log.Add(('  mode     : {0}{1}' -f $mode, $(if ($streamUrl) { ', Jellyfin link received' } else { '' })))

    # Stream and download modes: no file lookup at all
    if (($mode -eq 'stream' -or $mode -eq 'download') -and $streamUrl) { Invoke-PlayBridgeStream 'Jellyfin link' }

    $path = Format-PlayBridgePath $link.Path

    # Advanced: PlayBridge-custom.ps1 can change $path with your own PowerShell lines
    # (it replaces the old "YOUR NAS CONFIG" section, and is kept when PlayBridge is updated)
    $customFile = Join-Path $here 'PlayBridge-custom.ps1'
    if ([System.IO.File]::Exists($customFile)) {
        try { . $customFile; $path = Format-PlayBridgePath $path } catch { $log.Add('  custom   : error ' + $_) }
    }
    $log.Add('  path     : ' + $path)

    $kind = Get-PlayBridgePathKind $path
    $tried = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $found = $null       # confirmed path
    $maybe = $null       # path whose drive did not answer in time (probably sleeping disks)
    $firstTry = $null

    foreach ($stage in 'link', 'direct', 'share') {
        if ($stage -eq 'link') { $list = @(Get-PlayBridgeRuleMatches $path $config.Paths) }
        elseif ($stage -eq 'direct') { if ($kind -eq 'drive' -or $kind -eq 'unc') { $list = @($path) } else { $list = @() } }
        elseif ($kind -ne 'other') { $list = @(Get-PlayBridgeShareMatches $path @(Get-PlayBridgeShareRoots $config.Shares)) }
        else { $list = @() }

        foreach ($c in $list) {
            if (-not $c -or -not $tried.Add($c)) { continue }
            if (-not $firstTry) { $firstTry = $c }
            $left = $PlayBridge_CheckBudgetMs - $watch.ElapsedMilliseconds
            if ($left -le 0) { break }
            $r = Test-PlayBridgePath $c ([Math]::Min($PlayBridge_CheckTimeoutMs, $left))
            if ($r -eq $true) { $state = 'found' } elseif ($r -eq $false) { $state = 'not found' } else { $state = 'no answer yet' }
            $log.Add(('  {0,-9}: {1}  [{2}]' -f $stage, $c, $state))
            if ($r -eq $true) { $found = $c; break }
            if ($null -eq $r -and -not $maybe) {
                $maybe = $c
                # a folder link or the path given by Jellyfin is almost surely right: don't wake other disks
                if ($stage -ne 'share') { break }
            }
        }
        if ($found -or $maybe -or $watch.ElapsedMilliseconds -ge $PlayBridge_CheckBudgetMs) { break }
    }

    if ($found) { Invoke-PlayBridgePlay $found 'file' }
    if ($maybe) { Invoke-PlayBridgePlay $maybe 'file, drive still waking up' }
    if ($streamUrl -and $mode -ne 'path') { Invoke-PlayBridgeStream 'file not found, Jellyfin link' }
    if ($kind -eq 'drive' -or $kind -eq 'unc') { Invoke-PlayBridgePlay $firstTry 'file not found, the player tries anyway' }

    # NAS path that matches no Windows folder: offer the folder assistant instead of a player error
    $log.Add('  result   : not found on this PC')
    Write-PlayBridgeLog $here $log
    $shown = ConvertTo-PlayBridgeDisplayPath $path
    if ($streamUrl) {
        $text = "PlayBridge can't find this video on this PC:`n`n{0}`n`nYes: link its NAS folder to Windows (once, then every video of that folder opens directly).`nNo: stream it from Jellyfin this time." -f $shown
        $answer = Show-PlayBridgeMessage $text 'YesNoCancel' 'Warning'
        if ($answer -eq 'Yes') { Start-PlayBridgeSetup $here $Url }
        elseif ($answer -eq 'No') { $log.Clear(); Invoke-PlayBridgeStream 'Jellyfin link, chosen' }
    } elseif ($mode -ne 'path') {
        # Jellyfin link modes, but the browser script doesn't send Jellyfin links
        $text = "PlayBridge can't play this video:`n`n{0}`n`nPlayBridge is set to use Jellyfin links, but the browser script doesn't send them (it was installed for the Windows file path mode, or before the mode was changed).`n`nOK: open PlayBridge Settings, click Next and do the browser steps again (install script A or B)." -f $shown
        if ((Show-PlayBridgeMessage $text 'OKCancel' 'Warning') -eq 'OK') { Start-PlayBridgeSetup $here '' }
    } else {
        $text = "PlayBridge can't find this video on this PC:`n`n{0}`n`nIts NAS folder isn't linked to Windows yet.`n`nLink it now? (once per folder)" -f $shown
        if ((Show-PlayBridgeMessage $text 'YesNo' 'Warning') -eq 'Yes') { Start-PlayBridgeSetup $here $Url }
    }
    [Environment]::Exit(0)
} catch {
    # never fail silently: the window is hidden
    $log.Add('  ERROR    : ' + ($_ | Out-String).Trim())
    Write-PlayBridgeLog $here $log
    [void](Show-PlayBridgeMessage ("PlayBridge stopped because of an error:`n`n{0}`n`nDetails in {1}" -f $_.Exception.Message, (Join-Path $here 'PlayBridge.log')) 'OK' 'Error')
    [Environment]::Exit(1)
}
