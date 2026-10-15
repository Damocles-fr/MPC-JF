## Jellyfin PlayBridge 13.0.0 (pre-release)

> [!IMPORTANT]
> **Major version: MPC-JF becomes PlayBridge**
> - **Easy install with a GUI**: double-click `Install.cmd`, pick your player, click Next. No admin rights, no file to edit.
> - **Works remotely too**: new Jellyfin stream mode (default), at home or away. No NAS share or mapped drive needed.
> - **Your choice**: Jellyfin stream or download link (Jellyfin API), Windows file path (local disk, NAS share), or file path with stream fallback.
> - **All settings in one window**: player, fullscreen, how videos open, browser, Jellyfin address, browser script, NAS folders.
>
> Please report issues with your `PlayBridge.log`.
> ###### The previous stable version (MPC-JF 12.1) stays available in the releases. 

## Changelog
- New guided installer (`Install.cmd`) with a GUI; no admin rights, no file to edit, no registry file
- New Jellyfin link modes: stream link (default for new installations) or download link, at home and remotely, no NAS setup (ApiKey, Jellyfin 12 ready)
- Jellyfin link modes: the player starts once Jellyfin is ready (waits for sleeping NAS disks, "Waiting for Jellyfin" window with Cancel); clear message when Jellyfin refuses a video
- Windows file path mode: NAS videos found automatically through mapped drives and network shares; folder assistant when a video can't be found; optional stream fallback
- Older MPC-JF settings and "YOUR NAS CONFIG" lines imported automatically (they keep the file path mode)
- Detects installed players, browsers and your Jellyfin server; the Windows default video player is preselected; any other player or browser with Browse...
- Browser page of the setup: Violentmonkey, Jellyfin address, script A or B prepared for your PC and installed in one click, warning when it must be installed again, optional auto-update, "Test from the browser"; Jellyfin Media Player / Jellyfin Desktop as a choice (experimental)
- Clicks open the player more reliably: the video is looked up in advance, so the browser accepts the link
- Browser scripts renamed `PlayBridge.user.js` / `PlayBridgeIcon.user.js`, new `playbridge://` link; old `mpcjf://` links and old scripts keep working
- New icon; the yellow button (script B) gets a small arrow
- Start menu shortcut "PlayBridge Settings" to change anything or uninstall; `PlayBridge.log` for diagnostics (never contains your token)
- Development heavily LLM-assisted since this version (Claude Opus & Fable). The previous stable version (MPC-JF 12.1) stays available. 

## Known limitations
- The player must be able to open http links **for the stream and download modes**
- **File path mode**: your videos must be reachable from Windows (local disk, NAS share, mapped drive).
- Separate subtitle files (.srt next to the video) are not loaded in the **stream and download modes**; embedded subtitles work
- Subtitle detection is restricted when subtitle files are not embedded in the video file or located in the same directory (**Windows file path** mode).
- Restart the browser after the installation: it learns the new `playbridge://` link only when it starts
- Watched states are not synced.
- A stream contains your Jellyfin access token. Your player may keep it in its "recent files" list. Select the **Windows file path** option to avoid this.
