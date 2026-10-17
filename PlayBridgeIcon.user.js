// ==UserScript==
// @name         PlayBridge - yellow button for Jellyfin
// @namespace    https://github.com/Damocles-fr/MPC-JF/
// @version      13.0.1
// @updateURL    https://raw.githubusercontent.com/Damocles-fr/PlayBridge/refs/heads/main/PlayBridgeIcon.user.js
// @downloadURL  https://raw.githubusercontent.com/Damocles-fr/PlayBridge/refs/heads/main/PlayBridgeIcon.user.js
// @description  Adds a yellow button on Jellyfin item pages that opens the video in your own player through PlayBridge (Windows). Native Play buttons stay untouched.
// @author       Damocles-fr
// @match        http://localhost:8096/*
// @run-at       document-end
// @grant        none
// ==/UserScript==

(() => {
  'use strict';

  // ---- PlayBridge settings (PlayBridge Setup writes them in the copy it installs) ----
  const PROTOCOL = 'playbridge://';          // link opened by PlayBridge on this PC
  const STREAM_LINKS = false;          // true: also send the Jellyfin link data (stream, download, path+stream modes)

  const ICON_SRC = 'data:image/webp;base64,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';
  const BTN_CLASS = 'playbridge-launcher-btn';
  const STYLE_ID = 'playbridge-launcher-style';
  const lastSelectedByItem = new Map();

  let userIdPromise = null;
  let lastLaunchAt = 0;
  let syncQueued = false;

  // exceptions playlist + audio : itemId -> true (exclu) | false | 'pending'
  const playlistState = new Map();
  const SKIP_PLAYLIST = { skipPlaylist: true };

  const isGuidLike = (s) =>
    typeof s === 'string' && /^[0-9a-f]{8,}(-[0-9a-f]{4,}){0,4}$/i.test(s);

  const isVisible = (el) => {
    if (!el || !el.isConnected) return false;
    const cs = getComputedStyle(el);
    if (cs.display === 'none' || cs.visibility === 'hidden') return false;
    if (el.closest?.('[aria-hidden="true"]')) return false;
    const r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0;
  };

  const getUserId = async () => {
    if (!userIdPromise) userIdPromise = ApiClient.getCurrentUser().then((u) => u.Id);
    return userIdPromise;
  };

  const getItemIdFromHash = () => {
    const m = /[?&]id=([^&]+)/.exec(String(location.hash || ''));
    return m && isGuidLike(m[1]) ? m[1] : null;
  };

  // "#/details?id=" (JF récents) + "#!/details?id=" / "#!/itemdetails.html?id=" (anciennes versions)
  const isDetailsHash = () => {
    const h = String(location.hash || '');
    return h.includes('#/details') || /^#!?\/(details|itemdetails\.html)(\?|$)/i.test(h);
  };

  const isPlaylistItem = (item) => {
    const type = String(item?.Type || '').toLowerCase();
    const ctype = String(item?.CollectionType || '').toLowerCase();
    return type === 'playlist' || type.includes('playlistsfolder') || ctype === 'playlists';
  };

  // exclusion audio : musique, livres audio... restent dans le lecteur Jellyfin
  const AUDIO_TYPES = ['audio', 'musicalbum', 'musicartist', 'musicgenre', 'audiobook'];
  const AUDIO_COLLECTIONS = ['music', 'audiobooks'];

  const isAudioItem = (item) => {
    const mediaType = String(item?.MediaType || '').toLowerCase();
    const type = String(item?.Type || '').toLowerCase();
    const ctype = String(item?.CollectionType || '').toLowerCase();
    return mediaType === 'audio' || AUDIO_TYPES.includes(type) || AUDIO_COLLECTIONS.includes(ctype);
  };

  const isExcludedItem = (item) => isPlaylistItem(item) || isAudioItem(item);

  // renvoie true / false / 'pending' ; en cas d'erreur API on garde le comportement d'origine (false)
  const checkPlaylist = (itemId) => {
    if (playlistState.has(itemId)) return playlistState.get(itemId);
    playlistState.set(itemId, 'pending');

    getUserId()
      .then((userId) => getItemCached(userId, itemId))
      .then((item) => playlistState.set(itemId, isExcludedItem(item)))
      .catch(() => playlistState.set(itemId, false))
      .then(() => scheduleSync());

    return 'pending';
  };

  // ---- Stream links (PlayBridge 13+) ----
  // Off by default: the link then stays exactly as in older versions (older installs keep working).
  // PlayBridge Setup writes STREAM_LINKS = true in the copy it installs when PlayBridge uses Jellyfin links
  // (stream, download and path+stream modes).
  // Manual switch for this browser: in Jellyfin press F12 > Console and type
  //   localStorage.setItem('playbridge-stream', 'on')      (or 'off')
  const STREAM_KEY = 'playbridge-stream';
  const streamLinksOn = () => {
    if (STREAM_LINKS) return true;
    try { return localStorage.getItem(STREAM_KEY) === 'on'; } catch { return false; }
  };

  const showToast = (text) => {
    const box = document.createElement('div');
    box.textContent = text;
    box.style.cssText = 'position:fixed;left:50%;bottom:24px;transform:translateX(-50%);z-index:2147483647;' +
      'padding:12px 18px;border-radius:10px;background:rgba(20,20,20,.95);color:#fff;font:15px/1.4 sans-serif;' +
      'box-shadow:0 8px 30px rgba(0,0,0,.5);border:1px solid #ffaa00';
    const add = () => { (document.body || document.documentElement).appendChild(box); setTimeout(() => box.remove(), 10000); };
    if (document.body) add(); else document.addEventListener('DOMContentLoaded', add, { once: true });
  };

  // "?playbridge-stream=on" opened by PlayBridge Setup (auto-update mode). Jellyfin may rewrite the address
  // before this script runs, so the address of the page as it was loaded is checked too.
  (() => {
    let loaded = '';
    try { loaded = String((performance.getEntriesByType('navigation')[0] || {}).name || ''); } catch {}
    const m = /[?&#]playbridge-stream=(on|off)\b/i.exec(String(location.search) + String(location.hash) + ' ' + loaded);
    if (!m) return;
    const on = m[1].toLowerCase() === 'on';
    try { if (on) localStorage.setItem(STREAM_KEY, 'on'); else localStorage.removeItem(STREAM_KEY); } catch {}
    showToast(on ? 'PlayBridge: stream links are ON in this browser' : 'PlayBridge: stream links are OFF in this browser');
  })();

  // Media source picked by resolvePathFromItem, recorded in the caller's own ctx object (no shared state:
  // two resolutions running at the same time can't mix their items).
  const rememberSource = (ctx, item, source) => {
    if (ctx) ctx.source = { itemId: item?.Id, mediaSourceId: source?.Id || '', container: source?.Container || item?.Container || '' };
  };

  const streamQuery = (src) => {
    if (!src?.itemId || !streamLinksOn()) return '';
    try {
      const server = typeof ApiClient.serverAddress === 'function' ? ApiClient.serverAddress() : '';
      const token = typeof ApiClient.accessToken === 'function' ? ApiClient.accessToken() : '';
      if (!server || !token) return '';
      const q = new URLSearchParams({ server, id: src.itemId, token });
      if (src.mediaSourceId) q.set('ms', src.mediaSourceId);
      if (src.container) q.set('c', src.container);
      return '?' + q.toString();
    } catch { return ''; }
  };

  // Items fetched once and shared (playlist check, prefetch, click), for 10 minutes
  const itemCache = new Map();
  const getItemCached = (userId, itemId) => {
    const hit = itemCache.get(itemId);
    if (hit && Date.now() - hit.t < 600000) return hit.p;
    const p = ApiClient.getItem(userId, itemId);
    itemCache.set(itemId, { p, t: Date.now() });
    Promise.resolve(p).catch(() => itemCache.delete(itemId));
    return p;
  };

  const toPlayBridgeUrl = (rawPath, src = null) => {
    const forward = String(rawPath).replace(/\\/g, '/');
    const encoded = encodeURIComponent(forward).replace(/%2F/g, '/');
    return PROTOCOL + encoded + streamQuery(src);
  };

  const openLink = (path, src) => {
    const url = toPlayBridgeUrl(path, src);
    console.info('[PlayBridge] opening', url.replace(/token=[^&]+/, 'token=***'));
    window.location.replace(url);
  };

  const getSelectedMediaSourceId = (itemId) => {
    const sel = [...document.querySelectorAll('select.selectSource.detailTrackSelect, select.selectSource')].find(isVisible);
    const value = String(sel?.value || sel?.selectedOptions?.[0]?.value || '');
    if (isGuidLike(value)) return value;
    return itemId && lastSelectedByItem.has(itemId) ? lastSelectedByItem.get(itemId) : null;
  };

  const resolvePathFromItem = async (itemId, mediaSourceId = null, depth = 0, ctx = null) => {
    if (!itemId || depth > 6) return null;

    const userId = await getUserId();
    const item = await getItemCached(userId, itemId);

    // exceptions playlist + audio : jamais lancés dans le lecteur externe
    if (depth === 0 && isExcludedItem(item)) {
      playlistState.set(itemId, true);
      return SKIP_PLAYLIST;
    }

    const mediaSources = item?.MediaSources || [];

    if (mediaSourceId && mediaSources.length) {
      const wanted = mediaSources.find((x) =>
        String(x?.Id || '').toLowerCase() === String(mediaSourceId).toLowerCase() ||
        String(x?.MediaSourceId || '').toLowerCase() === String(mediaSourceId).toLowerCase()
      );
      if (wanted?.Path) { rememberSource(ctx, item, wanted); return wanted.Path; }
    }

    if (item?.Path && mediaSources.length <= 1) { rememberSource(ctx, item, mediaSources[0]); return item.Path; }
    if (mediaSources[0]?.Path) { rememberSource(ctx, item, mediaSources[0]); return mediaSources[0].Path; }

    const res = await ApiClient.getItems(userId, {
      parentId: itemId,
      recursive: true,
      includeItemTypes: 'Movie,Episode,Video',
      limit: 1,
      sortBy: 'SortName',
      sortOrder: 'Ascending'
    });

    const childId = res?.Items?.[0]?.Id;
    return childId ? resolvePathFromItem(childId, null, depth + 1, ctx) : null;
  };

  // The path of the current item is resolved as soon as the button appears, so that a click opens the
  // link at once: browsers only open playbridge:// links within a few seconds of a click.
  const pathCache = new Map();
  const cacheKey = (itemId, mediaSourceId) => itemId + '|' + (mediaSourceId || '');
  const prefetchPath = (itemId) => {
    if (!itemId) return;
    const msid = getSelectedMediaSourceId(itemId);
    const key = cacheKey(itemId, msid);
    if (pathCache.has(key)) return;
    pathCache.set(key, null);
    const ctx = {};
    resolvePathFromItem(itemId, msid, 0, ctx)
      .then((path) => { if (path && path !== SKIP_PLAYLIST) pathCache.set(key, { path, source: ctx.source, t: Date.now() }); else pathCache.delete(key); })
      .catch(() => pathCache.delete(key));
  };

  const launchPlayBridge = () => {
    const now = Date.now();
    if (now - lastLaunchAt < 600) return;
    lastLaunchAt = now;

    const itemId = getItemIdFromHash();
    if (!itemId) return;
    if (playlistState.get(itemId) === true) return;

    const mediaSourceId = getSelectedMediaSourceId(itemId);
    const hit = pathCache.get(cacheKey(itemId, mediaSourceId));
    if (hit && hit.path && now - hit.t < 600000) {
      openLink(hit.path, hit.source);
      return;
    }

    const ctx = {};
    resolvePathFromItem(itemId, mediaSourceId, 0, ctx).then((path) => {
      if (path === SKIP_PLAYLIST) {
        removeStaleButtons();
        return;
      }
      if (!path) {
        console.warn('[PlayBridge] Unable to resolve a local path for itemId:', itemId, 'mediaSourceId:', mediaSourceId);
        return;
      }
      pathCache.set(cacheKey(itemId, mediaSourceId), { path, source: ctx.source, t: Date.now() });
      openLink(path, ctx.source);
    }).catch((e) => console.warn('[PlayBridge] launch failed:', e));
  };

  const injectStyle = () => {
    if (document.getElementById(STYLE_ID)) return;

    const style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent = `
      .${BTN_CLASS} {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        flex: 0 0 auto;
        width: 3.45rem;
        height: 3.45rem;
        min-width: 3.45rem;
        padding: 0;
        margin: 0;
        border: 1px solid rgba(255,255,255,.14);
        border-radius: 999px;
        background: rgba(255,255,255,.06);
        cursor: pointer;
        line-height: 1;
        transition: background .15s ease, border-color .15s ease, transform .08s ease;
      }
      .${BTN_CLASS}:hover {
        background: rgba(255,255,255,.12);
        border-color: rgba(255,255,255,.24);
      }
      .${BTN_CLASS}:active {
        transform: scale(.97);
      }
      .${BTN_CLASS}:focus-visible {
        outline: 2px solid rgba(255,255,255,.35);
        outline-offset: 2px;
      }
      .${BTN_CLASS} img {
        display: block;
        width: 2.093rem;   /* the image includes the arrow: the triangle keeps its former size */
        height: 2.093rem;
        object-fit: contain;
        pointer-events: none;
        user-select: none;
        -webkit-user-drag: none;
      }
    `;
    document.head.appendChild(style);
  };

  const removeStaleButtons = () => {
    document.querySelectorAll('.' + BTN_CLASS).forEach((el) => el.remove());
  };

  const createButton = (itemId) => {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = BTN_CLASS;
    btn.dataset.itemId = itemId;
    btn.title = 'Open with PlayBridge';
    btn.setAttribute('aria-label', 'Open with PlayBridge');

    const img = document.createElement('img');
    img.src = ICON_SRC;
    img.alt = '';
    img.decoding = 'async';
    btn.appendChild(img);

    for (const type of ['pointerdown', 'pointerup', 'mousedown', 'mouseup', 'touchstart', 'touchend']) {
      btn.addEventListener(type, (e) => {
        e.stopPropagation();
        e.stopImmediatePropagation?.();
        if (type === 'pointerdown') prefetchPath(itemId);
      }, true);
    }
    btn.addEventListener(
      'click',
      (e) => {
        e.preventDefault();
        e.stopPropagation();
        e.stopImmediatePropagation?.();
        launchPlayBridge();
      },
      true
    );

    return btn;
  };

  const findButtonsHost = () => {
    const selectors = [
      '.mainDetailButtons',
      '.detailPagePrimaryContainer .buttonContainer',
      '.itemDetailPage .buttonContainer'
    ];

    for (const selector of selectors) {
      const host = [...document.querySelectorAll(selector)].find(isVisible);
      if (host) return host;
    }

    return null;
  };

  const syncButton = () => {
    syncQueued = false;

    const itemId = getItemIdFromHash();
    if (!itemId || !isDetailsHash()) {
      removeStaleButtons();
      return;
    }

    // exceptions : pas de bouton PlayBridge sur une playlist (ni le dossier Playlists) ni sur l'audio
    const playlist = checkPlaylist(itemId);
    if (playlist !== false) {
      removeStaleButtons();
      return;
    }

    injectStyle();

    const host = findButtonsHost();
    if (!host) return;

    const existing = host.querySelector('.' + BTN_CLASS);
    if (existing && existing.dataset.itemId === itemId) { prefetchPath(itemId); return; }

    removeStaleButtons();

    const btn = createButton(itemId);
    const firstAction = [...host.children].find((el) => el.matches?.('button,a,[role="button"]'));

    if (firstAction?.nextSibling) host.insertBefore(btn, firstAction.nextSibling);
    else if (firstAction) host.appendChild(btn);
    else host.prepend(btn);
    prefetchPath(itemId);
  };

  const scheduleSync = () => {
    if (syncQueued) return;
    syncQueued = true;
    requestAnimationFrame(syncButton);
  };

  document.addEventListener(
    'change',
    (e) => {
      const t = e?.target;
      if (!t?.matches?.('select.selectSource.detailTrackSelect, select.selectSource')) return;
      if (!isVisible(t)) return;

      const itemId = getItemIdFromHash();
      const mediaSourceId = String(t.value || t.selectedOptions?.[0]?.value || '');
      if (itemId && isGuidLike(mediaSourceId)) lastSelectedByItem.set(itemId, mediaSourceId);
      prefetchPath(itemId);
    },
    true
  );

  new MutationObserver(scheduleSync).observe(document.body, { childList: true, subtree: true });
  window.addEventListener('hashchange', scheduleSync, true);
  window.addEventListener('popstate', scheduleSync, true);
  scheduleSync();
})();