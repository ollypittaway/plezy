import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_part.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/media/media_version.dart';
import 'package:plezy/services/playback_bandwidth.dart';
import 'package:plezy/utils/media_server_http_client.dart';

import '../test_helpers/media_items.dart';

class _SpeedClient extends Fake implements MediaServerClient, PlaybackSpeedClient {
  @override
  String playbackEndpoint = 'https://first.example';
  @override
  final authenticationSessionId = Object();
  var samples = 0;
  var result = Completer<double?>();

  @override
  Future<double?> samplePlaybackMbps(MediaItem item, AbortController abort) {
    samples++;
    return result.future;
  }
}

void main() {
  final item = testMediaItem(serverId: 'server', durationMs: 10000);
  const uhd = MediaVersion(id: 'original', videoResolution: '4k', bitrate: 40000);

  test('startup and playback share a pending measurement, and a changed endpoint gets its own sample', () async {
    final client = _SpeedClient();
    final bandwidth = PlaybackBandwidth();
    addTearDown(bandwidth.dispose);
    bandwidth.warmUp([item], {'server': client});
    final warning = bandwidth.check(client, item, uhd);
    expect(client.samples, 1);
    client.result.complete(49);
    expect(await warning, (measuredMbps: 49.0, fileMbps: 40.0));
    expect(await bandwidth.check(client, item, uhd), (measuredMbps: 49.0, fileMbps: 40.0));
    expect(client.samples, 1);
    client.playbackEndpoint = 'https://second.example';
    client.result = Completer<double?>()..complete(50);
    expect(await bandwidth.check(client, item, uhd), isNull);
    expect(client.samples, 2);
  });

  test('HD and unknown bitrates skip the probe, and unavailable speed permits playback', () async {
    final client = _SpeedClient();
    final bandwidth = PlaybackBandwidth();
    addTearDown(bandwidth.dispose);
    const hd = MediaVersion(id: 'hd', height: 1080, bitrate: 40000);
    const unknown = MediaVersion(id: 'unknown', height: 2160);
    expect(await bandwidth.check(client, item, hd), isNull);
    expect(await bandwidth.check(client, item, unknown), isNull);
    expect(client.samples, 0);
    client.result.complete(null);
    expect(await bandwidth.check(client, item, uhd), isNull);
    expect(client.samples, 1);
  });

  test('file size and duration estimate the bitrate only when every part has a known size', () {
    const part = MediaPart(id: 'p', sizeBytes: 25000000);
    const sized = MediaVersion(id: 'two', height: 2160, parts: [part, part]);
    const incomplete = MediaVersion(
      id: 'two',
      height: 2160,
      parts: [
        part,
        MediaPart(id: 'missing'),
      ],
    );
    expect(PlaybackBandwidth.fileMbps(item, sized), 40.0);
    expect(PlaybackBandwidth.fileMbps(item, incomplete), isNull);
  });
}
