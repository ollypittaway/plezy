import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/widgets/splash_logo.dart';

void main() {
  testWidgets('the splash surface shows through around the emblem, wordmark and signature', (tester) async {
    LocaleSettings.setLocaleSync(AppLocale.en);
    const background = Color(0xff305070);
    final key = GlobalKey();
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: const ColoredBox(color: background, child: SplashLogo(size: 160)),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() => precacheImage(const AssetImage('assets/gucciplexa.webp'), key.currentContext!));
    await tester.pumpAndSettle();
    final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage();
      try {
        return await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      } finally {
        image.dispose();
      }
    });
    int color(int x, int y) => bytes!.getUint32((y * 160 + x) * 4);
    expect(color(3, 3), 0x305070ff);
    expect(color(150, 150), 0x305070ff);
    // The three inked regions still contain bright foreground pixels.
    for (final (top, bottom) in [(20, 80), (92, 115), (121, 147)]) {
      expect(
        [
          for (var y = top; y < bottom; y++)
            for (var x = 10; x < 150; x++) color(x, y) >> 24,
        ].any((red) => red > 210),
        isTrue,
      );
    }
  });
}
