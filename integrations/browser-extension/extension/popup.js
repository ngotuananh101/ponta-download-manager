// PDM popup: one list of everything downloadable on the active tab —
// the formats the yt-dlp probe found for the page and the video/audio
// the content script scanned — plus the download-interception toggle.
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

  // The two sources render into the same list. Page media is known as
  // soon as storage answers; the yt-dlp formats arrive later, after the
  // probe, and outrank the page scan (the probe knows the real streams
  // behind a player page, which a scan cannot see). Re-rendering the
  // whole list on every update keeps one ordering rule: formats on top,
  // then page media, never two half-lists side by side.
  let mediaItems = [];
  let formatRows = [];
  // Whether the probe has answered (or will never run). Until then the
  // page scan's empty list proves nothing about the page.
  let probeSettled = false;

  function renderMediaRow(item) {
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
    return row;
  }

  // The empty message speaks for both sources: it may only claim
  // nothing was found once neither has anything to show. While the
  // probe is still running the page scan's result alone decides, so a
  // popup with media never flashes the message.
  function render() {
    listEl.innerHTML = '';
    for (const row of formatRows) {
      listEl.append(row);
    }
    for (const item of mediaItems) {
      listEl.append(renderMediaRow(item));
    }
    emptyEl.hidden =
      formatRows.length > 0 || mediaItems.length > 0 || !probeSettled;
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
    mediaItems = (reply && reply.items) || [];
    render();
  });

  // yt-dlp probe: resolve the active tab first — its URL is the video
  // URL the ytdlp.download message needs, and the page the video came
  // from (the referrer) — then ask the background to probe it. A tab
  // that is not http(s) (chrome://, about:, file:, ...) is never
  // probed and shows no error: there is no probe result to show.
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
  function isHttpUrl(url) {
    return typeof url === 'string' && /^https?:\/\//i.test(url);
  }

  const applyProbeState = (state) => {
    probeSettled = state.state !== 'loading';
    formatRows = probeHelpers.probeView(doc, state, onProbeDownload);
    render();
  };

  const sendProbe = () => {
    chromeApi.runtime.sendMessage({type: 'ytdlp.probe'}, (reply) => {
      applyProbeState(probeHelpers.probeState(reply));
    });
  };

  const startProbe = () => {
    applyProbeState({state: 'loading'});
    sendProbe();
  };
  if (chromeApi.tabs && chromeApi.tabs.query) {
    chromeApi.tabs.query({active: true, currentWindow: true}, (tabs) => {
      tabUrl = tabs && tabs[0] && tabs[0].url ? tabs[0].url : null;
      if (isHttpUrl(tabUrl)) {
        startProbe();
      } else {
        // No probe will run, so the page scan is the only source: let
        // the empty message account for its result now.
        probeSettled = true;
        render();
      }
    });
  } else {
    startProbe();
  }
}

if (typeof chrome !== 'undefined' && typeof document !== 'undefined') {
  initPopup(document, chrome);
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {initPopup};
}
