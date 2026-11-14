// PDM popup probe helpers: pure functions for the yt-dlp probe rows
// of the popup (status line + formats, rendered into the popup's one
// list). Kept pure so node tests can drive them with a fake DOM,
// mirroring content.js.

function formatBytes(bytes) {
  if (bytes == null || Number.isNaN(bytes)) {
    return '';
  }
  if (bytes < 1024) {
    return bytes + ' B';
  }
  if (bytes < 1024 * 1024) {
    return (bytes / 1024).toFixed(1) + ' KiB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return (bytes / (1024 * 1024)).toFixed(1) + ' MiB';
  }
  return (bytes / (1024 * 1024 * 1024)).toFixed(1) + ' GiB';
}

function formatKind(format) {
  const hasVideo = format.vcodec && format.vcodec !== 'none';
  const hasAudio = format.acodec && format.acodec !== 'none';
  if (hasVideo && hasAudio) {
    return 'combined';
  }
  if (hasVideo) {
    return 'video-only';
  }
  return 'audio-only';
}

// The badge a format row shares with a page-media row: a format with a
// video track is a video, an audio-only one is audio.
function formatBadge(format) {
  return formatKind(format) === 'audio-only' ? 'audio' : 'video';
}

// '1080p · video only · mp4 · 100.0 MiB',
// '360p · mp4 · 11.8 MiB', 'medium · audio only · m4a · 4.0 MiB'.
function formatLabel(format) {
  const parts = [];
  if (format.height) {
    parts.push(format.height + 'p');
  } else if (format.resolution) {
    parts.push(format.resolution);
  } else if (format.note) {
    parts.push(format.note);
  }
  const kind = formatKind(format);
  const marker =
    kind === 'video-only'
      ? 'video only'
      : kind === 'audio-only'
        ? 'audio only'
        : null;
  if (marker && parts[0] !== marker) {
    parts.push(marker);
  }
  parts.push(format.ext);
  const size = format.filesize ?? format.filesizeApprox;
  if (size != null) {
    parts.push(formatBytes(size));
  }
  return parts.join(' · ');
}

// Strips everything the native host rejects in a file name (/, \, ..)
// plus the other characters unsafe in file names. Falls back to 'video'
// so the download always has a name.
function sanitizeFileName(name) {
  const cleaned = String(name || '')
    .replace(/[/\\:*?"<>|]/g, '')
    .replace(/[\u0000-\u001f\u007f]/g, '')
    .replace(/\.{2,}/g, '.')
    .replace(/\s+/g, ' ')
    .trim()
    .replace(/^\.+/, '')
    .replace(/\.+$/, '');
  return cleaned || 'video';
}

function fileNameForProbe(probe, format) {
  return sanitizeFileName(probe.title || 'video') + '.' + format.ext;
}

// Maps a raw yt-dlp failure to copy the user can act on. YouTube's
// two common failures are opaque to anyone who has not read yt-dlp's
// source: the player challenge needs a JavaScript runtime ("Requested
// format is not available"), and the bot check wants a signed-in
// session. Anything else is passed through unchanged, so a bug report
// keeps the real error.
function probeErrorMessage(message) {
  const text = String(message || '');
  if (/Requested format is not available/i.test(text)) {
    return (
      'YouTube could not be read by the bundled downloader. ' +
      'Update PDM and try again; if it still fails, restart the app.'
    );
  }
  if (
    /not a bot|LOGIN_REQUIRED|Sign in to confirm/i.test(text)
  ) {
    return (
      'YouTube wants you to sign in before it will serve this video. ' +
      'Sign in to YouTube in this browser, then try again.'
    );
  }
  return text;
}

// Maps a background probe reply ({ok, probe} or {ok: false, code,
// message}) to a render state. `null` is never passed here — the
// loading state is a separate explicit state (see renderProbe).
function probeState(reply) {
  if (!reply || reply.ok === false) {
    if (reply && reply.code === 'internal') {
      return {
        state: 'error',
        message: 'Could not reach the PDM app. Start the app and try again.',
      };
    }
    const raw = (reply && reply.message) || 'Could not check this page.';
    return {
      state: 'error',
      message: probeErrorMessage(raw),
    };
  }
  const probe = reply.probe;
  if (!probe) {
    return {state: 'error', message: 'Could not check this page.'};
  }
  if (
    probe.supported &&
    Array.isArray(probe.formats) &&
    probe.formats.length > 0
  ) {
    return {state: 'formats', probe};
  }
  if (!probe.supported) {
    if (probe.errorCode === 'yt-dlp-unsupported') {
      return {
        state: 'not-supported',
        message: 'yt-dlp does not support this page.',
      };
    }
    if (probe.errorCode === 'unavailable') {
      return {
        state: 'unavailable',
        message: 'This video is unavailable (private or removed).',
      };
    }
    return {
      state: 'error',
      message: probeErrorMessage(probe.errorMessage) ||
        'Could not check this page.',
    };
  }
  return {
    state: 'not-supported',
    message: 'No downloadable formats found on this page.',
  };
}

// Renders a probe state into the popup's header status line and its
// one list. `state` is either {state: 'loading'} or a probeState()
// result. `onDownload` is called with {format, fileName} when a
// format's Download button is clicked; it marks the button Sent and
// is responsible for sending the ytdlp.download message.
//
// The rows are appended to `#list`, after any page-media rows already
// there, so yt-dlp formats and scanned media read as one list. The
// returned array holds the rows that were appended (empty for a
// non-formats state), so the caller can place them above the media
// rows instead of below them.
function probeView(doc, state, onDownload) {
  const statusEl = doc.getElementById('probe-status');
  const titleEl = doc.getElementById('probe-title');
  if (!statusEl || !titleEl) {
    return [];
  }
  const rows = [];
  if (state.state === 'loading') {
    statusEl.className = '';
    statusEl.hidden = false;
    statusEl.textContent = 'Checking this page for downloads…';
    titleEl.hidden = true;
    return rows;
  }
  if (state.state === 'formats') {
    const probe = state.probe;
    statusEl.className = '';
    statusEl.hidden = true;
    titleEl.hidden = !probe.title;
    titleEl.textContent = probe.title || '';
    for (const format of probe.formats) {
      const row = doc.createElement('li');
      const badge = doc.createElement('span');
      badge.className = 'badge ' + formatBadge(format);
      badge.textContent = formatBadge(format);
      const label = doc.createElement('span');
      label.className = 'name';
      label.textContent = formatLabel(format);
      label.title = format.formatId;
      const button = doc.createElement('button');
      button.textContent = 'Download';
      button.addEventListener('click', () => {
        button.disabled = true;
        button.textContent = 'Sent';
        onDownload({format, fileName: fileNameForProbe(probe, format)});
      });
      row.append(badge, label, button);
      rows.push(row);
    }
    return rows;
  }
  statusEl.className = state.state === 'error' ? 'error' : '';
  statusEl.hidden = false;
  statusEl.textContent = state.message;
  titleEl.hidden = true;
  return rows;
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    formatBytes,
    formatKind,
    formatBadge,
    formatLabel,
    sanitizeFileName,
    fileNameForProbe,
    probeErrorMessage,
    probeState,
    probeView,
  };
}
