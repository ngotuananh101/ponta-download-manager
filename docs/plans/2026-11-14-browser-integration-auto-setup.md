# Browser Integration Auto-Setup

Date: 2026-11-14

## Goal

Ship the browser extension and native messaging host with PDM, register the
host automatically for the current desktop user, and reduce manual extension
setup without misrepresenting browser-controlled installation requirements.

## Platform boundaries

- Native host registration: Linux per-user native messaging manifests;
  Windows per-user HKCU registry entries pointing to family-specific manifests.
- Linux Chromium profiles: unpacked-extension seeding only when the browser
  is closed and the user has already enabled Developer mode. Never enable
  Developer mode or re-enable an extension disabled by the user or browser.
  This is a compatibility mechanism, not a stable installation API. Preserve
  unrelated preferences and surface failures instead of claiming success.
- Windows Chromium profiles: do not modify authenticated extension preferences;
  explain Developer mode / Load unpacked.
- Firefox: register the host; permanent add-on installation requires a signed
  release, which is not yet published. Do not claim it is installed.
- Only standard, non-sandboxed browser locations are detected automatically.
  macOS, custom user-data directories, Snap/Flatpak and managed policies are
  outside this change's automatic setup scope.
- Debug builds must not register paths into disposable build directories.
- Package hooks run elevated and must not write browser integration into the
  installer/root account's home. Setup runs at the user's first release launch.

## Implementation

1. Pin the unpacked extension identity with a public manifest key. Test that
   the key-derived Chromium id matches the native host's allowed origin.
2. Add a best-effort, idempotent registration service and startup wiring.
3. Add extension profile inspection/setup with test fixtures for missing,
   corrupt, disabled, moved and running-browser profiles.
4. Add Menu -> Browser integration with explicit registration state and
   installation instructions, and a retry that refreshes registration/setup.
5. Compile the native host from repository sources before release builds;
   package it under bin/ and package extension/ without tests.
6. Keep install.sh as a development/repair registrar with a pinned id and
   optional --host path. Do not read or inspect browser cookie material.
7. Document first-launch behavior and unsupported installation environments.

## Verification

- TDD: failing service, script and widget tests before behavior changes.
- Full desktop tests and analyzer; engine/package/host tests and analyzers;
  extension node tests; tools pytest suite.
- Independently review profile write safety, result/status truthfulness,
  native host lookup and release packaging; adversarially verify findings.
- Build Linux release and check bin/pdm-native-host and extension/ layout.
- Earlier local Chrome 157 experiment verified that a closed Linux profile
  can load the pinned unpacked extension and spawn the bundled native host.
  A running-browser experiment demonstrated why live profile writes are unsafe.
- Windows registration is covered by process/registry test seams; Windows
  installers and real-browser behavior require Windows CI/device verification.

## Delivery

No browser session cookies are inspected or exposed. Existing cookie redaction
and external tool checksum verification remain unchanged. No store publication,
enterprise force policies, commit or push is performed without a separate user
request. Include this plan as a Plan: trailer when committing these changes.
