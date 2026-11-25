import tempfile
import unittest
from unittest.mock import patch

from app import ExpiredToken, create_app, firebase_sender


class PanelTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.admin = {'Authorization': 'Bearer ' + 'a' * 32}
        self.sent = []
        self.app, self.work = create_app(self.directory.name, 'a' * 32, sender=lambda *args: self.sent.append(args))
        self.client = self.app.test_client()
        self.pair = {'Authorization': 'Bearer ' + self.dashboard()['pairKey']}

    def dashboard(self):
        return self.client.get('/api/admin', headers=self.admin).json

    def device(self, fid, installation='x' * 48):
        return self.client.put('/api/device', headers=self.pair, json={'installation': installation, 'fid': fid})

    def publish(self, title='Film night', key='first'):
        return self.client.post('/api/notifications', headers={**self.admin, 'Idempotency-Key': key},
                                json={'title': title, 'body': 'New films are ready.'})

    def test_console_api_and_restart(self):
        with self.client.get('/') as response:
            self.assertEqual(response.status_code, 200)
        self.assertEqual(self.client.get('/api/feed').status_code, 401)
        self.assertEqual(self.client.get('/api/admin', headers=self.pair).status_code, 401)
        self.assertEqual(self.client.post('/api/notifications', headers=self.pair, json={}).status_code, 401)
        self.assertEqual(self.device('old-fid').status_code, 204)
        self.assertEqual(self.publish().status_code, 201)
        self.assertEqual(self.publish().status_code, 200)
        self.assertEqual(self.publish('Different message').status_code, 409)
        self.device('new-fid')
        # A new worker can deliver what the first instance accepted.
        app, work = create_app(self.directory.name, 'a' * 32, sender=lambda *args: self.sent.append(args))
        self.assertTrue(work())
        self.assertFalse(work())
        self.assertEqual(self.sent, [('new-fid', 1, 'Film night', 'New films are ready.')])
        self.assertEqual(self.dashboard()['messages'][0]['accepted'], 1)
        feed = app.test_client().get('/api/feed', headers=self.pair)
        self.assertEqual(feed.json['messages'][0]['title'], 'Film night')
        self.assertEqual(feed.headers['Cache-Control'], 'no-store')

    def test_disable_removes_pending_push(self):
        self.device('first-device')
        self.publish()
        self.assertEqual(self.device(None).status_code, 204)
        self.assertFalse(self.work())
        self.assertEqual(self.dashboard()['phones'], 0)
        self.assertEqual(len(self.client.get('/api/feed', headers=self.pair).json['messages']), 1)

    def test_offline_retry_and_expired_destination(self):
        self.device('expired-device')
        self.publish()
        def transient(*args):
            raise ConnectionError()
        def expired(*args):
            raise ExpiredToken()
        _, work = create_app(self.directory.name, 'a' * 32, sender=transient)
        with patch('app.time.time', return_value=100):
            self.assertTrue(work())
            self.assertFalse(work())
        _, work = create_app(self.directory.name, 'a' * 32, sender=expired)
        with patch('app.time.time', return_value=200):
            self.assertTrue(work())
        self.assertEqual(self.dashboard()['phones'], 0)
        self.assertEqual(self.dashboard()['messages'][0]['failed'], 1)

    def test_in_app_only_and_limits(self):
        app, _ = create_app(self.directory.name, 'a' * 32)
        client = app.test_client()
        self.assertFalse(client.get('/api/feed', headers=self.pair).json['push'])
        self.assertEqual(client.put('/api/device', headers=self.pair, json={'installation': 'i' * 32, 'fid': 'one'}).status_code, 503)
        self.assertEqual(self.publish(' ').status_code, 400)
        self.assertEqual(self.publish('x' * 121).status_code, 400)

    def test_mobile_push_payload_targets_the_registered_fid(self):
        from firebase_admin import messaging
        with patch('firebase_admin.initialize_app'), patch('firebase_admin.messaging.send') as dispatch:
            firebase_sender()('device-id', 17, 'Film night', 'New releases')
        message = dispatch.call_args.args[0]
        self.assertEqual(message.fid, 'device-id')
        self.assertEqual(message.notification.body, 'New releases')
        self.assertEqual(message.data['noticeId'], '17')
        self.assertEqual(message.android.notification.tag, message.apns.headers['apns-collapse-id'])
        self.assertEqual(message.apns.payload.aps.sound, 'default')


if __name__ == '__main__':
    unittest.main()
