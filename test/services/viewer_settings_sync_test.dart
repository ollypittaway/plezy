import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/connection/connection.dart';
import 'package:plezy/profiles/active_profile_provider.dart';
import 'package:plezy/profiles/profile.dart';
import 'package:plezy/profiles/profile_connection.dart';
import 'package:plezy/providers/hidden_libraries_provider.dart';
import 'package:plezy/providers/libraries_provider.dart';
import 'package:plezy/services/announcement_service.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/storage_service.dart';
import 'package:plezy/services/viewer_settings_sync.dart';
import '../test_helpers/prefs.dart';

class _Viewer extends Fake with ChangeNotifier implements ActiveProfileProvider {
  final owner = Profile.plexHome(
    id: 'viewer-a',
    displayName: 'Viewer',
    parentConnectionId: 'p',
    plexHomeUserUuid: 'uuid-a',
    createdAt: DateTime(2026),
  );
  @override
  Profile get active => owner;
  @override
  String get activeId => owner.id;
  @override
  Map<String, Connection> get connectionsById => {
    'p': PlexAccountConnection(
      id: 'p',
      accountToken: 'unused-owner',
      clientIdentifier: 'client',
      accountLabel: 'Plex',
      servers: [],
      createdAt: DateTime(2026),
    ),
  };
  @override
  Map<String, List<ProfileConnection>> get connectionsByProfile => {
    owner.id: [
      ProfileConnection(profileId: owner.id, connectionId: 'p', userIdentifier: 'uuid-a', userToken: 'viewer-only'),
    ],
  };
}

class _Panel extends Fake with ChangeNotifier implements AnnouncementService {
  @override
  Uri get url => Uri.parse('https://panel.example');
  @override
  Future<String> settingsSession(Uri origin, String token, String clientId, String? uuid) async {
    expect(token, 'viewer-only');
    expect(uuid, 'uuid-a');
    return 'ticket';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
  });
  test('viewer overrides inherit existing preferences, survive switches, and reset independently', () async {
    final settings = await SettingsService.getInstance(), storage = await StorageService.getInstance();
    await settings.write(SettingsService.subtitleFontSize, 55);
    await storage.setActiveProfileId('a');
    final font = settings.listenable(SettingsService.subtitleFontSize);
    expect(font.value, 55);
    await settings.write(SettingsService.subtitleFontSize, 62);
    await settings.write(SettingsService.viewerAccent, 'rose');
    await storage.setActiveProfileId('b');
    expect(font.value, 55);
    expect(settings.read(SettingsService.viewerAccent), 'default');
    await storage.setActiveProfileId('a');
    expect(font.value, 62);
    expect(settings.read(SettingsService.viewerAccent), 'rose');
    await settings.reset(SettingsService.subtitleFontSize);
    expect(font.value, 42);
    await storage.setActiveProfileId('b');
    expect(font.value, 55);
  });

  test('pulls viewer settings then merges offline edits with another device and retries a conflict', () async {
    final settings = await SettingsService.getInstance(), storage = await StorageService.getInstance();
    final viewer = _Viewer(), panel = _Panel();
    await storage.setActiveProfileId(viewer.activeId);
    final libraries = LibrariesProvider(storageService: storage);
    final hidden = HiddenLibrariesProvider(storageService: storage, profileId: viewer.activeId);
    await hidden.ensureInitialized();
    var rev = 1, fail = false, conflict = false, deleted = false;
    final cloud = <String, dynamic>{
      'viewer_accent': 'violet',
      'subtitle_font_size': 59,
      'library_order': ['s/1'],
      'hidden_libraries': ['s/2'],
    };
    final patches = <Map>[];
    final client = MockClient((r) async {
      expect(r.headers['Authorization'], 'Bearer ticket');
      expect(r.headers.containsKey('X-Plex-Token'), isFalse);
      if (fail) return http.Response('', 503);
      if (deleted) {
        if (r.method == 'GET') return http.Response(jsonEncode({'revision': rev}), 410);
        final body = jsonDecode(r.body) as Map;
        expect(body['reconnect'], true);
        expect(body['revision'], rev);
        deleted = false;
      }
      if (r.method == 'PATCH') {
        if (conflict) {
          conflict = false;
          rev++;
          cloud['seek_time_small'] = 17;
          return http.Response('', 409);
        }
        final body = jsonDecode(r.body) as Map;
        expect(body['revision'], rev);
        patches.add(body['changes'] as Map);
        cloud.addAll(Map.from(body['changes'] as Map));
        rev++;
      }
      return http.Response(jsonEncode({'revision': rev, 'prefs': cloud}), 200);
    });
    final sync = ViewerSettingsSync(
      viewer.activeId,
      viewer,
      panel,
      settings,
      storage,
      hidden,
      libraries,
      client: client,
    );
    addTearDown(() {
      sync.dispose();
      libraries.dispose();
      hidden.dispose();
      viewer.dispose();
      panel.dispose();
    });
    expect(sync.enabled, isFalse);
    await sync.setEnabled(true);
    await sync.sync();
    expect(sync.synced, isTrue);
    expect(settings.read(SettingsService.subtitleFontSize), 59);
    expect(settings.read(SettingsService.viewerAccent), 'violet');
    expect(hidden.hiddenLibraryKeys, {'s/2'});
    expect(storage.getLibraryOrder(), ['s/1']);
    fail = true;
    await settings.write(SettingsService.subtitleFontSize, 64);
    await sync.sync();
    expect(sync.failed, isTrue);
    fail = false;
    cloud['viewer_accent'] = 'blue';
    rev++;
    conflict = true;
    await sync.sync();
    expect(sync.failed, isFalse);
    expect(settings.read(SettingsService.viewerAccent), 'blue');
    expect(settings.read(SettingsService.seekTimeSmall), 17);
    expect(patches.last, {'subtitle_font_size': 64});
    expect(cloud['subtitle_font_size'], 64);
    deleted = true;
    rev++;
    cloud.clear();
    final writes = patches.length;
    await sync.sync();
    expect(sync.enabled, isFalse);
    expect(settings.read(SettingsService.subtitleFontSize), 64);
    await sync.sync();
    expect(patches, hasLength(writes));
    await sync.setEnabled(true);
    await sync.sync();
    expect(sync.synced, isTrue);
    expect(cloud['subtitle_font_size'], 64);
  });
}
