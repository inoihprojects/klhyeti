import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// sqflite talks to the platform's native SQLite bindings on Android/iOS
/// out of the box. On Windows/Linux desktop there's no such platform
/// channel, so we swap in sqflite_common_ffi's pure-Dart/FFI implementation
/// instead. Same [databaseFactory] API either way — nothing else in the app
/// needs to know which one is active.
void configureSqfliteForCurrentPlatform() {
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  // Android (and iOS, if this is ever built for it) keep the default
  // sqflite databaseFactory.
}
