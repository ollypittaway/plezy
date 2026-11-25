import 'dart:async';

import '../media/media_item.dart';
import '../media/media_item_types.dart';
import '../media/media_server_client.dart';
import '../media/media_version.dart';
import '../utils/media_server_http_client.dart';

typedef _Connection = (MediaServerClient, Object, String);
typedef BandwidthWarning = ({double measuredMbps, double fileMbps});

/// One small background transfer when Home first has a playable item.
/// Reuse it for this profile, endpoint and login. On a different server or
/// after the sample ages out, check the actual playback path again.
class PlaybackBandwidth {
  final _samples = <_Connection, ({DateTime at, double? mbps})>{};
  final _pending = <_Connection, Future<double?>>{};
  final _requests = <AbortController>{};
  bool _warmed = false;
  bool _disposed = false;

  void warmUp(Iterable<MediaItem> items, Map<String, MediaServerClient> clients) {
    if (_warmed || _disposed) return;
    for (final item in items) {
      final client = clients[item.serverId];
      if (client == null || client is! PlaybackSpeedClient || !(item.isMovie || item.isEpisode)) continue;
      _warmed = true;
      unawaited(_measure(client, item));
      return;
    }
  }

  Future<BandwidthWarning?> check(MediaServerClient client, MediaItem item, MediaVersion version) async {
    if (!version.is4K || _disposed) return null;
    final bitrate = fileMbps(item, version);
    if (bitrate == null) return null;
    final measured = await _measure(client, item);
    // The file advertises its average. Leave room for variable-bitrate peaks.
    return measured != null && measured < bitrate * 1.25 ? (measuredMbps: measured, fileMbps: bitrate) : null;
  }

  static double? fileMbps(MediaItem item, MediaVersion version) {
    final kbps = version.bitrate;
    if (kbps != null && kbps > 0) return kbps / 1000;
    final duration = item.durationMs;
    if (duration == null || duration <= 0 || version.parts.isEmpty) return null;
    var bytes = 0;
    for (final part in version.parts) {
      final size = part.sizeBytes;
      if (size == null || size <= 0) return null;
      bytes += size;
    }
    return bytes * 8 / (duration * 1000);
  }

  Future<double?> _measure(MediaServerClient client, MediaItem item) {
    final Object source = client;
    if (source is! PlaybackSpeedClient || _disposed) return Future.value();
    final key = (client, client.authenticationSessionId, source.playbackEndpoint);
    final sample = _samples[key];
    final ttl = sample?.mbps == null ? const Duration(seconds: 20) : const Duration(minutes: 5);
    if (sample != null && DateTime.now().difference(sample.at) < ttl) return Future.value(sample.mbps);
    return _pending[key] ??= _run(key, source, item).whenComplete(() {
      _pending.remove(key);
    });
  }

  Future<double?> _run(_Connection key, PlaybackSpeedClient source, MediaItem item) async {
    final request = AbortController();
    _requests.add(request);
    double? value;
    try {
      // Includes any metadata fetch needed to find a file part.
      value = await source.samplePlaybackMbps(item, request).timeout(const Duration(seconds: 6), onTimeout: () => null);
    } catch (_) {
      // An unavailable sample should never prevent playback.
    } finally {
      _requests.remove(request);
      request.abort();
    }
    if (_disposed || !identical(key.$1.authenticationSessionId, key.$2) || source.playbackEndpoint != key.$3) {
      return null;
    }
    _samples[key] = (at: DateTime.now(), mbps: value);
    return value;
  }

  void dispose() {
    _disposed = true;
    for (final request in _requests) {
      request.abort();
    }
    _samples.clear();
  }
}
