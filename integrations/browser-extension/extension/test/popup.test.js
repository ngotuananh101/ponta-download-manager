const test = require('node:test');
const assert = require('node:assert/strict');
const {
  formatBytes,
  formatBadge,
  formatLabel,
  sanitizeFileName,
  fileNameForProbe,
  probeState,
  probeView,
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
  };
  // Mirror the initial hidden state of popup.html.
  byId.empty.hidden = true;
  byId['probe-status'].hidden = true;
  byId['probe-title'].hidden = true;
  return {
    byId,
    getElementById: (id) => byId[id] || null,
    createElement: (tag) => fakeEl(tag),
  };
}

const TAB_URL = 'https://www.youtube.com/watch?v=abc123';

const CLIP = {
  url: 'https://cdn.example.com/clip.mp4',
  fileName: 'clip.mp4',
  type: 'video',
  referrer: TAB_URL,
};

const SONG = {
  url: 'https://cdn.example.com/song.mp3',
  fileName: 'song.mp3',
  type: 'audio',
  referrer: TAB_URL,
};

/// A fake chrome API. [media] is what media.list answers; the yt-dlp
/// probe stays pending until [replyProbe] is called.
function fakeChrome({media = [], tabUrl = TAB_URL} = {}) {
  const sent = [];
  const probeCallbacks = [];
  return {
    sent,
    replyProbe: (reply) => {
      probeCallbacks.forEach((cb) => cb(reply));
    },
    tabs: {
      query: (query, cb) => {
        cb(tabUrl == null ? [] : [{url: tabUrl}]);
      },
    },
    runtime: {
      sendMessage: (message, cb) => {
        sent.push(message);
        if (message.type === 'ytdlp.probe') {
          probeCallbacks.push(cb);
        } else if (message.type === 'media.list') {
          cb({items: media});
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

function openPopup(options) {
  const doc = fakeDoc();
  const chromeApi = fakeChrome(options);
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

test('formatBadge maps a format to the badge it shares with page media', () => {
  assert.equal(formatBadge(supportedProbe.formats[0]), 'video');
  assert.equal(formatBadge(supportedProbe.formats[1]), 'video');
  assert.equal(formatBadge(supportedProbe.formats[2]), 'audio');
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

const FORMAT_UNAVAILABLE =
  'ERROR: [youtube] LftM_19IToM: Requested format is not available. ' +
  'Use --list-formats for a list of available formats';

test('probeState explains the YouTube JS-runtime failure', () => {
  // The raw yt-dlp line tells the user nothing they can act on; the
  // popup should say what is wrong and that updating the app fixes it.
  const state = probeState({
    ok: false,
    code: 'yt-dlp-probe-failed',
    message: FORMAT_UNAVAILABLE,
  });
  assert.equal(state.state, 'error');
  assert.match(state.message, /YouTube/);
  assert.match(state.message, /update|restart/i);
  assert.doesNotMatch(state.message, /--list-formats/);
});

test('probeState explains the bot-check failure', () => {
  const state = probeState({
    ok: false,
    code: 'yt-dlp-probe-failed',
    message:
      'ERROR: [youtube] abc: Sign in to confirm you’re not a bot. ' +
      'Use --cookies-from-browser or --cookies for the authentication.',
  });
  assert.equal(state.state, 'error');
  assert.match(state.message, /YouTube/);
  assert.match(state.message, /sign in|log in/i);
  assert.doesNotMatch(state.message, /--cookies/);
});

test('probeState keeps the message for an unrelated failure', () => {
  // A failure the popup does not understand is still shown verbatim,
  // so the user (and a bug report) keeps the real error.
  assert.equal(
    probeState({
      ok: false,
      code: 'yt-dlp-probe-failed',
      message: 'ERROR: unable to download webpage',
    }).message,
    'ERROR: unable to download webpage',
  );
});

test('error state marks the status line', () => {
  const doc = fakeDoc();
  probeView(doc, {state: 'error', message: 'boom'}, () => {});
  assert.equal(doc.byId['probe-status'].className, 'error');
});

test('loading state has no error class', () => {
  const doc = fakeDoc();
  probeView(doc, {state: 'loading'}, () => {});
  assert.equal(doc.byId['probe-status'].className, '');
});

test('probeView shows the loading state and returns no rows', () => {
  const doc = fakeDoc();
  const rows = probeView(doc, {state: 'loading'}, () => {});
  assert.equal(doc.byId['probe-status'].hidden, false);
  assert.match(doc.byId['probe-status'].textContent, /Checking/);
  assert.equal(doc.byId['probe-title'].hidden, true);
  assert.deepEqual(rows, []);
});

test('the popup asks for the page media and probes the tab', () => {
  const {doc, chromeApi} = openPopup();
  assert.deepEqual(
    chromeApi.sent.map((m) => m.type),
    ['intercept.get', 'media.list', 'ytdlp.probe'],
  );
  assert.equal(doc.byId['probe-status'].hidden, false);
  assert.match(doc.byId['probe-status'].textContent, /Checking/);
  assert.equal(doc.byId.list.children.length, 0);
});

test('formats render as rows of the one list', () => {
  const {doc, chromeApi} = openPopup();
  chromeApi.replyProbe({ok: true, probe: supportedProbe});
  assert.equal(doc.byId['probe-title'].hidden, false);
  assert.equal(doc.byId['probe-title'].textContent, 'My Video: Part 1/2');
  assert.equal(doc.byId['probe-status'].hidden, true);
  const rows = doc.byId.list.children;
  assert.equal(rows.length, 3);
  assert.equal(rows[0].children[0].className, 'badge video');
  assert.equal(rows[2].children[0].className, 'badge audio');
  assert.deepEqual(
    rows.map((row) => row.children[1].textContent),
    [
      '1080p · video only · mp4 · 100.0 MiB',
      '360p · mp4 · 11.8 MiB',
      'medium · audio only · m4a · 4.0 MiB',
    ],
  );
  assert.equal(doc.byId.empty.hidden, true);
});

test('unsupported shows the not-supported message', () => {
  const {doc, chromeApi} = openPopup();
  chromeApi.replyProbe({
    ok: true,
    probe: {supported: false, errorCode: 'yt-dlp-unsupported'},
  });
  assert.equal(doc.byId['probe-status'].hidden, false);
  assert.match(doc.byId['probe-status'].textContent, /not support/i);
  assert.equal(doc.byId.list.children.length, 0);
});

test('unavailable shows the unavailable message', () => {
  const {doc, chromeApi} = openPopup();
  chromeApi.replyProbe({
    ok: true,
    probe: {supported: false, errorCode: 'unavailable'},
  });
  assert.equal(doc.byId['probe-status'].hidden, false);
  assert.match(doc.byId['probe-status'].textContent, /unavailable/i);
  assert.equal(doc.byId.list.children.length, 0);
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
  assert.equal(doc.byId.list.children.length, 0);
});

test("clicking a format's Download posts ytdlp.download with that formatId", () => {
  const {doc, chromeApi} = openPopup();
  chromeApi.replyProbe({ok: true, probe: supportedProbe});
  const button = doc.byId.list.children[0].children[2];
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

test('media rows carry the media type badge', () => {
  const {doc} = openPopup({media: [CLIP, SONG]});
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

test('page media still lists when no format is found', () => {
  const {doc, chromeApi} = openPopup({media: [CLIP]});
  chromeApi.replyProbe({
    ok: true,
    probe: {supported: false, errorCode: 'yt-dlp-unsupported'},
  });
  assert.equal(doc.byId.list.children.length, 1);
  assert.equal(doc.byId.list.children[0].children[1].textContent, 'clip.mp4');
});

test('yt-dlp formats and page media share the one list', () => {
  const {doc, chromeApi} = openPopup({media: [CLIP]});
  chromeApi.replyProbe({ok: true, probe: supportedProbe});
  // Three yt-dlp formats on top, then the page's own media.
  const rows = doc.byId.list.children;
  assert.equal(rows.length, 4);
  assert.equal(rows[3].children[1].textContent, 'clip.mp4');
  assert.equal(doc.byId.empty.hidden, true);
});

test('the empty message shows only once every source answered', () => {
  const {doc, chromeApi} = openPopup();
  // Page scan empty, probe still loading: no empty message yet.
  assert.equal(doc.byId.empty.hidden, true);
  chromeApi.replyProbe({
    ok: true,
    probe: {supported: false, errorCode: 'yt-dlp-unsupported'},
  });
  assert.equal(doc.byId.empty.hidden, false);
});

test('page media alone keeps the empty message hidden', () => {
  const {doc} = openPopup({media: [CLIP]});
  assert.equal(doc.byId.empty.hidden, true);
  assert.equal(doc.byId.list.children.length, 1);
});

test('page media renders while the probe is still loading', () => {
  const {doc} = openPopup({media: [CLIP]});
  const rows = doc.byId.list.children;
  assert.equal(rows.length, 1);
  assert.equal(rows[0].children[1].textContent, 'clip.mp4');
});

test('probe is not sent for a non-http tab', () => {
  const {doc, chromeApi} = openPopup({tabUrl: 'chrome://extensions'});
  assert.equal(
    chromeApi.sent.some((m) => m.type === 'ytdlp.probe'),
    false,
  );
  assert.equal(doc.byId['probe-status'].hidden, true);
  // Nothing can be found: the popup says so instead of staying blank.
  assert.equal(doc.byId.empty.hidden, false);
});

test('probe is not sent when there is no active tab', () => {
  const {doc, chromeApi} = openPopup({tabUrl: null});
  assert.equal(
    chromeApi.sent.some((m) => m.type === 'ytdlp.probe'),
    false,
  );
  assert.equal(doc.byId['probe-status'].hidden, true);
});
