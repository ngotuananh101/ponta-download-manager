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
