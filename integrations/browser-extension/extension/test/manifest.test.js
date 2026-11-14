const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const manifest = JSON.parse(
  fs.readFileSync(path.join(__dirname, '..', 'manifest.json'), 'utf8'),
);

test('the manifest declares a background script for Firefox as well as a service worker', () => {
  // Chrome MV3 uses service_worker and ignores scripts; Firefox
  // 113-120 falls back to scripts, Firefox 121+ uses the worker.
  // The same file serves both: it only registers listeners at the
  // top level and uses no service-worker-only globals.
  assert.equal(manifest.background.service_worker, 'background.js');
  assert.deepEqual(manifest.background.scripts, ['background.js']);
});

test('the manifest keeps the Firefox extension id', () => {
  assert.equal(
    manifest.browser_specific_settings.gecko.id,
    'pdm@ponta.dev',
  );
});

test('the Firefox floor covers chrome.storage.session (Firefox 112+)', () => {
  const min = manifest.browser_specific_settings.gecko.strict_min_version;
  const [major] = min.split('.').map(Number);
  assert.ok(major >= 112, `strict_min_version is ${min}`);
});

test('the manifest requests the cookies permission', () => {
  assert.ok(
    manifest.permissions.includes('cookies'),
    `permissions are ${manifest.permissions.join(', ')}`,
  );
});

test('the manifest pins the extension id with a public key', () => {
  // Without a "key", Chrome derives the id from the unpacked folder's
  // path, so the id was different on every machine and the native host
  // manifest (allowed_origins) had to be written by hand. With "key",
  // the id is SHA-256(public key) and identical everywhere — the app
  // can register the host for a known id.
  assert.equal(typeof manifest.key, 'string');
  const der = Buffer.from(manifest.key, 'base64');
  assert.ok(der.length >= 128, `public key is ${der.length} bytes`);
  assert.equal(chromeExtensionId(der), 'hiojpajnfchdajfiegibmklalpgndono');
});

// Chromium: components/crx_file/id_util.cc — SHA-256 of the DER
// SubjectPublicKeyInfo, first 16 bytes, each hex nibble mapped 0-f to
// a-p.
function chromeExtensionId(der) {
  const digest = require('node:crypto').createHash('sha256').update(der).digest();
  return Array.from(digest.subarray(0, 16))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
    .split('')
    .map((c) => String.fromCharCode('a'.charCodeAt(0) + parseInt(c, 16)))
    .join('');
}
