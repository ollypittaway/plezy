import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../utils/device_channel.dart';
import 'package:auto_updater/auto_updater.dart';
import 'package:plezy/utils/app_logger.dart';
import 'package:plezy/utils/app_version.dart';
import 'package:plezy/utils/media_server_http_client.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'base_shared_preferences_service.dart';

/// Service to check for new versions on GitHub
/// Only enabled when ENABLE_UPDATE_CHECK build flag is set
///
/// On macOS (non-Homebrew) and installed Windows: delegates to Sparkle/WinSparkle
/// via auto_updater for native update dialogs and in-app installs.
/// On all other platforms: falls back to GitHub API check + browser link dialog.
class UpdateService {
  static const String _githubRepo = 'ollypittaway/plezy';
  static const bool _firestickBuild = bool.fromEnvironment('GUCCIPLEXA_FIRESTICK');
  static const String _firestickAsset = 'GucciPlexa-Firestick.apk';
  static bool get supportsApkUpdates => Platform.isAndroid && _firestickBuild;

  static const String _keySkippedVersion = 'update_skipped_version';
  static const String _keyLastCheckTime = 'update_last_check_time';

  // Check cooldown: 6 hours
  static const Duration _checkCooldown = Duration(hours: 6);

  static bool _nativeUpdaterInitialized = false;

  /// Check if update checking is enabled via build flag
  static bool get isUpdateCheckEnabled {
    return const bool.fromEnvironment('ENABLE_UPDATE_CHECK', defaultValue: false);
  }

  /// Whether any in-app update path applies to this install.
  /// False inside a packaged (MSIX/Store) install: the Store owns updates and
  /// the package directory is read-only, so neither WinSparkle nor the GitHub
  /// fallback dialog has anything it can do. Gates the settings entry too, so
  /// no dead affordance ships.
  static bool get isUpdateCheckAvailable => isUpdateCheckEnabled && !PlatformDetector.isPackagedInstall();

  /// Whether the native auto_updater (Sparkle/WinSparkle) should be used.
  /// True on macOS (non-Homebrew) and installed Windows (has uninstaller).
  static bool get useNativeUpdater {
    // GucciPlexa does not publish a Sparkle/WinSparkle appcast. Never use
    // upstream Plezy's native update feed.
    return false;
  }

  /// Initialize the native auto_updater (Sparkle/WinSparkle).
  /// Call once at startup if [useNativeUpdater] is true.
  static Future<void> initNativeUpdater() async {
    if (_nativeUpdaterInitialized) return;

    try {
      if (!useNativeUpdater) return;
      _nativeUpdaterInitialized = true;
    } catch (error, stackTrace) {
      appLogger.e('Failed to initialize native auto updater', error: error, stackTrace: stackTrace);
    }
  }

  /// Trigger a background update check via Sparkle/WinSparkle.
  /// Only shows UI if an update is found.
  static Future<void> checkForUpdatesNative({bool inBackground = true}) async {
    if (!_nativeUpdaterInitialized) {
      await initNativeUpdater();
      if (!_nativeUpdaterInitialized) return;
    }
    try {
      await autoUpdater.checkForUpdates(inBackground: inBackground);
    } catch (error, stackTrace) {
      appLogger.e('Native update check failed', error: error, stackTrace: stackTrace);
    }
  }

  static Future<void> skipVersion(String version) async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setString(_keySkippedVersion, version);
  }

  static Future<String?> getSkippedVersion() async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    return prefs.getString(_keySkippedVersion);
  }

  /// Check if cooldown period has passed since last check
  static Future<bool> shouldCheckForUpdates() async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final lastCheckString = prefs.getString(_keyLastCheckTime);
    if (lastCheckString == null) return true;

    final now = DateTime.now();
    final lastCheck = DateTime.tryParse(lastCheckString);
    if (lastCheck == null || lastCheck.isAfter(now)) {
      await prefs.remove(_keyLastCheckTime);
      return true;
    }

    return now.difference(lastCheck) >= _checkCooldown;
  }

  static Future<void> _updateLastCheckTime() async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setString(_keyLastCheckTime, DateTime.now().toIso8601String());
  }

  /// Internal method that performs the actual update check
  /// [respectCooldown] - if true, checks cooldown and records the attempt before the request
  /// [throwOnFailure] - if true, a failed check (network, non-200, bad payload)
  /// is rethrown instead of reading as "no update"
  static Future<Map<String, dynamic>?> _performUpdateCheck({
    required bool respectCooldown,
    MediaServerHttpClient? client,
    bool forceEnabled = false,
    bool throwOnFailure = false,
  }) async {
    if (!forceEnabled && !isUpdateCheckAvailable) {
      return null;
    }

    // Check cooldown if requested
    if (respectCooldown && !supportsApkUpdates && !await shouldCheckForUpdates()) {
      return null;
    }

    try {
      // Without the running version there is nothing to compare a release to.
      final currentVersion = (await AppVersion.current()).version;
      if (currentVersion == null) throw StateError('App version unknown');

      if (respectCooldown) {
        await _updateLastCheckTime();
      }

      final response = await (client ?? httpClient).get(
        'https://api.github.com/repos/$_githubRepo/releases/latest',
        headers: {'Accept': 'application/vnd.github+json'},
      );

      if (response.statusCode != 200) {
        throw StateError('Release check returned HTTP ${response.statusCode}');
      }
      final data = response.data;
      final latestVersion = data['tag_name'] as String;

      // Remove 'v' prefix if present
      final cleanVersion = latestVersion.startsWith('v') ? latestVersion.substring(1) : latestVersion;

      final hasUpdate = _isNewerVersion(cleanVersion, currentVersion);

      if (hasUpdate) {
        final apk = supportsApkUpdates ? firestickAssetForRelease(data, cleanVersion) : null;
        // A release may be public before the Fire Stick package has arrived.
        if (supportsApkUpdates && apk == null) return null;
        // Check if this version was skipped
        final skippedVersion = await getSkippedVersion();
        if (skippedVersion == cleanVersion) {
          return null;
        }

        return {
          'hasUpdate': true,
          if (apk != null) 'apkUrl': apk['url'],
          if (apk != null) 'apkSha256': apk['sha256'],
          'currentVersion': currentVersion,
          'latestVersion': cleanVersion,
          'releaseUrl': data['html_url'] as String,
          'releaseName': data['name'] as String? ?? 'Version $cleanVersion',
          'releaseNotes': data['body'] as String? ?? '',
          'publishedAt': data['published_at'] as String,
        };
      }
    } catch (error, stackTrace) {
      appLogger.e('Failed to check for updates', error: error, stackTrace: stackTrace);
      if (throwOnFailure) rethrow;
    }

    return null;
  }

  /// Accept only the expected signed asset and GitHub-provided SHA-256 digest.
  @visibleForTesting
  static Map<String, String>? firestickAssetForRelease(dynamic data, String version) {
    if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version) || data is! Map) return null;
    final assets = data['assets'];
    if (assets is! List) return null;
    final expected = 'https://github.com/$_githubRepo/releases/download/v$version/$_firestickAsset';
    for (final asset in assets) {
      if (asset is! Map || asset['name'] != _firestickAsset || asset['browser_download_url'] != expected) continue;
      final digest = asset['digest'];
      if (digest is String && RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(digest)) {
        return {'url': expected, 'sha256': digest.substring(7)};
      }
    }
    return null;
  }

  static bool _installing = false;

  static Future<bool> installApkUpdate(Map<String, dynamic> info) async {
    if (!supportsApkUpdates || _installing) return false;
    final version = info['latestVersion'];
    final digest = info['apkSha256'];
    if (version is! String || !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version) ||
        digest is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest) ||
        info['apkUrl'] != 'https://github.com/$_githubRepo/releases/download/v$version/$_firestickAsset') {
      throw StateError('Invalid update metadata');
    }
    _installing = true;
    final client = http.Client();
    File? file;
    try {
      final allowed = await deviceChannel.invokeMethod<bool>('canInstallGucciPlexaUpdate') ?? false;
      if (!allowed) {
        await deviceChannel.invokeMethod<void>('openGucciPlexaInstallSettings');
        return false;
      }
      final cache = await getTemporaryDirectory();
      final directory = await Directory(cache.path + '/gucciplexa-update').create(recursive: true);
      final target = File(directory.path + '/update.apk');
      file = target;
      final response = await client.send(http.Request('GET', Uri.parse(info['apkUrl'] as String)))
          .timeout(const Duration(seconds: 45));
      if (response.statusCode != 200) throw StateError('Download failed: HTTP ' + response.statusCode.toString());
      const maxBytes = 500 * 1024 * 1024;
      if ((response.contentLength ?? 0) > maxBytes) throw StateError('Update is too large');
      final sink = target.openWrite();
      var bytes = 0;
      try {
        await for (final chunk in response.stream.timeout(const Duration(seconds: 45))) {
          bytes += chunk.length;
          if (bytes > maxBytes) throw StateError('Update is too large');
          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }
      if (bytes == 0 || (response.contentLength != null && bytes != response.contentLength)) {
        throw StateError('Incomplete update download');
      }
      final actual = await sha256.bind(target.openRead()).first;
      if (actual.toString() != digest) throw StateError('Update checksum mismatch');
      await deviceChannel.invokeMethod<void>('installGucciPlexaUpdate', {'path': target.path});
      return true;
    } catch (_) {
      if (file != null && await file.exists()) await file.delete();
      rethrow;
    } finally {
      client.close();
      _installing = false;
    }
  }

  @visibleForTesting
  static Future<Map<String, dynamic>?> debugPerformUpdateCheck({
    required bool respectCooldown,
    required MediaServerHttpClient client,
    bool throwOnFailure = false,
  }) {
    return _performUpdateCheck(
      respectCooldown: respectCooldown,
      client: client,
      forceEnabled: true,
      throwOnFailure: throwOnFailure,
    );
  }

  /// Check for updates on GitHub (manual check, ignores cooldown)
  /// Returns a map with update info, or null when there is no update (or the
  /// release is skipped). Throws when the check itself fails, so the caller
  /// can say so instead of reporting the latest version.
  static Future<Map<String, dynamic>?> checkForUpdates() {
    return _performUpdateCheck(respectCooldown: false, throwOnFailure: true);
  }

  /// Check for updates on startup (respects cooldown and skipped versions)
  /// Returns update info if available, null otherwise
  static Future<Map<String, dynamic>?> checkForUpdatesOnStartup() {
    return _performUpdateCheck(respectCooldown: true);
  }

  /// Parse version string into list of integers
  /// Handles versions like "1.2.3+4" by taking only the numeric parts
  static List<int> _parseVersionParts(String version) {
    return version.split('.').map((p) {
      final numPart = p.split('+').first.split('-').first;
      return int.tryParse(numPart) ?? 0;
    }).toList();
  }

  /// Compare two version strings
  /// Returns true if newVersion is newer than currentVersion
  static bool _isNewerVersion(String newVersion, String currentVersion) {
    try {
      final newParts = _parseVersionParts(newVersion);
      final currentParts = _parseVersionParts(currentVersion);

      // Compare each part
      final maxLength = newParts.length > currentParts.length ? newParts.length : currentParts.length;

      for (int i = 0; i < maxLength; i++) {
        final newPart = i < newParts.length ? newParts[i] : 0;
        final currentPart = i < currentParts.length ? currentParts[i] : 0;

        if (newPart > currentPart) return true;
        if (newPart < currentPart) return false;
      }

      return false;
    } catch (error, stackTrace) {
      appLogger.e('Error comparing versions', error: error, stackTrace: stackTrace);
      return false;
    }
  }
}
