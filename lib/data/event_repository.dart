import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/calendar_event.dart';
import '../models/revision.dart';
import 'app_database.dart';

/// Owns the local SQLite database and is the single place the rest of the
/// app (UI + sync) reads and writes events through.
///
/// Notifies its listeners whenever events change, by an edit here or by a
/// sync, so the calendar can redraw even while a sync runs in the
/// background. [edits] counts only the edits made on this device: that
/// is what automatic sync waits for, and a sync's own writes must not set
/// off another sync.
class EventRepository extends ChangeNotifier {
  final ValueNotifier<int> edits = ValueNotifier<int>(0);

  Database? _db;
  String? _deviceId;

  /// This device's own stable id, generated once on first run and reused
  /// forever after. Call [init] before reading this.
  String get deviceId {
    final id = _deviceId;
    if (id == null) {
      throw StateError('EventRepository.init() has not completed yet.');
    }
    return id;
  }

  /// [dbPath] and [singleInstance] are for tests — see
  /// [openAppDatabase]'s doc comment. The real app just calls `init()`.
  Future<void> init({String? dbPath, bool singleInstance = true}) async {
    final db = await openAppDatabase(
      path: dbPath,
      singleInstance: singleInstance,
    );
    _db = db;
    _deviceId = await _loadOrCreateDeviceId(db);
  }

  /// The open database, so other repositories (settings) can share it.
  Database get database => _database;

  Database get _database {
    final db = _db;
    if (db == null) {
      throw StateError('EventRepository.init() has not completed yet.');
    }
    return db;
  }

  Future<String> _loadOrCreateDeviceId(Database db) async {
    final rows = await db.query('device_identity', limit: 1);
    if (rows.isNotEmpty) {
      return rows.first['id']! as String;
    }
    final id = newUuid();
    await db.insert('device_identity', {'id': id});
    return id;
  }

  // --- Reads used by the calendar UI ---------------------------------

  /// Events overlapping the local calendar day of [day]; its time of day is
  /// ignored. The bounds are this device's own midnights: UTC midnights
  /// would shift the day by the timezone offset, putting early-morning
  /// events on the previous day's list (east of UTC) or late-evening ones
  /// on the next (west of it), while their dots stayed on the right day.
  Future<List<CalendarEvent>> eventsForDay(DateTime day) async {
    final DateTime start = DateTime(day.year, day.month, day.day);
    // Component arithmetic, not Duration: a daylight-saving day can be 23
    // or 25 hours long.
    final DateTime end = DateTime(day.year, day.month, day.day + 1);
    final rows = await _database.query(
      'events',
      where: 'deleted = 0 AND start_at < ? AND end_at > ?',
      whereArgs: [
        end.toUtc().millisecondsSinceEpoch,
        start.toUtc().millisecondsSinceEpoch,
      ],
      orderBy: 'start_at ASC',
    );
    return rows.map(CalendarEvent.fromDbMap).toList();
  }

  /// How many events start on each local day in [rangeStart, rangeEnd).
  /// Keys are local midnight, so they can be compared to a calendar cell.
  Future<Map<DateTime, int>> eventCountsInRange(
      DateTime rangeStart, DateTime rangeEnd) async {
    final rows = await _database.query(
      'events',
      columns: ['start_at'],
      where: 'deleted = 0 AND start_at >= ? AND start_at < ?',
      whereArgs: [
        rangeStart.toUtc().millisecondsSinceEpoch,
        rangeEnd.toUtc().millisecondsSinceEpoch,
      ],
    );
    final counts = <DateTime, int>{};
    for (final row in rows) {
      final dt = DateTime.fromMillisecondsSinceEpoch(row['start_at']! as int,
              isUtc: true)
          .toLocal();
      final day = DateTime(dt.year, dt.month, dt.day);
      counts[day] = (counts[day] ?? 0) + 1;
    }
    return counts;
  }

  Future<CalendarEvent?> getById(String id) async {
    final rows = await _database.query('events', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return CalendarEvent.fromDbMap(rows.first);
  }

  // --- Writes from the UI ---------------------------------------------

  Future<void> createEvent({
    required String title,
    String? description,
    String? location,
    required DateTime startAt,
    required DateTime endAt,
    bool allDay = false,
  }) async {
    final event = CalendarEvent(
      id: newUuid(),
      title: title,
      description: description,
      location: location,
      startAt: startAt,
      endAt: endAt,
      allDay: allDay,
      updatedAt: DateTime.now().toUtc(),
      originDeviceId: deviceId,
      rev: newRevision(),
    );
    await _database.insert('events', event.toDbMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    _edited();
  }

  void _edited() {
    edits.value++;
    notifyListeners();
  }

  /// For the sync layer, once a sync has written events: one redraw for
  /// the lot rather than one per event.
  void markSynced() => notifyListeners();

  /// Rebuilds the row from scratch rather than using [CalendarEvent.copyWith]
  /// so that clearing a field (e.g. deleting the description) actually
  /// clears it instead of being ignored as "no change" — copyWith can't
  /// tell "leave this alone" apart from "set this to null".
  Future<void> updateEvent(
    CalendarEvent existing, {
    required String title,
    String? description,
    String? location,
    required DateTime startAt,
    required DateTime endAt,
    required bool allDay,
  }) async {
    final updated = CalendarEvent(
      id: existing.id,
      title: title,
      description: description,
      location: location,
      startAt: startAt,
      endAt: endAt,
      allDay: allDay,
      updatedAt: DateTime.now().toUtc(),
      deleted: false,
      originDeviceId: deviceId,
      rev: newRevision(),
      history: existing.historyForNextEdit(),
    );
    await _database.insert('events', updated.toDbMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    _edited();
  }

  /// Soft-delete: keeps the row as a tombstone so the deletion can be
  /// synced to the other device instead of silently reappearing there.
  Future<void> softDelete(String id) async {
    final existing = await getById(id);
    if (existing == null) return;
    final tombstoned = existing.asTombstone(
      updatedAt: DateTime.now().toUtc(),
      originDeviceId: deviceId,
      rev: newRevision(),
      history: existing.historyForNextEdit(),
    );
    await _database.insert('events', tombstoned.toDbMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    _edited();
  }

  // --- Used by the sync layer -------------------------------------------

  /// Everything, tombstones included — see ARCHITECTURE.md for why file
  /// sync just exports the full dataset instead of an incremental delta.
  Future<List<CalendarEvent>> allEventsForExport() async {
    final rows = await _database.query('events');
    return rows.map(CalendarEvent.fromDbMap).toList();
  }

  /// Writes an event exactly as given, revision and all — used when a sync
  /// takes another device's version. Doesn't notify: the sync does that
  /// once at the end ([markSynced]).
  Future<void> applyIncoming(CalendarEvent event) async {
    // A peer running an older version may still send tombstones with their
    // old content attached; never store that.
    final toStore = event.deleted ? event.asTombstone() : event;
    await _database.insert('events', toStore.toDbMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Settles a conflict: [keep]'s content, as a new revision made on top
  /// of both [keep] and [other], so that whichever of the two a device
  /// holds, it takes this one as newer and doesn't ask again.
  Future<void> resolveConflict({
    required CalendarEvent keep,
    required CalendarEvent other,
  }) async {
    final settled = keep.copyWith(
      updatedAt: DateTime.now().toUtc(),
      originDeviceId: deviceId,
      rev: newRevision(),
      history: mergeHistories([
        [keep.rev, other.rev],
        keep.history,
        other.history,
      ]),
    );
    await applyIncoming(settled);
    _edited();
  }

  /// Two devices made the same edit independently, so the content agrees
  /// but the revisions don't. Both devices settle on the same one of the
  /// two (the lower id, a choice each makes alike without asking the
  /// other) with the other in its history. Once they have synced both
  /// ways they hold the same revision again, and later edits on either
  /// are recognised as newer. Not an edit: nothing anyone can see changes.
  Future<void> absorb(CalendarEvent local, CalendarEvent incoming) async {
    final bool keepLocal = local.rev.compareTo(incoming.rev) < 0;
    final winner = keepLocal ? local : incoming;
    final loser = keepLocal ? incoming : local;
    await applyIncoming(winner.copyWith(
      history: mergeHistories([
        winner.history,
        [loser.rev],
        loser.history,
      ]),
    ));
  }
}
