// PDM popup probe helpers: pure functions for the yt-dlp probe section
// of the popup (status line + formats list). Kept pure so node tests can
// drive them with a fake DOM, mirroring content.js.

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
    return {
      state: 'error',
      message: (reply && reply.message) || 'Could not check this page.',
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
      message: probe.errorMessage || 'Could not check this page.',
    };
  }
  return {
    state: 'not-supported',
    message: 'No downloadable formats found on this page.',
  };
}

// Renders a probe state into the popup's probe section. `state` is
// either {state: 'loading'} or a probeState() result. `onDownload` is
// called with {format, fileName} when a format's Download button is
// clicked; it marks the button Sent and is responsible for sending the
// ytdlp.download message.
function renderProbe(doc, state, onDownload) {
  const statusEl = doc.getElementById('probe-status');
  const titleEl = doc.getElementById('probe-title');
  const listEl = doc.getElementById('probe-formats');
  if (!statusEl || !titleEl || !listEl) {
    return;
  }
  listEl.innerHTML = '';
  if (state.state === 'loading') {
    statusEl.className = '';
    statusEl.hidden = false;
    statusEl.textContent = 'Checking this page for downloads…';
    titleEl.hidden = true;
    listEl.hidden = true;
    return;
  }
  if (state.state === 'formats') {
    const probe = state.probe;
    statusEl.className = '';
    statusEl.hidden = true;
    titleEl.hidden = !probe.title;
    titleEl.textContent = probe.title || '';
    listEl.hidden = false;
    for (const format of probe.formats) {
      const row = doc.createElement('li');
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
      row.append(label, button);
      listEl.append(row);
    }
    return;
  }
  statusEl.className = state.state === 'error' ? 'error' : '';
  statusEl.hidden = false;
  statusEl.textContent = state.message;
  titleEl.hidden = true;
  listEl.hidden = true;
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    formatBytes,
    formatKind,
    formatLabel,
    sanitizeFileName,
    fileNameForProbe,
    probeState,
    renderProbe,
  };
}
