import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/services/announcement_service.dart';

import 'package:plezy/services/base_shared_preferences_service.dart';
import 'package:plezy/services/sensitive_prefs.dart';

import '../test_helpers/prefs.dart';

class _TestPush implements AnnouncementPush {
  final events = StreamController<String>.broadcast(sync: true);
  bool stopped = false;
  bool? prompted;

  @override
  final supported = true;
  @override
  Stream<String> get registrations => events.stream;
  @override
  Stream<void> get foregroundMessages => const Stream.empty();
  @override
  Future<void> prepare({required bool prompt}) async => prompted = prompt;
  @override
  Future<void> register() async => events.add('first-installation-id');
  @override
  Future<void> stop() async => stopped = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const key = 'abcdefghijklmnopqrstuvwxyz1234567890';
  setUp(resetSharedPreferencesForTest);

  test('pair links require HTTPS or loopback and carry their credential only in the fragment', () {
    expect(AnnouncementService.parsePairLink('https://panel.example/#$key').host, 'panel.example');
    expect(AnnouncementService.parsePairLink('http://127.0.0.1:8080/#$key').port, 8080);
    for (final link in [
      'http://panel.example/#$key',
      'https://a@panel.example/#$key',
      'https://panel.example/?token=$key',
      'https://panel.example/#short',
    ]) {
      expect(() => AnnouncementService.parsePairLink(link), throwsFormatException);
    }
  });

  test('pair, fetch new announcements, restore on restart, then disconnect', () async {
    var count = 1;
    final seen = <Uri>[];
    MockClient client() => MockClient((request) async {
      seen.add(request.url);
      expect(request.headers['Authorization'], 'Bearer $key');
      expect(request.url.toString(), 'https://panel.example/api/feed');
      return http.Response(
        jsonEncode({
          'push': false,
          'messages': [
            for (var id = count; id > 0; id--) {'id': id, 'title': 'Title $id', 'body': 'Body'},
          ],
        }),
        200,
      );
    });
    final first = AnnouncementService(client: client());
    await first.start();
    await first.pair('https://panel.example/#$key');
    await Future<void>.delayed(Duration.zero);
    count = 2;
    await first.refresh();
    expect(first.messages.first.id, 2);
    expect(first.pushAvailable, false);
    first.dispose();
    final second = AnnouncementService(client: client());
    addTearDown(second.dispose);
    await second.start();
    await Future<void>.delayed(Duration.zero);
    expect(second.url?.host, 'panel.example');
    expect(second.messages.first.title, 'Title 2');
    await second.disconnect();
    expect(second.messages, isEmpty);
    final requests = seen.length;
    await second.refresh();
    expect(seen.length, requests);
  });
  test('a malformed saved pairing leaves the screen ready to pair again', () async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setString(announcementPairPref, '{"url":"https://panel.example"}');
    final service = AnnouncementService();
    addTearDown(service.dispose);
    await service.start();
    expect(service.url, isNull);
    expect(service.status, isNotNull);
  });

  test('mobile opt-in registers, updates the destination on rotation, and revokes on disconnect', () async {
    final push = _TestPush();
    addTearDown(push.events.close);
    final registrations = <Map<String, dynamic>>[];
    final service = AnnouncementService(
      push: push,
      client: MockClient((req) async {
        expect(req.headers['Authorization'], 'Bearer $key');
        if (req.url.path == '/api/device') {
          expect(req.method, 'PUT');
          registrations.add(jsonDecode(req.body) as Map<String, dynamic>);
          return http.Response('', 204);
        }
        return http.Response('{"push":true,"messages":[]}', 200);
      }),
    );
    addTearDown(service.dispose);
    await service.start();
    await service.pair('https://panel.example/#$key');
    expect(registrations, isEmpty);
    await service.setPush(true);
    expect(push.prompted, isTrue);
    expect(service.pushEnabled, isTrue);
    push.events.add('rotated-installation-id');
    await service.disconnect();
    expect(registrations.map((row) => row['fid']), ['first-installation-id', 'rotated-installation-id', null]);
    expect(registrations.map((row) => row['installation']).toSet(), hasLength(1));
    expect(push.stopped, isTrue);
    expect(service.pushEnabled, isFalse);
  });
}
