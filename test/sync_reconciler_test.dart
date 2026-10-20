// The reconciler, against independent in-memory databases standing in
// for devices, talking through the same SyncPayload the sync file and
// direct sync use. Runs as a plain `flutter test`: no device needed.
//
// Event times are local, as they are in the app: CI runs these tests in
// several timezones, and a UTC time can fall on a different local day.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show inMemoryDatabasePath;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:klhyeti/data/event_repository.dart';
import 'package:klhyeti/models/calendar_event.dart';
import 'package:klhyeti/models/revision.dart';
import 'package:klhyeti/sync/sync_payload.dart';
import 'package:klhyeti/sync/sync_reconciler.dart';

Future<EventRepository> newDeviceRepo() async {
  final repo = EventRepository();
  // singleInstance: false is required here: sqflite caches connections by
  // path, and every simulated "device" in this test opens the same
  // ':memory:' path string, so without this they'd all share one database.
  await repo.init(dbPath: inMemoryDatabasePath, singleInstance: false);
  return repo;
}

Future<SyncPayload> exportAll(EventRepository repo, {String? name}) async {
  return SyncPayload(
    deviceId: repo.deviceId,
    deviceName: name,
    generatedAt: DateTime.now().toUtc(),
    events: await repo.allEventsForExport(),
  );
}

final DateTime day = DateTime(2026, 10, 3);

Future<CalendarEvent> only(EventRepository repo) async =>
    (await repo.eventsForDay(day)).single;

Future<void> retitle(EventRepository repo, String title) async {
  final event = await only(repo);
  await repo.updateEvent(
    event,
    title: title,
    startAt: event.startAt,
    endAt: event.endAt,
    allDay: false,
  );
}

/// [first] creates one event and every device in [others] gets it.
Future<void> share(EventRepository first, List<EventRepository> others) async {
  await first.createEvent(
    title: 'Team lunch',
    startAt: DateTime(2026, 10, 3, 12),
    endAt: DateTime(2026, 10, 3, 13),
  );
  for (final other in others) {
    await reconcile(other, await exportAll(first));
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('a brand new event propagates to a peer with no conflict', () async {
    final phone = await newDeviceRepo();
    final desktop = await newDeviceRepo();

    await phone.createEvent(
      title: 'Dentist',
      startAt: DateTime(2026, 10, 1, 9),
      endAt: DateTime(2026, 10, 1, 10),
    );

    final result = await reconcile(desktop, await exportAll(phone));

    expect(result.inserted, 1);
    expect(result.conflicts, isEmpty);
    final events = await desktop.eventsForDay(DateTime(2026, 10, 1));
    expect(events.single.title, 'Dentist');
  });

  test('only one side editing fast-forwards with no conflict', () async {
    final phone = await newDeviceRepo();
    final desktop = await newDeviceRepo();
    await share(phone, [desktop]);

    await retitle(phone, 'Team lunch (moved)');
    final result = await reconcile(desktop, await exportAll(phone));

    expect(result.fastForwarded, 1);
    expect(result.conflicts, isEmpty);
    expect((await only(desktop)).title, 'Team lunch (moved)');
  });

  test('both sides editing is a real conflict, and settling ends it',
      () async {
    final phone = await newDeviceRepo();
    final desktop = await newDeviceRepo();
    await share(phone, [desktop]);

    await retitle(phone, 'Team lunch (phone edit)');
    await retitle(desktop, 'Team lunch (desktop edit)');

    final result = await reconcile(desktop, await exportAll(phone));
    expect(result.conflicts, hasLength(1));
    final conflict = result.conflicts.single;
    expect(conflict.local.title, 'Team lunch (desktop edit)');
    expect(conflict.incoming.title, 'Team lunch (phone edit)');

    // The desktop's user keeps the desktop's version...
    await desktop.resolveConflict(
        keep: conflict.local, other: conflict.incoming);
    expect((await only(desktop)).title, 'Team lunch (desktop edit)');

    // ...and the phone takes it as newer, without asking again.
    final back = await reconcile(phone, await exportAll(desktop));
    expect(back.conflicts, isEmpty);
    expect(back.fastForwarded, 1);
    expect((await only(phone)).title, 'Team lunch (desktop edit)');
  });

  test('an unsettled conflict comes back, and nothing is overwritten',
      () async {
    final phone = await newDeviceRepo();
    final desktop = await newDeviceRepo();
    await share(phone, [desktop]);
    await retitle(phone, 'Review (phone edit)');
    await retitle(desktop, 'Review (desktop edit)');

    for (var i = 0; i < 2; i++) {
      final result = await reconcile(desktop, await exportAll(phone));
      expect(result.conflicts, hasLength(1));
      expect((await only(desktop)).title, 'Review (desktop edit)');
    }
  });

  test('a peer\'s stale copy never replaces a newer local edit', () async {
    final phone = await newDeviceRepo();
    final desktop = await newDeviceRepo();
    await share(phone, [desktop]);

    // Only the desktop edits, and the phone is never sent the edit.
    await retitle(desktop, 'Plan (desktop edit)');

    // The phone exports its old copy twice.
    for (var i = 0; i < 2; i++) {
      final result = await reconcile(desktop, await exportAll(phone));
      expect(result.conflicts, isEmpty);
      expect(result.fastForwarded, 0);
    }
    expect((await only(desktop)).title, 'Plan (desktop edit)');
  });

  test('what counts as newer does not depend on any clock', () async {
    final phone = await newDeviceRepo();
    final desktop = await newDeviceRepo();
    await share(phone, [desktop]);
    final shared = await only(desktop);

    // An edit made on top of the shared version, by a device whose clock
    // is a day slow...
    final slowClock = shared.copyWith(
      title: 'Edited on a slow clock',
      updatedAt: shared.updatedAt.subtract(const Duration(days: 1)),
      originDeviceId: 'slow',
      rev: newRevision(),
      history: shared.historyForNextEdit(),
    );
    final result = await reconcile(
      desktop,
      SyncPayload(
        deviceId: 'slow',
        generatedAt: DateTime.now().toUtc(),
        events: [slowClock],
      ),
    );
    // ...is still newer.
    expect(result.conflicts, isEmpty);
    expect(result.fastForwarded, 1);
    expect((await only(desktop)).title, 'Edited on a slow clock');

    // And an independent edit from a device whose clock is a day fast is
    // still a conflict, not a quiet win.
    final fastClock = shared.copyWith(
      title: 'Edited on a fast clock',
      updatedAt: shared.updatedAt.add(const Duration(days: 1)),
      originDeviceId: 'fast',
      rev: newRevision(),
      history: shared.historyForNextEdit(),
    );
    final second = await reconcile(
      desktop,
      SyncPayload(
        deviceId: 'fast',
        generatedAt: DateTime.now().toUtc(),
        events: [fastClock],
      ),
    );
    expect(second.conflicts, hasLength(1));
  });

  test('three devices: an edit made on top of another is not a conflict',
      () async {
    final phone = await newDeviceRepo();
    final pc = await newDeviceRepo();
    final laptop = await newDeviceRepo();
    await share(phone, [pc, laptop]);

    // The phone edits and both others get it.
    await retitle(phone, 'Lunch (phone)');
    await reconcile(pc, await exportAll(phone));
    await reconcile(laptop, await exportAll(phone));

    // The PC edits on top of the phone's version and syncs with the
    // laptop, which still holds the phone's version.
    await retitle(pc, 'Lunch (PC, after the phone)');
    final result = await reconcile(laptop, await exportAll(pc));

    expect(result.conflicts, isEmpty);
    expect(result.fastForwarded, 1);
    expect((await only(laptop)).title, 'Lunch (PC, after the phone)');

    // The phone, two steps behind, catches up without a conflict too.
    final behind = await reconcile(phone, await exportAll(laptop));
    expect(behind.conflicts, isEmpty);
    expect((await only(phone)).title, 'Lunch (PC, after the phone)');
  });

  test('three devices: a conflict settled on one is settled for all',
      () async {
    final phone = await newDeviceRepo();
    final pc = await newDeviceRepo();
    final laptop = await newDeviceRepo();
    await share(phone, [pc, laptop]);

    await retitle(phone, 'Lunch (phone)');
    await reconcile(laptop, await exportAll(phone));
    await retitle(pc, 'Lunch (PC)');

    // The PC meets the phone's edit, a real conflict, and keeps its own.
    final result = await reconcile(pc, await exportAll(phone));
    final conflict = result.conflicts.single;
    await pc.resolveConflict(keep: conflict.local, other: conflict.incoming);

    // The laptop holds the phone's version: it takes the settled one as
    // newer, without asking a second person to settle it again.
    final onLaptop = await reconcile(laptop, await exportAll(pc));
    expect(onLaptop.conflicts, isEmpty);
    expect((await only(laptop)).title, 'Lunch (PC)');
    final onPhone = await reconcile(phone, await exportAll(pc));
    expect(onPhone.conflicts, isEmpty);
    expect((await only(phone)).title, 'Lunch (PC)');
  });

  test('the same edit made on two devices is not a conflict', () async {
    final phone = await newDeviceRepo();
    final pc = await newDeviceRepo();
    await share(phone, [pc]);
    await retitle(phone, 'Lunch at one');
    await retitle(pc, 'Lunch at one');

    final result = await reconcile(pc, await exportAll(phone));
    expect(result.conflicts, isEmpty);
    await reconcile(phone, await exportAll(pc));

    // Once both have synced, they agree on one revision, so a later edit
    // on either is simply newer.
    expect((await only(phone)).rev, (await only(pc)).rev);
    await retitle(phone, 'Lunch at two');
    final later = await reconcile(pc, await exportAll(phone));
    expect(later.conflicts, isEmpty);
    expect((await only(pc)).title, 'Lunch at two');
  });

  test('events from before revisions sync between devices alike',
      () async {
    final a = await newDeviceRepo();
    final b = await newDeviceRepo();
    // The same old version on both, as sync files from 0.2 leave it.
    final old = CalendarEvent(
      id: 'old-event',
      title: 'From 0.2',
      startAt: DateTime(2026, 10, 3, 9),
      endAt: DateTime(2026, 10, 3, 10),
      updatedAt: DateTime.utc(2026, 9, 1),
      originDeviceId: 'someone',
    );
    await a.applyIncoming(old);
    await b.applyIncoming(old);

    // A sync file from an older version has no revisions in it at all.
    final legacyJson = old.toJson()
      ..remove('rev')
      ..remove('history');
    final payload = SyncPayload.decode(SyncPayload(
      deviceId: 'old-build',
      generatedAt: DateTime.now().toUtc(),
      events: [CalendarEvent.fromJson(legacyJson)],
    ).encode());

    final result = await reconcile(b, payload);
    expect(result.conflicts, isEmpty);
    expect(result.unchanged, 1);

    // And an edit made on the new version is newer than the old one.
    await retitle(a, 'Edited since');
    final edited = await reconcile(b, await exportAll(a));
    expect(edited.fastForwarded, 1);
  });

  test('the device with the latest conflicting edit counts as newest', () {
    CalendarEvent edited(String id, String device, int minute) {
      return CalendarEvent(
        id: id,
        title: id,
        startAt: DateTime(2026, 10, 5, 9),
        endAt: DateTime(2026, 10, 5, 10),
        updatedAt: DateTime.utc(2026, 10, 1, 12, minute),
        originDeviceId: device,
      );
    }

    final conflicts = [
      SyncConflict(
        local: edited('a', 'here', 30),
        incoming: edited('a', 'there', 10),
      ),
      SyncConflict(
        local: edited('b', 'here', 5),
        incoming: edited('b', 'there', 20),
      ),
    ];

    // Judged across all conflicts, not one by one: 30 beats 20.
    expect(localIsNewest(conflicts), isTrue);
    expect(localIsNewest([conflicts[1]]), isFalse);
    // A tie stays with this device.
    expect(
      localIsNewest([
        SyncConflict(
          local: edited('c', 'here', 7),
          incoming: edited('c', 'there', 7),
        ),
      ]),
      isTrue,
    );
  });

  test('the sender\'s device name travels in the payload', () {
    final payload = SyncPayload(
      deviceId: 'd1',
      deviceName: 'Desk',
      generatedAt: DateTime.utc(2026, 10, 5),
      events: const [],
    );
    expect(SyncPayload.decode(payload.encode()).deviceName, 'Desk');
    // Files from before 0.3 have no name; they must still load.
    expect(
      SyncPayload.decode(
        '{"deviceId":"d1","generatedAt":"2026-10-05T00:00:00.000Z",'
        '"events":[]}',
      ).deviceName,
      isNull,
    );
  });

  test('a deletion propagates as a tombstone, not a silent revival',
      () async {
    final phone = await newDeviceRepo();
    final desktop = await newDeviceRepo();

    await phone.createEvent(
      title: 'Cancelled trip',
      startAt: DateTime(2026, 11, 1, 8),
      endAt: DateTime(2026, 11, 3, 20),
      allDay: true,
    );
    await reconcile(desktop, await exportAll(phone));
    expect(await desktop.eventsForDay(DateTime(2026, 11, 1)), hasLength(1));

    final created =
        (await phone.eventsForDay(DateTime(2026, 11, 1))).single;
    await phone.softDelete(created.id);

    final result = await reconcile(desktop, await exportAll(phone));
    expect(result.conflicts, isEmpty);

    expect(await desktop.eventsForDay(DateTime(2026, 11, 1)), isEmpty);
    final tombstone = await desktop.getById(created.id);
    expect(tombstone, isNotNull);
    expect(tombstone!.deleted, isTrue);

    // Deleting must actually remove what the event said, on both sides.
    for (final repo in [phone, desktop]) {
      final t = (await repo.getById(created.id))!;
      expect(t.title, isEmpty);
      expect(t.description, isNull);
      expect(t.location, isNull);
    }
    final exported = await exportAll(phone);
    expect(exported.encode(), isNot(contains('Cancelled trip')));
  });

  test('an incoming tombstone that still carries content is scrubbed',
      () async {
    final desktop = await newDeviceRepo();
    final leaky = CalendarEvent(
      id: 'old-peer-event',
      title: 'Secret meeting',
      description: 'should not survive',
      location: 'somewhere',
      startAt: DateTime(2026, 12, 1, 9),
      endAt: DateTime(2026, 12, 1, 10),
      updatedAt: DateTime.now().toUtc(),
      deleted: true,
      originDeviceId: 'old-peer',
    );

    await reconcile(
      desktop,
      SyncPayload(
        deviceId: 'old-peer',
        generatedAt: DateTime.now().toUtc(),
        events: [leaky],
      ),
    );

    final stored = (await desktop.getById('old-peer-event'))!;
    expect(stored.deleted, isTrue);
    expect(stored.title, isEmpty);
    expect(stored.description, isNull);
    expect(stored.location, isNull);
  });
}
