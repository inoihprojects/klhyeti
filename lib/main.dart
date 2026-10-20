// Klhyeti — a local-first calendar for Android, Windows and Linux.
// Copyright (C) 2026 InoIH
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version. It is distributed WITHOUT ANY WARRANTY; see
// the GNU General Public License (LICENSE in this repository) for details.

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'data/database_factory_io.dart';
import 'data/event_repository.dart';
import 'data/holiday_repository.dart';
import 'data/peer_repository.dart';
import 'data/settings_repository.dart';
import 'screens/calendar_screen.dart';
import 'sync/sync_service.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureSqfliteForCurrentPlatform();

  final repo = EventRepository();
  await repo.init();

  final settings = SettingsRepository(repo.database);
  await settings.load();

  final holidays = HolidayRepository(repo.database);
  await holidays.load();

  final sync = SyncService(
    repo: repo,
    settings: settings,
    peers: PeerRepository(repo.database),
  );
  await sync.start();

  runApp(KlhyetiApp(
    repo: repo,
    settings: settings,
    holidays: holidays,
    sync: sync,
  ));
}

class KlhyetiApp extends StatefulWidget {
  final EventRepository repo;
  final SettingsRepository settings;
  final HolidayRepository holidays;
  final SyncService sync;

  const KlhyetiApp({
    super.key,
    required this.repo,
    required this.settings,
    required this.holidays,
    required this.sync,
  });

  @override
  State<KlhyetiApp> createState() => _KlhyetiAppState();
}

class _KlhyetiAppState extends State<KlhyetiApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// On Android a backgrounded app stops listening for syncs, and picks
  /// up again when it comes back. Desktop apps keep listening while
  /// minimised: they are still open.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!Platform.isAndroid) return;
    if (state == AppLifecycleState.resumed) {
      widget.sync.setActive(true);
    } else if (state == AppLifecycleState.paused) {
      widget.sync.setActive(false);
    }
  }

  static final GlobalKey<NavigatorState> _navigator =
      GlobalKey<NavigatorState>();

  /// The mouse's back (thumb) button goes back a screen, as in a browser.
  /// The forward button is left alone: there is no forward history here.
  static void _handleMouseButtons(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse) return;
    if ((event.buttons & kBackMouseButton) != 0) {
      _navigator.currentState?.maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds the app when a setting changes, for the theme. Screens that
    // draw settings or holidays listen to those themselves.
    final settings = widget.settings;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        title: 'Klhyeti',
        debugShowCheckedModeBanner: false,
        theme: buildKlhyetiTheme(Brightness.light),
        darkTheme: buildKlhyetiTheme(Brightness.dark),
        themeMode: settings.themeMode,
        themeAnimationDuration: Motion.theme,
        themeAnimationCurve: Curves.easeInOut,
        navigatorKey: _navigator,
        // Above the navigator, so the back button works on every screen
        // and closes dialogs too.
        builder: (context, child) => Listener(
          onPointerDown: _handleMouseButtons,
          child: child,
        ),
        home: CalendarScreen(
          repo: widget.repo,
          settings: settings,
          holidays: widget.holidays,
          sync: widget.sync,
        ),
      ),
    );
  }
}
