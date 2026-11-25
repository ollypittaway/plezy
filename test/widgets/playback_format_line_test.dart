import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_part.dart';
import 'package:plezy/media/media_stream.dart';
import 'package:plezy/media/media_version.dart';
import 'package:plezy/mpv/mpv.dart';
import 'package:plezy/widgets/video_controls/widgets/playback_format_line.dart';

import '../test_helpers/player_streams.dart';

class _Player extends Fake implements Player {
  final changes = StreamController<TrackSelection>.broadcast();
  @override
  late final streams = emptyPlayerStreams(track: changes.stream);
  @override
  var state = const PlayerState();
  @override
  bool get providesNativeStats => false;
  final properties = <String, String>{};
  @override
  Future<String?> getProperty(String name) async => properties[name];
  @override
  Future<void> dispose({bool preserveDisplayMode = false}) async => changes.close();
}

void main() {
  const source = MediaVersion(
    id: 'uhd',
    width: 3840,
    height: 1608,
    videoCodec: 'hevc',
    parts: [
      MediaPart(
        id: 'part',
        streams: [MediaStream(id: 'v', kind: MediaStreamKind.video, dolbyVision: true)],
      ),
    ],
  );

  testWidgets('shows direct-play picture format and follows the active audio track', (tester) async {
    final player = _Player();
    addTearDown(player.dispose);
    const atmos = AudioTrack(id: '1', title: 'English Atmos', codec: 'truehd', channels: 8);
    const commentary = AudioTrack(id: '2', title: 'Commentary', codec: 'aac', channels: 2);
    player.state = const PlayerState(
      tracks: Tracks(audio: [atmos, commentary]),
      track: TrackSelection(audio: atmos),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PlaybackFormatLine(player: player, version: source, isTranscoding: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('4K · Dolby Vision · HEVC · Dolby Atmos 7.1'), findsOneWidget);
    player.state = player.state.copyWith(track: const TrackSelection(audio: commentary));
    player.changes.add(player.state.track);
    await tester.pumpAndSettle();
    expect(find.text('4K · Dolby Vision · HEVC · AAC Stereo'), findsOneWidget);
  });

  testWidgets('startup badges appear at middle left, pass taps through and fade once per title', (tester) async {
    final player = _Player();
    addTearDown(player.dispose);
    var taps = 0;
    Widget playback(String id) => MaterialApp(
      home: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => taps++),
            PlaybackFormatLine(
              key: ValueKey(id),
              player: player,
              version: source,
              isTranscoding: false,
              showStartupBadges: true,
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(playback('first'));
    await tester.pump();
    expect(find.text('4K'), findsOneWidget);
    expect(find.text('Dolby Vision'), findsOneWidget);
    final panel = find.byKey(const ValueKey('playback-format-panel'));
    expect(find.descendant(of: panel, matching: find.text('HEVC')), findsOneWidget);
    expect(find.descendant(of: panel, matching: find.text('Dolby Vision')), findsOneWidget);
    final badges = tester.getRect(panel);
    final screen = tester.getRect(find.byType(Scaffold));
    expect(badges.left - screen.left, 24);
    expect(badges.center.dy, closeTo(screen.center.dy, 1));
    await tester.tapAt(tester.getCenter(find.text('Dolby Vision')));
    expect(taps, 1);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(playback('first'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 230));
    await tester.pump();
    expect(find.text('4K'), findsNothing);
    player.changes.add(player.state.track);
    await tester.pump();
    expect(find.text('Dolby Vision'), findsNothing);
    await tester.pumpWidget(playback('next'));
    await tester.pump();
    expect(find.text('Dolby Vision'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('transcodes show the received resolution and codec instead of source formats', (tester) async {
    final player = _Player();
    addTearDown(player.dispose);
    player.properties.addAll({'video-params/w': '1280', 'video-params/h': '720', 'video-format': 'h264'});
    await tester.pumpWidget(
      MaterialApp(
        home: PlaybackFormatLine(player: player, version: source, isTranscoding: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Transcoding · 720p · H.264'), findsOneWidget);
  });
}
