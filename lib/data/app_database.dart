import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

const int _schemaVersion = 8;

const String _createSettingsTable = '''
  CREATE TABLE settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
  )
''';

/// Holiday calendars imported from .ics files, and their days (yyyymmdd).
/// Bundled regions aren't stored here; they are read from the app's assets.
const List<String> _createHolidayTables = [
  '''
  CREATE TABLE holiday_calendars (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    imported_at INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE holiday_days (
    calendar_id INTEGER NOT NULL,
    day INTEGER NOT NULL,
    name TEXT NOT NULL
  )
  ''',
  'CREATE INDEX idx_holiday_days_calendar ON holiday_days (calendar_id)',
];

/// Direct sync: this device's own TLS certificate and key (one row), and
/// the devices it has been paired with. Binary values are stored as
/// base64 text.
const List<String> _createPairingTables = [
  '''
  CREATE TABLE tls_identity (
    id INTEGER PRIMARY KEY,
    cert_pem TEXT NOT NULL,
    key_pem TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE paired_devices (
    device_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    cert TEXT NOT NULL,
    secret TEXT NOT NULL,
    address TEXT
  )
  ''',
];

/// Opens (creating if needed) the app's local SQLite database.
///
/// Schema:
///  - `events`: one row per calendar event, see CalendarEvent.
///  - `device_identity`: a single row holding this device's own stable id.
///  - `settings`: this device's preferences, never synced.
///  - `holiday_calendars`, `holiday_days`: imported .ics holiday calendars.
///  - `tls_identity`, `paired_devices`: see [_createPairingTables].
///
/// The file lives in the app's private data folder (`getApplicationSupport
/// Directory`: AppData on Windows, ~/.local/share on Linux, the app's
/// private storage on Android) — not in the user's Documents folder.
///
/// [path] overrides where the database lives — used by tests to point at
/// an in-memory database ([inMemoryDatabasePath]) instead of a real file.
/// [singleInstance] should stay true for the real app (one shared
/// connection); tests simulating two separate devices against
/// [inMemoryDatabasePath] must pass false, or sqflite's own connection
/// cache will hand back the *same* in-memory database for both "devices".
Future<Database> openAppDatabase({
  String? path,
  String fileName = 'klhyeti.db',
  bool singleInstance = true,
}) async {
  final String dbPath;
  if (path != null) {
    dbPath = path;
  } else {
    final Directory dataDir = await getApplicationSupportDirectory();
    await dataDir.create(recursive: true);
    dbPath = p.join(dataDir.path, fileName);
    await _moveFromOldLocation(fileName, dbPath);
  }

  return openDatabase(
    dbPath,
    version: _schemaVersion,
    singleInstance: singleInstance,
    onCreate: (Database db, int version) async {
      await db.execute('''
        CREATE TABLE events (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          description TEXT,
          location TEXT,
          start_at INTEGER NOT NULL,
          end_at INTEGER NOT NULL,
          all_day INTEGER NOT NULL DEFAULT 0,
          updated_at INTEGER NOT NULL,
          deleted INTEGER NOT NULL DEFAULT 0,
          origin_device_id TEXT NOT NULL,
          rev TEXT,
          history TEXT
        )
      ''');
      await db.execute('''
        CREATE INDEX idx_events_start_at ON events (start_at)
      ''');
      await db.execute('''
        CREATE TABLE device_identity (
          id TEXT PRIMARY KEY
        )
      ''');
      await db.execute(_createSettingsTable);
      for (final sql in _createHolidayTables) {
        await db.execute(sql);
      }
      for (final sql in _createPairingTables) {
        await db.execute(sql);
      }
    },
    onUpgrade: (Database db, int oldVersion, int newVersion) async {
      if (oldVersion < 2) {
        // Version 1 kept a deleted event's title/description/location/times
        // in its tombstone. Wipe them (see CalendarEvent.asTombstone).
        await db.execute('''
          UPDATE events
          SET title = '', description = NULL, location = NULL,
              start_at = 0, end_at = 0, all_day = 0
          WHERE deleted = 1
        ''');
      }
      if (oldVersion < 3) {
        await db.execute(_createSettingsTable);
      }
      if (oldVersion < 4) {
        for (final sql in _createHolidayTables) {
          await db.execute(sql);
        }
      }
      if (oldVersion < 5) {
        for (final sql in _createPairingTables) {
          await db.execute(sql);
        }
      } else if (oldVersion == 5) {
        // Version 5's paired_devices had no address column; a database
        // coming from before 5 has just been given it above.
        await db.execute('ALTER TABLE paired_devices ADD COLUMN address TEXT');
      }
      if (oldVersion < 7) {
        // Revisions (see revision.dart). Rows left without one are read
        // with their legacy revision, which every device works out alike.
        await db.execute('ALTER TABLE events ADD COLUMN rev TEXT');
        await db.execute('ALTER TABLE events ADD COLUMN history TEXT');
      }
      if (oldVersion < 8) {
        // Per-peer sync times, which the reconciler used before revisions
        // replaced them in 0.3. Nothing has read them since.
        await db.execute('DROP TABLE IF EXISTS sync_state');
      }
    },
  );
}

/// Version 0.1.0 kept the database in the user's Documents folder. If a
/// database is still there and none exists at the new location, move it
/// (plus any SQLite side files) so nobody loses their events.
Future<void> _moveFromOldLocation(String fileName, String newPath) async {
  if (await File(newPath).exists()) return;

  final Directory oldDir;
  try {
    oldDir = await getApplicationDocumentsDirectory();
  } catch (_) {
    return;
  }
  final String oldPath = p.join(oldDir.path, fileName);
  if (p.equals(oldPath, newPath)) return;
  if (!await File(oldPath).exists()) return;

  for (final suffix in const ['', '-journal', '-wal', '-shm']) {
    final source = File('$oldPath$suffix');
    if (!await source.exists()) continue;
    final target = '$newPath$suffix';
    try {
      await source.rename(target);
    } on FileSystemException {
      // rename() fails across drives/volumes; fall back to copy + delete.
      await source.copy(target);
      await source.delete();
    }
  }
}
