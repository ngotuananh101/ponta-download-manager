const test = require('node:test');
const assert = require('node:assert/strict');
const {setupExtension, fileNameFromUrl} = require('../background.js');

function fakePort(name) {
  const messageListeners = [];
  const disconnectListeners = [];
  const port = {
    name,
    posted: [],
    disconnected: false,
    onMessage: {
      addListener: (fn) => messageListeners.push(fn),
      removeListener: (fn) => {
        const i = messageListeners.indexOf(fn);
        if (i >= 0) messageListeners.splice(i, 1);
      },
    },
    onDisconnect: {
      addListener: (fn) => disconnectListeners.push(fn),
      removeListener: (fn) => {
        const i = disconnectListeners.indexOf(fn);
        if (i >= 0) disconnectListeners.splice(i, 1);
      },
    },
    postMessage: (msg) => {
      port.posted.push(msg);
    },
    disconnect: () => {
      port.disconnected = true;
    },
    _emitMessage: (msg) => {
      [...messageListeners].forEach((fn) => fn(msg));
    },
    _emitDisconnect: () => {
      [...disconnectListeners].forEach((fn) => fn());
    },
  };
  return port;
}

function fakeChrome() {
  const listeners = {
    installed: [],
    clicked: [],
    created: [],
    determiningFilename: [],
    message: [],
    tabRemoved: [],
    tabUpdated: [],
  };
  const ports = [];
  const notifications = [];
  const cancelled = [];
  const erased = [];
  const paused = [];
  const resumed = [];
  const storageValues = {pdmIntercept: true};
  const storageChangeListeners = [];
  let activeTabId = 1;
  const chromeApi = {
    runtime: {
      lastError: null,
      onInstalled: {addListener: (fn) => listeners.installed.push(fn)},
      onMessage: {addListener: (fn) => listeners.message.push(fn)},
      connectNative: (name) => {
        const port = fakePort(name);
        ports.push(port);
        return port;
      },
    },
    tabs: {
      onRemoved: {addListener: (fn) => listeners.tabRemoved.push(fn)},
      onUpdated: {addListener: (fn) => listeners.tabUpdated.push(fn)},
      query: (queryInfo, cb) => {
        cb([{id: activeTabId}]);
      },
    },
    contextMenus: {
      created: [],
      create: (item) => {
        chromeApi.contextMenus.created.push(item);
      },
      onClicked: {addListener: (fn) => listeners.clicked.push(fn)},
    },
    notifications: {
      created: notifications,
      create: (opts) => {
        notifications.push(opts);
        return 'notif-1';
      },
    },
    downloads: {
      onCreated: {addListener: (fn) => listeners.created.push(fn)},
      onDeterminingFilename: {
        addListener: (fn) => listeners.determiningFilename.push(fn),
      },
      cancel: (id, cb) => {
        cancelled.push(id);
        if (cb) cb();
      },
      erase: (query, cb) => {
        erased.push(query);
        if (cb) cb();
      },
      pause: (id, cb) => {
        paused.push(id);
        if (cb) cb();
      },
      resume: (id, cb) => {
        resumed.push(id);
        if (cb) cb();
      },
    },
    storage: {
      local: {
        get: (defaults, cb) => {
          const result = {...defaults, ...storageValues};
          if (cb) cb(result);
        },
        set: (items, cb) => {
          const changes = {};
          for (const key of Object.keys(items)) {
            changes[key] = {
              oldValue: storageValues[key],
              newValue: items[key],
            };
            storageValues[key] = items[key];
          }
          if (cb) cb();
          for (const fn of storageChangeListeners) {
            fn(changes, 'local');
          }
        },
      },
      onChanged: {
        addListener: (fn) => storageChangeListeners.push(fn),
      },
    },
  };
  return {
    chromeApi,
    listeners,
    ports,
    notifications,
    cancelled,
    erased,
    paused,
    resumed,
    storageValues,
    setActiveTabId: (id) => {
      activeTabId = id;
    },
  };
}

function emitMessage(listeners, message, sender = {}) {
  assert.equal(listeners.message.length, 1);
  let response;
  let async = false;
  const sendResponse = (value) => {
    response = value;
  };
  const result = listeners.message[0](message, sender, sendResponse);
  if (result === true) {
    async = true;
  }
  return {response: () => response, async};
}

function emitDownloadCreated(listeners, item) {
  assert.equal(listeners.created.length, 1);
  listeners.created[0](item);
}

function emitDeterminingFilename(listeners, item) {
  assert.equal(listeners.determiningFilename.length, 1);
  let suggested = false;
  const suggest = () => {
    suggested = true;
  };
  const deferred = listeners.determiningFilename[0](item, suggest);
  return {deferred, suggested};
}

function installed(chromeApi, listeners) {
  setupExtension(chromeApi);
  assert.equal(listeners.installed.length, 1);
  listeners.installed[0]();
}

test('fileNameFromUrl takes the last path segment', () => {
  assert.equal(fileNameFromUrl('http://example.com/a/b.zip'), 'b.zip');
  assert.equal(fileNameFromUrl('http://example.com/'), undefined);
  assert.equal(fileNameFromUrl('not a url'), undefined);
});

test('install creates the link and media menu items', () => {
  const {chromeApi, listeners} = fakeChrome();
  installed(chromeApi, listeners);
  assert.equal(chromeApi.contextMenus.created.length, 2);
  assert.deepEqual(chromeApi.contextMenus.created[0], {
    id: 'pdm-download-link',
    title: 'Download with PDM',
    contexts: ['link'],
  });
  assert.deepEqual(chromeApi.contextMenus.created[1], {
    id: 'pdm-download-media',
    title: 'Download with PDM',
    contexts: ['image', 'video', 'audio'],
  });
});

test('a link click posts a download.create message', () => {
  const {chromeApi, listeners, ports} = fakeChrome();
  installed(chromeApi, listeners);
  listeners.clicked[0]({linkUrl: 'http://example.com/a/b.zip'});
  assert.equal(ports.length, 1);
  assert.equal(ports[0].name, 'com.ponta.pdm');
  assert.equal(ports[0].posted.length, 1);
  const message = ports[0].posted[0];
  assert.equal(message.type, 'download.create');
  assert.equal(message.url, 'http://example.com/a/b.zip');
  assert.equal(message.fileName, 'b.zip');
  assert.equal(typeof message.id, 'string');
});

test('a success reply shows a notification and disconnects', () => {
  const {chromeApi, listeners, ports, notifications} = fakeChrome();
  installed(chromeApi, listeners);
  listeners.clicked[0]({linkUrl: 'http://example.com/a/b.zip'});
  const message = ports[0].posted[0];
  ports[0]._emitMessage({id: message.id, ok: true, downloadId: 'dl-1'});
  assert.equal(notifications.length, 1);
  assert.equal(notifications[0].title, 'Download added');
  assert.match(notifications[0].message, /b\.zip/);
  assert.equal(ports[0].disconnected, true);
});

test('a failure reply shows the error', () => {
  const {chromeApi, listeners, ports, notifications} = fakeChrome();
  installed(chromeApi, listeners);
  listeners.clicked[0]({linkUrl: 'http://example.com/a/b.zip'});
  const message = ports[0].posted[0];
  ports[0]._emitMessage({
    id: message.id,
    ok: false,
    code: 'connection-closed',
    message: 'Engine is not running',
  });
  assert.equal(notifications.length, 1);
  assert.equal(notifications[0].title, 'PDM download failed');
  assert.equal(notifications[0].message, 'Engine is not running');
});

test('a reply with a different id is ignored', () => {
  const {chromeApi, listeners, ports, notifications} = fakeChrome();
  installed(chromeApi, listeners);
  listeners.clicked[0]({linkUrl: 'http://example.com/a/b.zip'});
  ports[0]._emitMessage({id: 'someone-else', ok: true, downloadId: 'dl-9'});
  assert.equal(notifications.length, 0);
  assert.equal(ports[0].disconnected, false);
});

test('a port disconnect with lastError shows the install hint', () => {
  const {chromeApi, listeners, ports, notifications} = fakeChrome();
  installed(chromeApi, listeners);
  listeners.clicked[0]({linkUrl: 'http://example.com/a/b.zip'});
  chromeApi.runtime.lastError = {message: 'No such native host'};
  ports[0]._emitDisconnect();
  assert.equal(notifications.length, 1);
  assert.equal(notifications[0].title, 'PDM download failed');
  assert.match(notifications[0].message, /install\.sh/);
});

test('a click with no url posts nothing', () => {
  const {chromeApi, listeners, ports} = fakeChrome();
  installed(chromeApi, listeners);
  listeners.clicked[0]({});
  assert.equal(ports.length, 0);
});

test('a browser download is intercepted: cancel + erase + post to PDM', () => {
  const {chromeApi, listeners, ports, cancelled, erased, paused} =
    fakeChrome();
  installed(chromeApi, listeners);
  emitDownloadCreated(listeners, {
    id: 7,
    url: 'https://example.com/files/setup.exe',
    filename: 'setup.exe',
    state: 'in_progress',
  });
  // Created only pauses and holds the download; the cancel happens
  // once the filename is determined, so the Save As dialog is
  // deferred first.
  assert.deepEqual(paused, [7]);
  assert.deepEqual(cancelled, []);
  assert.equal(ports.length, 0);
  const {deferred, suggested} = emitDeterminingFilename(listeners, {
    id: 7,
    url: 'https://example.com/files/setup.exe',
    filename: 'setup.exe',
    state: 'in_progress',
  });
  assert.equal(deferred, true);
  assert.equal(suggested, false);
  assert.deepEqual(cancelled, [7]);
  assert.deepEqual(erased, [{id: 7}]);
  assert.equal(ports.length, 1);
  assert.equal(ports[0].posted.length, 1);
  const message = ports[0].posted[0];
  assert.equal(message.type, 'download.create');
  assert.equal(message.url, 'https://example.com/files/setup.exe');
  assert.equal(message.fileName, 'setup.exe');
});

test('a blob download is not intercepted', () => {
  const {chromeApi, listeners, ports, cancelled, erased} = fakeChrome();
  installed(chromeApi, listeners);
  emitDownloadCreated(listeners, {
    id: 8,
    url: 'blob:https://example.com/1234-5678',
    filename: 'video.mp4',
    state: 'in_progress',
  });
  assert.deepEqual(cancelled, []);
  assert.deepEqual(erased, []);
  assert.equal(ports.length, 0);
});

test('interception off does nothing on download created', () => {
  const {chromeApi, listeners, ports, cancelled, storageValues} = fakeChrome();
  storageValues.pdmIntercept = false;
  installed(chromeApi, listeners);
  emitDownloadCreated(listeners, {
    id: 9,
    url: 'https://example.com/a.zip',
    filename: 'a.zip',
    state: 'in_progress',
  });
  assert.deepEqual(cancelled, []);
  assert.equal(ports.length, 0);
});

test('the intercepted file name comes from the browser filename', () => {
  const {chromeApi, listeners, ports} = fakeChrome();
  installed(chromeApi, listeners);
  emitDownloadCreated(listeners, {
    id: 10,
    url: 'https://example.com/download?id=42',
    filename: 'report-2026.pdf',
    state: 'in_progress',
  });
  emitDeterminingFilename(listeners, {
    id: 10,
    url: 'https://example.com/download?id=42',
    filename: 'report-2026.pdf',
    state: 'in_progress',
  });
  assert.equal(ports[0].posted[0].fileName, 'report-2026.pdf');
});

test('an intercepted download that PDM rejects shows the error', () => {
  const {chromeApi, listeners, ports, notifications} = fakeChrome();
  installed(chromeApi, listeners);
  emitDownloadCreated(listeners, {
    id: 11,
    url: 'https://example.com/a.zip',
    filename: 'a.zip',
    state: 'in_progress',
  });
  emitDeterminingFilename(listeners, {
    id: 11,
    url: 'https://example.com/a.zip',
    filename: 'a.zip',
    state: 'in_progress',
  });
  const message = ports[0].posted[0];
  ports[0]._emitMessage({id: message.id, ok: false, message: 'Engine is not running'});
  assert.equal(notifications.length, 1);
  assert.equal(notifications[0].title, 'PDM download failed');
  assert.equal(notifications[0].message, 'Engine is not running');
});

test('determiningFilename is not deferred for a download that was never held', () => {
  const {chromeApi, listeners, ports, cancelled} = fakeChrome();
  installed(chromeApi, listeners);
  const {deferred, suggested} = emitDeterminingFilename(listeners, {
    id: 12,
    url: 'https://example.com/b.zip',
    filename: 'b.zip',
    state: 'in_progress',
  });
  assert.equal(deferred, false);
  assert.equal(suggested, false);
  assert.deepEqual(cancelled, []);
  assert.equal(ports.length, 0);
});

test('turning interception off after the hold releases the download', () => {
  const {chromeApi, listeners, ports, cancelled, paused, resumed} =
    fakeChrome();
  installed(chromeApi, listeners);
  emitDownloadCreated(listeners, {
    id: 13,
    url: 'https://example.com/c.zip',
    filename: 'c.zip',
    state: 'in_progress',
  });
  assert.deepEqual(paused, [13]);
  // The user flips interception off before the filename is
  // determined.
  emitMessage(listeners, {type: 'intercept.set', enabled: false});
  const {deferred} = emitDeterminingFilename(listeners, {
    id: 13,
    url: 'https://example.com/c.zip',
    filename: 'c.zip',
    state: 'in_progress',
  });
  assert.equal(deferred, false);
  assert.deepEqual(cancelled, []);
  assert.deepEqual(resumed, [13]);
  assert.equal(ports.length, 0);
});

test('without onDeterminingFilename, created cancels at once', () => {
  const {chromeApi, listeners, ports, cancelled} = fakeChrome();
  // An older browser without the determiningFilename event: the
  // two-stage flow is unavailable, so interception falls back to
  // cancelling in onCreated.
  delete chromeApi.downloads.onDeterminingFilename;
  installed(chromeApi, listeners);
  emitDownloadCreated(listeners, {
    id: 14,
    url: 'https://example.com/d.zip',
    filename: 'd.zip',
    state: 'in_progress',
  });
  assert.deepEqual(cancelled, [14]);
  assert.equal(ports.length, 1);
  assert.equal(ports[0].posted[0].type, 'download.create');
});

test('media.found stores items per tab and media.list returns them', () => {
  const {chromeApi, listeners, setActiveTabId} = fakeChrome();
  installed(chromeApi, listeners);
  emitMessage(
    listeners,
    {
      type: 'media.found',
      items: [{url: 'https://cdn.example.com/clip.mp4', fileName: 'clip.mp4', type: 'video'}],
    },
    {tab: {id: 3}},
  );
  emitMessage(
    listeners,
    {
      type: 'media.found',
      items: [{url: 'https://cdn.example.com/song.mp3', fileName: 'song.mp3', type: 'audio'}],
    },
    {tab: {id: 4}},
  );
  setActiveTabId(3);
  const reply = emitMessage(listeners, {type: 'media.list'});
  assert.deepEqual(reply.response(), {
    items: [{url: 'https://cdn.example.com/clip.mp4', fileName: 'clip.mp4', type: 'video'}],
  });
});

test('media.list returns an empty list when the tab has no media', () => {
  const {chromeApi, listeners} = fakeChrome();
  installed(chromeApi, listeners);
  const reply = emitMessage(listeners, {type: 'media.list'});
  assert.deepEqual(reply.response(), {items: []});
});

test('media.download posts a download.create to PDM', () => {
  const {chromeApi, listeners, ports} = fakeChrome();
  installed(chromeApi, listeners);
  const reply = emitMessage(listeners, {
    type: 'media.download',
    url: 'https://cdn.example.com/clip.mp4',
    fileName: 'clip.mp4',
  });
  assert.equal(ports.length, 1);
  assert.equal(ports[0].posted[0].type, 'download.create');
  assert.equal(ports[0].posted[0].url, 'https://cdn.example.com/clip.mp4');
  assert.equal(ports[0].posted[0].fileName, 'clip.mp4');
  assert.deepEqual(reply.response(), {ok: true});
});

test('closing a tab clears its stored media', () => {
  const {chromeApi, listeners, setActiveTabId} = fakeChrome();
  installed(chromeApi, listeners);
  emitMessage(
    listeners,
    {
      type: 'media.found',
      items: [{url: 'https://cdn.example.com/clip.mp4', fileName: 'clip.mp4', type: 'video'}],
    },
    {tab: {id: 5}},
  );
  assert.equal(listeners.tabRemoved.length, 1);
  listeners.tabRemoved[0](5);
  setActiveTabId(5);
  const reply = emitMessage(listeners, {type: 'media.list'});
  assert.deepEqual(reply.response(), {items: []});
});

test('intercept get and set round-trip through storage', () => {
  const {chromeApi, listeners, storageValues} = fakeChrome();
  installed(chromeApi, listeners);
  let reply = emitMessage(listeners, {type: 'intercept.get'});
  assert.deepEqual(reply.response(), {enabled: true});
  reply = emitMessage(listeners, {type: 'intercept.set', enabled: false});
  assert.deepEqual(reply.response(), {ok: true});
  assert.equal(storageValues.pdmIntercept, false);
  reply = emitMessage(listeners, {type: 'intercept.get'});
  assert.deepEqual(reply.response(), {enabled: false});
});
