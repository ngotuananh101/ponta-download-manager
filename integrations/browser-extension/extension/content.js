// PDM media capture (content script). Scans the page for video and
// audio URLs — <video>/<audio> src and <source> children, plus links
// to media files — and reports them to the background script, which
// the popup lists per tab. Images are deliberately not captured.
// Only http(s) URLs are reported: blob: and data: URLs cannot be
// downloaded by PDM.

const VIDEO_EXTS = new Set([
  'mp4', 'webm', 'mkv', 'mov', 'avi', 'm4v', 'mpg', 'mpeg', '3gp',
]);
const AUDIO_EXTS = new Set([
  'mp3', 'flac', 'wav', 'ogg', 'm4a', 'aac', 'wma', 'opus',
]);

function mediaType(url) {
  let path;
  try {
    path = new URL(url).pathname;
  } catch {
    return null;
  }
  const ext = path.split('.').pop().toLowerCase();
  if (VIDEO_EXTS.has(ext)) {
    return 'video';
  }
  if (AUDIO_EXTS.has(ext)) {
    return 'audio';
  }
  return null;
}

function isMediaUrl(url) {
  return mediaType(url) !== null;
}

function fileNameFromMediaUrl(url) {
  try {
    const parsed = new URL(url);
    const segments = parsed.pathname.split('/');
    const last = segments[segments.length - 1];
    if (!last) {
      return 'media';
    }
    try {
      return decodeURIComponent(last);
    } catch {
      return last;
    }
  } catch {
    return 'media';
  }
}

// Scans a document-like object ({querySelectorAll, baseURI}) and
// returns deduped {url, fileName, type} items. Kept pure so node
// tests can drive it with a fake DOM.
function collectMedia(doc) {
  const seen = new Set();
  const items = [];
  const add = (raw, type) => {
    if (!raw) {
      return;
    }
    let url;
    try {
      url = new URL(raw, doc.baseURI || 'http://localhost/').href;
    } catch {
      return;
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return;
    }
    if (seen.has(url)) {
      return;
    }
    const resolvedType = type || mediaType(url);
    if (!resolvedType) {
      return;
    }
    seen.add(url);
    items.push({
      url,
      fileName: fileNameFromMediaUrl(url),
      type: resolvedType,
    });
  };
  for (const media of doc.querySelectorAll('video, audio')) {
    const tagType =
      media.tagName.toLowerCase() === 'video' ? 'video' : 'audio';
    add(media.getAttribute('src'), tagType);
    for (const source of media.querySelectorAll('source')) {
      add(source.getAttribute('src'), tagType);
    }
  }
  for (const link of doc.querySelectorAll('a[href]')) {
    add(link.getAttribute('href'));
  }
  return items;
}

function scanAndSend() {
  if (typeof chrome === 'undefined' || !chrome.runtime) {
    return;
  }
  chrome.runtime.sendMessage({
    type: 'media.found',
    items: collectMedia(document),
  });
}

// In the real extension, scan once at load and re-scan (debounced)
// when the DOM changes, so dynamically added media is picked up.
if (typeof chrome !== 'undefined' && chrome.runtime && chrome.runtime.id) {
  scanAndSend();
  let scanTimer = null;
  const scheduleScan = () => {
    if (scanTimer) {
      return;
    }
    scanTimer = setTimeout(() => {
      scanTimer = null;
      scanAndSend();
    }, 500);
  };
  if (typeof MutationObserver !== 'undefined' && document.body) {
    new MutationObserver(scheduleScan).observe(document.body, {
      childList: true,
      subtree: true,
    });
  }
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {collectMedia, isMediaUrl, mediaType, fileNameFromMediaUrl};
}
