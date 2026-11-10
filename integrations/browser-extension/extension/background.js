// PDM browser extension (MV3 service worker).
// Adds a "Download with PDM" context-menu entry and forwards the
// click to the native host, which talks to the running engine.
// All chrome.* access goes through `chromeApi` so tests can
// substitute a fake.

const HOST_NAME = 'com.ponta.pdm';

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

function setupExtension(chromeApi) {
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
    const fileName = fileNameFromUrl(url);
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
  });
}

// In the real extension, `chrome` is the global API object.
if (typeof chrome !== 'undefined' && chrome.runtime && chrome.runtime.id) {
  setupExtension(chrome);
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {setupExtension, fileNameFromUrl, HOST_NAME};
}
