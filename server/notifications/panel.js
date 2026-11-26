'use strict';
const el = (id) => document.getElementById(id);
let key = '',
  pairing = '',
  refreshTimer,
  pending;
async function api(path, options = {}) {
  const response = await fetch(path, {
    ...options,
    headers: {
      Authorization: 'Bearer ' + key,
      'Content-Type': 'application/json',
      ...options.headers,
    },
  });
  if (!response.ok)
    throw new Error(
      response.status === 401
        ? 'Check your admin key.'
        : response.status === 400
          ? 'Check the title and message length.'
          : 'The panel could not complete the request.',
    );
  return response.json();
}
function removeButton(label, question, path) {
  const button = document.createElement('button');
  button.className = 'remove';
  button.textContent = label;
  button.type = 'button';
  button.onclick = async () => {
    if (!window.confirm(question)) return;
    button.disabled = true;
    try {
      await api(path, { method: 'DELETE' });
      await refresh();
    } catch (e) {
      el('status').textContent = e.message;
      button.disabled = false;
    }
  };
  return button;
}
async function refresh() {
  const active = key;
  const data = await api('/api/admin');
  if (key !== active) return;
  pairing = location.origin + '/#' + data.pairKey;
  el('phones').textContent = data.push
    ? 'In-app delivery enabled · ' + data.phones + ' paired for mobile push'
    : 'In-app delivery enabled. Add Firebase credentials to enable mobile push.';
  const viewers = data.viewers.map((viewer) => {
    const row = document.createElement('li');
    const name = document.createElement('span');
    name.textContent = viewer.label;
    const date = document.createElement('time');
    date.dateTime = new Date(viewer.updated * 1000).toISOString();
    date.textContent = new Date(viewer.updated * 1000).toLocaleString();
    const identity = document.createElement('small');
    identity.textContent = viewer.id.slice(0, 10);
    row.append(name, identity, date, removeButton('Delete settings',
      'Delete synced settings for ' + viewer.label + ' (' + identity.textContent + ')? Devices keep their local settings.',
      '/api/admin/viewers/' + encodeURIComponent(viewer.id)));
    return row;
  });
  el('viewers').replaceChildren(...viewers);
  if (!viewers.length) el('viewers').textContent = 'No viewer has synced yet.';
  const rows = data.messages.map((message) => {
    const row = document.createElement('li');
    for (const [tag, value] of [
      ['strong', message.title],
      ['p', message.body],
      [
        'small',
        new Date(message.created * 1000).toLocaleString() +
          ' · Push accepted ' +
          message.accepted +
          ' · Queued ' +
          message.queued +
          (message.failed ? ' · Failed ' + message.failed : ''),
      ],
    ]) {
      const node = document.createElement(tag);
      node.textContent = value;
      row.append(node);
    }
    row.append(removeButton('Remove', 'Remove “' + message.title + '” from every device’s recent announcements?',
      '/api/admin/announcements/' + message.id));
    return row;
  });
  el('history').replaceChildren(...rows);
  if (!rows.length) el('history').textContent = 'No announcements yet.';
}
el('signin').onsubmit = async (event) => {
  event.preventDefault();
  el('login-status').textContent = '';
  key = el('admin').value;
  try {
    await refresh();
    el('admin').value = '';
    el('login').hidden = true;
    el('workspace').hidden = false;
    el('status').textContent = '';
    clearInterval(refreshTimer);
    refreshTimer = setInterval(
      () => refresh().catch((e) => (el('status').textContent = e.message)),
      15000,
    );
  } catch (e) {
    key = '';
    el('login-status').textContent = e.message;
  }
};
el('signout').onclick = () => location.reload();
el('pair').onclick = () => {
  el('link').value = pairing;
  el('pairing').showModal();
};
el('close').onclick = () => el('pairing').close();
el('copy').onclick = async () => {
  el('link').select();
  try {
    await navigator.clipboard.writeText(pairing);
    el('copy').textContent = 'Copied';
  } catch {
    el('copy').textContent = 'Select and copy the link';
  }
};
el('compose').onsubmit = async (event) => {
  event.preventDefault();
  const body = JSON.stringify({ title: el('title').value.trim(), body: el('body').value.trim() });
  if (pending?.body !== body) pending = { body, id: crypto.randomUUID() };
  el('send').disabled = true;
  try {
    await api('/api/notifications', {
      method: 'POST',
      headers: { 'Idempotency-Key': pending.id },
      body,
    });
    pending = null;
    event.target.reset();
    el('status').textContent = 'Announcement published.';
    await refresh();
  } catch (e) {
    el('status').textContent = e.message;
  } finally {
    el('send').disabled = false;
  }
};

for (const name of ['settings', 'notifications']) {
  el(name + '-tab').onclick = () => {
    for (const page of ['settings', 'notifications']) {
      el(page + '-tab').setAttribute('aria-pressed', String(page === name));
      el(page + '-page').hidden = page !== name;
    }
  };
}
