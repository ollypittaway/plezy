import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/screens/settings/announcement_settings_screen.dart';
import 'package:provider/provider.dart';
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
    expect(
      AnnouncementService.parsePairLink('https://panel.pittaway.dev/#$key').origin,
      'https://panel.offstage.download',
    );
    expect(
      AnnouncementService.parsePairLink('https://panel.pittaway.dev:8443/#$key').origin,
      'https://panel.pittaway.dev:8443',
    );
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
    await (await BaseSharedPreferencesService.sharedCache()).setBool(AnnouncementService.automaticPairingPref, false);
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
    await first.dismissMessages('viewer-a', [1]);
    expect(first.visibleMessages('viewer-a').map((notice) => notice.id), [2]);
    expect(first.visibleMessages('viewer-b'), hasLength(2));
    first.dispose();
    final second = AnnouncementService(client: client());
    addTearDown(second.dispose);
    await second.start();
    await Future<void>.delayed(Duration.zero);
    expect(second.url?.host, 'panel.example');
    expect(second.messages.first.title, 'Title 2');
    expect(second.visibleMessages('viewer-a').single.id, 2);
    await second.dismissMessages('viewer-a', second.visibleMessages('viewer-a').map((notice) => notice.id));
    expect(second.visibleMessages('viewer-a'), isEmpty);
    count = 3;
    await second.refresh();
    expect(second.visibleMessages('viewer-a').single.id, 3);
    expect(second.visibleMessages('viewer-b'), hasLength(3));
    await second.disconnect();
    expect(second.messages, isEmpty);
    final requests = seen.length;
    await second.refresh();
    expect(seen.length, requests);
  });
  test('enrolls without a Plex token, retries after going offline and respects opt-out across restarts', () async {
    var online = false, enrollments = 0, reads = 0;
    const installation = '0123456789abcdef0123456789abcdef';
    MockClient client() => MockClient((request) async {
      expect(request.url.origin, 'https://panel.offstage.download');
      expect(request.headers['X-Plex-Token'], isNull);
      if (request.url.path == '/api/pair') {
        enrollments++;
        expect(request.method, 'POST');
        expect(request.followRedirects, isFalse);
        expect(request.headers['Authorization'], isNull);
        if (!online) return http.Response('', 503);
        return http.Response(jsonEncode({'installation': installation, 'key': key}), 201);
      }
      reads++;
      expect(request.url.path, '/api/feed');
      expect(request.headers['Authorization'], 'Bearer $key');
      return http.Response('{"messages":[],"push":false}', 200);
    });
    Future<void> settle() => Future<void>.delayed(Duration.zero);
    final first = AnnouncementService(client: client());
    await first.start();
    await settle();
    expect(first.automaticPairing, isTrue);
    expect(first.url, isNull);
    expect(first.status, isNotNull);
    online = true;
    await first.refresh();
    expect(first.url, AnnouncementService.officialPanel);
    expect(enrollments, 2);
    first.dispose();

    final second = AnnouncementService(client: client());
    await second.start();
    await settle();
    expect(second.url, AnnouncementService.officialPanel);
    expect(enrollments, 2, reason: 'Reuse the stored device credential');
    await second.setAutomaticPairing(false);
    expect(second.url, isNull);
    second.dispose();
    final readsBefore = reads;
    final third = AnnouncementService(client: client());
    addTearDown(third.dispose);
    await third.start();
    await settle();
    await third.refresh();
    expect(third.automaticPairing, isFalse);
    expect(reads, readsBefore);
    expect(enrollments, 2);
    await third.setAutomaticPairing(true);
    await settle();
    expect(third.url, AnnouncementService.officialPanel);
    expect(enrollments, 3);
  });
  test('restores an existing private panel without attempting automatic enrollment', () async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setString(
      announcementPairPref,
      jsonEncode({
        'url': 'https://custom.example',
        'key': key,
        'installation': 'older-install',
        'seen': 0,
        'push': false,
      }),
    );
    final calls = <Uri>[];
    final service = AnnouncementService(
      client: MockClient((r) async {
        calls.add(r.url);
        return http.Response('{"messages":[],"push":false}', 200);
      }),
    );
    addTearDown(service.dispose);
    await service.start();
    await Future<void>.delayed(Duration.zero);
    expect(service.automaticPairing, isFalse);
    expect(calls.single.toString(), 'https://custom.example/api/feed');
  });

  test('moves the former official pairing and its viewer preferences to the new host', () async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    const former = 'https://panel.pittaway.dev';
    final current = AnnouncementService.officialPanel.origin;
    final oldScope = jsonEncode([former, 'viewer-a']);
    final newScope = jsonEncode([current, 'viewer-a']);
    await prefs.setString('user_a_sync_v1_enabled', oldScope);
    await prefs.setString('user_a_sync_v1_base_$oldScope', '{"speed":1.5}');
    await prefs.setStringList('user_a_dismissed_announcements_$former', ['1']);
    await prefs.setStringList('user_a_dismissed_announcements_$current', ['2']);
    await prefs.setString(
      announcementPairPref,
      jsonEncode({'url': former, 'key': key, 'installation': 'existing', 'seen': 2, 'push': false}),
    );
    final calls = <String>[];
    final service = AnnouncementService(
      client: MockClient((r) async {
        calls.add(r.url.path);
        expect(r.url.origin, current);
        expect(r.headers['Authorization'], 'Bearer $key');
        return http.Response('{"messages":[],"push":false}', 200);
      }),
    );
    addTearDown(service.dispose);
    await service.start();
    await Future<void>.delayed(Duration.zero);
    expect(service.automaticPairing, isTrue);
    expect(calls, ['/api/feed']);
    final pair = jsonDecode(prefs.getString(announcementPairPref)!);
    expect(pair['url'], current);
    expect(pair['installation'], 'existing');
    expect(pair['seen'], 2);
    expect(prefs.getString('user_a_sync_v1_enabled'), newScope);
    expect(prefs.getString('user_a_sync_v1_base_$newScope'), '{"speed":1.5}');
    expect(prefs.getStringList('user_a_dismissed_announcements_$current'), unorderedEquals(['1', '2']));
    expect(prefs.getString('user_a_sync_v1_base_$oldScope'), isNull);
    expect(prefs.getStringList('user_a_dismissed_announcements_$former'), isNull);
    await service.setAutomaticPairing(false);
    expect(service.url, isNull);
  });

  test('an opted-out device retries its old push revocation only on the new panel', () async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setBool(AnnouncementService.automaticPairingPref, false);
    await prefs.setString(
      announcementPendingUnregisterPref,
      jsonEncode({'url': 'https://panel.pittaway.dev', 'key': key, 'installation': 'existing'}),
    );
    final calls = <Uri>[];
    final service = AnnouncementService(
      client: MockClient((r) async {
        calls.add(r.url);
        expect(r.method, 'PUT');
        expect(r.headers['Authorization'], 'Bearer $key');
        expect(jsonDecode(r.body), {'installation': 'existing', 'fid': null});
        return http.Response('', 204);
      }),
    );
    addTearDown(service.dispose);
    await service.start();
    await service.refresh();
    expect(calls.single.toString(), 'https://panel.offstage.download/api/device');
    expect(prefs.containsKey(announcementPendingUnregisterPref), isFalse);
    expect(service.automaticPairing, isFalse);
  });

  test('turning off while enrollment is in flight ignores its late reply', () async {
    final pairStarted = Completer<void>();
    final pairReply = Completer<http.Response>();
    var feedCalls = 0;
    final service = AnnouncementService(
      client: MockClient((request) async {
        if (request.url.path == '/api/pair') {
          pairStarted.complete();
          return pairReply.future;
        }
        feedCalls++;
        return http.Response('{"messages":[],"push":false}', 200);
      }),
    );
    addTearDown(service.dispose);
    await service.start();
    await pairStarted.future;
    final optOut = service.setAutomaticPairing(false);
    await Future<void>.delayed(Duration.zero);
    final prefs = await BaseSharedPreferencesService.sharedCache();
    expect(prefs.getBool(AnnouncementService.automaticPairingPref), isFalse);
    pairReply.complete(http.Response(jsonEncode({'installation': '0' * 32, 'key': key}), 201));
    await optOut;
    expect(service.url, isNull);
    expect(feedCalls, 0);
    expect(prefs.containsKey(announcementPairPref), isFalse);
  });

  test('offline opt-out stops native push and retries only the revocation on restart', () async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setString(
      announcementPairPref,
      jsonEncode({
        'url': 'https://custom.example',
        'key': key,
        'installation': 'installed-before',
        'seen': 0,
        'push': true,
      }),
    );
    final push = _TestPush();
    addTearDown(push.events.close);
    var online = false;
    final calls = <String>[];
    MockClient client() => MockClient((request) async {
      calls.add(request.url.path);
      if (request.url.path == '/api/feed') return http.Response('{"messages":[],"push":false}', 200);
      expect(jsonDecode(request.body), {'installation': 'installed-before', 'fid': null});
      return http.Response('', online ? 204 : 503);
    });
    final service = AnnouncementService(client: client(), push: push);
    await service.start();
    await service.disconnect();
    expect(service.url, isNull);
    expect(push.stopped, isTrue);
    expect(prefs.containsKey(announcementPendingUnregisterPref), isTrue);
    service.dispose();
    online = true;
    calls.clear();
    final next = AnnouncementService(client: client(), push: push);
    addTearDown(next.dispose);
    await next.start();
    await next.refresh();
    expect(calls, ['/api/device']);
    expect(prefs.containsKey(announcementPendingUnregisterPref), isFalse);
    expect(next.automaticPairing, isFalse);
  });

  testWidgets('Notifications offers one switch for the official panel and remembers the choice', (tester) async {
    final service = AnnouncementService(
      client: MockClient((request) async {
        if (request.url.path == '/api/pair') {
          return http.Response(jsonEncode({'installation': '1' * 32, 'key': key}), 201);
        }
        return http.Response('{"messages":[],"push":false}', 200);
      }),
    );
    await service.start();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: service,
        child: const MaterialApp(home: Scaffold(body: AnnouncementSettingsScreen(embedded: true))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('panel.offstage.download'), findsOneWidget);
    final pairing = find.widgetWithText(SwitchListTile, t.announcements.automaticPairing);
    expect(tester.widget<SwitchListTile>(pairing).value, isTrue);
    await tester.tap(pairing);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(pairing).value, isFalse);
    expect(find.text('panel.offstage.download'), findsNothing);
    expect(find.text(t.announcements.link), findsOneWidget);
    await tester.tap(pairing);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(pairing).value, isTrue);
    expect(find.text('panel.offstage.download'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
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
    await (await BaseSharedPreferencesService.sharedCache()).setBool(AnnouncementService.automaticPairingPref, false);
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
