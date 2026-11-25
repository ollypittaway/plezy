import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/models/transcode_quality_preset.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/widgets/startup_playback_check.dart';

import '../test_helpers/prefs.dart';

class _InterruptedWrite extends Fake implements SettingsService {
  _InterruptedWrite(this.settings);
  final SettingsService settings;
  bool interrupt = true;
  final writes = <String>[];

  @override
  T read<T>(Pref<T> pref) => settings.read(pref);

  @override
  Future<void> reset<T>(Pref<T> pref, {void Function()? checkCurrent}) async {
    writes.add(pref.key);
    if (interrupt && pref.key == SettingsService.directPlayCoveredQuality.key) {
      interrupt = false;
      throw StateError('Temporary storage failure');
    }
    await settings.reset(pref, checkCurrent: checkCurrent);
  }
}

void main() {
  late SettingsService settings;
  late StartupPlaybackCheck launch;

  setUp(() async {
    resetSharedPreferencesForTest();
    LocaleSettings.setLocaleSync(AppLocale.en);
    settings = await SettingsService.getInstance();
    launch = StartupPlaybackCheck(settings);
  });

  Future<void> open(WidgetTester tester, {bool mobile = false, bool plex = true}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => launch.run(context, mobile: mobile, hasPlex: plex),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('matching defaults go straight through at startup', (tester) async {
    await open(tester, mobile: true);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('ignoring keeps settings and suppresses the check until the next launch', (tester) async {
    await settings.write(SettingsService.defaultQualityPreset, TranscodeQualityPreset.p720_2mbps);
    await settings.write(SettingsService.directPlayCoveredQuality, false);
    await open(tester);
    expect(find.textContaining('720p 2 Mbps'), findsOneWidget);
    expect(find.text(t.playbackCheck.directPlay), findsOneWidget);
    await tester.tap(find.text(t.playbackCheck.ignore));
    await tester.pumpAndSettle();
    await open(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(settings.read(SettingsService.defaultQualityPreset), TranscodeQualityPreset.p720_2mbps);
    expect(settings.read(SettingsService.directPlayCoveredQuality), isFalse);
    launch = StartupPlaybackCheck(settings);
    await open(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('one click restores the listed settings through their normal listeners', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 700);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await settings.write(SettingsService.defaultQualityPreset, TranscodeQualityPreset.p1080_10mbps);
    await settings.write(SettingsService.cellularQualityPreset, TranscodeQualityPreset.p480_1_5mbps);
    await settings.write(SettingsService.directPlayCoveredQuality, false);
    await settings.write(SettingsService.enableHardwareDecoding, false);
    final quality = settings.listenable(SettingsService.defaultQualityPreset);
    await open(tester, mobile: true);
    expect(find.text(t.playbackCheck.mobileData), findsOneWidget);
    await tester.tap(find.text(t.playbackCheck.fix));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(quality.value, TranscodeQualityPreset.original);
    expect(settings.read(SettingsService.cellularQualityPreset), isNull);
    expect(settings.read(SettingsService.directPlayCoveredQuality), isTrue);
    expect(settings.read(SettingsService.enableHardwareDecoding), isFalse);
    launch = StartupPlaybackCheck(settings);
    await open(tester, mobile: true);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a partial save can retry just the remaining setting', (tester) async {
    await settings.write(SettingsService.defaultQualityPreset, TranscodeQualityPreset.p720_2mbps);
    await settings.write(SettingsService.directPlayCoveredQuality, false);
    final interrupted = _InterruptedWrite(settings);
    launch = StartupPlaybackCheck(interrupted);
    await open(tester);
    await tester.tap(find.text(t.playbackCheck.fix));
    await tester.pumpAndSettle();
    expect(find.text(t.playbackCheck.saveFailed), findsOneWidget);
    expect(find.text(t.settings.defaultQualityTitle), findsNothing);
    expect(settings.read(SettingsService.directPlayCoveredQuality), isFalse);
    await tester.tap(find.text(t.common.retry));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(settings.read(SettingsService.directPlayCoveredQuality), isTrue);
    expect(interrupted.writes, [
      SettingsService.defaultQualityPreset.key,
      SettingsService.directPlayCoveredQuality.key,
      SettingsService.directPlayCoveredQuality.key,
    ]);
  });

  testWidgets('cellular caps and Plex-only settings do not prompt on an unrelated desktop', (tester) async {
    await settings.write(SettingsService.cellularQualityPreset, TranscodeQualityPreset.p720_4mbps);
    await settings.write(SettingsService.directPlayCoveredQuality, false);
    await open(tester, plex: false);
    expect(find.byType(AlertDialog), findsNothing);
    expect(settings.read(SettingsService.directPlayCoveredQuality), isFalse);
    expect(settings.read(SettingsService.cellularQualityPreset), TranscodeQualityPreset.p720_4mbps);
  });

  testWidgets('mobile data warning follows the effective cellular preset', (tester) async {
    await settings.write(SettingsService.defaultQualityPreset, TranscodeQualityPreset.p720_2mbps);
    await open(tester, mobile: true);
    expect(find.text(t.settings.cellularQualityTitle), findsNothing);
    expect(find.text(t.playbackCheck.mobileData), findsOneWidget);
    await tester.tap(find.text(t.playbackCheck.ignore));
    await tester.pumpAndSettle();
    await settings.write(SettingsService.cellularQualityPreset, TranscodeQualityPreset.original);
    launch = StartupPlaybackCheck(settings);
    await open(tester, mobile: true);
    expect(find.text(t.playbackCheck.mobileData), findsNothing);
  });
}
