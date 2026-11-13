// PDM popup: lists the video/audio the content script found on the
// active tab, and the download-interception toggle.
(function () {
  const listEl = document.getElementById('list');
  const emptyEl = document.getElementById('empty');
  const toggleEl = document.getElementById('intercept');

  function render(items) {
    listEl.innerHTML = '';
    emptyEl.hidden = items.length > 0;
    for (const item of items) {
      const row = document.createElement('li');
      const badge = document.createElement('span');
      badge.className = 'badge';
      badge.textContent = item.type;
      const name = document.createElement('span');
      name.className = 'name';
      name.textContent = item.fileName || item.url;
      name.title = item.url;
      const button = document.createElement('button');
      button.textContent = 'Download';
      button.addEventListener('click', () => {
        button.disabled = true;
        button.textContent = 'Sent';
        chrome.runtime.sendMessage({
          type: 'media.download',
          url: item.url,
          fileName: item.fileName,
          referrer: item.referrer,
        });
      });
      row.append(badge, name, button);
      listEl.append(row);
    }
  }

  chrome.runtime.sendMessage({type: 'intercept.get'}, (reply) => {
    toggleEl.checked = !reply || reply.enabled !== false;
  });
  toggleEl.addEventListener('change', () => {
    chrome.runtime.sendMessage({
      type: 'intercept.set',
      enabled: toggleEl.checked,
    });
  });
  chrome.runtime.sendMessage({type: 'media.list'}, (reply) => {
    render((reply && reply.items) || []);
  });
})();
