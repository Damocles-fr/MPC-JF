/* jshint esversion: 11, browser: true, devel: true */
/* globals ApiClient */
// MPC-JF 12.1.0 - JS Injector version for Jellyfin Media Player / Jellyfin Desktop (Windows)
// https://github.com/Damocles-fr/MPC-JF
(() => {
  'use strict';
  const ALLOWED_DEVICE_ID = 'PUT_DEVICE_ID_HERE';

  const CFG = { debug: false };
  const log = (...a) => { if (CFG.debug) console.log('[MPCJF]', ...a); };

  const asId = (v) => (typeof v === 'string' || typeof v === 'number') && String(v) ? String(v) : null;

  const getApiClientDeviceId = () => {
    try {
      if (typeof window.ApiClient?.deviceId === 'function') {
        const v = asId(window.ApiClient.deviceId());
        if (v) return v;
      }
    } catch {}

    const candidates = [
      window.ApiClient?._deviceId,
      window.ApiClient?.deviceId,
      window.ApiClient?._serverInfo?.DeviceId,
      window.ApiClient?.serverInfo?.DeviceId
    ];

    for (const c of candidates) {
      const v = asId(c);
      if (v) return v;
    }

    return null;
  };

  // Le script peut être injecté avant que Jellyfin n'ait créé ApiClient : on attend (30 s max)
  const waitForDeviceId = (timeoutMs = 30000, stepMs = 250) => new Promise((resolve) => {
    const t0 = Date.now();
    const tick = () => {
      const id = getApiClientDeviceId();
      if (id) return resolve(id);
      if (Date.now() - t0 >= timeoutMs) return resolve(null);
      setTimeout(tick, stepMs);
    };
    tick();
  });

  // Jellyfin Media Player / Jellyfin Desktop (et non un navigateur)
  const isDesktopApp = () => {
    if (window.NativeShell) return true;
    try {
      return /jellyfin\s*(media\s*player|desktop)/i.test(String(window.ApiClient?.appName?.() || ''));
    } catch {
      return false;
    }
  };

  // Tant que PUT_DEVICE_ID_HERE n'est pas remplacé : affiche le DeviceId dans l'app desktop
  // (plus besoin de le chercher dans les logs, dont l'emplacement change selon la version de l'app)
  const showDeviceIdHelper = (deviceId) => {
    if (document.getElementById('mpcjf-deviceid-helper')) return;

    const box = document.createElement('div');
    box.id = 'mpcjf-deviceid-helper';
    box.style.cssText = [
      'position:fixed', 'left:50%', 'bottom:24px', 'transform:translateX(-50%)', 'z-index:2147483647',
      'max-width:min(92vw,640px)', 'padding:14px 16px', 'border-radius:12px',
      'background:rgba(20,20,20,.96)', 'color:#fff', 'font:14px/1.4 sans-serif',
      'box-shadow:0 8px 30px rgba(0,0,0,.5)', 'border:1px solid rgba(255,255,255,.18)'
    ].join(';');

    const title = document.createElement('div');
    title.style.cssText = 'font-weight:bold;margin-bottom:6px';
    title.textContent = 'MPC-JF : DeviceId of this app';

    const hint = document.createElement('div');
    hint.style.cssText = 'opacity:.8;margin-bottom:8px';
    hint.textContent = 'Replace PUT_DEVICE_ID_HERE with this value in the MPC-JF script (Dashboard → JS Injector), save, then restart the app.';

    const field = document.createElement('input');
    field.type = 'text';
    field.readOnly = true;
    field.value = deviceId;
    field.style.cssText = 'width:100%;box-sizing:border-box;padding:6px 8px;border-radius:6px;border:1px solid #555;background:#000;color:#fff;font-family:monospace';
    field.addEventListener('focus', () => field.select());

    const row = document.createElement('div');
    row.style.cssText = 'display:flex;gap:8px;justify-content:flex-end;margin-top:10px';

    const mkBtn = (label, onClick) => {
      const b = document.createElement('button');
      b.type = 'button';
      b.textContent = label;
      b.style.cssText = 'padding:6px 14px;border-radius:6px;border:0;cursor:pointer;background:#00a4dc;color:#fff';
      b.addEventListener('click', (e) => { e.preventDefault(); e.stopPropagation(); onClick(b); });
      return b;
    };

    const copyBtn = mkBtn('Copy', async (b) => {
      let ok = false;
      try { await navigator.clipboard.writeText(deviceId); ok = true; } catch {}
      if (!ok) {
        try { field.focus(); field.select(); ok = document.execCommand('copy'); } catch {}
      }
      b.textContent = ok ? 'Copied ✓' : 'Select + Ctrl+C';
    });
    const closeBtn = mkBtn('Close', () => box.remove());
    closeBtn.style.background = '#444';

    row.append(copyBtn, closeBtn);
    box.append(title, hint, field, row);
    (document.body || document.documentElement).appendChild(box);
  };

  const initMPCJF = () => {
    // mémorise le choix "version" par itemId (utile quand Jellyfin recycle le DOM)
    const lastSelectedByItem = new Map();

    // true pendant qu'on rejoue un clic vers Jellyfin (exception playlist) : nos écouteurs l'ignorent
    let bypassNative = false;

    let _userIdPromise = null;
    const getUserId = async () => {
      if (!_userIdPromise) _userIdPromise = ApiClient.getCurrentUser().then(u => u.Id);
      return _userIdPromise;
    };

    const toMPCJFUrl = (rawPath) => {
      const forward = String(rawPath).replace(/\\/g, '/');
      const encoded = encodeURIComponent(forward).replace(/%2F/g, '/');
      return 'MPCJF://' + encoded;
    };

    const isGuidLike = (s) =>
      typeof s === 'string' && /^[0-9a-f]{8,}(-[0-9a-f]{4,}){0,4}$/i.test(s);

    const getAttr = (el, name) => (el && el.getAttribute) ? el.getAttribute(name) : null;

    const isVisible = (el) => {
      if (!el || !el.isConnected) return false;
      const cs = getComputedStyle(el);
      if (cs.display === 'none' || cs.visibility === 'hidden') return false;
      if (el.closest && el.closest('[aria-hidden="true"]')) return false;
      const r = el.getBoundingClientRect();
      return (r.width > 0 || r.height > 0);
    };

    const getIdFromEl = (el) => {
      if (!el || !el.getAttribute) return null;

      const directAttrs = [
        'data-id',
        'data-itemid',
        'data-item-id',
        'data-baseitemid',
        'data-playbackid',
        'data-entityid',
        'data-mediaid',
        'data-episodeid'
      ];

      for (const a of directAttrs) {
        const v = getAttr(el, a);
        if (v && isGuidLike(v)) return v;
      }

      const ds = el.dataset || {};
      const dsCandidates = [ds.id, ds.itemid, ds.itemId, ds.baseitemid, ds.baseItemId, ds.entityid, ds.entityId];
      for (const v of dsCandidates) {
        if (v && isGuidLike(v)) return v;
      }

      const href = getAttr(el, 'href');
      if (href) {
        const m = /[?&]id=([^&]+)/.exec(href);
        if (m && isGuidLike(m[1])) return m[1];
      }

      return null;
    };

    const getIdFromHash = () => {
      const h = String(location.hash || '');
      const m = /[?&]id=([^&]+)/.exec(h);
      if (m && isGuidLike(m[1])) return m[1];
      return null;
    };

    const buildPath = (target) => {
      const out = [];
      let el = target;
      while (el) {
        out.push(el);
        el = el.parentNode;
        if (out.length > 25) break;
      }
      out.push(document, window);
      return out;
    };

    const eventPath = (e) => (e && typeof e.composedPath === 'function') ? e.composedPath() : buildPath(e.target);

    const normalizeText = (s) => String(s || '').trim().toLowerCase();
    const classHasToken = (cls, token) => new RegExp(`(^|[\\s_-])${token}([\\s_-]|$)`, 'i')
      .test(String(cls || ''));

    // ---- Exceptions : playlists + titres de médias contenant "Play" ----

    // lettres/chiffres (accents inclus) : sert à détecter des mots entiers
    const WORD_CHARS = 'a-z0-9\\u00c0-\\u024f';
    const PLAY_WORD_RE = new RegExp(`(^|[^${WORD_CHARS}])(play|lire|reprendre|resume)(?=$|[^${WORD_CHARS}])`, 'i');
    const TOKEN_SPLIT_RE = new RegExp(`[^${WORD_CHARS}:.]+`);

    // "playlist", "playlists", "play list", "playlist_add", "addtoplaylist", "liste(s) de lecture"...
    const PLAYLIST_RE = /playlist|(^|[^a-z])play[\s_-]lists?|listes?[\s_-]+de[\s_-]+lecture/i;
    const mentionsPlaylist = (s) => !!s && PLAYLIST_RE.test(String(s).replace(/display/gi, ' '));

    // mots autorisés dans un libellé de commande de lecture (en / fr)
    const COMMAND_WORDS = new Set([
      'play', 'lire', 'reprendre', 'resume', 'playback', 'lecture',
      'all', 'tout', 'tous', 'toutes', 'from', 'here', 'the', 'this', 'beginning', 'start', 'now', 'next',
      'depuis', 'le', 'la', 'les', 'l', 'à', 'a', 'au', 'partir', 'de', 'd', 'du', 'ici', 'début', 'debut',
      'maintenant', 'ensuite', 'ce', 'cet', 'cette', 'with', 'avec', 'in', 'dans', 'at', 'position',
      'item', 'élément', 'element', 'media', 'média', 'movie', 'film', 'video', 'vidéo', 'episode', 'épisode',
      'button', 'bouton', 'mpc', 'hc', 'be', 'jf', 'mpcjf'
    ]);

    const isCommandToken = (t) =>
      COMMAND_WORDS.has(t) || /^\d[\d:.hms]*$/.test(t) || /^s\d+e\d+$/.test(t);

    // Un aria-label / title n'est une commande de lecture que s'il ne contient QUE des mots de commande :
    // "Play", "Resume", "Lire", "Reprendre à 12:34", "Tout lire à partir d'ici"... -> oui
    // "Foul Play", "Play Misty for Me", "Ready Player One", "Add to playlist", "Display"... -> non
    const isPlayCommandLabel = (label) => {
      const s = normalizeText(label);
      if (!s || !PLAY_WORD_RE.test(s) || mentionsPlaylist(s)) return false;

      const tokens = s
        .replace(/[\u2019'`]/g, ' ')
        .split(TOKEN_SPLIT_RE)
        .map(t => t.replace(/^[:.]+|[:.]+$/g, ''))
        .filter(Boolean);

      return tokens.length > 0 && tokens.every(isCommandToken);
    };

    // vrai lien de navigation (carte, titre cliquable...) -> jamais une commande de lecture via son libellé
    const isNavigationLink = (el) => {
      const href = normalizeText(getAttr(el, 'href'));
      return !!href && href !== '#' && !/^javascript:/.test(href);
    };

    // full = true : contrôle cliqué + ce qu'il contient ; false : ancêtres (marqueurs "forts" uniquement)
    const nodeHasPlaylistMarker = (el, full) => {
      if (!el || !el.getAttribute) return false;

      const type = normalizeText(getAttr(el, 'data-type'));
      const ctype = normalizeText(getAttr(el, 'data-collectiontype'));
      if (type === 'playlist' || type.includes('playlistsfolder') || ctype === 'playlists') return true;

      if (mentionsPlaylist(getAttr(el, 'class')) || mentionsPlaylist(getAttr(el, 'data-action'))) return true;

      if (!full) return false;

      const attrs = ['aria-label', 'title', 'data-id', 'data-testid', 'data-mode', 'data-command', 'href'];
      if (attrs.some(a => mentionsPlaylist(getAttr(el, a)))) return true;

      const tag = String(el.tagName || '').toLowerCase();
      const isInteractive = tag === 'button' || tag === 'a' || normalizeText(getAttr(el, 'role')) === 'button';
      if (!isInteractive) return false;

      const txt = String(el.textContent || '');
      return txt.length <= 80 && mentionsPlaylist(txt);
    };

    const nodeHasAudioMarker = (el) => {
      if (!el || !el.getAttribute) return false;
      const mediaType = normalizeText(getAttr(el, 'data-mediatype'));
      const type = normalizeText(getAttr(el, 'data-type'));
      const ctype = normalizeText(getAttr(el, 'data-collectiontype'));
      return mediaType === 'audio' || AUDIO_TYPES.includes(type) || AUDIO_COLLECTIONS.includes(ctype);
    };

    // Parcourt le chemin du clic : tout ce qui est sous le contrôle + le contrôle (contrôle complet),
    // puis les ancêtres jusqu'au premier élément portant un itemId (la carte / ligne du média).
    // Playlist ou audio -> on laisse Jellyfin gérer.
    const isExcludedContext = (path, control) => {
      let passedControl = false;
      for (const node of path) {
        if (!node || !node.getAttribute) continue;
        if (nodeHasPlaylistMarker(node, !passedControl) || nodeHasAudioMarker(node)) return true;
        if (node === control) passedControl = true;
        if (passedControl && getIdFromEl(node)) break;
      }
      return false;
    };

    const isPlaylistItem = (item) => {
      const type = normalizeText(item && item.Type);
      const ctype = normalizeText(item && item.CollectionType);
      return type === 'playlist' || type.includes('playlistsfolder') || ctype === 'playlists';
    };

    // exclusion audio : musique, livres audio... restent dans le lecteur Jellyfin
    const AUDIO_TYPES = ['audio', 'musicalbum', 'musicartist', 'musicgenre', 'audiobook'];
    const AUDIO_COLLECTIONS = ['music', 'audiobooks'];

    const isAudioItem = (item) => {
      const mediaType = normalizeText(item?.MediaType);
      const type = normalizeText(item?.Type);
      const ctype = normalizeText(item?.CollectionType);
      return mediaType === 'audio' || AUDIO_TYPES.includes(type) || AUDIO_COLLECTIONS.includes(ctype);
    };

    const isExcludedItem = (item) => isPlaylistItem(item) || isAudioItem(item);

    const SKIP_NATIVE = { skipNative: true };

    // rend la main à Jellyfin (lecture / ouverture native) sans que nos écouteurs n'interceptent
    const replayNatively = (control) => {
      if (!control || !control.isConnected || typeof control.click !== 'function') return;
      bypassNative = true;
      try { control.click(); } finally { bypassNative = false; }
    };

    // ------------------------------------------------------------------

    const looksLikePlayControl = (el) => {
      if (!el || !el.getAttribute) return false;

      const aria = normalizeText(getAttr(el, 'aria-label'));
      const title = normalizeText(getAttr(el, 'title'));
      const cls = String(el.className || '');
      const txt = normalizeText(el.textContent);

      // --- NEW: Blacklist Section ---
      // If the button mentions "mark" or "check", it's a status toggle, not a play command.
      const isMarkControl = aria.includes('mark') || title.includes('mark') ||
                           aria.includes('check') || title.includes('check') ||
                           classHasToken(cls, 'played');

      if (isMarkControl) return false;
      // ------------------------------

      const dataMode = normalizeText(getAttr(el, 'data-mode'));
      const dataAction = normalizeText(getAttr(el, 'data-action'));
      const dataCommand = normalizeText(getAttr(el, 'data-command'));

      // exception playlist (addtoplaylist, setplaylistindex, ...)
      if (mentionsPlaylist(dataMode) || mentionsPlaylist(dataAction) || mentionsPlaylist(dataCommand)) return false;

      if (dataMode === 'play' || dataMode === 'resume') return true;
      if (dataAction === 'play' || dataAction === 'resume') return true;
      if (dataCommand.includes('play') || dataCommand.includes('resume')) return true;

      // Cartes / titres cliquables : data-action="link", "menu", "none"... ou vrai href.
      // Leur aria-label / title / texte contient le NOM du média (ex. "Ready Player One") -> ignorés.
      const isLinkLike = isNavigationLink(el) || (!!dataAction && !/^(play|resume)/.test(dataAction));

      if (!isLinkLike) {
        if (isPlayCommandLabel(aria) || isPlayCommandLabel(title)) return true;
        if (txt === 'play_arrow' || txt === 'play_circle' || txt === 'resume' || txt === 'replay') return true;
      }

      if (classHasToken(cls, 'play') || classHasToken(cls, 'resume')) return true;

      return false;
    };

    const findPlayControlInPath = (path) => {
      for (const node of path) {
        if (!node || !node.getAttribute) continue;

        const tag = String(node.tagName || '').toLowerCase();
        const role = normalizeText(getAttr(node, 'role'));
        const isInteractive = (tag === 'button' || tag === 'a' || role === 'button');

        if (isInteractive && looksLikePlayControl(node)) return node;

        if (!isInteractive && looksLikePlayControl(node)) {
          const owner = node.closest ? node.closest('button,a,[role="button"]') : null;
          if (owner && looksLikePlayControl(owner)) return owner;
        }
      }
      return null;
    };

    // ---- Vue liste (playlist...) : ligne entière cliquable avec data-action="playallfromhere" ----
    const VIDEO_TYPES = ['movie', 'episode', 'video', 'musicvideo', 'trailer'];

    const isDragHandle = (node) =>
      !!(node && node.getAttribute && classHasToken(getAttr(node, 'class'), 'listViewDragHandle'));

    // Même logique que Jellyfin : 1er ancêtre ".itemAction", puis son data-action
    // ou celui du premier ancêtre qui en possède un.
    const findPlayAllFromHereControl = (path) => {
      let card = null;
      let cardIndex = -1;
      let action = '';

      for (let i = 0; i < path.length; i++) {
        const node = path[i];
        if (!node || !node.getAttribute) continue;

        if (!card) {
          if (isDragHandle(node)) return null;
          if (!classHasToken(getAttr(node, 'class'), 'itemAction')) continue;
          card = node;
          cardIndex = i;
        }

        const a = getAttr(node, 'data-action');
        if (a) { action = normalizeText(a); break; }
      }

      if (!card || action !== 'playallfromhere') return null;

      // élément du média (ligne) : uniquement la vidéo, l'audio reste géré par Jellyfin
      let itemEl = null;
      for (let i = cardIndex; i < path.length; i++) {
        if (getIdFromEl(path[i])) { itemEl = path[i]; break; }
      }
      if (!itemEl) return null;

      const mediaType = normalizeText(getAttr(itemEl, 'data-mediatype'));
      const type = normalizeText(getAttr(itemEl, 'data-type'));
      const isVideo = mediaType ? mediaType === 'video' : VIDEO_TYPES.includes(type);

      return isVideo ? card : null;
    };

    const findControl = (path) => findPlayControlInPath(path) || findPlayAllFromHereControl(path);

    // un appui commencé sur la poignée de réorganisation n'est jamais une lecture
    let pointerDownOnDragHandle = false;
    document.addEventListener('pointerdown', (e) => {
      pointerDownOnDragHandle = eventPath(e).some(isDragHandle);
    }, true);

    const findItemIdInPath = (path) => {
      for (const node of path) {
        const id = getIdFromEl(node);
        if (id) return id;
      }
      return getIdFromHash();
    };

    // ---- Source/version select (multi-versions) ----
    const getSelectValueAsMediaSourceId = (sel) => {
      if (!sel) return null;

      // propriété value
      let v = String(sel.value || '');
      if (isGuidLike(v)) return v;

      // selectedOptions / selectedIndex
      const opt =
        (sel.selectedOptions && sel.selectedOptions[0]) ||
        (sel.options && sel.options[sel.selectedIndex]) ||
        sel.querySelector?.('option[selected]') ||
        null;

      v = String(opt?.value || '');
      if (isGuidLike(v)) return v;

      return null;
    };

    const findVisibleSourceSelectFromPath = (path) => {
      const strong = 'select.selectSource.detailTrackSelect';
      const weak = 'select.selectSource';

      for (const node of path) {
        if (!node || !node.querySelectorAll) continue;

        const a = [...node.querySelectorAll(strong)].find(isVisible);
        if (a) return a;

        const b = [...node.querySelectorAll(weak)].find(isVisible);
        if (b) return b;
      }
      return null;
    };

    const findVisibleSourceSelectInDocument = () => {
      const strong = [...document.querySelectorAll('select.selectSource.detailTrackSelect')].find(isVisible);
      if (strong) return strong;

      const weak = [...document.querySelectorAll('select.selectSource')].find(isVisible);
      if (weak) return weak;

      return null;
    };

    const getSelectedMediaSourceId = (path, itemId) => {
      // 1) select visible dans la même vue que le clic
      const localSel = findVisibleSourceSelectFromPath(path);
      const localVal = getSelectValueAsMediaSourceId(localSel);
      if (localVal) return localVal;

      // 2) select visible dans le document (page details active)
      const docSel = findVisibleSourceSelectInDocument();
      const docVal = getSelectValueAsMediaSourceId(docSel);
      if (docVal) return docVal;

      // 3) fallback mémoire par itemId
      if (itemId && lastSelectedByItem.has(itemId)) return lastSelectedByItem.get(itemId);

      return null;
    };

    // mémorise le choix quand l'utilisateur change la version
    document.addEventListener('change', (e) => {
      const t = e?.target;
      if (!t || !t.matches) return;

      if (!t.matches('select.selectSource.detailTrackSelect, select.selectSource')) return;
      if (!isVisible(t)) return;

      const itemId = getIdFromHash();
      const msid = getSelectValueAsMediaSourceId(t);
      if (itemId && msid) {
        lastSelectedByItem.set(itemId, msid);
        log('remember', { itemId, msid });
      }
    }, true);

    const stopEvent = (e) => {
      try { e.preventDefault(); } catch {}
      try { e.stopPropagation(); } catch {}
      try { e.stopImmediatePropagation(); } catch {}
    };

    const resolvePathFromItem = async (itemId, mediaSourceId = null, depth = 0) => {
      if (!itemId || depth > 6) return null;

      const userId = await getUserId();
      const item = await ApiClient.getItem(userId, itemId);

      // exceptions playlist + audio : on laisse Jellyfin gérer
      if (depth === 0 && isExcludedItem(item)) return SKIP_NATIVE;

      const ms = item && item.MediaSources;

      // priorité à la MediaSource sélectionnée
      if (mediaSourceId && ms && ms.length) {
        const wanted = ms.find(x =>
          String(x?.Id || '').toLowerCase() === String(mediaSourceId).toLowerCase() ||
          String(x?.MediaSourceId || '').toLowerCase() === String(mediaSourceId).toLowerCase()
        );
        if (wanted?.Path) return wanted.Path;
      }

      // comportement standard
      if (item?.Path && (!ms || ms.length <= 1)) return item.Path;
      if (ms?.length && ms[0]?.Path) return ms[0].Path;

      // Folder-like items: find a playable descendant
      const query = {
        parentId: itemId,
        recursive: true,
        includeItemTypes: 'Movie,Episode,Video',
        limit: 1,
        sortBy: 'SortName',
        sortOrder: 'Ascending'
      };

      const res = await ApiClient.getItems(userId, query);
      if (res?.Items?.length && res.Items[0]?.Id) {
        return resolvePathFromItem(res.Items[0].Id, null, depth + 1);
      }

      return null;
    };

    let _lastLaunchAt = 0;
    const launchMPCJF = async (itemId, mediaSourceId = null, control = null) => {
      const now = Date.now();
      if (now - _lastLaunchAt < 600) return;
      _lastLaunchAt = now;

      const p = await resolvePathFromItem(itemId, mediaSourceId);

      if (p === SKIP_NATIVE) {
        log('playlist/audio -> native Jellyfin', { itemId });
        replayNatively(control);
        return;
      }

      if (!p) {
        console.warn('[MPCJF] Unable to resolve a local Path for itemId:', itemId, 'mediaSourceId:', mediaSourceId);
        return;
      }

      const url = toMPCJFUrl(p);
      log('launch', { itemId, mediaSourceId, path: p, url });
      window.location.replace(url);
    };

    const shouldIgnore = (e) => {
      if (!e) return true;
      if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return true;
      if (typeof e.button === 'number' && e.button !== 0) return true;
      return false;
    };

    const onUserActivate = (e) => {
      if (bypassNative) return;
      if (shouldIgnore(e)) return;
      if (pointerDownOnDragHandle) return;

      const path = eventPath(e);
      const control = findControl(path);
      if (!control) return;

      if (isExcludedContext(path, control)) {
        log('playlist/audio context -> ignored', control);
        return;
      }

      const itemId = findItemIdInPath(path);
      if (!itemId) return;

      const mediaSourceId = getSelectedMediaSourceId(path, itemId);

      stopEvent(e);
      launchMPCJF(itemId, mediaSourceId, control);
    };

    document.addEventListener('click', onUserActivate, true);
    document.addEventListener('pointerup', onUserActivate, true);

    document.addEventListener('keydown', (e) => {
      if (bypassNative) return;

      const key = e && e.key;
      if (key !== 'Enter' && key !== ' ') return;

      const path = eventPath(e);
      const control = findControl(path);
      if (!control) return;

      if (isExcludedContext(path, control)) {
        log('playlist/audio context -> ignored', control);
        return;
      }

      const itemId = findItemIdInPath(path);
      if (!itemId) return;

      const mediaSourceId = getSelectedMediaSourceId(path, itemId);

      stopEvent(e);
      launchMPCJF(itemId, mediaSourceId, control);
    }, true);

    log('loaded');
  };

  (async () => {
    const notConfigured = !ALLOWED_DEVICE_ID || ALLOWED_DEVICE_ID === 'PUT_DEVICE_ID_HERE';
    const currentDeviceId = await waitForDeviceId();

    if (notConfigured) {
      console.warn('[MPCJF] Script disabled: set ALLOWED_DEVICE_ID first.', currentDeviceId ? { currentDeviceId } : '');
      if (currentDeviceId && isDesktopApp()) showDeviceIdHelper(currentDeviceId);
      return;
    }

    if (!currentDeviceId) {
      console.warn('[MPCJF] Script disabled: unable to read current Jellyfin DeviceId.');
      return;
    }

    if (String(currentDeviceId).trim() !== String(ALLOWED_DEVICE_ID).trim()) {
      log('disabled for this device', { currentDeviceId, allowed: ALLOWED_DEVICE_ID });
      return;
    }

    log('enabled for allowed device', { currentDeviceId });
    initMPCJF();
  })();
})();
