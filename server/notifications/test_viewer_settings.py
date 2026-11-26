import sqlite3
import tempfile
import unittest
from flask import abort

from app import create_app


class ViewerSettingsTests(unittest.TestCase):
    def test_pairing_identity_isolation_merges_and_persistence(self):
        with tempfile.TemporaryDirectory() as directory:
            owner_label = 'Olly'
            def verify(token, client_id):
                if token not in ('mock_owner_token', 'mock_kid_token') or client_id not in ('device', 'second-device'):
                    abort(401)
                return ('owner', owner_label) if token == 'mock_owner_token' else ('child', 'Olly')
            app, _ = create_app(directory, 'a'*32, verifier=verify)
            client = app.test_client()
            admin = {'Authorization': 'Bearer '+'a'*32}
            pair = {'Authorization': 'Bearer '+client.get('/api/admin', headers=admin).json['pairKey']}
            def session(token, uuid):
                return client.post('/api/settings/session', headers={**pair, 'X-Plex-Token': token, 'X-Viewer-UUID': uuid, 'X-Plex-Client-Identifier':'device'})
            self.assertEqual(session('mock_owner_token', 'child').status_code, 403)
            self.assertEqual(session('invalid', 'owner').status_code, 401)
            self.assertEqual(client.get('/api/settings', headers=pair).status_code, 401)
            owner = {'Authorization':'Bearer '+session('mock_owner_token','owner').json['session']}
            child = {'Authorization':'Bearer '+session('mock_kid_token','child').json['session']}
            def save(who, rev, changes):
                return client.patch('/api/settings', headers=who, json={'revision':rev,'changes':changes})
            self.assertEqual(save(owner,0,{'viewer_accent':'violet','subtitle_font_size':65}).status_code, 200)
            self.assertEqual(save(owner,0,{'auto_play_next_episode':False}).status_code, 409)
            self.assertEqual(save(owner,1,{'subtitle_font_size':True}).status_code, 400)
            self.assertEqual(save(owner,1,{'server_token':'foo'}).status_code, 400)
            self.assertEqual(save(owner,1,{'library_order':['a','a']}).status_code, 400)
            self.assertEqual(save(owner,1,{'auto_play_next_episode':False}).json['prefs']['viewer_accent'], 'violet')
            self.assertEqual(client.get('/api/settings',headers=child).json['prefs'], {})
            self.assertEqual(client.get('/api/admin',headers=owner).status_code, 401)
            self.assertEqual(client.get('/api/admin',headers=admin).json['viewers'][0]['label'], 'Olly')
            # The second device signs in from scratch, after a display-name change.
            owner_label = 'Renamed'
            second_session = client.post('/api/settings/session', headers={**pair,
                'X-Plex-Token':'mock_owner_token', 'X-Plex-Client-Identifier':'second-device'}).json['session']
            restored = client.get('/api/settings', headers={'Authorization':'Bearer '+second_session}).json
            self.assertEqual(restored['prefs'], {'viewer_accent':'violet', 'subtitle_font_size':65, 'auto_play_next_episode':False})
            restarted,_ = create_app(directory, 'a'*32, verifier=verify)
            self.assertEqual(restarted.test_client().get('/api/settings',headers=owner).json['revision'],2)
            subject = client.get('/api/admin', headers=admin).json['viewers'][0]['id']
            route = '/api/admin/viewers/' + subject
            self.assertEqual(client.delete(route, headers=owner).status_code, 401)
            self.assertEqual(client.delete(route, headers=admin).status_code, 200)
            self.assertEqual(client.get('/api/admin', headers=admin).json['viewers'], [])
            removed = client.get('/api/settings', headers=owner)
            self.assertEqual(removed.status_code, 410)
            self.assertEqual(save(owner, 2, {'viewer_accent':'rose'}).status_code, 410)
            self.assertEqual(client.get('/api/settings', headers=child).status_code, 200)
            self.assertEqual(client.patch('/api/settings',headers=owner,json={
                'revision':removed.json['revision'], 'changes':{'viewer_accent':'blue'}, 'reconnect':True
            }).json['prefs'], {'viewer_accent':'blue'})
            with sqlite3.connect(directory+'/announcements.sqlite3') as db:
                self.assertNotIn('mock_owner_token', '\n'.join(db.iterdump()))
