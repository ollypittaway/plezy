import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../i18n/strings.g.dart';
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

/// An installation pairs to one panel. Only that panel's read key travels to it.
class AnnouncementService extends ChangeNotifier with WidgetsBindingObserver {
  AnnouncementService({http.Client? client, AnnouncementPush? push})
    : _client = client ?? http.Client(),
      _native = push ?? AnnouncementPush();
  final AnnouncementPush _native;
  final http.Client _client;
  Uri? _url;
  String _key = '', _installation = '';
  int _seen = 0;
  bool _push = false, _active = true, _disposed = false, _refreshPending = false;
  bool pushAvailable = false;
  String? status;
  List<Announcement> messages = const [];
  Uri? get url => _url;
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

  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    await _serial(() async {
      final prefs = await BaseSharedPreferencesService.sharedCache();
      try {
        final stored = prefs.getString(announcementPairPref);
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
          _url = Uri.parse(pair.origin);
          _key = pair.fragment;
          _installation = install;
          _seen = seen;
          _push = push;
        } else {
          throw const FormatException();
        }
      } on FormatException {
        status = t.announcements.invalidLink;
      } on TypeError {
        status = t.announcements.invalidLink;
      }
      _notify();
    });
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
    return uri;
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
      jsonEncode({'url': _url.toString(), 'key': _key, 'installation': _installation, 'seen': _seen, 'push': _push}),
    );
  }

  Future<void> pair(String link) => _serial(() async {
    if (_url != null) throw FormatException(t.announcements.alreadyPaired);
    final uri = parsePairLink(link);
    final origin = Uri.parse(uri.origin);
    final feed = await _request(origin, uri.fragment, '/api/feed');
    _readFeed(feed);
    _url = origin;
    _key = uri.fragment;
    final random = Random.secure();
    _installation = base64UrlEncode(List.generate(32, (_) => random.nextInt(256)));
    _seen = messages.firstOrNull?.id ?? 0;
    status = null;
    await _save();
    _schedule();
    _notify();
  });

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

  Future<void> disconnect() => _serial(() async {
    if (_push) await _unregister();
    await (await BaseSharedPreferencesService.sharedCache()).remove(announcementPairPref);
    _url = null;
    _installation = _key = '';
    _seen = 0;
    _push = pushAvailable = false;
    status = null;
    messages = const [];
    _timer?.cancel();
    _notify();
  });

  Future<void> refresh() async {
    if (_refreshPending || _url == null || !_active || _disposed) return;
    _refreshPending = true;
    try {
      await _serial(() async {
        if (_url == null) return;
        try {
          _readFeed(await _request(_url!, _key, '/api/feed'));
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
          status = t.announcements.refreshError;
        }
        _notify();
      });
    } finally {
      _refreshPending = false;
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (_url == null || !_active || _disposed) return;
    unawaited(refresh());
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
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
