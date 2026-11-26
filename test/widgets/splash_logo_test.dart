import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/widgets/splash_logo.dart';

void main() {
  testWidgets('curtain follows the viewer accent and preserves the transparent opening and shaded folds', (
    tester,
  ) async {
    const size = 128;
    final key = GlobalKey();
    Future<ByteData> render(Color accent) async {
      await tester.pumpWidget(
        Theme(
          data: ThemeData(colorScheme: ColorScheme.dark(primary: accent)),
          child: Center(
            child: RepaintBoundary(key: key, child: const OffstageMark(size: 128)),
          ),
        ),
      );
      await tester.runAsync(() => precacheImage(const AssetImage('assets/offstage/mark.webp'), key.currentContext!));
      await tester.pumpAndSettle();
      final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      return (await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        } finally {
          image.dispose();
        }
      }))!;
    }

    final teal = await render(const Color(0xff2dd4bf));
    final rose = await render(const Color(0xffff99b6));
    final shades = <int>{};
    var tinted = 0;
    for (var i = 0; i < size * size * 4; i += 4) {
      expect(rose.getUint8(i + 3), teal.getUint8(i + 3));
      if (teal.getUint8(i + 3) == 255 && teal.getUint8(i + 1) > 45) {
        if (rose.getUint8(i) > teal.getUint8(i) && rose.getUint8(i + 1) < teal.getUint8(i + 1)) tinted++;
        shades.add(rose.getUint8(i));
      }
    }
    expect(tinted, greaterThan(3000));
    expect(shades.length, greaterThan(50));
    expect(rose.getUint8((64 * size + 64) * 4 + 3), 0);
    expect(rose.getUint8(3), 0);
    // The sides extend into the corners of the approved rounded square.
    expect(rose.getUint8((15 * size + 16) * 4 + 3), 255);
  });

  testWidgets('the packaged curtain plays once with the approved 1.9-second opening', (tester) async {
    final bytes = await rootBundle.load('assets/offstage/launch.webp');
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
      try {
        expect(codec.repetitionCount, 0);
        expect(codec.frameCount, 58);
        var opening = Duration.zero;
        for (var i = 1; i < codec.frameCount; i++) {
          final frame = await codec.getNextFrame();
          opening += frame.duration;
          frame.image.dispose();
        }
        expect(opening, const Duration(milliseconds: 1900));
        final rest = await codec.getNextFrame();
        final pixels = (await rest.image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        final side = rest.image.width;
        int alpha(int x, int y) => pixels.getUint8((y * side + x) * 4 + 3);
        expect(alpha(side ~/ 8, side ~/ 8), 255);
        expect(alpha(side ~/ 2, side ~/ 2), 0);
        rest.image.dispose();
      } finally {
        codec.dispose();
      }
    });
  });

  testWidgets('reduced motion shows the resting curtain and releases startup immediately', (tester) async {
    var finished = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: OffstageMark(size: 80, onLaunchFinished: () => finished++),
        ),
      ),
    );
    expect(finished, 1);
    expect((tester.widget<Image>(find.byType(Image)).image as AssetImage).assetName, 'assets/offstage/mark.webp');
    await tester.pump(const Duration(seconds: 5));
    expect(finished, 1);
  });
}
