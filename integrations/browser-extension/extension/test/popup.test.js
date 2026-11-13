const test = require('node:test');
const assert = require('node:assert/strict');
const {
  formatBytes,
  formatLabel,
  sanitizeFileName,
  fileNameForProbe,
  probeState,
  renderProbe,
} = require('../popup_probe.js');
const {initPopup} = require('../popup.js');

function fakeEl(tag) {
  const listeners = {};
  const el = {
    tagName: tag.toUpperCase(),
    children: [],
    textContent: '',
    className: '',
    hidden: false,
    disabled: false,
    checked: false,
    title: '',
    addEventListener: (type, fn) => {
      (listeners[type] = listeners[type] || []).push(fn);
    },
    append: (...nodes) => {
      el.children.push(...nodes);
    },
    click: () => {
      (listeners.click || []).forEach((fn) => fn());
    },
  };
  Object.defineProperty(el, 'innerHTML', {
    get: () => '',
    set: (value) => {
      if (value === '') {
        el.children = [];
      }
    },
  });
  return el;
}

function fakeDoc() {
  const byId = {
    list: fakeEl('ul'),
    empty: fakeEl('p'),
    intercept: fakeEl('input'),
    'probe-status': fakeEl('p'),
    'probe-title': fakeEl('h2'),
    'probe-formats': fakeEl('ul'),
  };
  // Mirror the initial hidden state of popup.html.
  byId.empty.hidden = true;
  byId['probe-status'].hidden = true;
  byId['probe-title'].hidden = true;
  byId['probe-formats'].hidden = true;
  return {
    byId,
    getElementById: (id) => byId[id] || null,
    createElement: (tag) => fakeEl(tag),
  };
}

const TAB_URL = 'https://www.youtube.com/watch?v=abc123';

function fakeChrome() {
  const sent = [];
  const probeCallbacks = [];
  return {
    sent,
    replyProbe: (reply) => {
      probeCallbacks.forEach((cb) => cb(reply));
    },
    tabs: {
      query: (query, cb) => {
        cb([{url: TAB_URL}]);
      },
    },
    runtime: {
      sendMessage: (message, cb) => {
        sent.push(message);
        if (message.type === 'ytdlp.probe') {
          probeCallbacks.push(cb);
        } else if (message.type === 'media.list') {
          cb({items: []});
        } else if (message.type === 'intercept.get') {
          cb({enabled: true});
        } else if (cb) {
          cb({});
        }
      },
    },
  };
}

const supportedProbe = {
  supported: true,
  title: 'My Video: Part 1/2',
  thumbnail: 'https://i.ytimg.com/vi/abc123/hqdefault.jpg',
  durationSeconds: 360,
  formats: [
    {
      formatId: '137',
      ext: 'mp4',
      resolution: '1920x1080',
      width: 1920,
      height: 1080,
      filesize: 104857600,
      filesizeApprox: null,
      vcodec: 'avc1',
      acodec: 'none',
      fps: 30,
      note: '1080p',
    },
    {
      formatId: '18',
      ext: 'mp4',
      resolution: '640x360',
      width: 640,
      height: 360,
      filesize: 12345678,
      filesizeApprox: null,
      vcodec: 'avc1',
      acodec: 'mp4a',
      fps: 30,
      note: '360p',
    },
    {
      formatId: '140',
      ext: 'm4a',
      resolution: null,
      width: null,
      height: null,
      filesize: 4194304,
      filesizeApprox: null,
      vcodec: 'none',
      acodec: 'mp4a',
      fps: null,
      note: 'medium',
    },
  ],
};

function openPopup() {
  const doc = fakeDoc();
  const chromeApi = fakeChrome();
  initPopup(doc, chromeApi);
  return {doc, chromeApi};
}

test('formatBytes formats byte counts', () => {
  assert.equal(formatBytes(0), '0 B');
  assert.equal(formatBytes(512), '512 B');
  assert.equal(formatBytes(2048), '2.0 KiB');
  assert.equal(formatBytes(12345678), '11.8 MiB');
  assert.equal(formatBytes(3 * 1024 * 1024 * 1024), '3.0 GiB');
  assert.equal(formatBytes(null), '');
});

test('formatLabel shows resolution, ext and size', () => {
  assert.equal(
    formatLabel(supportedProbe.formats[1]),
    '360p · mp4 · 11.8 MiB',
  );
  assert.equal(
    formatLabel(supportedProbe.formats[0]),
    '1080p · video only · mp4 · 100.0 MiB',
  );
  assert.equal(
    formatLabel(supportedProbe.formats[2]),
    'medium · audio only · m4a · 4.0 MiB',
  );
});

test('sanitizeFileName strips characters the host rejects', () => {
  assert.equal(sanitizeFileName('My Video: Part 1/2'), 'My Video Part 12');
  assert.equal(sanitizeFileName('a..b'), 'a.b');
  assert.equal(sanitizeFileName(''), 'video');
  assert.equal(sanitizeFileName('  spaced  out  '), 'spaced out');
});

test('fileNameForProbe sanitizes the title and appends the ext', () => {
  assert.equal(
    fileNameForProbe(supportedProbe, supportedProbe.formats[0]),
    'My Video Part 12.mp4',
  );
  assert.equal(
    fileNameForProbe({title: ''}, supportedProbe.formats[2]),
    'video.m4a',
  );
});

test('probeState maps replies to states', () => {
  assert.equal(probeState(undefined).state, 'error');
  assert.match(
    probeState({ok: false, code: 'internal'}).message,
    /Start the app/,
  );
  assert.equal(
    probeState({
      ok: false,
      code: 'yt-dlp-probe-failed',
      message: 'boom',
    }).message,
    'boom',
  );
  assert.equal(
    probeState({
      ok: true,
      probe: {supported: false, errorCode: 'yt-dlp-unsupported'},
    }).state,
    'not-supported',
  );
  assert.equal(
    probeState({
      ok: true,
      probe: {supported: false, errorCode: 'unavailable'},
    }).state,
    'unavailable',
  );
  assert.equal(probeState({ok: true, probe: supportedProbe}).state, 'formats');
  assert.equal(
    probeState({ok: true, probe: {supported: true, formats: []}}).state,
    'not-supported',
  );
});

test('error state marks the status line', () => {
  const doc = fakeDoc();
  renderProbe(doc, {state: 'error', message: 'boom'}, () => {});
  assert.equal(doc.byId['probe-status'].className, 'error');
});

test('loading state has no error class', () => {
  const doc = fakeDoc();
  renderProbe(doc, {state: 'loading'}, () => {});
  assert.equal(doc.byId['probe-status'].className, '');
});

test('renderProbe shows the loading state', () => {
  const doc = fakeDoc();
  let downloaded = null;
  renderProbe(doc, {state: 'loading'}, (choice) => {
    downloaded = choice;
  });
  assert.equal(doc.byId['probe-status'].hidden, false);
  assert.match(doc.byId['probe-status'].textContent, /Checking/);
  assert.equal(doc.byId['probe-title'].hidden, true);
  assert.equal(doc.byId['probe-formats'].hidden, true);
  assert.equal(downloaded, null);
});

test('loading state shows while the probe is pending', () => {
  const {doc, chromeApi} = openPopup();
  assert.deepEqual(
    chromeApi.sent.map((m) => m.type),
    ['intercept.get', 'media.list', 'ytdlp.probe'],
  );
  assert.equal(doc.byId['probe-status'].hidden, false);
  assert.match(doc.byId['probe-status'].textContent, /Checking/);
  assert.equal(doc.byId['probe-formats'].children.length, 0);
});

test('formats render with the right labels', () => {
  const {doc, chromeApi} = openPopup();
  chromeApi.replyProbe({ok: true, probe: supportedProbe});
  assert.equal(doc.byId['probe-title'].hidden, false);
  assert.equal(doc.byId['probe-title'].textContent, 'My Video: Part 1/2');
  assert.equal(doc.byId['probe-status'].hidden, true);
  const rows = doc.byId['probe-formats'].children;
  assert.equal(rows.length, 3);
  const labels = rows.map((row) => row.children[0].textContent);
  assert.deepEqual(labels, [
    '1080p · video only · mp4 · 100.0 MiB',
    '360p · mp4 · 11.8 MiB',
    'medium · audio only · m4a · 4.0 MiB',
  ]);
});

test('unsupported shows the not-supported message', () => {
  const {doc, chromeApi} = openPopup();
  chromeApi.replyProbe({
    ok: true,
    probe: {supported: false, errorCode: 'yt-dlp-unsupported'},
  });
  assert.equal(doc.byId['probe-status'].hidden, false);
  assert.match(doc.byId['probe-status'].textContent, /not support/i);
  assert.equal(doc.byId['probe-formats'].children.length, 0);
});

test('unavailable shows the unavailable message', () => {
  const {doc, chromeApi} = openPopup();
  chromeApi.replyProbe({
    ok: true,
    probe: {supported: false, errorCode: 'unavailable'},
  });
  assert.equal(doc.byId['probe-status'].hidden, false);
  assert.match(doc.byId['probe-status'].textContent, /unavailable/i);
  assert.equal(doc.byId['probe-formats'].children.length, 0);
});

test('error shows the error message', () => {
  const {doc, chromeApi} = openPopup();
  chromeApi.replyProbe({
    ok: false,
    code: 'yt-dlp-probe-failed',
    message: 'yt-dlp exited with code 1',
  });
  assert.equal(
    doc.byId['probe-status'].textContent,
    'yt-dlp exited with code 1',
  );
  assert.equal(doc.byId['probe-formats'].children.length, 0);
});

test("clicking a format's Download posts ytdlp.download with that formatId", () => {
  const {doc, chromeApi} = openPopup();
  chromeApi.replyProbe({ok: true, probe: supportedProbe});
  const rows = doc.byId['probe-formats'].children;
  const button = rows[0].children[1];
  assert.equal(button.textContent, 'Download');
  button.click();
  assert.equal(button.disabled, true);
  assert.equal(button.textContent, 'Sent');
  const download = chromeApi.sent.find((m) => m.type === 'ytdlp.download');
  assert.deepEqual(download, {
    type: 'ytdlp.download',
    url: TAB_URL,
    formatId: '137',
    fileName: 'My Video Part 12.mp4',
    referrer: TAB_URL,
  });
});

test('media badges carry the media type class', () => {
  const doc = fakeDoc();
  const chromeApi = fakeChrome();
  chromeApi.runtime.sendMessage = (message, cb) => {
    chromeApi.sent.push(message);
    if (message.type === 'media.list') {
      cb({
        items: [
          {
            url: 'https://cdn.example.com/clip.mp4',
            fileName: 'clip.mp4',
            type: 'video',
            referrer: TAB_URL,
          },
          {
            url: 'https://cdn.example.com/song.mp3',
            fileName: 'song.mp3',
            type: 'audio',
            referrer: TAB_URL,
          },
        ],
      });
    } else if (message.type === 'intercept.get') {
      cb({enabled: true});
    } else if (cb) {
      cb({});
    }
  };
  initPopup(doc, chromeApi);
  assert.equal(doc.byId.list.children.length, 2);
  assert.equal(
    doc.byId.list.children[0].children[0].className,
    'badge video',
  );
  assert.equal(
    doc.byId.list.children[1].children[0].className,
    'badge audio',
  );
});

test('probe is not sent for a non-http tab', () => {
  const doc = fakeDoc();
  const chromeApi = fakeChrome();
  chromeApi.tabs.query = (query, cb) => {
    cb([{url: 'chrome://extensions'}]);
  };
  initPopup(doc, chromeApi);
  assert.equal(
    chromeApi.sent.some((m) => m.type === 'ytdlp.probe'),
    false,
  );
  assert.equal(doc.byId['probe-status'].hidden, true);
  assert.equal(doc.byId['probe-formats'].hidden, true);
});

test('probe is not sent when there is no active tab', () => {
  const doc = fakeDoc();
  const chromeApi = fakeChrome();
  chromeApi.tabs.query = (query, cb) => {
    cb([]);
  };
  initPopup(doc, chromeApi);
  assert.equal(
    chromeApi.sent.some((m) => m.type === 'ytdlp.probe'),
    false,
  );
  assert.equal(doc.byId['probe-status'].hidden, true);
});

test('media list still renders', () => {
  const doc = fakeDoc();
  const chromeApi = fakeChrome();
  chromeApi.runtime.sendMessage = (message, cb) => {
    chromeApi.sent.push(message);
    if (message.type === 'media.list') {
      cb({
        items: [
          {
            url: 'https://cdn.example.com/clip.mp4',
            fileName: 'clip.mp4',
            type: 'video',
            referrer: TAB_URL,
          },
        ],
      });
    } else if (message.type === 'intercept.get') {
      cb({enabled: true});
    } else if (cb) {
      cb({});
    }
  };
  initPopup(doc, chromeApi);
  assert.equal(doc.byId.list.children.length, 1);
  assert.equal(doc.byId.list.children[0].children[1].textContent, 'clip.mp4');
});
