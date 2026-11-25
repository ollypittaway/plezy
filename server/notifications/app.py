"""GucciPlexa's private broadcast panel and device feed."""
import hashlib
import os
import secrets
import sqlite3
import threading
import time
from contextlib import contextmanager
from pathlib import Path

from flask import Flask, abort, request, send_from_directory


def create_app(directory, admin_key, *, sender=None):
    if not admin_key or len(admin_key.encode()) < 24:
        raise ValueError("Set ADMIN_KEY to a random secret of at least 24 characters")
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    db_path = directory / "announcements.sqlite3"

    @contextmanager
    def db():
        conn = sqlite3.connect(db_path, timeout=10)
        conn.row_factory = sqlite3.Row
        try:
            with conn:
                yield conn
        finally:
            conn.close()

    with db() as conn:
        conn.executescript("""
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS config(key TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS notices(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, body TEXT NOT NULL, created INTEGER NOT NULL, request_key TEXT UNIQUE);
            CREATE TABLE IF NOT EXISTS devices(id TEXT PRIMARY KEY, token TEXT UNIQUE NOT NULL);
            CREATE TABLE IF NOT EXISTS deliveries(notice INTEGER NOT NULL, device TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'queued', attempts INTEGER NOT NULL DEFAULT 0, retry_at INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(notice, device));
        """)
        conn.execute("INSERT OR IGNORE INTO config VALUES ('pair', ?)", (secrets.token_urlsafe(32),))
        pair_key = conn.execute("SELECT value FROM config WHERE key='pair'").fetchone()[0]

    app = Flask(__name__, static_folder=None)
    app.config['MAX_CONTENT_LENGTH'] = 8192

    def authorize(key):
        if not secrets.compare_digest(request.headers.get('Authorization', '').encode(), ('Bearer ' + key).encode()):
            abort(401)

    @app.after_request
    def headers(response):
        response.headers.update({
            'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer',
            'Content-Security-Policy': "default-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
        })
        return response

    @app.get('/')
    def index():
        return send_from_directory(app.root_path, 'index.html')

    @app.get('/panel.<ext>')
    def asset(ext):
        if ext not in ('js', 'css'):
            abort(404)
        return send_from_directory(app.root_path, 'panel.' + ext)

    @app.get('/health')
    def health():
        return {'ok': True}

    @app.get('/api/feed')
    def feed():
        authorize(pair_key)
        with db() as conn:
            notices = conn.execute('SELECT id,title,body,created FROM notices ORDER BY id DESC LIMIT 50')
            return {'push': sender is not None, 'messages': [dict(row) for row in notices]}

    @app.put('/api/device')
    def device():
        authorize(pair_key)
        data = request.get_json()
        if not isinstance(data, dict) or not isinstance(data.get('installation'), str) or not 32 <= len(data['installation']) <= 128 or 'fid' not in data:
            abort(400)
        device_id = hashlib.sha256(data['installation'].encode()).hexdigest()
        token = data['fid']
        if token is not None and (not isinstance(token, str) or not 1 <= len(token) <= 4096):
            abort(400)
        if token is not None and sender is None:
            abort(503)
        with db() as conn:
            if token is None:
                conn.execute("DELETE FROM deliveries WHERE device=? AND state='queued'", (device_id,))
                conn.execute('DELETE FROM devices WHERE id=?', (device_id,))
            else:
                # Retire pending rows for any previous pairing of this FID.
                conn.execute("""UPDATE deliveries SET state='failed' WHERE state='queued' AND device IN
                             (SELECT id FROM devices WHERE token=? AND id<>?)""", (token, device_id))
                conn.execute('DELETE FROM devices WHERE token=? AND id<>?', (token, device_id))
                conn.execute('INSERT INTO devices VALUES(?,?) ON CONFLICT(id) DO UPDATE SET token=excluded.token', (device_id, token))
        return '', 204

    @app.get('/api/admin')
    def admin():
        authorize(admin_key)
        with db() as conn:
            rows = conn.execute("""
                SELECT n.id,n.title,n.body,n.created,
                       COUNT(CASE WHEN d.state='sent' THEN 1 END) AS accepted,
                       COUNT(CASE WHEN d.state='queued' THEN 1 END) AS queued,
                       COUNT(CASE WHEN d.state='failed' THEN 1 END) AS failed
                FROM notices n LEFT JOIN deliveries d ON n.id=d.notice
                GROUP BY n.id ORDER BY n.id DESC LIMIT 30
            """)
            return {'pairKey': pair_key, 'push': sender is not None, 'phones': conn.execute('SELECT COUNT(*) FROM devices').fetchone()[0],
                    'messages': [dict(row) for row in rows]}

    @app.post('/api/notifications')
    def publish():
        authorize(admin_key)
        data = request.get_json()
        if not isinstance(data, dict):
            abort(400)
        title, body = data.get('title'), data.get('body')
        if not all(isinstance(s, str) and s.strip() for s in (title, body)):
            abort(400)
        title, body = title.strip(), body.strip()
        if len(title) > 120 or len(body) > 1000 or len((title + body).encode()) > 3000:
            abort(400)
        key = request.headers.get('Idempotency-Key')
        if key is not None and not 1 <= len(key) <= 128:
            abort(400)
        with db() as conn:
            conn.execute('BEGIN IMMEDIATE')
            if key and (old := conn.execute('SELECT id,title,body FROM notices WHERE request_key=?', (key,)).fetchone()):
                if (old['title'], old['body']) != (title, body):
                    abort(409)
                return {'id': old['id']}, 200
            notice = conn.execute('INSERT INTO notices(title,body,created,request_key) VALUES(?,?,?,?)',
                                  (title, body, int(time.time()), key)).lastrowid
            conn.execute('INSERT INTO deliveries(notice,device) SELECT ?,id FROM devices', (notice,))
        return {'id': notice}, 201

    def deliver_one():
        # One delivery worker per persistent volume. Sending happens outside the
        # transaction so a slow push provider cannot stall the panel or feed.
        with db() as conn:
            row = conn.execute("""
                SELECT d.notice,d.device,d.attempts,p.token,n.title,n.body FROM deliveries d
                JOIN notices n ON d.notice=n.id JOIN devices p ON d.device=p.id
                WHERE d.state='queued' AND d.retry_at<=? ORDER BY d.notice LIMIT 1
            """, (time.time(),)).fetchone()
        if not row:
            return False
        try:
            sender(row['token'], row['notice'], row['title'], row['body'])
            state = 'sent'
        except ExpiredToken:
            with db() as conn:
                conn.execute('DELETE FROM devices WHERE id=? AND token=?', (row['device'], row['token']))
                if conn.execute('SELECT 1 FROM devices WHERE id=?', (row['device'],)).fetchone():
                    return True  # Token rotated while the old request was in flight.
                conn.execute("UPDATE deliveries SET state='failed' WHERE device=? AND state='queued'", (row['device'],))
            return True
        except Exception as error:
            app.logger.warning('Push dispatch for notice %s failed (%s)', row['notice'], type(error).__name__)
            state = 'failed' if row['attempts'] >= 9 else 'queued'
        with db() as conn:
            conn.execute('UPDATE deliveries SET state=?, attempts=attempts+1,retry_at=? WHERE notice=? AND device=?',
                         (state, int(time.time()) + min(3600, 15 * 2 ** row['attempts']), row['notice'], row['device']))
        return True

    return app, deliver_one


class ExpiredToken(Exception):
    pass


def firebase_sender():
    import firebase_admin
    from firebase_admin import messaging

    firebase_admin.initialize_app()  # Credentials are a Coolify-mounted secret.
    def send(token, notice_id, title, body):
        try:
            messaging.send(messaging.Message(
                fid=token, notification=messaging.Notification(title=title, body=body),
                data={'noticeId': str(notice_id)},
                android=messaging.AndroidConfig(priority='high', notification=messaging.AndroidNotification(tag=f'gucciplexa-{notice_id}')),
                apns=messaging.APNSConfig(headers={'apns-collapse-id': f'gucciplexa-{notice_id}', 'apns-push-type': 'alert'},
                                         payload=messaging.APNSPayload(aps=messaging.Aps(sound='default'))),
            ))
        except messaging.UnregisteredError as error:
            raise ExpiredToken() from error
    return send


if __name__ == '__main__':
    from waitress import serve

    sender = firebase_sender() if os.getenv('GOOGLE_APPLICATION_CREDENTIALS') else None
    app, deliver = create_app(os.getenv('DATA_DIR', '/data'), os.environ.get('ADMIN_KEY'), sender=sender)
    if sender:
        def worker():
            while True:
                try:
                    if deliver():
                        continue
                except sqlite3.Error:
                    app.logger.exception('Could not read push queue')
                time.sleep(2)
        threading.Thread(target=worker, daemon=True).start()
    serve(app, host=os.getenv('BIND_ADDRESS', '0.0.0.0'), port=int(os.getenv('PORT', '8080')), max_request_body_size=8192)
