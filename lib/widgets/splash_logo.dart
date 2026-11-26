import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../i18n/strings.g.dart';

class OffstageWordmark extends StatelessWidget {
  const OffstageWordmark({super.key, required this.width, required this.color, this.excludeFromSemantics = false});

  final double width;
  final Color color;
  final bool excludeFromSemantics;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/offstage/wordmark.svg',
    width: width,
    height: width * 984 / 3757,
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    excludeFromSemantics: excludeFromSemantics,
    semanticsLabel: excludeFromSemantics ? null : t.app.title,
  );
}

class OffstageMark extends StatelessWidget {
  const OffstageMark({super.key, required this.size, this.onLaunchFinished});

  final double size;
  final VoidCallback? onLaunchFinished;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    // The original fabric is teal (#2DD4BF). Scale the shift by each pixel's
    // green-channel intensity so the folds, highlights and alpha survive.
    final redShift = (accent.r * 255 - 45) / 212;
    final greenScale = accent.g * 255 / 212;
    final blueShift = (accent.b * 255 - 191) / 212;
    final finish = onLaunchFinished;
    return SizedBox.square(
      dimension: size,
      child: ColorFiltered(
        colorFilter: ColorFilter.matrix([
          1, redShift, 0, 0, 0, // red
          0, greenScale, 0, 0, 0, // green
          0, blueShift, 1, 0, 0, // blue
          0, 0, 0, 1, 0, // alpha
        ]),
        child: finish == null ? _restingMark() : _LaunchCurtain(onFinished: finish),
      ),
    );
  }

  static Widget _restingMark() => Image.asset('assets/offstage/mark.webp', excludeFromSemantics: true);
}

class _LaunchCurtain extends StatefulWidget {
  const _LaunchCurtain({required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<_LaunchCurtain> createState() => _LaunchCurtainState();
}

class _LaunchCurtainState extends State<_LaunchCurtain> {
  // The pack's 1.9 s movement sampled at 30 fps, including its resting frame.
  static const lastFrame = 57;
  bool _finished = false;
  late final Timer _timeout;

  @override
  void initState() {
    super.initState();
    // Startup can continue even if the platform decoder stalls.
    _timeout = Timer(const Duration(seconds: 4), _finish);
  }

  void _finish() {
    if (!mounted || _finished) return;
    _finished = true;
    _timeout.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onFinished();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _timeout.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _finish();
      return OffstageMark._restingMark();
    }
    return Image.asset(
      'assets/offstage/launch.webp',
      excludeFromSemantics: true,
      frameBuilder: (_, child, frame, _) {
        if (frame == lastFrame) _finish();
        return child;
      },
      errorBuilder: (_, _, _) {
        _finish();
        return OffstageMark._restingMark();
      },
    );
  }
}

class SplashLogo extends StatelessWidget {
  const SplashLogo({super.key, required this.size, this.onLaunchFinished});

  final double size;
  final VoidCallback? onLaunchFinished;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: t.app.title,
    child: SizedBox.square(
      dimension: size,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          OffstageMark(size: size * 0.62, onLaunchFinished: onLaunchFinished),
          SizedBox(height: size * 0.045),
          OffstageWordmark(
            width: size * 0.60,
            color: Theme.of(context).colorScheme.onSurface,
            excludeFromSemantics: true,
          ),
        ],
      ),
    ),
  );
}
