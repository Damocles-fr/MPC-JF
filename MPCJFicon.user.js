// ==UserScript==
// @name         MPC-JF - MPC icon launcher for Jellyfin
// @namespace    https://github.com/Damocles-fr/MPCJF/
// @version      10.11.1
// @updateURL    https://raw.githubusercontent.com/Damocles-fr/MPCJF/refs/heads/main/MPCJFicon.user.js
// @downloadURL  https://raw.githubusercontent.com/Damocles-fr/MPCJF/refs/heads/main/MPCJFicon.user.js
// @description  Add a dedicated MPC-JF launcher button on Jellyfin media detail pages. Native Play buttons stay untouched.
// @author       Damocles-fr
// @match        http://localhost:8096/*
// @run-at       document-end
// @grant        none
// ==/UserScript==

(() => {
  'use strict';

  const ICON_SRC = 'data:image/webp;base64,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';
  const BTN_CLASS = 'mpcjf-launcher-btn';
  const STYLE_ID = 'mpcjf-launcher-style';
  const lastSelectedByItem = new Map();

  let userIdPromise = null;
  let lastLaunchAt = 0;
  let syncQueued = false;

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

  const toMPCJFUrl = (rawPath) => {
    const forward = String(rawPath).replace(/\\/g, '/');
    const encoded = encodeURIComponent(forward).replace(/%2F/g, '/');
    return 'MPCJF://' + encoded;
  };

  const getSelectedMediaSourceId = (itemId) => {
    const sel = [...document.querySelectorAll('select.selectSource.detailTrackSelect, select.selectSource')].find(isVisible);
    const value = String(sel?.value || sel?.selectedOptions?.[0]?.value || '');
    if (isGuidLike(value)) return value;
    return itemId && lastSelectedByItem.has(itemId) ? lastSelectedByItem.get(itemId) : null;
  };

  const resolvePathFromItem = async (itemId, mediaSourceId = null, depth = 0) => {
    if (!itemId || depth > 6) return null;

    const userId = await getUserId();
    const item = await ApiClient.getItem(userId, itemId);
    const mediaSources = item?.MediaSources || [];

    if (mediaSourceId && mediaSources.length) {
      const wanted = mediaSources.find((x) =>
        String(x?.Id || '').toLowerCase() === String(mediaSourceId).toLowerCase() ||
        String(x?.MediaSourceId || '').toLowerCase() === String(mediaSourceId).toLowerCase()
      );
      if (wanted?.Path) return wanted.Path;
    }

    if (item?.Path && mediaSources.length <= 1) return item.Path;
    if (mediaSources[0]?.Path) return mediaSources[0].Path;

    const res = await ApiClient.getItems(userId, {
      parentId: itemId,
      recursive: true,
      includeItemTypes: 'Movie,Episode,Video',
      limit: 1,
      sortBy: 'SortName',
      sortOrder: 'Ascending'
    });

    const childId = res?.Items?.[0]?.Id;
    return childId ? resolvePathFromItem(childId, null, depth + 1) : null;
  };

  const launchMPCJF = async () => {
    const now = Date.now();
    if (now - lastLaunchAt < 600) return;
    lastLaunchAt = now;

    const itemId = getItemIdFromHash();
    if (!itemId) return;

    const mediaSourceId = getSelectedMediaSourceId(itemId);
    const path = await resolvePathFromItem(itemId, mediaSourceId);
    if (!path) {
      console.warn('[MPCJF] Unable to resolve a local path for itemId:', itemId, 'mediaSourceId:', mediaSourceId);
      return;
    }

    window.location.replace(toMPCJFUrl(path));
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
        width: 1.9rem;
        height: 1.9rem;
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
    btn.title = 'Open with MPC-JF';
    btn.setAttribute('aria-label', 'Open with MPC-JF');

    const img = document.createElement('img');
    img.src = ICON_SRC;
    img.alt = '';
    img.decoding = 'async';
    btn.appendChild(img);

    btn.addEventListener(
      'click',
      (e) => {
        e.preventDefault();
        e.stopPropagation();
        e.stopImmediatePropagation?.();
        launchMPCJF();
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
    if (!itemId || !String(location.hash || '').includes('#/details')) {
      removeStaleButtons();
      return;
    }

    injectStyle();

    const host = findButtonsHost();
    if (!host) return;

    const existing = host.querySelector('.' + BTN_CLASS);
    if (existing && existing.dataset.itemId === itemId) return;

    removeStaleButtons();

    const btn = createButton(itemId);
    const firstAction = [...host.children].find((el) => el.matches?.('button,a,[role="button"]'));

    if (firstAction?.nextSibling) host.insertBefore(btn, firstAction.nextSibling);
    else if (firstAction) host.appendChild(btn);
    else host.prepend(btn);
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
    },
    true
  );

  new MutationObserver(scheduleSync).observe(document.body, { childList: true, subtree: true });
  window.addEventListener('hashchange', scheduleSync, true);
  window.addEventListener('popstate', scheduleSync, true);
  scheduleSync();
})();