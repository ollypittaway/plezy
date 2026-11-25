import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../i18n/strings.g.dart';
import '../../../media/media_display_criteria.dart';
import '../../../media/media_source_info.dart';
import '../../../media/media_version.dart';
import '../../../mpv/mpv.dart';
import '../../../services/track_selection_service.dart';
import '../../../utils/codec_utils.dart';
import '../../../utils/formatters.dart';
import '../../../utils/media_quality_labels.dart';
import '../../../utils/resolution_label.dart';

typedef _VideoFormat = ({int? width, int? height, String? codec, String? transfer, int? dolbyVisionProfile});

/// One snapshot of the opened video, plus the player's live audio selection.
/// Source HDR tags describe the direct-play file. A transcode has its own
/// picture format, which must come from the player instead.
class PlaybackFormatLine extends StatefulWidget {
  final Player player;
  final MediaVersion? version;
  final MediaSourceInfo? source;
  final bool isTranscoding;
  final bool showStartupBadges;

  const PlaybackFormatLine({
    super.key,
    required this.player,
    this.version,
    this.source,
    required this.isTranscoding,
    this.showStartupBadges = false,
  });

  @override
  State<PlaybackFormatLine> createState() => _PlaybackFormatLineState();
}

class _PlaybackFormatLineState extends State<PlaybackFormatLine> {
  Timer? _hideTimer;
  bool _fading = false;
  bool _finished = false;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  late final _openedVideo = _readVideo(widget.player);

  Future<_VideoFormat?> _readVideo(Player player) async {
    try {
      if (player.providesNativeStats) {
        final stats = await player.getStats();
        int? number(String key, String fallback) => int.tryParse('${stats[key] ?? stats[fallback]}');
        return (
          width: number('videoWidth', 'video-params/w'),
          height: number('videoHeight', 'video-params/h'),
          codec: (stats['videoCodec'] ?? stats['videoMimeType'] ?? stats['video-codec']) as String?,
          transfer: stats['video-params/gamma'] as String?,
          dolbyVisionProfile: (stats['dvSourceProfile'] as num?)?.toInt(),
        );
      }
      final values = await Future.wait([
        for (final key in ['video-params/w', 'video-params/h', 'video-format', 'video-params/gamma'])
          player.getProperty(key),
      ]);
      return (
        width: int.tryParse(values[0] ?? ''),
        height: int.tryParse(values[1] ?? ''),
        codec: values[2],
        transfer: values[3],
        dolbyVisionProfile: null,
      );
    } catch (_) {
      return null;
    }
  }

  List<String> _picture(_VideoFormat? opened) {
    final version = widget.isTranscoding ? null : widget.version;
    final criteria = widget.isTranscoding ? null : widget.source?.displayCriteria;
    final video = version == null ? null : videoStreamForPart(version, partIndex: widget.source?.partIndex);
    final width = opened?.width ?? criteria?.width;
    final height = opened?.height ?? criteria?.height;
    final dimensions = resolutionLabelFromDimensions(
      (width ?? 0) > 0 ? width : null,
      (height ?? 0) > 0 ? height : null,
    );
    final resolution = dimensions != null
        ? resolutionDisplayLabel(dimensions)
        : version == null
        ? null
        : formatVersionResolution(version);
    final codec = CodecUtils.formatPlayerVideoCodec(opened?.codec ?? video?.codec ?? version?.videoCodec);
    final dolbyVision =
        video?.dolbyVision == true ||
        (criteria?.doviProfile ?? 0) > 0 ||
        (opened?.dolbyVisionProfile ?? 0) > 0 ||
        codec == 'Dolby Vision';
    final color = classifyMediaDisplayColor(transfer: opened?.transfer ?? criteria?.transfer);
    final range = dolbyVision
        ? 'Dolby Vision'
        : video?.displayTitle?.toUpperCase().contains('HDR10+') == true
        ? 'HDR10+'
        : color == MediaDisplayColorType.hlg
        ? 'HLG'
        : video?.hdr == true || color.isHdr || criteria?.isHdr == true
        ? 'HDR'
        : null;
    return [if (widget.isTranscoding) t.fileInfo.transcoding, ?resolution, ?range, if (codec != range) ?codec];
  }

  String? _audio() {
    final state = widget.player.state;
    final selected = state.track.audio;
    if (selected == null || selected.id == 'no' || selected.id == 'auto') return null;
    final track = state.tracks.audio.where((row) => row.id == selected.id).firstOrNull ?? selected;
    final source = widget.isTranscoding
        ? null
        : playingSourceAudioTrack(
            selectedMpvTrack: track,
            mpvTracks: state.tracks.audio,
            sourceTracks: widget.source?.audioTracks ?? const [],
          );
    final codec = track.codec ?? source?.codec;
    final label = codec == null || codec.isEmpty
        ? null
        : CodecUtils.formatAudioCodec(codec, profile: track.codecProfile);
    final atmos = [
      track.title,
      track.codecProfile,
      codec,
      source?.title,
      source?.displayTitle,
    ].nonNulls.any((hint) => hint.toLowerCase().contains('atmos') || hint.toLowerCase().contains('eac3-joc'));
    final channels = CodecUtils.formatAudioChannels(track.channels ?? source?.channels);
    final parts = [if (atmos) 'Dolby Atmos' else ?label, ?channels];
    return parts.isEmpty ? null : parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return const SizedBox.shrink();
    return FutureBuilder<_VideoFormat?>(
      future: _openedVideo,
      builder: (_, snapshot) => StreamBuilder<TrackSelection>(
        stream: widget.player.streams.track,
        builder: (_, _) => StreamBuilder<Tracks>(
          stream: widget.player.streams.tracks,
          builder: (_, _) {
            final audio = _audio();
            final labels = [..._picture(snapshot.data), ?audio];
            if (labels.isEmpty) return const SizedBox.shrink();
            if (widget.showStartupBadges) return _startupBadges(labels, audio);
            return Text(
              toBulletedString(labels),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
            );
          },
        ),
      ),
    );
  }

  Widget _startupBadges(List<String> labels, String? audio) {
    // Start the clock only once a format is known. Audio and decoder updates
    // may fill in more badges while the notification is on screen.
    _hideTimer ??= Timer(const Duration(seconds: 4), () => setState(() => _fading = true));
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: AnimatedOpacity(
              opacity: _fading ? 0 : 1,
              duration: const Duration(milliseconds: 220),
              onEnd: () {
                if (_fading) setState(() => _finished = true);
              },
              child: Semantics(
                container: true,
                liveRegion: true,
                excludeSemantics: true,
                label: toBulletedString(labels),
                child: Wrap(
                  direction: Axis.vertical,
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    for (final label in labels)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xDC141617),
                          border: Border.all(color: Colors.white38),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (label == audio || label == 'Dolby Vision') ...[
                                Icon(
                                  label == audio ? Symbols.surround_sound_rounded : Symbols.contrast_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                              ],
                              Flexible(
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
