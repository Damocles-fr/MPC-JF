# MPC-JF ▸ External player launcher for Jellyfin (Windows)
<p align="center">
  <img src="./MPCJF.webp" alt="MPC-JF logo" width="128"><br>
</p>

### ▶︎ Features :
- Support **MPC-BE, PotPlayer or MPC-HC** (and more ? Try with your own player **.exe**)
- The easiest way to use madVR with Jellyfin
- Support Jellyfin Web through userscript (Firefox or Chrome-based)
- Support **Jellyfin Media Player / Jellyfin Desktop** (Windows app) with a DeviceId through JavaScript Injector
- Compatible with Jellyfin 12+ (and older versions)
- **Alternative version script** : add a new yellow Play button to the item pages, external player is only triggered from that icon

#### Requirements & limitations :
- Your media folders HDDs/NAS/network drives must be mounted with a letter in Windows (D:\ E:\ ...)
- Watched states are not synced.

> [!WARNING]
> **The only official repository is https://github.com/Damocles-fr/MPC-JF**
> 
> Malicious clones sometimes rank high on Google and distribute ZIP files containing malware.
> Please report any fake repositories: "Report repository" (middle of the right sidebar) → Malware

## Installation

### 0. Download MPC-JF.zip
Download **latest for Jellyfin 12+ or 10.11.x** : [MPC-JF.zip](https://github.com/Damocles-fr/MPC-JF/releases/)

### 1. Place Required Files
- Before extracting the archive, right-click the downloaded .zip → Properties → check **Unblock** → Apply. This also unblocks the extracted .ps1 scripts required for execution.
- Extract and move the MPC-JF folder to :
  ```
  C:\ProgramData\
  ```
- You should end up with: `C:\ProgramData\MPC-JF\` (with all files inside).

### 2. If you don't use ***MPC-BE*** and its default path :
- Edit the file `MPCJF.ps1` and replace the path ***in the last line*** with ***your own*** corresponding path. (MPC-HC or any other player path)
- E.g. for PotPlayer default path : ``` & "C:\Program Files\DAUM\PotPlayer\PotPlayerMini64.exe" "`"$path`"" ```

### 3. (Recommended) : Installation for Web Browser 
- In your web browser, install ViolentMonkey extension :
https://addons.mozilla.org/fr/firefox/addon/violentmonkey/
	###### Alternatively you can use TamperMonkey or any userscript extension
- Install MPCJF.user.js (replace all playing functions), one-click install with auto-update : [MPCJF.user.js](https://raw.githubusercontent.com/Damocles-fr/MPC-JF/refs/heads/main/MPCJF.user.js)

	or

	Alternative : MPCJFicon.user.js (add a new yellow Play button to the item pages, external player is only triggered from that icon), one-click install with auto-update : [MPCJFicon.user.js](https://raw.githubusercontent.com/Damocles-fr/MPC-JF/refs/heads/main/MPCJFicon.user.js)
- If your Jellyfin server is not at the default address ``` http://localhost:8096/ ```, add your own address **without editing the script**, so auto-updates keep working :
	- **Violentmonkey** : Dashboard → click **`</>`** on MPC-JF → **Settings** ***tab*** → add your address in the **@match** rules
	- **Tampermonkey** : Dashboard → MPC-JF → **Settings** tab → **Includes/Excludes** → **User matches** → **Add...**
	
  ```
  http://192.168.1.10:8096/*
  ```
	##### - Don't forget the * at the end.

### 4. (Optional) : Installation for Jellyfin Media Player / Jellyfin Desktop (Windows app)
- Install the **[JavaScript Injector plugin](https://github.com/n00bcodr/Jellyfin-JavaScript-Injector)** on your Jellyfin server if it is not already installed. A server restart may be required.
- Go to: Jellyfin → **Admin Dashboard → JS Injector → Add Script**
- Name it MPCJF or whatever, then copy/paste the entire `MPC-JF-JSinjector-deviceID.js` script.
- Check **Requires Authentication** and **Enabled**, then click **Save**.
- Open (or restart) Jellyfin Media Player / Jellyfin Desktop and log in : a **MPC-JF : DeviceId of this app** box appears at the bottom of the screen. Click **Copy**.
- Go back to your script in **Dashboard → JS Injector**, replace `PUT_DEVICE_ID_HERE` with the copied DeviceId (keep the quotes), then click **Save**.
- Restart the desktop app. Done.

###### If the DeviceId box doesn't appear, find the DeviceId in the app log (paste the path in the File Explorer address bar) :
- Jellyfin Media Player : `%LOCALAPPDATA%\JellyfinMediaPlayer\logs\JellyfinMediaPlayer.log`
- Jellyfin Desktop : `%LOCALAPPDATA%\jellyfin-desktop\Logs\jellyfin-desktop.log` (or `%LOCALAPPDATA%\Jellyfin Desktop\profiles\<profile-id>\logs\` depending on the version)
- Open it with Notepad, `Ctrl + F` → `deviceId` (preferably the last one), and copy the long random string after `deviceId:` or `deviceId=`.
- If it doesn't work, close and reopen/reconnect the app, then search again at the bottom of the log.

###### Notes : Jellyfin Desktop doesn't import Jellyfin Media Player settings : switching app means a new DeviceId, so redo this step.
###### Notes : If you do not find `deviceId:` or the one you copy/paste is not working, close and reopen/reconnect Jellyfin Media Player, then reopen the log file and search again at the bottom.
###### Alternative : Add a new yellow Play button to the item pages that will show everywhere, external player is only triggered from that icon  : Go to Jellyfin → **Admin Dashboard → JS Injector → Add Script**. Name it MPCJFbutton or whatever, then copy/paste the entire : [MPCJFicon.user.js](https://raw.githubusercontent.com/Damocles-fr/MPC-JF/refs/heads/main/MPCJFicon.user.js) Check **Enabled**, then click **Save**.

### 5. Enable PowerShell Scripts Execution to allow MPCJF.ps1
- In Windows 11, go to, Settings → Developers → PowerShell → Allow unsigned scripts
- Or if you can't find it :
	- Search for `PowerShell` in the Start menu, right-click it, and select **Run as Administrator**.
	- Type the following command and press Enter:
     ```
     Set-ExecutionPolicy RemoteSigned
     ```
- Or
     ```
     Set-ExecutionPolicy RemoteSigned -Force
     ```
### 6. Apply MPC-JF Registry Settings
- Run `MPCJF.reg` and confirm changes.
- You may need to re-run `MPCJF.reg` after major Media Player Updates.

### Optional :  Hide the PowerShell window at MPC-JF launch
- `Install-MPCJF-HiddenProtocol.ps1` must be in your default MPC-JF folder.
- It **requires VBScript** installed (may not be installed by default on all Windows 11 installation)
- Run the file `Install-MPCJF-HiddenProtocol.ps1` (Right click and ***Run with PowerShell***)

### Optional : Adjust Full-Screen Settings
- Fullscreen is *On* by default
- Edit "MPCJF.ps1" located in ``` C:\ProgramData\MPC-JF ```
- At the end of the script, remove or re-add ```/fullscreen``` e.g. ```"`"$path`""/fullscreen```
###### (not supported by all media players, for PotPlayer you can adjust this in Potplayer's preferences → General → Startup → Startup → Window Size)

### 7. Done !
- Restart your web browser and/or refresh Jellyfin Web UI, test if it works already. If not, see Workaround below.

---

### Workaround : If the Media Player starts but fails to launch the media
- Your NAS/network drives must be mounted with a letter like D:\ E:\ ... in Windows.
- Edit "MPCJF.ps1" located in ``` C:\ProgramData\MPC-JF ```
  	- At the end of the file, just below : ``` # YOUR NAS CONFIG, IF NEEDED, ADD YOUR OWN WORKAROUND JUST BELOW ```
  	- For each drive, add this line : ``` $path = $path -replace "\\share\\SHAREFOLDER\\", "D:" ```
  	- In this, change ``` "\\share\\SHAREFOLDER\\" ```
  	  It should be ***the part*** of the path that appear in your NAS (and maybe in your library path in Jellyfin server too), but not appearing in the Windows explorer path of your movies. 
  	- Add double backslash ``` \\ ``` instead of single backslash ``` \ ``` in your own path, they are essential.
  	- Replace "D:" with the corresponding drive letter in Windows.
  	- For example ``` $path = $path -replace "\\share\\MEDIA\\", "D:" ```
	That works for everything located in my NAS mounted as the D: drive in Windows, so D:\FILMS, D:\SERIES, D:\FILMS\folder1\Movie1.mkv etc.
  	- If you have other drives, do the same for them by adding lines below.
  	- No need to add lines for every library folder, just one line for each different drive should be enough.

---

### TIPS :
- **Re-run** `MPCJF.reg` (& `Install-MPCJF-HiddenProtocol.ps1`) after a new Media Player/MPC/Potplayer update 
- You will have to checkmark the media as watched in Jellyfin yourself...
- MPC-HC is not the best anymore to use with MadVR, try Potplayer, it's highly customizable and support nearly all renderer including madVR and D3D11 with RTX video.
- To Resume watching the last media, set your Player settings to resume the last file automatically at opening → Potplayer's preferences → General → Startup → Check `Play the last played item` (and open the player instead of jellyfin to resume).
- If Jellyfin removed or changed you JMP deviceId : re-do step 4 `deviceId: ` part.
- If MPC takes time to launch the media, it's because HDDs are in standby and MPC is waiting for them to respond. I have made a tiny watcher that wake up my NAS HDDs at JF Home screen for faster first play here : 
[jellyfin-nas-hdd-spinup](https://github.com/Damocles-fr/jellyfin-nas-hdd-spinup)
- To uninstall `Install-MPCJF-HiddenProtocol.ps1` : run in Powershell :
     ```
     Remove-Item -Recurse -Force "HKCU:\Software\Classes\MPCJF" -ErrorAction SilentlyContinue
     Remove-Item -Recurse -Force (Join-Path $env:LOCALAPPDATA "MPCJF") -ErrorAction SilentlyContinue
     ```
- If you use the Firefox extension ``` Dark Reader ``` , it breaks Jellyfin pictures loading in browsers, deactivate it only for jellyfin : Go into Dark Reader settings while you have the Jellyfin page open (firefox menu bar), click to  Jellyfin URL.
- Here is my guide with many **quality-of-life improvements** for using Jellyfin (lots of tips and tricks, auto-start-stop server, fullscreen UI, shortcut links to media folders, etc.) : [PPJF](https://github.com/Damocles-fr/PPJF/)

---

### Files in C:\ProgramData\MPC-JF
- ``` MPCJF.ps1 ``` : Do not delete. Main Script.
- ``` MPCJF.reg ``` : Do not delete. You may need to run it again if the script doesn't run anymore, maybe after some PotPlayer/MPC updates.
- ``` Install-MPCJF-HiddenProtocol.ps1 ``` : One time run to hide the Powershell window at Player launch. You may need to run it again after some PotPlayer/MPC updates.
- ``` MPCJF.user.js ``` : Main browser script, it's in ViolentMonkey in your browser. Use this one if an auto-update of the script has broken things for your version.
- ``` MPC-JF-JSinjector-deviceID.js ``` : Jellyfin Media Player / Jellyfin Desktop (Windows app) JS Injector script.

---

### Need Help?
- Don't hesitate to open an [issue](https://github.com/Damocles-fr/MPC-JF/issues)
- **DM me**: https://forum.jellyfin.org/u-damocles
- GitHub with my other Jellyfin projects: https://github.com/Damocles-fr/
