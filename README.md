# MPC-JF ▸ External player launcher for Jellyfin (Windows)
<p align="center">
  <img src="./MPCJF.webp" alt="Android view" width="128"><br>
</p>

### ▶︎ Features :
- Support **MPC-BE, MPC-HC, or PotPlayer** (and more ? Try with your own player **.exe**)
- Support Jellyfin Web through userscript (Firefox or Chrome-based)
- Support **Jellyfin Media Player** (JMP Desktop Windows App) with a DeviceId through JavaScript Injector
- **Alternative version script** : add a new yellow Play button to the item pages, external player is only triggered from that icon

#### Requirements & limitations :
- Your media folders HDDs/NAS/network drives must be mounted with a letter in Windows (D:\ E:\ ...)
- Watched states are not synced.

## Installation
### 0. Download MPC-JF.zip
Download **latest for Jellyfin 10.11.+** : [MPC-JF.zip](https://github.com/Damocles-fr/MPC-JF/releases/)

### 1. Place Required Files
- Extract and move the MPC-JF folder to :
  ```
  C:\ProgramData\
  ```
- You should end up with: `C:\ProgramData\MPC-JF\` (with all files inside).

### 2. If you don't use ***MPC-BE*** and his default path :
- Edit the file `MPCJF.ps1` and replace the path ***in the last line*** with ***your own*** corresponding path. (MPC-HC or any other player path)
- E.g. for PotPlayer default path : ``` & "C:\Program Files\DAUM\PotPlayer\PotPlayerMini64.exe" "`"$path`"" ```

### 3. (Recommended) : Installation for Web Browser 
- In your web browser, install ViolentMonkey extension :
https://addons.mozilla.org/fr/firefox/addon/violentmonkey/
	###### Alternatively you can use TamperMonkey or any userscript extension
- Install MPCJF.user.js (replace all playing functions), one-click install with auto-update : [MPCJF.user.js](https://raw.githubusercontent.com/Damocles-fr/MPC-JF/refs/heads/main/MPCJF.user.js)
- Alternative : MPCJFicon.user.js (add a new yellow Play button to the item pages, external player is only triggered from that icon), one-click install with auto-update : [MPCJFicon.user.js](https://raw.githubusercontent.com/Damocles-fr/MPC-JF/refs/heads/main/MPCJFicon.user.js)
- If your Jellyfin Server is not set the default adress ``` http://localhost:8096/ ``` : Select **Modify** to replace ``` http://localhost:8096/ ``` with your Jellyfin web URL, for exemple :
  ```
  // @match        http://192.168.1.10:8096/*
  ```
	##### - Don't forget the * at the end.
	##### - To allow modifications, and so it doesn’t get overwritten if I update this script, uncheck Allow Updates & Allow Modification.
	###### To find and modify the installed `MPCJF.user.js` Browser settings → Extensions → **Violentmonkey** → Options → Go to **Installed Scripts** > ***`</>`***
	
### 4. (Optional) : Installation for Jellyfin Media Player only (JMP Desktop Windows App)
- Install the **[JavaScript Injector plugin](https://github.com/n00bcodr/Jellyfin-JavaScript-Injector)** on your Jellyfin server if it is not already installed. A server restart may be required.
- Go to: Jellyfin => **Admin Dashboard => JS Injector => Add Script**
- Name it MPCJF or whatever, then copy/paste the entire `MPC-JF-JSinjector-deviceID.js` script.
- On the PC, go to your corresponding `C:\Users\YourUserName\AppData\Local\JellyfinMediaPlayer\logs\`
- Open `JellyfinMediaPlayer.log` with Notepad.
- Press `Ctrl + F` and search for: `deviceId: ` (preferably at the bottom)
- You should find a line containing `deviceId:` `LongRandomString`
- Copy just that `LongRandomString`
- Go back to your script in: **Dashboard => JS Injector**
- Paste/Replace: `PUT_DEVICE_ID_HERE` with your `long random string` device Id.
- Check **Enabled**, then click **Save**.

###### Notes : If you do not find `deviceId:` or the one you copy/paste is not working, close and reopen/reconnect Jellyfin Media Player, then reopen the log file and search again at the bottom.

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

### Optional :  Hide the Powerscript window at MPC-JF launch
- `Install-MPCJF-HiddenProtocol.ps1` must be in your default MPC-JF folder.
- It **require VBScript** installed (may not be installed by default on all Windows 11 installation)
- Run the file `Install-MPCJF-HiddenProtocol.ps1` (Right click and ***Run with PowerShell***)

### Optional : Adjust Full-Screen Settings
- Fullscreen is *On* by default
- Edit "MPCJF.ps1" located in ``` C:\ProgramData\MPC-JF ```
- At the end of the script, remove or re-add ```/fullscreen``` e.g. ```"`"$path`""/fullscreen``` (not supported by all media players)

### 7. Done !
- Restart your web browser and/or refresh Jellyfin Web UI, test if it works already. If not, see Workaround below.
###### For Jellyfin Media Player, it can take a few restarts and right click => Reload before it works.

---

### Workaround : If the Media Player starts but fail to launch the media
- Your NAS/network drives must be mount with a letter like D:\ E:\ ... in Windows.
- Edit "MPCJF.ps1" located in ``` C:\ProgramData\MPC-JF ```
  	- At the end of the file, just below : ``` # YOUR NAS CONFIG, IF NEEDED, ADD YOUR OWN WORKAROUND JUST BELOW ```
  	- For each drive, add this line : ``` $path = $path -replace "\\share\\SHAREFOLDER\\", "D:" ```
  	- In this, change ``` "\\share\\SHAREFOLDER\\" ```
  	  It should be ***the part*** of the path that appear in your NAS (and maybe in your library path in Jellyfin server too), but not appearing in the Windows explorer path of your movies. 
  	- Add double backslash ``` \\ ``` instead of single backslash ``` \ ``` in your own path, they are essential.
  	- Replace "D:" with the corresponding drive letter in Windows.
  	- For exemple ``` $path = $path -replace "\\share\\MEDIA\\", "D:" ```
	That works for everything located in my NAS mounted as the D: drive in Windows, so D:\FILMS, D:\SERIES, D:\FILMS\folder1\Movie1.mkv etc.
  	- If you have other drives, do the same for them by adding lines below.
  	- No need to do add lines for every library folder, just one line for each different drive should be enough.

---

### TIPS :
- You will have to checkmark the media as watched in Jellyfin yourself...
- To Resume watching the last media, set your Player settings to resume the last file automatically at openning (and open the player instead of jellyfin to resume).
- Sometimes if it stop working, because of idk, **MPC updates** or some specific settings change, just **re-run** `MPCJF.reg` (& `Install-MPCJF-HiddenProtocol.ps1`).
- If you change your server adress : modify the installed **MPCJF** userscript : Browser settings → Extensions → **Violentmonkey** → Options → Go to **Installed Scripts** → MPC-JF ***`</>`***
- If Jellyfin removed or changed you JMP deviceId : re-do step 4 `deviceId: ` part.
- If MPC takes time to launch the media, it's because HDDs are in standby and MPC is waiting for them to respond. I have made a tiny watcher that wake up my NAS HDDs at JF Home screen for faster first play here : 
[jellyfin-nas-hdd-spinup](https://github.com/Damocles-fr/jellyfin-nas-hdd-spinup)
- To uninstall `Install-MPCJF-HiddenProtocol.ps1` : run in Powershell :
     ```
     Remove-Item -Recurse -Force "HKCU:\Software\Classes\MPCJF" -ErrorAction SilentlyContinue
     Remove-Item -Recurse -Force (Join-Path $env:LOCALAPPDATA "MPCJF") -ErrorAction SilentlyContinue
     ```
- If you use the Firefox extension ``` Dark Reader ``` , it breaks Jellyfin pictures loading in browsers, desactivate it only for jellyfin : Go into Dark Reader settings while you have the Jellyfin page open (firefox menu bar), click to  Jellyfin URL.
- Here is my guide with many **quality-of-life improvements** for using Jellyfin (lots of tips and tricks, auto-start-stop server, fullscreen UI, shortcut links to media folders, etc.) : [PPFJ](https://github.com/Damocles-fr/PPJF/)

---

### Files in C:\ProgramData\MPC-JF
- ``` MPCJF.ps1 ``` : Do not delete. Main Script.
- ``` MPCJF.reg ``` : Do not delete. You may need to run it again if the script don't run anymore, maybe after some MPC updates.
- ``` Install-MPCJF-HiddenProtocol.ps1 ``` : One time run to hide the Powershell window at MPC launch. You may need to run it again if the script don't run hidden anymore
- ``` MPCJF.user.js ``` : backup file of the main browser script, it's also in ViolentMonkey in your browser. Use this one if an auto-update of the script have broken things for your version.
- ``` MPC-JF-JSinjector-deviceID.js ``` : Jellyfin Media Player (Desktop App) JS Injector script.

---

### Need Help?
- Don't hesitate to open an [issue](https://github.com/Damocles-fr/MPC-JF/issues)
- **DM me**: https://forum.jellyfin.org/u-damocles
- GitHub with my other Jellyfin projects: https://github.com/Damocles-fr/
