import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/connection/connection.dart';
import 'package:plezy/connection/connection_registry.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/models/plex/plex_home_user.dart';
import 'package:plezy/profiles/plex_home_service.dart';
import 'package:plezy/profiles/profile.dart';
import 'package:plezy/profiles/profile_connection_registry.dart';
import 'package:plezy/screens/auth_screen.dart';
import 'package:plezy/services/storage_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/splash_logo.dart';

import '../test_helpers/prefs.dart';

void main() {
  setUp(resetSharedPreferencesForTest);

  for (final (size, palette) in [
    (const Size(1280, 720), MonoPalette.dark),
    (const Size(360, 720), MonoPalette.light),
    (const Size(740, 360), MonoPalette.oled),
  ]) {
    testWidgets('the full logo is centered above the sign-in options at ${size.width}×${size.height}', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(theme: monoTheme(palette), home: const AuthScreen(initializeServices: false)),
        ),
      );
      await tester.pump();

      final curtain = tester.getRect(find.byType(OffstageMark));
      final wordmark = tester.getRect(find.byType(OffstageWordmark));
      final signIn = tester.getRect(find.text(t.auth.signInWithPlex));
      expect(curtain.center.dx, closeTo(size.width / 2, 1));
      expect(wordmark.center.dx, closeTo(curtain.center.dx, 1));
      expect(curtain.bottom, lessThan(wordmark.top));
      expect(wordmark.bottom, lessThan(signIn.top));
      expect(tester.widget<OffstageMark>(find.byType(OffstageMark)).onLaunchFinished, isNull);

      final lastOption = find.text(t.auth.connectToMediaBrowser(product: 'Emby'));
      await tester.ensureVisible(lastOption);
      await tester.pumpAndSettle();
      expect(lastOption.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('initial profile is built from the refreshed Plex Home cache', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final connections = ConnectionRegistry(db);
    final profileConnections = ProfileConnectionRegistry(db);
    final storage = await StorageService.getInstance();
    final plexHome = PlexHomeService(
      connections: connections,
      profileConnections: profileConnections,
      storage: storage,
      plexHomeUserFetcher: (_) async => [
        PlexHomeUser(
          id: 1,
          uuid: 'home-user-a',
          title: 'Home User',
          thumb: '',
          hasPassword: false,
          restricted: false,
          updatedAt: null,
          admin: true,
          guest: false,
          protected: false,
        ),
      ],
    );
    addTearDown(() async {
      await plexHome.dispose();
      await db.close();
    });

    final account = PlexAccountConnection(
      id: 'plex-account-a',
      accountToken: 'account-token',
      clientIdentifier: 'client-a',
      accountLabel: 'Plex',
      createdAt: DateTime(2026, 1, 1),
    );
    await connections.upsert(account);
    await plexHome.refresh(account);

    final profile = initialPlexHomeProfileFromCache(plexHome, account);

    expect(profile, isNotNull);
    expect(profile!.id, plexHomeProfileId(accountConnectionId: account.id, homeUserUuid: 'home-user-a'));
    expect(profile.parentConnectionId, account.id);
    expect(profile.displayName, 'Home User');
  });

  test('a PIN-protected single Plex Home user is left for the picker', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final connections = ConnectionRegistry(db);
    final profileConnections = ProfileConnectionRegistry(db);
    final storage = await StorageService.getInstance();
    final plexHome = PlexHomeService(
      connections: connections,
      profileConnections: profileConnections,
      storage: storage,
      plexHomeUserFetcher: (_) async => [
        PlexHomeUser(
          id: 1,
          uuid: 'home-user-a',
          title: 'Home User',
          thumb: '',
          hasPassword: true,
          restricted: false,
          updatedAt: null,
          admin: true,
          guest: false,
          protected: true,
        ),
      ],
    );
    addTearDown(() async {
      await plexHome.dispose();
      await db.close();
    });

    final account = PlexAccountConnection(
      id: 'plex-account-a',
      accountToken: 'account-token',
      clientIdentifier: 'client-a',
      accountLabel: 'Plex',
      createdAt: DateTime(2026, 1, 1),
    );
    await connections.upsert(account);
    await plexHome.refresh(account);

    expect(initialPlexHomeProfileFromCache(plexHome, account), isNull);
    expect(
      shouldPromptForInitialProfileSelection(
        activeProfile: null,
        hasProfiles: false,
        accountHasHomeUsers: plexHome.current[account.id]?.isNotEmpty == true,
        requireProfileSelectionOnOpen: false,
      ),
      isTrue,
    );
  });

  test('initial profile selection is required when home users exist but no profile is active', () {
    expect(
      shouldPromptForInitialProfileSelection(
        activeProfile: null,
        hasProfiles: false,
        accountHasHomeUsers: true,
        requireProfileSelectionOnOpen: false,
      ),
      isTrue,
    );
  });

  test('initial profile selection is skipped when a profile was auto-selected', () {
    final profile = Profile.local(id: 'local-owner', displayName: 'Owner', createdAt: DateTime(2026, 1, 1));

    expect(
      shouldPromptForInitialProfileSelection(
        activeProfile: profile,
        hasProfiles: true,
        accountHasHomeUsers: true,
        requireProfileSelectionOnOpen: false,
      ),
      isFalse,
    );
  });

  test('initial profile selection is required when the launch setting is enabled', () {
    final profile = Profile.local(id: 'local-owner', displayName: 'Owner', createdAt: DateTime(2026, 1, 1));

    expect(
      shouldPromptForInitialProfileSelection(
        activeProfile: profile,
        hasProfiles: true,
        accountHasHomeUsers: true,
        requireProfileSelectionOnOpen: true,
      ),
      isTrue,
    );
  });

  test('initial profile selection is skipped when no profiles are available', () {
    expect(
      shouldPromptForInitialProfileSelection(
        activeProfile: null,
        hasProfiles: false,
        accountHasHomeUsers: false,
        requireProfileSelectionOnOpen: false,
      ),
      isFalse,
    );
  });
}
