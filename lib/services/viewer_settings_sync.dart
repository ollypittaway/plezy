import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../connection/connection.dart';
import '../profiles/active_profile_provider.dart';
import '../profiles/profile.dart';
import '../providers/hidden_libraries_provider.dart';
import '../providers/libraries_provider.dart';
import 'account_preferences_accounts.dart';
import 'announcement_service.dart';
import 'settings_service.dart';
import 'storage_service.dart';

typedef _Identity = ({Uri origin, String ref, String token, String clientId, String? uuid});

/// One instance belongs to one keyed profile session. The three-way merge
/// uploads local changes only, and a revision check protects concurrent devices.
class ViewerSettingsSync extends ChangeNotifier with WidgetsBindingObserver {
  ViewerSettingsSync(
    this.profileId,
    this.active,
    this.panel,
    this.settings,
    this.storage,
    this.hidden,
    this.libraries, {
    http.Client? client,
  }) : _client = client ?? http.Client() {
    _prefsListener = settings.listenableOfAll(SettingsService.viewerPrefs.values.toList());
    active.addListener(_configurationChanged);
    panel.addListener(_configurationChanged);
    _prefsListener.addListener(_schedule);
    hidden.addListener(_schedule);
    libraries.addListener(_schedule);
    WidgetsBinding.instance.addObserver(this);
    _configurationChanged();
  }

  final String profileId;
  final ActiveProfileProvider active;
  final AnnouncementService panel;
  final SettingsService settings;
  final StorageService storage;
  final HiddenLibrariesProvider hidden;
  final LibrariesProvider libraries;
  final http.Client _client;
  late final Listenable _prefsListener;
  Timer? _debounce, _poll;
  _Identity? _identity;
  String? _ticket;
  bool _disposed = false, _foreground = true;
  bool busy = false, failed = false, synced = false;
  int _epoch = 0;
  bool _explicitEnable = false;
  String get _prefix => profileScopedPrefsKey(profileId, 'sync_v1');
  String get _scope => jsonEncode([_identity?.origin.origin, _identity?.ref]);
  bool get available => _identity != null;
  bool get enabled => available && storage.readNullableString('${_prefix}_enabled') == _scope;

  _Identity? _resolve() {
    final origin = panel.url;
    final profile = active.active;
    if (profile?.id != profileId || origin == null || origin.scheme != 'https') return null;
    final accounts = resolveAccountPreferenceAccounts(
      profile: profile,
      profileConnections: active.connectionsByProfile[profileId] ?? [],
      connections: active.connectionsById.values.toList(),
    ).accounts;
    final account = accounts.where((a) => a.plexToken != null).firstOrNull;
    if (account == null) return null;
    final connection = account.connection as PlexAccountConnection;
    return (
      origin: origin,
      ref: account.ref.key,
      token: account.plexToken!,
      clientId: connection.clientIdentifier,
      uuid: account.ref.plexHomeUserUuid,
    );
  }

  void _configurationChanged() {
    final identity = _resolve();
    if (_identity == identity) return;
    _explicitEnable = false;
    _identity = identity;
    _restart();
  }

  void _restart() {
    _epoch++;
    _ticket = null;
    failed = synced = busy = false;
    _debounce?.cancel();
    _poll?.cancel();
    if (enabled && _foreground) {
      _poll = Timer.periodic(const Duration(minutes: 2), (_) => sync());
      _schedule();
    }
    if (!_disposed) notifyListeners();
  }

  void _schedule() {
    if (_disposed || !enabled || !_foreground) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 1), sync);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _schedule();
  }

  Future<void> setEnabled(bool value) async {
    if (value && !available) return;
    if (value) {
      await storage.writeString('${_prefix}_enabled', _scope);
    } else {
      await storage.prefs.remove('${_prefix}_enabled');
    }
    if (!_disposed) {
      _explicitEnable = value;
      _restart();
    }
  }

  Map<String, dynamic> _snapshot() => {
    for (final entry in SettingsService.viewerPrefs.entries) entry.key: entry.value.toJson(settings.read(entry.value)),
    'hidden_libraries': storage.getHiddenLibrariesForProfile(profileId).toList()..sort(),
    'library_order': storage.getLibraryOrder() ?? <String>[],
  };

  Future<({int revision, Map<String, dynamic> prefs})> _exchange(_Identity id, {Map<String, dynamic>? patch}) async {
    final req = http.Request(patch == null ? 'GET' : 'PATCH', id.origin.resolve('/api/settings'))
      ..followRedirects = false
      ..headers.addAll({'Authorization': 'Bearer $_ticket', 'Content-Type': 'application/json'});
    if (patch != null) req.body = jsonEncode(patch);
    final reply = await _client.send(req).then(http.Response.fromStream).timeout(const Duration(seconds: 10));
    if (reply.statusCode == 401) throw const _Expired();
    if (reply.statusCode == 410) throw _Removed(jsonDecode(reply.body)['revision'] as int);
    if (reply.statusCode == 409) throw const _Conflict();
    if (reply.statusCode != 200) throw const FormatException();
    final data = jsonDecode(utf8.decode(reply.bodyBytes)) as Map;
    final prefs = Map<String, dynamic>.from(data['prefs'] as Map);
    for (final entry in prefs.entries) {
      if (entry.key == 'library_order' || entry.key == 'hidden_libraries') {
        final list = entry.value;
        if (list is! List || list.length > 256 || !list.every((s) => s is String && s.isNotEmpty && s.length <= 256)) {
          throw const FormatException();
        }
      } else if (SettingsService.viewerPrefs[entry.key] case final pref?) {
        SettingsService.validateEditableValue(pref, pref.fromJson(entry.value));
      }
    }
    return (revision: data['revision'] as int, prefs: prefs);
  }

  Future<void> sync() async {
    final id = _identity;
    if (_disposed || !_foreground || !enabled || busy || id == null) return;
    final epoch = _epoch;
    bool current() =>
        !_disposed &&
        epoch == _epoch &&
        active.activeId == profileId &&
        storage.getActiveProfileId() == profileId &&
        enabled;
    if (!current()) return;
    busy = true;
    notifyListeners();
    try {
      for (var attempt = 0; attempt < 3 && current(); attempt++) {
        try {
          if (_ticket == null) {
            final ticket = await panel.settingsSession(id.origin, id.token, id.clientId, id.uuid);
            if (!current()) return;
            _ticket = ticket;
          }
          final cloud = await _exchange(id);
          if (!current()) return;
          _explicitEnable = false;
          final key = '${_prefix}_base_$_scope';
          final raw = storage.readNullableString(key);
          final base = raw == null ? <String, dynamic>{} : jsonDecode(raw) as Map<String, dynamic>;
          final before = _snapshot();
          final changes = <String, dynamic>{
            for (final entry in before.entries)
              if (!cloud.prefs.containsKey(entry.key) ||
                  (base.containsKey(entry.key) &&
                      !deepEquals(base[entry.key], entry.value) &&
                      !deepEquals(cloud.prefs[entry.key], entry.value)))
                entry.key: entry.value,
          };
          final result = changes.isEmpty
              ? cloud
              : await _exchange(id, patch: {'revision': cloud.revision, 'changes': changes});
          if (!current()) return;
          for (final entry in before.entries) {
            final value = result.prefs[entry.key];
            if (value == null || deepEquals(value, entry.value) || !deepEquals(_snapshot()[entry.key], entry.value)) {
              continue;
            }
            if (entry.key == 'hidden_libraries') {
              await storage.saveHiddenLibrariesForProfile(profileId, (value as List).cast<String>().toSet());
              if (current()) await hidden.refresh();
            } else if (entry.key == 'library_order') {
              await storage.saveLibraryOrder((value as List).cast<String>(), profileId: profileId);
              if (current()) libraries.reloadStoredOrder();
            } else {
              final key = profileScopedPrefsKey(profileId, entry.key);
              final stored = entry.key == SettingsService.defaultPlaybackSpeed.key ? (value as num).toDouble() : value;
              switch (stored) {
                case bool():
                  await storage.writeBool(key, stored);
                case int():
                  await storage.writeInt(key, stored);
                case double():
                  await storage.writeDouble(key, stored);
                case String():
                  await storage.writeString(key, stored);
              }
            }
            if (!current()) return;
          }
          settings.refreshActiveListenables();
          await storage.writeString(key, jsonEncode(result.prefs));
          if (!current()) return;
          failed = false;
          synced = true;
          return;
        } on _Removed catch (removed) {
          if (!current()) return;
          if (_explicitEnable) {
            await _exchange(id, patch: {'revision': removed.revision, 'changes': _snapshot(), 'reconnect': true});
            if (!current()) return;
            _explicitEnable = false;
            continue;
          }
          await storage.prefs.remove('${_prefix}_base_$_scope');
          if (current()) await setEnabled(false);
          return;
        } on _Conflict {
          continue;
        } on _Expired {
          if (!current()) return;
          _ticket = null;
        }
      }
      if (current()) failed = true;
    } catch (_) {
      if (current()) failed = true;
    } finally {
      if (!_disposed && epoch == _epoch) {
        busy = false;
        notifyListeners();
      }
    }
  }

  static bool deepEquals(Object? a, Object? b) => a is List && b is List ? listEquals(a, b) : a == b;

  @override
  void dispose() {
    _disposed = true;
    active.removeListener(_configurationChanged);
    panel.removeListener(_configurationChanged);
    _prefsListener.removeListener(_schedule);
    hidden.removeListener(_schedule);
    libraries.removeListener(_schedule);
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _poll?.cancel();
    _client.close();
    super.dispose();
  }
}

class _Conflict implements Exception {
  const _Conflict();
}

class _Expired implements Exception {
  const _Expired();
}

class _Removed implements Exception {
  const _Removed(this.revision);
  final int revision;
}
