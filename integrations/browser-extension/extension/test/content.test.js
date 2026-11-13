const test = require('node:test');
const assert = require('node:assert/strict');
const {collectMedia, mediaType, fileNameFromMediaUrl, scanAndSend} =
  require('../content.js');

function el(tag, attrs, children = []) {
  return {
    tagName: tag.toUpperCase(),
    getAttribute: (name) => (name in attrs ? attrs[name] : null),
    querySelectorAll: (sel) => {
      if (sel === 'source') {
        return children;
      }
      return [];
    },
  };
}

function fakeDoc(elements, baseURI = 'https://example.com/page/') {
  return {
    baseURI,
    querySelectorAll: (sel) => {
      const tags = sel
        .split(',')
        .map((s) => s.trim().toUpperCase().replace(/\[.*\]$/, ''));
      return elements.filter((e) => tags.includes(e.tagName));
    },
  };
}

test('mediaType classifies video and audio by extension', () => {
  assert.equal(mediaType('https://example.com/a.mp4'), 'video');
  assert.equal(mediaType('https://example.com/a.WEBM'), 'video');
  assert.equal(mediaType('https://example.com/a.mkv'), 'video');
  assert.equal(mediaType('https://example.com/a.mp3'), 'audio');
  assert.equal(mediaType('https://example.com/a.flac'), 'audio');
  assert.equal(mediaType('https://example.com/a.ogg'), 'audio');
  assert.equal(mediaType('https://example.com/a.png'), null);
  assert.equal(mediaType('https://example.com/a.zip'), null);
  assert.equal(mediaType('not a url'), null);
});

test('mediaType classifies streaming playlists as video', () => {
  assert.equal(mediaType('https://example.com/stream.m3u8'), 'video');
  assert.equal(mediaType('https://example.com/STREAM.M3U8'), 'video');
  assert.equal(mediaType('https://example.com/manifest.mpd'), 'video');
});

test('fileNameFromMediaUrl takes the last path segment', () => {
  assert.equal(
    fileNameFromMediaUrl('https://example.com/v/clip.mp4'),
    'clip.mp4',
  );
  assert.equal(
    fileNameFromMediaUrl('https://example.com/v/my%20song.mp3'),
    'my song.mp3',
  );
  assert.equal(fileNameFromMediaUrl('https://example.com/v/'), 'media');
});

test('collectMedia finds video and audio src and source children', () => {
  const doc = fakeDoc([
    el('video', {src: 'https://cdn.example.com/clip.mp4'}),
    el('video', {}, [
      el('source', {src: 'https://cdn.example.com/a.webm'}),
      el('source', {src: 'https://cdn.example.com/a.mp4'}),
    ]),
    el('audio', {src: 'https://cdn.example.com/song.mp3'}),
    el('audio', {}, [el('source', {src: 'https://cdn.example.com/s.ogg'})]),
  ]);
  const items = collectMedia(doc);
  assert.equal(items.length, 5);
  const byUrl = new Map(items.map((i) => [i.url, i]));
  assert.equal(byUrl.get('https://cdn.example.com/clip.mp4').type, 'video');
  assert.equal(byUrl.get('https://cdn.example.com/a.webm').type, 'video');
  assert.equal(byUrl.get('https://cdn.example.com/song.mp3').type, 'audio');
  assert.equal(byUrl.get('https://cdn.example.com/s.ogg').type, 'audio');
  assert.equal(
    byUrl.get('https://cdn.example.com/clip.mp4').fileName,
    'clip.mp4',
  );
});

test('collectMedia finds media links and resolves relative urls', () => {
  const doc = fakeDoc([
    el('a', {href: '/files/movie.mkv'}),
    el('a', {href: 'https://example.com/files/song.flac'}),
    el('a', {href: '/images/photo.png'}),
    el('a', {href: 'https://example.com/page.html'}),
  ]);
  const items = collectMedia(doc);
  assert.equal(items.length, 2);
  const urls = items.map((i) => i.url).sort();
  assert.deepEqual(urls, [
    'https://example.com/files/movie.mkv',
    'https://example.com/files/song.flac',
  ]);
});

test('collectMedia finds streaming playlist links', () => {
  const doc = fakeDoc([
    el('a', {href: '/streams/live.m3u8'}),
    el('a', {href: 'https://example.com/streams/manifest.mpd'}),
    el('a', {href: 'https://example.com/page.html'}),
  ]);
  const items = collectMedia(doc);
  assert.equal(items.length, 2);
  const byUrl = new Map(items.map((i) => [i.url, i]));
  assert.equal(byUrl.get('https://example.com/streams/live.m3u8').type, 'video');
  assert.equal(
    byUrl.get('https://example.com/streams/live.m3u8').fileName,
    'live.m3u8',
  );
  assert.equal(
    byUrl.get('https://example.com/streams/manifest.mpd').type,
    'video',
  );
});

test('collectMedia dedups the same url and drops blob and data urls', () => {
  const doc = fakeDoc([
    el('video', {src: 'https://cdn.example.com/clip.mp4'}),
    el('a', {href: 'https://cdn.example.com/clip.mp4'}),
    el('video', {src: 'blob:https://example.com/1234'}),
    el('audio', {src: 'data:audio/mp3;base64,AAAA'}),
  ]);
  const items = collectMedia(doc);
  assert.equal(items.length, 1);
  assert.equal(items[0].url, 'https://cdn.example.com/clip.mp4');
});

test('collectMedia ignores images and non-media elements', () => {
  const doc = fakeDoc([
    el('img', {src: 'https://example.com/pic.jpg'}),
    el('video', {poster: 'https://example.com/poster.jpg'}),
  ]);
  assert.deepEqual(collectMedia(doc), []);
});

test('collectMedia attaches the page url as referrer', () => {
  const doc = fakeDoc([
    el('video', {src: 'https://cdn.example.com/clip.mp4'}),
  ]);
  const items = collectMedia(doc);
  assert.equal(items.length, 1);
  assert.equal(items[0].referrer, 'https://example.com/page/');
});

test('scanAndSend does nothing when the extension context is invalidated', () => {
  let calls = 0;
  globalThis.chrome = {
    runtime: {
      sendMessage: () => {
        calls += 1;
        throw new Error('Extension context invalidated.');
      },
    },
  };
  globalThis.document = fakeDoc([
    el('video', {src: 'https://cdn.example.com/clip.mp4'}),
  ]);
  try {
    assert.doesNotThrow(() => scanAndSend());
    assert.equal(calls, 0);
  } finally {
    delete globalThis.chrome;
    delete globalThis.document;
  }
});

test('scanAndSend reports media when the context is valid', () => {
  let sent = null;
  globalThis.chrome = {
    runtime: {
      id: 'test-extension-id',
      sendMessage: (message) => {
        sent = message;
      },
    },
  };
  globalThis.document = fakeDoc([
    el('video', {src: 'https://cdn.example.com/clip.mp4'}),
  ]);
  try {
    scanAndSend();
    assert.equal(sent.type, 'media.found');
    assert.equal(sent.items.length, 1);
    assert.equal(sent.items[0].url, 'https://cdn.example.com/clip.mp4');
  } finally {
    delete globalThis.chrome;
    delete globalThis.document;
  }
});
