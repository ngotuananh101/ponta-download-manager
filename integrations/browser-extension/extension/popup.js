// PDM popup: lists the video/audio the content script found on the
// active tab, the download-interception toggle, and the yt-dlp probe
// section (formats for the current page, when yt-dlp supports it).
// The probe helpers live in popup_probe.js (loaded before this file);
// in node tests they come from require('./popup_probe.js') instead.
const probeHelpers =
  typeof module !== 'undefined' && module.exports
    ? require('./popup_probe.js')
    : globalThis;

function initPopup(doc, chromeApi) {
  const listEl = doc.getElementById('list');
  const emptyEl = doc.getElementById('empty');
  const toggleEl = doc.getElementById('intercept');

  function render(items) {
    listEl.innerHTML = '';
    emptyEl.hidden = items.length > 0;
    for (const item of items) {
      const row = doc.createElement('li');
      const badge = doc.createElement('span');
      badge.className = 'badge ' + item.type;
      badge.textContent = item.type;
      const name = doc.createElement('span');
      name.className = 'name';
      name.textContent = item.fileName || item.url;
      name.title = item.url;
      const button = doc.createElement('button');
      button.textContent = 'Download';
      button.addEventListener('click', () => {
        button.disabled = true;
        button.textContent = 'Sent';
        chromeApi.runtime.sendMessage({
          type: 'media.download',
          url: item.url,
          fileName: item.fileName,
          referrer: item.referrer,
        });
      });
      row.append(badge, name, button);
      listEl.append(row);
    }
  }

  chromeApi.runtime.sendMessage({type: 'intercept.get'}, (reply) => {
    toggleEl.checked = !reply || reply.enabled !== false;
  });
  toggleEl.addEventListener('change', () => {
    chromeApi.runtime.sendMessage({
      type: 'intercept.set',
      enabled: toggleEl.checked,
    });
  });
  chromeApi.runtime.sendMessage({type: 'media.list'}, (reply) => {
    render((reply && reply.items) || []);
  });

  // yt-dlp probe: resolve the active tab first — its URL is the video
  // URL the ytdlp.download message needs, and the page the video came
  // from (the referrer) — then ask the background to probe it.
  let tabUrl = null;
  const onProbeDownload = (choice) => {
    chromeApi.runtime.sendMessage({
      type: 'ytdlp.download',
      url: tabUrl,
      formatId: choice.format.formatId,
      fileName: choice.fileName,
      referrer: tabUrl,
    });
  };
  probeHelpers.renderProbe(doc, {state: 'loading'}, onProbeDownload);
  const sendProbe = () => {
    chromeApi.runtime.sendMessage({type: 'ytdlp.probe'}, (reply) => {
      probeHelpers.renderProbe(
        doc,
        probeHelpers.probeState(reply),
        onProbeDownload,
      );
    });
  };
  if (chromeApi.tabs && chromeApi.tabs.query) {
    chromeApi.tabs.query({active: true, currentWindow: true}, (tabs) => {
      tabUrl = tabs && tabs[0] && tabs[0].url ? tabs[0].url : null;
      sendProbe();
    });
  } else {
    sendProbe();
  }
}

if (typeof chrome !== 'undefined' && typeof document !== 'undefined') {
  initPopup(document, chrome);
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {initPopup};
}
