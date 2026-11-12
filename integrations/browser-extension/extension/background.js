// PDM browser extension (MV3 service worker).
// Adds a "Download with PDM" context-menu entry and forwards the
// click to the native host, which talks to the running engine.
// All chrome.* access goes through `chromeApi` so tests can
// substitute a fake.

const HOST_NAME = 'com.ponta.pdm';

// Interception is on by default; the popup flips it in storage.
let interceptEnabled = true;

// Media found on each tab, by tab id. Filled by content scripts,
// cleared when a tab closes or navigates.
//
// It lives in chrome.storage.session, not an in-memory Map: an MV3
// service worker is evicted when idle, and a Map would lose every
// tab's media with it. The Map below is only a fallback for browsers
// without storage.session (older Firefox); the session store is the
// source of truth whenever it exists.
const MEDIA_KEY = 'mediaByTab';
const mediaByTab = new Map();

function mediaStore(chromeApi) {
  return chromeApi.storage && chromeApi.storage.session
    ? chromeApi.storage.session
    : null;
}

function getMediaForTab(chromeApi, tabId, callback) {
  const store = mediaStore(chromeApi);
  if (store == null) {
    callback(mediaByTab.get(tabId) || []);
    return;
  }
  store.get({[MEDIA_KEY]: {}}, (items) => {
    const byTab = (items && items[MEDIA_KEY]) || {};
    callback(byTab[tabId] || []);
  });
}

function setMediaForTab(chromeApi, tabId, items) {
  const store = mediaStore(chromeApi);
  if (store == null) {
    mediaByTab.set(tabId, items);
    return;
  }
  store.get({[MEDIA_KEY]: {}}, (stored) => {
    const byTab = {...((stored && stored[MEDIA_KEY]) || {})};
    byTab[tabId] = items;
    store.set({[MEDIA_KEY]: byTab}, () => {});
  });
}

function clearMediaForTab(chromeApi, tabId) {
  const store = mediaStore(chromeApi);
  if (store == null) {
    mediaByTab.delete(tabId);
    return;
  }
  store.get({[MEDIA_KEY]: {}}, (stored) => {
    const byTab = {...((stored && stored[MEDIA_KEY]) || {})};
    if (!(tabId in byTab)) {
      return;
    }
    delete byTab[tabId];
    store.set({[MEDIA_KEY]: byTab}, () => {});
  });
}

// Downloads we have decided to intercept, by download id. A download
// is paused in onCreated and only cancelled once
// onDeterminingFilename has deferred Chrome's Save As dialog; without
// that deferral the dialog opens before the cancel lands, so the user
// sees both the browser dialog and the PDM download.
const pendingIntercept = new Set();

function fileNameFromUrl(url) {
  try {
    const parsed = new URL(url);
    const segments = parsed.pathname.split('/').filter(Boolean);
    const last = segments[segments.length - 1];
    return last || undefined;
  } catch {
    return undefined;
  }
}

// Only http(s) can be handed to PDM. blob: and data: URLs live only
// in the browser's memory, so the browser keeps downloading those.
function isInterceptableUrl(url) {
  return (
    typeof url === 'string' &&
    (url.startsWith('http://') || url.startsWith('https://'))
  );
}

// The browser's suggested file name, if any, wins over the URL;
// it may carry a directory, so only the last segment is used.
function fileNameFromDownloadItem(item) {
  if (item.filename) {
    const base = item.filename.split('/').pop().split('\\').pop();
    if (base) {
      return base;
    }
  }
  return fileNameFromUrl(item.url);
}

function randomId() {
  if (typeof crypto !== 'undefined' && crypto.randomUUID) {
    return crypto.randomUUID();
  }
  return `req-${Date.now()}-${Math.floor(Math.random() * 1e9)}`;
}

function showError(chromeApi, message) {
  chromeApi.notifications.create({
    type: 'basic',
    iconUrl: 'icons/icon48.png',
    title: 'PDM download failed',
    message,
  });
}

// Sends one download to PDM through the native host. Shared by the
// context menu and the download interceptor.
function sendDownload(chromeApi, url, fileName) {
  const id = randomId();
  let port;
  try {
    port = chromeApi.runtime.connectNative(HOST_NAME);
  } catch {
    showError(
      chromeApi,
      'PDM native host is not installed — run install.sh',
    );
    return;
  }
  const onMessage = (reply) => {
    if (!reply || reply.id !== id) {
      return;
    }
    port.onMessage.removeListener(onMessage);
    port.disconnect();
    if (reply.ok) {
      chromeApi.notifications.create({
        type: 'basic',
        iconUrl: 'icons/icon48.png',
        title: 'Download added',
        message: fileName ? `${fileName} — download started` : 'Download started',
      });
    } else {
      showError(chromeApi, reply.message || 'Download failed');
    }
  };
  const onDisconnect = () => {
    port.onMessage.removeListener(onMessage);
    const error = chromeApi.runtime.lastError;
    if (error) {
      showError(
        chromeApi,
        'PDM native host is not installed — run install.sh',
      );
    }
  };
  port.onMessage.addListener(onMessage);
  port.onDisconnect.addListener(onDisconnect);
  port.postMessage({type: 'download.create', id, url, fileName});
}

// Intercepts one browser download: stops the browser's own download
// and hands the URL to PDM instead. Returns true when the download
// was intercepted.
function interceptDownload(chromeApi, item) {
  if (!interceptEnabled) {
    return false;
  }
  if (!item || !isInterceptableUrl(item.url)) {
    return false;
  }
  const fileName = fileNameFromDownloadItem(item);
  if (chromeApi.downloads.cancel) {
    chromeApi.downloads.cancel(item.id, () => {});
  }
  if (chromeApi.downloads.erase) {
    chromeApi.downloads.erase({id: item.id}, () => {});
  }
  sendDownload(chromeApi, item.url, fileName);
  return true;
}

// Marks a download for interception and pauses it, so no data moves
// before onDeterminingFilename decides. Returns true when the
// download is held for interception.
function holdForIntercept(chromeApi, item) {
  if (!interceptEnabled) {
    return false;
  }
  if (!item || !isInterceptableUrl(item.url)) {
    return false;
  }
  pendingIntercept.add(item.id);
  if (chromeApi.downloads.pause) {
    chromeApi.downloads.pause(item.id, () => {});
  }
  return true;
}

// Runs when Chrome determines a download's file name. Returning true
// defers the Save As dialog until suggest() is called; on intercept
// suggest is never called and the download is cancelled first, so
// Chrome never reaches the dialog step.
function handleDeterminingFilename(chromeApi, item, suggest) {
  if (!pendingIntercept.has(item.id)) {
    return false;
  }
  pendingIntercept.delete(item.id);
  if (interceptDownload(chromeApi, item)) {
    return true;
  }
  // Interception was turned off after the download was held: give
  // the download back to the browser.
  if (chromeApi.downloads.resume) {
    chromeApi.downloads.resume(item.id, () => {});
  }
  return false;
}

function loadInterceptSetting(chromeApi) {
  interceptEnabled = true;
  if (!chromeApi.storage || !chromeApi.storage.local) {
    return;
  }
  chromeApi.storage.local.get({pdmIntercept: true}, (items) => {
    interceptEnabled = items.pdmIntercept !== false;
  });
  if (chromeApi.storage.onChanged) {
    chromeApi.storage.onChanged.addListener((changes, area) => {
      if (area === 'local' && changes.pdmIntercept) {
        interceptEnabled = changes.pdmIntercept.newValue !== false;
      }
    });
  }
}

function setInterceptEnabled(chromeApi, enabled) {
  interceptEnabled = enabled;
  if (chromeApi.storage && chromeApi.storage.local) {
    chromeApi.storage.local.set({pdmIntercept: enabled}, () => {});
  }
}

// Answers messages from the popup and from content scripts.
function handleMessage(chromeApi, message, sender, sendResponse) {
  if (!message || typeof message.type !== 'string') {
    return false;
  }
  switch (message.type) {
    case 'media.found': {
      const tabId = sender && sender.tab && sender.tab.id;
      if (typeof tabId === 'number' && Array.isArray(message.items)) {
        setMediaForTab(chromeApi, tabId, message.items);
      }
      return false;
    }
    case 'media.list': {
      if (!chromeApi.tabs || !chromeApi.tabs.query) {
        sendResponse({items: []});
        return false;
      }
      chromeApi.tabs.query({active: true, currentWindow: true}, (tabs) => {
        const tabId = tabs && tabs[0] && tabs[0].id;
        if (typeof tabId !== 'number') {
          sendResponse({items: []});
          return;
        }
        getMediaForTab(chromeApi, tabId, (items) => {
          sendResponse({items});
        });
      });
      return true;
    }
    case 'media.download': {
      if (typeof message.url === 'string') {
        sendDownload(chromeApi, message.url, message.fileName);
      }
      sendResponse({ok: true});
      return false;
    }
    case 'intercept.get': {
      sendResponse({enabled: interceptEnabled});
      return false;
    }
    case 'intercept.set': {
      setInterceptEnabled(chromeApi, message.enabled !== false);
      sendResponse({ok: true});
      return false;
    }
    default:
      return false;
  }
}

function setupExtension(chromeApi) {
  loadInterceptSetting(chromeApi);
  chromeApi.runtime.onInstalled.addListener(() => {
    chromeApi.contextMenus.create({
      id: 'pdm-download-link',
      title: 'Download with PDM',
      contexts: ['link'],
    });
    chromeApi.contextMenus.create({
      id: 'pdm-download-media',
      title: 'Download with PDM',
      contexts: ['image', 'video', 'audio'],
    });
  });

  chromeApi.contextMenus.onClicked.addListener((info) => {
    const url = info.linkUrl || info.srcUrl;
    if (!url) {
      return;
    }
    sendDownload(chromeApi, url, fileNameFromUrl(url));
  });

  if (chromeApi.downloads && chromeApi.downloads.onCreated) {
    chromeApi.downloads.onCreated.addListener((item) => {
      if (chromeApi.downloads.onDeterminingFilename) {
        // Two-stage: pause now, defer the Save As dialog and cancel
        // in onDeterminingFilename.
        holdForIntercept(chromeApi, item);
      } else {
        // No onDeterminingFilename (older browser): cancel at once.
        interceptDownload(chromeApi, item);
      }
    });
  }

  if (chromeApi.downloads && chromeApi.downloads.onDeterminingFilename) {
    chromeApi.downloads.onDeterminingFilename.addListener(
      (item, suggest) => {
        return handleDeterminingFilename(chromeApi, item, suggest);
      },
    );
  }

  if (chromeApi.runtime.onMessage) {
    chromeApi.runtime.onMessage.addListener((message, sender, sendResponse) => {
      return handleMessage(chromeApi, message, sender, sendResponse);
    });
  }

  if (chromeApi.tabs) {
    if (chromeApi.tabs.onRemoved) {
      chromeApi.tabs.onRemoved.addListener((tabId) => {
        clearMediaForTab(chromeApi, tabId);
      });
    }
    if (chromeApi.tabs.onUpdated) {
      chromeApi.tabs.onUpdated.addListener((tabId, changeInfo) => {
        if (changeInfo.url) {
          clearMediaForTab(chromeApi, tabId);
        }
      });
    }
  }
}

// In the real extension, `chrome` is the global API object.
if (typeof chrome !== 'undefined' && chrome.runtime && chrome.runtime.id) {
  setupExtension(chrome);
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    setupExtension,
    fileNameFromUrl,
    isInterceptableUrl,
    fileNameFromDownloadItem,
    HOST_NAME,
  };
}
