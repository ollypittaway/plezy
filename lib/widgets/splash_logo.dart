import 'package:flutter/widgets.dart';

import '../i18n/strings.g.dart';

class SplashLogo extends StatelessWidget {
  const SplashLogo({super.key, required this.size});

  final double size;

  // Both inks have a bright red component. Mask the original near-black
  // backing (RGB 10,10,12), preserving the emblem, wordmark and signature.
  static const _ink = ColorFilter.matrix([
    1, 0, 0, 0, 0, // red
    0, 1, 0, 0, 0, // green
    0, 0, 1, 0, 0, // blue
    1.25, 0, 0, 0, -26, // coverage
  ]);

  @override
  Widget build(BuildContext context) => ColorFiltered(
    colorFilter: _ink,
    child: Image.asset('assets/gucciplexa.webp', semanticLabel: t.app.title, width: size, height: size),
  );
}
