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
async function refresh() {
  const active = key;
  const data = await api('/api/admin');
  if (key !== active) return;
  pairing = location.origin + '/#' + data.pairKey;
  el('phones').textContent = data.push
    ? 'In-app delivery enabled · ' + data.phones + ' paired for mobile push'
    : 'In-app delivery enabled. Add Firebase credentials to enable mobile push.';
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
    return row;
  });
  el('history').replaceChildren(...rows);
  if (!rows.length) el('history').textContent = 'No announcements yet.';
}
el('signin').onsubmit = async (event) => {
  event.preventDefault();
  key = el('admin').value;
  try {
    await refresh();
    el('admin').value = '';
    el('login').hidden = true;
    el('workspace').hidden = el('signout').hidden = false;
    el('status').textContent = '';
    clearInterval(refreshTimer);
    refreshTimer = setInterval(
      () => refresh().catch((e) => (el('status').textContent = e.message)),
      15000,
    );
  } catch (e) {
    key = '';
    el('status').textContent = e.message;
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
