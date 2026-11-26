import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../i18n/strings.g.dart';
import '../profiles/profile.dart';
import '../utils/platform_detector.dart';
import '../utils/snackbar_helper.dart';
import 'base_shared_preferences_service.dart';
import 'sensitive_prefs.dart';

typedef Announcement = ({int id, String title, String body});

/// The system permission and device-registration side of mobile announcements.
class AnnouncementPush {
  bool get supported => (Platform.isAndroid || Platform.isIOS) && !PlatformDetector.isTVDevice();

  Future<void> prepare({required bool prompt}) async {
    try {
      await Firebase.initializeApp();
    } on FirebaseException {
      throw FormatException(t.announcements.setupNeeded);
    }
    final fcm = FirebaseMessaging.instance;
    final settings = prompt ? await fcm.requestPermission() : await fcm.getNotificationSettings();
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      throw FormatException(t.announcements.permission);
    }
  }

  Stream<String> get registrations => FirebaseMessaging.instance.onRegistered;
  Stream<void> get foregroundMessages => FirebaseMessaging.onMessage.map<void>((_) {});

  Future<void> register() async {
    final fcm = FirebaseMessaging.instance;
    await fcm.setAutoInitEnabled(true);
    if (Platform.isIOS) {
      for (var attempt = 0; attempt < 12 && await fcm.getAPNSToken() == null; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      if (await fcm.getAPNSToken() == null) throw FormatException(t.announcements.applePending);
    }
    await fcm.register().timeout(const Duration(seconds: 15));
  }

  Future<void> stop() async {
    final messaging = FirebaseMessaging.instance;
    await messaging.setAutoInitEnabled(false);
    await messaging.unregister().timeout(const Duration(seconds: 5));
  }
}

/// An installation pairs with one panel for announcements and optional viewer settings sync.
class AnnouncementService extends ChangeNotifier with WidgetsBindingObserver {
  AnnouncementService({http.Client? client, AnnouncementPush? push})
    : _client = client ?? http.Client(),
      _native = push ?? AnnouncementPush();
  static final officialPanel = Uri.https('panel.offstage.download');
  static const _previousPanelOrigin = 'https://panel.pittaway.dev';
  static const automaticPairingPref = 'gucciplexa_automatic_pairing';
  bool _automatic = true, _disconnectRequested = false;
  bool get automaticPairing => _automatic;
  final AnnouncementPush _native;
  final http.Client _client;
  Uri? _url;
  String _key = '', _installation = '';
  int _seen = 0;
  bool _push = false, _active = true, _disposed = false, _refreshPending = false;
  bool pushAvailable = false;
  String? status;
  List<Announcement> messages = const [];
  SharedPreferencesWithCache? _prefs;

  String _dismissedKey(String? profileId) =>
      profileScopedPrefsKey(profileId ?? '', 'dismissed_announcements_${url?.origin}');

  List<Announcement> visibleMessages(String? profileId) {
    final dismissed = _prefs?.getStringList(_dismissedKey(profileId))?.toSet() ?? const <String>{};
    return messages.where((notice) => !dismissed.contains(notice.id.toString())).toList();
  }

  Future<void> dismissMessages(String? profileId, Iterable<int> ids) {
    final key = _dismissedKey(profileId);
    final selected = ids.map((id) => id.toString()).toSet();
    return _serial(() async {
      final prefs = _prefs ??= await BaseSharedPreferencesService.sharedCache();
      final dismissed = {...?prefs.getStringList(key), ...selected};
      await prefs.setStringList(key, dismissed.toList());
      _notify();
    });
  }

  Uri? get url => _disconnectRequested ? null : _url;
  bool get pushEnabled => _push;
  bool get supportsPush => _native.supported;
  Timer? _timer;
  StreamSubscription<String>? _tokens;
  StreamSubscription<void>? _foreground;
  Future<void> _pending = Future.value();

  Future<void> _serial(Future<void> Function() action) {
    final next = _pending.then((_) async {
      if (!_disposed) await action();
    });
    _pending = next.catchError((Object _) {});
    return next;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // Update the local origin-scoped records before a viewer's sync session can start.
  static Future<void> _migratePanelPreferences(SharedPreferencesWithCache prefs) async {
    const oldScope = '["$_previousPanelOrigin",';
    final newScope = '["${officialPanel.origin}",';
    for (final key in prefs.keys) {
      if (key.endsWith('dismissed_announcements_$_previousPanelOrigin')) {
        final target = key.substring(0, key.length - _previousPanelOrigin.length) + officialPanel.origin;
        final merged = {...?prefs.getStringList(target), ...?prefs.getStringList(key)};
        await prefs.setStringList(target, merged.toList());
        await prefs.remove(key);
      } else if (key.contains('sync_v1_base_$oldScope')) {
        final target = key.replaceFirst('sync_v1_base_$oldScope', 'sync_v1_base_$newScope');
        final base = prefs.get(key);
        if (base is! String) continue;
        if (!prefs.containsKey(target)) await prefs.setString(target, base);
        await prefs.remove(key);
      } else if (key.endsWith('sync_v1_enabled')) {
        final value = prefs.get(key);
        if (value is String && value.startsWith(oldScope)) {
          await prefs.setString(key, newScope + value.substring(oldScope.length));
        }
      }
    }
  }

  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    await _serial(() async {
      final prefs = _prefs = await BaseSharedPreferencesService.sharedCache();
      try {
        await _migratePanelPreferences(prefs);
        final stored = prefs.getString(announcementPairPref);
        _automatic = prefs.getBool(automaticPairingPref) ?? stored == null;
        if (stored == null) return;
        final config = jsonDecode(stored);
        if (config case {
          'url': final String url,
          'key': final String key,
          'installation': final String install,
          'seen': final int seen,
          'push': final bool push,
        }) {
          final pair = parsePairLink('$url/#$key');
          // Early app builds paired the official panel through a private link.
          // Reuse that working credential, seen marker and push registration.
          final storedAutomatic = config['automatic'] as bool? ?? pair.origin == officialPanel.origin;
          _automatic = prefs.getBool(automaticPairingPref) ?? storedAutomatic;
          if (storedAutomatic && !_automatic) {
            await prefs.remove(announcementPairPref);
            return;
          }
          _url = Uri.parse(pair.origin);
          _key = pair.fragment;
          _installation = install;
          _seen = seen;
          _push = push;
          if (Uri.parse(url).origin != pair.origin) await _save();
        } else {
          throw const FormatException();
        }
      } on FormatException {
        status = t.announcements.invalidLink;
      } on TypeError {
        status = t.announcements.invalidLink;
      }
    });
    await _serial(_retryUnregister);
    _notify();
    _schedule();
  }

  static Uri parsePairLink(String link) {
    final uri = Uri.tryParse(link.trim());
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        (uri.path != '' && uri.path != '/') ||
        (uri.scheme != 'https' && !(uri.scheme == 'http' && ['localhost', '127.0.0.1', '::1'].contains(uri.host))) ||
        !RegExp(r'^[A-Za-z0-9_-]{32,128}$').hasMatch(uri.fragment)) {
      throw FormatException(t.announcements.invalidLink);
    }
    // Only the exact former official HTTPS origin may carry its pairing to the new host.
    return uri.origin == _previousPanelOrigin ? uri.replace(host: officialPanel.host) : uri;
  }

  Future<Map<String, dynamic>> _request(Uri origin, String key, String path, {Map<String, dynamic>? data}) async {
    final req = http.Request(data == null ? 'GET' : 'PUT', origin.resolve(path))
      ..followRedirects = false
      ..headers['Authorization'] = 'Bearer $key';
    if (data != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(data);
    }
    final reply = await _client.send(req).then(http.Response.fromStream).timeout(const Duration(seconds: 10));
    if (reply.statusCode == 401) throw FormatException(t.announcements.unauthorized);
    if (reply.statusCode < 200 || reply.statusCode >= 300) throw FormatException(t.announcements.unavailable);
    return reply.body.isEmpty ? {} : jsonDecode(utf8.decode(reply.bodyBytes)) as Map<String, dynamic>;
  }

  /// Only an explicitly trusted, still-paired HTTPS origin can receive this
  /// short exchange. Subsequent preference requests use a settings-only ticket.
  Future<String> settingsSession(Uri trustedOrigin, String token, String clientId, String? viewerUuid) async {
    if (trustedOrigin != url || trustedOrigin.scheme != 'https') throw const FormatException();
    final req = http.Request('POST', trustedOrigin.resolve('/api/settings/session'))
      ..followRedirects = false
      ..headers.addAll({
        'Authorization': 'Bearer $_key',
        'X-Plex-Token': token,
        'X-Plex-Client-Identifier': clientId,
        'X-Viewer-UUID': ?viewerUuid,
      });
    final reply = await _client.send(req).then(http.Response.fromStream).timeout(const Duration(seconds: 10));
    if (reply.statusCode != 200) throw const FormatException();
    return (jsonDecode(reply.body) as Map)['session'] as String;
  }

  void _readFeed(Map<String, dynamic> feed) {
    final rows = feed['messages'] as List;
    messages = [
      for (final row in rows) (id: row['id'] as int, title: row['title'] as String, body: row['body'] as String),
    ];
    pushAvailable = feed['push'] == true;
  }

  Future<void> _save() async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setString(
      announcementPairPref,
      jsonEncode({
        'url': _url.toString(),
        'key': _key,
        'installation': _installation,
        'seen': _seen,
        'push': _push,
        'automatic': _automatic,
      }),
    );
  }

  Future<void> pair(String link) => _serial(() async {
    if (_url != null) throw FormatException(t.announcements.alreadyPaired);
    final uri = parsePairLink(link);
    final origin = Uri.parse(uri.origin);
    final random = Random.secure();
    final installation = base64UrlEncode(List.generate(32, (_) => random.nextInt(256)));
    await _connect(origin, uri.fragment, installation, automatic: false);
    _schedule();
  });

  Future<void> _connect(Uri origin, String key, String installation, {required bool automatic}) async {
    final feed = await _request(origin, key, '/api/feed');
    if (_disposed || _disconnectRequested) return;
    _readFeed(feed);
    _url = origin;
    _key = key;
    _installation = installation;
    _automatic = automatic;
    _seen = messages.firstOrNull?.id ?? 0;
    status = null;
    await _save();
    await (await BaseSharedPreferencesService.sharedCache()).setBool(automaticPairingPref, automatic);
    _notify();
  }

  Future<void> _autoPair() async {
    final request = http.Request('POST', officialPanel.resolve('/api/pair'))..followRedirects = false;
    final reply = await _client.send(request).then(http.Response.fromStream).timeout(const Duration(seconds: 10));
    if (reply.statusCode != 201) throw FormatException(t.announcements.unavailable);
    final data = jsonDecode(reply.body);
    if (data case {
      'installation': final String installation,
      'key': final String key,
    } when RegExp(r'^[0-9a-f]{32}$').hasMatch(installation)) {
      parsePairLink('${officialPanel.origin}/#$key');
      if (!_disposed && !_disconnectRequested) await _connect(officialPanel, key, installation, automatic: true);
    } else {
      throw const FormatException();
    }
  }

  Future<void> setAutomaticPairing(bool value) {
    if (!value) return disconnect();
    return _serial(() async {
      if (_url != null && !_automatic) throw FormatException(t.announcements.alreadyPaired);
      _automatic = true;
      await (await BaseSharedPreferencesService.sharedCache()).setBool(automaticPairingPref, true);
      _schedule();
      _notify();
    });
  }

  Future<void> _register(String? token) =>
      _request(_url!, _key, '/api/device', data: {'installation': _installation, 'fid': token});

  Future<void> _bindPush({required bool prompt}) async {
    await _native.prepare(prompt: prompt);
    final first = Completer<String?>();
    final installation = _installation;
    await _tokens?.cancel();
    _tokens = _native.registrations.listen(
      (fid) {
        if (!first.isCompleted) {
          first.complete(fid);
        } else {
          unawaited(
            _serial(() async {
              if (!_push || installation != _installation) return;
              try {
                await _register(fid);
              } catch (_) {
                await _tokens?.cancel();
                _tokens = null;
                status = t.announcements.registrationError;
                _notify();
              }
            }),
          );
        }
      },
      onError: (Object _) {
        if (!first.isCompleted) first.complete(null);
        status = t.announcements.registrationError;
        _notify();
      },
    );
    try {
      await _native.register();
      final fid = await first.future.timeout(const Duration(seconds: 15), onTimeout: () => null);
      if (fid == null) throw FormatException(t.announcements.tokenPending);
      await _register(fid);
      _foreground ??= _native.foregroundMessages.listen((_) => refresh());
    } catch (_) {
      await _tokens?.cancel();
      _tokens = null;
      rethrow;
    }
  }

  Future<void> setPush(bool value) => _serial(() async {
    if (_url == null || !supportsPush) return;
    if (value) {
      if (!pushAvailable) throw FormatException(t.announcements.configurePush);
      try {
        await _retryUnregister();
        if ((await BaseSharedPreferencesService.sharedCache()).containsKey(announcementPendingUnregisterPref)) {
          throw FormatException(t.announcements.unavailable);
        }
        await _bindPush(prompt: true);
      } catch (_) {
        if (!_push) {
          try {
            await _native.stop();
          } catch (_) {
            // An unconfigured build has no native registration to remove.
          }
        }
        rethrow;
      }
    } else {
      await _unregister();
    }
    _push = value;
    status = null;
    await _save();
    _notify();
  });

  Future<void> _unregister() async {
    await _register(null);
    await _stopNativePush();
  }

  Future<void> _stopNativePush() async {
    await _tokens?.cancel();
    await _foreground?.cancel();
    _tokens = null;
    _foreground = null;
    // The panel has already revoked this destination even if the OS is offline.
    try {
      await _native.stop();
    } catch (_) {
      // Registration may already have been invalidated by the device.
    }
  }

  Future<void> disconnect() async {
    _disconnectRequested = true;
    _automatic = false;
    _timer?.cancel();
    _notify();
    // Persist the choice before awaiting a feed request that may be offline.
    try {
      await (await BaseSharedPreferencesService.sharedCache()).setBool(automaticPairingPref, false);
      await _serial(_disconnect);
    } finally {
      _disconnectRequested = false;
      _notify();
    }
  }

  Future<void> _disconnect() async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    if (_push) {
      await prefs.setString(
        announcementPendingUnregisterPref,
        jsonEncode({'url': _url!.origin, 'key': _key, 'installation': _installation}),
      );
    }
    // Removing the pairing must also work offline. The only outstanding
    // request after opt-out is a previously enabled mobile push revocation.
    await prefs.remove(announcementPairPref);
    final hadPush = _push;
    _url = null;
    _installation = _key = '';
    _seen = 0;
    _push = pushAvailable = false;
    status = null;
    messages = const [];
    _timer?.cancel();
    _notify();
    if (hadPush) {
      await _stopNativePush();
      await _retryUnregister();
    }
  }

  Future<void> _retryUnregister() async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final pending = prefs.getString(announcementPendingUnregisterPref);
    if (pending == null) return;
    try {
      final record = jsonDecode(pending) as Map;
      final uri = parsePairLink('${record['url']}/#${record['key']}');
      await _request(
        Uri.parse(uri.origin),
        uri.fragment,
        '/api/device',
        data: {'installation': record['installation'], 'fid': null},
      );
      await prefs.remove(announcementPendingUnregisterPref);
    } catch (_) {
      // Retry at the next launch or resume without reconnecting the device.
    }
  }

  Future<void> refresh() async {
    if (_disconnectRequested || _refreshPending || (_url == null && !_automatic) || !_active || _disposed) return;
    _refreshPending = true;
    try {
      await _serial(() async {
        if (!_active || _disposed) return;
        try {
          if (_url == null) {
            if (_automatic) await _autoPair();
            return;
          }
          final feed = await _request(_url!, _key, '/api/feed');
          if (_disposed || _disconnectRequested) return;
          _readFeed(feed);
          final newest = messages.firstOrNull;
          if (newest != null && newest.id > _seen && _active && !_disposed) {
            _seen = newest.id;
            await _save();
            showMainSnackBar('${newest.title}\n${newest.body}', duration: const Duration(seconds: 7));
          }
          status = null;
          if (_push && pushAvailable && supportsPush && _tokens == null) {
            try {
              await _bindPush(prompt: false);
            } catch (_) {
              status = t.announcements.registrationError;
            }
          }
        } catch (_) {
          status = _url == null ? t.announcements.autoRetry : t.announcements.refreshError;
        }
        _notify();
      });
    } finally {
      _refreshPending = false;
    }
  }

  void _schedule() {
    _timer?.cancel();
    if ((_url == null && !_automatic) || !_active || _disposed) return;
    unawaited(refresh());
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active) unawaited(_serial(_retryUnregister));
    _schedule();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _tokens?.cancel();
    _foreground?.cancel();
    _client.close();
    super.dispose();
  }
}
