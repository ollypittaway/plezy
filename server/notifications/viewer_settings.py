"""Plex-verified, revisioned viewer preferences. Plex credentials are never persisted."""
import hashlib
import http.client
import json
import re
import time

from flask import abort, request
from itsdangerous import BadData, URLSafeTimedSerializer

ACCENTS = {'default', 'teal', 'blue', 'violet', 'rose', 'amber'}
TOGGLES = {'auto_play_next_episode', 'hide_spoilers', 'subtitle_bold', 'subtitle_italic',
           'subtitle_use_margins', 'subtitle_anchor_to_screen'}
RANGES = {'auto_skip_delay': (1, 30), 'play_next_countdown': (0, 30), 'seek_time_small': (1, 120), 'seek_time_large': (1, 120),
          'rewind_on_resume': (0, 10), 'subtitle_font_size': (10, 80), 'subtitle_border_size': (0, 5),
          'subtitle_position': (0, 150), 'subtitle_background_opacity': (0, 100)}
COLORS = {'subtitle_text_color', 'subtitle_border_color', 'subtitle_background_color'}


def verify_plex(token, client_id):
    conn = http.client.HTTPSConnection('plex.tv', timeout=6)
    try:
        conn.request('GET', '/api/v2/user', headers={'Accept': 'application/json', 'X-Plex-Product': 'GucciPlexa',
                     'X-Plex-Client-Identifier': client_id, 'X-Plex-Token': token})
        reply = conn.getresponse()
        if reply.status in (401, 403):
            abort(401)
        if reply.status != 200:
            abort(503)
        user = json.loads(reply.read(65536))
        if not isinstance(user, dict) or not isinstance(user.get('uuid'), str) or not user['uuid']:
            abort(401)
        return user['uuid'], str(user.get('friendlyName') or user.get('username') or 'Plex viewer')[:120]
    except (OSError, http.client.HTTPException, ValueError):
        abort(503)
    finally:
        conn.close()


def valid(key, value):
    if key == 'viewer_accent':
        return isinstance(value, str) and value in ACCENTS
    if key in ('skip_intro_mode', 'skip_credits_mode'):
        return isinstance(value, str) and value in {'off', 'button', 'auto'}
    if key == 'default_playback_speed':
        return type(value) in (float, int) and 0.25 <= value <= 8
    if key in TOGGLES:
        return type(value) is bool
    if key in RANGES:
        lo, hi = RANGES[key]
        return type(value) is int and lo <= value <= hi
    if key in COLORS:
        return isinstance(value, str) and re.fullmatch(r'#[0-9a-fA-F]{6}', value) is not None
    if key in ('library_order', 'hidden_libraries'):
        return (isinstance(value, list) and len(value) <= 256 and
                all(isinstance(s, str) and 0 < len(s) <= 256 for s in value) and len(set(value)) == len(value))
    return False


def register_settings(app, db, authorize_installation, verifier=verify_plex):
    tickets = URLSafeTimedSerializer(app.secret_key or app.config['SYNC_SIGNING_KEY'], salt='viewer-settings-v1')
    with db() as conn:
        conn.execute('''CREATE TABLE IF NOT EXISTS viewer_settings(
            subject TEXT PRIMARY KEY, label TEXT NOT NULL, revision INTEGER NOT NULL, prefs TEXT NOT NULL, updated INTEGER NOT NULL)''')

    @app.post('/api/settings/session')
    def session():
        authorize_installation()
        token = request.headers.get('X-Plex-Token', '')
        client_id = request.headers.get('X-Plex-Client-Identifier', '')
        if not token or len(token) > 8192 or not client_id or len(client_id) > 256:
            abort(401)
        uuid, label = verifier(token, client_id)
        expected = request.headers.get('X-Viewer-UUID')
        if expected and expected != uuid:
            abort(403)
        return {'session': tickets.dumps([hashlib.sha256(uuid.encode()).hexdigest(), label])}

    @app.route('/api/settings', methods=['GET', 'PATCH'])
    def settings():
        auth = request.headers.get('Authorization', '')
        if not auth.startswith('Bearer '):
            abort(401)
        try:
            subject, label = tickets.loads(auth[7:], max_age=3600)
        except BadData:
            abort(401)
        with db() as conn:
            if request.method == 'PATCH':
                conn.execute('BEGIN IMMEDIATE')
            row = conn.execute('SELECT revision,prefs,updated FROM viewer_settings WHERE subject=?', (subject,)).fetchone()
            rev, prefs = (row['revision'], json.loads(row['prefs'])) if row else (0, {})
            removed = row is not None and row['updated'] == 0
            if request.method == 'GET' and removed:
                return {'revision': rev}, 410
            if request.method == 'PATCH':
                data = request.get_json()
                if not isinstance(data, dict) or not isinstance(data.get('changes'), dict) or type(data.get('revision')) is not int:
                    abort(400)
                if removed and data.get('reconnect') is not True:
                    return {'revision': rev}, 410
                if not all(valid(k, v) for k, v in data['changes'].items()):
                    abort(400)
                if rev != data['revision']:
                    return {'revision': rev, 'prefs': prefs}, 409
                merged = {**prefs, **data['changes']}
                if not row or removed or merged != prefs:
                    prefs, rev = merged, rev + 1
                    conn.execute('''INSERT INTO viewer_settings VALUES(?,?,?,?,?) ON CONFLICT(subject)
                        DO UPDATE SET label=excluded.label,revision=excluded.revision,prefs=excluded.prefs,updated=excluded.updated''',
                                 (subject, label, rev, json.dumps(prefs), int(time.time())))
            return {'revision': rev, 'prefs': prefs}
