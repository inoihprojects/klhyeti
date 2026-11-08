// Repeating events: which dates a rule gives, how a schedule is stored
// and listed, and how leaving out or changing one date syncs.
//
// Dates are local, as in the app; CI runs these in several timezones.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:klhyeti/data/event_repository.dart';
import 'package:klhyeti/models/calendar_event.dart';
import 'package:klhyeti/models/recurrence.dart';
import 'package:klhyeti/sync/sync_payload.dart';
import 'package:klhyeti/sync/sync_reconciler.dart';

List<int> datesOf(Recurrence rule, DateTime start, DateTime from, DateTime to) =>
    [for (final d in rule.datesBetween(start, from, to)) ymd(d)];

Future<EventRepository> newRepo() async {
  final repo = EventRepository();
  await repo.init(dbPath: inMemoryDatabasePath, singleInstance: false);
  return repo;
}

Future<SyncPayload> exportAll(EventRepository repo) async => SyncPayload(
      deviceId: repo.deviceId,
      generatedAt: DateTime.now().toUtc(),
      events: await repo.allEventsForExport(),
    );

const Recurrence everySunday = Recurrence(
  unit: RepeatUnit.week,
  weekdays: {DateTime.sunday},
);

/// "Gym" every Sunday 10:00 to 11:00 from 1 November 2026, a Sunday.
Future<void> addGym(EventRepository repo) => repo.createEvent(
      title: 'Gym',
      startAt: DateTime(2026, 11, 1, 10),
      endAt: DateTime(2026, 11, 1, 11),
      rrule: everySunday.format(),
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('rules', () {
    test('are written the same way every time, and read back', () {
      const rule = Recurrence(
        unit: RepeatUnit.week,
        interval: 2,
        weekdays: {DateTime.thursday, DateTime.monday},
        until: 20271231,
      );
      expect(rule.format(),
          'FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,TH;WKST=MO;UNTIL=20271231');
      expect(Recurrence.parse(rule.format())!.format(), rule.format());
      expect(const Recurrence(unit: RepeatUnit.month).format(),
          'FREQ=MONTHLY;INTERVAL=1');
      expect(Recurrence.parse(null), isNull);
      expect(Recurrence.parse('FREQ=HOURLY;INTERVAL=1'), isNull);
    });

    test('every 3 days', () {
      const rule = Recurrence(unit: RepeatUnit.day, interval: 3);
      expect(
        datesOf(rule, DateTime(2026, 11, 1), DateTime(2026, 11, 10),
            DateTime(2026, 11, 20)),
        [20261110, 20261113, 20261116, 20261119],
      );
    });

    test('every 2 weeks on Monday and Thursday', () {
      const rule = Recurrence(
        unit: RepeatUnit.week,
        interval: 2,
        weekdays: {DateTime.monday, DateTime.thursday},
      );
      expect(
        datesOf(rule, DateTime(2026, 11, 2), DateTime(2026, 11, 1),
            DateTime(2026, 12, 1)),
        [20261102, 20261105, 20261116, 20261119, 20261130],
      );
      // Starting the search partway gives the same dates.
      expect(
        datesOf(rule, DateTime(2026, 11, 2), DateTime(2026, 11, 17),
            DateTime(2026, 11, 20)),
        [20261119],
      );
    });

    test('"every 2 weeks" counts weeks from where its maker\'s week starts',
        () {
      Recurrence rule(bool monday) => Recurrence(
            unit: RepeatUnit.week,
            interval: 2,
            weekdays: const {DateTime.sunday, DateTime.wednesday},
            weekStartsMonday: monday,
          );
      final start = DateTime(2026, 11, 1);
      final end = DateTime(2026, 12, 1);
      expect(datesOf(rule(false), start, start, end),
          [20261101, 20261104, 20261115, 20261118, 20261129]);
      expect(datesOf(rule(true), start, start, end),
          [20261101, 20261111, 20261115, 20261125, 20261129]);
      // And the choice travels with the rule.
      expect(Recurrence.parse(rule(false).format())!.weekStartsMonday, isFalse);
    });

    test('a monthly date some months lack skips those months', () {
      const rule = Recurrence(unit: RepeatUnit.month);
      expect(
        datesOf(rule, DateTime(2026, 1, 31), DateTime(2026, 1, 1),
            DateTime(2027, 1, 1)),
        [20260131, 20260331, 20260531, 20260731, 20260831, 20261031, 20261231],
      );
    });

    test('29 February comes only in leap years', () {
      const rule = Recurrence(unit: RepeatUnit.year);
      expect(
        datesOf(rule, DateTime(2024, 2, 29), DateTime(2024, 1, 1),
            DateTime(2033, 1, 1)),
        [20240229, 20280229, 20320229],
      );
    });

    test('every 2 months, looked up from later on', () {
      const rule = Recurrence(unit: RepeatUnit.month, interval: 2);
      expect(
        datesOf(rule, DateTime(2026, 1, 15), DateTime(2026, 6, 1),
            DateTime(2026, 9, 1)),
        [20260715],
      );
    });

    test('the end date is the last one it can fall on', () {
      final rule = everySunday.copyWith(until: 20261115);
      expect(
        datesOf(rule, DateTime(2026, 11, 1), DateTime(2026, 11, 1),
            DateTime(2026, 12, 1)),
        [20261101, 20261108, 20261115],
      );
    });

    test('nothing before the first date', () {
      const rule = Recurrence(unit: RepeatUnit.day);
      expect(
        datesOf(rule, DateTime(2026, 11, 5), DateTime(2026, 11, 1),
            DateTime(2026, 11, 7)),
        [20261105, 20261106],
      );
    });
  });

  group('schedules', () {
    test('are listed on each of their dates, at the same time', () async {
      final repo = await newRepo();
      await addGym(repo);

      final sunday = await repo.eventsForDay(DateTime(2026, 11, 8));
      expect(sunday, hasLength(1));
      expect(sunday.single.startAt.toLocal(), DateTime(2026, 11, 8, 10));
      expect(sunday.single.occurrenceDay, 20261108);
      expect(await repo.eventsForDay(DateTime(2026, 11, 9)), isEmpty);
      expect(await repo.eventsForDay(DateTime(2026, 10, 25)), isEmpty);
      // One row, however many dates.
      expect(await repo.allEventsForExport(), hasLength(1));
    });

    test('get a dot on each of their dates', () async {
      final repo = await newRepo();
      await addGym(repo);
      final counts = await repo.eventCountsInRange(
          DateTime(2026, 11, 1), DateTime(2026, 12, 1));
      expect(counts.keys.toList()..sort(), [
        DateTime(2026, 11, 1),
        DateTime(2026, 11, 8),
        DateTime(2026, 11, 15),
        DateTime(2026, 11, 22),
        DateTime(2026, 11, 29),
      ]);
    });

    test('lose one date when it is deleted, and keep the rest', () async {
      final repo = await newRepo();
      await addGym(repo);
      final id = (await repo.allEventsForExport()).single.id;

      await repo.skipDate(id, 20261108);

      expect(await repo.eventsForDay(DateTime(2026, 11, 8)), isEmpty);
      expect(await repo.eventsForDay(DateTime(2026, 11, 15)), hasLength(1));
      expect((await repo.getById(id))!.exdates, [20261108]);
    });

    test('can have one date changed on its own', () async {
      final repo = await newRepo();
      await addGym(repo);
      final id = (await repo.allEventsForExport()).single.id;

      await repo.detachDate(
        id,
        20261108,
        title: 'Gym, later',
        startAt: DateTime(2026, 11, 8, 18),
        endAt: DateTime(2026, 11, 8, 19),
        allDay: false,
      );

      final day = await repo.eventsForDay(DateTime(2026, 11, 8));
      expect(day.map((e) => e.title), ['Gym, later']);
      expect(day.single.occurrenceDay, isNull);
      expect((await repo.eventsForDay(DateTime(2026, 11, 15))).single.title,
          'Gym');
    });

    test('that stop repeating forget their skipped dates', () async {
      final repo = await newRepo();
      await addGym(repo);
      final series = (await repo.allEventsForExport()).single;
      await repo.skipDate(series.id, 20261108);

      await repo.updateEvent(
        (await repo.getById(series.id))!,
        title: 'Gym',
        startAt: series.startAt,
        endAt: series.endAt,
        allDay: false,
      );

      final now = (await repo.getById(series.id))!;
      expect(now.rrule, isNull);
      expect(now.exdates, isEmpty);
    });

    test('leave no repeat behind when deleted', () async {
      final repo = await newRepo();
      await addGym(repo);
      final id = (await repo.allEventsForExport()).single.id;
      await repo.softDelete(id);
      final gone = (await repo.getById(id))!;
      expect(gone.deleted, isTrue);
      expect(gone.rrule, isNull);
      expect(await repo.eventsForDay(DateTime(2026, 11, 8)), isEmpty);
    });

    test('sync with their repeat and skipped dates', () async {
      final phone = await newRepo();
      final desk = await newRepo();
      await addGym(phone);
      await reconcile(desk, await exportAll(phone));
      expect(await desk.eventsForDay(DateTime(2026, 11, 15)), hasLength(1));

      // A date skipped on the phone is an edit the desk takes as newer.
      final id = (await phone.allEventsForExport()).single.id;
      await phone.skipDate(id, 20261115);
      final result = await reconcile(desk, await exportAll(phone));
      expect(result.fastForwarded, 1);
      expect(result.conflicts, isEmpty);
      expect(await desk.eventsForDay(DateTime(2026, 11, 15)), isEmpty);
    });

    test('skipping different dates on two devices is a conflict', () async {
      final phone = await newRepo();
      final desk = await newRepo();
      await addGym(phone);
      await reconcile(desk, await exportAll(phone));
      final id = (await phone.allEventsForExport()).single.id;

      await phone.skipDate(id, 20261108);
      await desk.skipDate(id, 20261115);

      final result = await reconcile(desk, await exportAll(phone));
      expect(result.conflicts, hasLength(1));
    });
  });

  group('sync format 2', () {
    test('carries repeats, under a key Klhyeti 1.0 does not read', () async {
      final repo = await newRepo();
      await addGym(repo);
      final id = (await repo.allEventsForExport()).single.id;
      await repo.skipDate(id, 20261108);

      final json = (await exportAll(repo)).toJson();
      expect(json['format'], 2);
      expect(json.containsKey('events'), isFalse);

      final back = SyncPayload.decode((await exportAll(repo)).encode());
      final CalendarEvent event = back.events.single;
      expect(event.rrule, everySunday.format());
      expect(event.exdates, [20261108]);
    });

    test('a file from a newer Klhyeti is refused, not misread', () {
      expect(
        () => SyncPayload.decode(
          '{"format":3,"deviceId":"d1",'
          '"generatedAt":"2026-11-01T00:00:00.000Z","events3":[]}',
        ),
        throwsA(isA<NewerSyncFormat>()),
      );
    });
  });
}
