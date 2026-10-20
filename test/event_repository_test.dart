// Which day an event belongs to must follow the device's own calendar,
// not UTC. In a UTC timezone the two agree, which is how the day list once
// got this wrong unnoticed; CI therefore also runs the tests in a timezone
// far east and one far west of UTC, where a mistake shows.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show inMemoryDatabasePath;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:klhyeti/data/event_repository.dart';

Future<EventRepository> newRepo() async {
  final repo = EventRepository();
  await repo.init(dbPath: inMemoryDatabasePath, singleInstance: false);
  return repo;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('a just-after-midnight event is listed on its own day', () async {
    final repo = await newRepo();
    await repo.createEvent(
      title: 'Night train',
      startAt: DateTime(2026, 10, 5, 0, 30),
      endAt: DateTime(2026, 10, 5, 1, 30),
    );

    expect(await repo.eventsForDay(DateTime(2026, 10, 5)), hasLength(1));
    expect(await repo.eventsForDay(DateTime(2026, 10, 4)), isEmpty);
  });

  test('a late-evening event is listed on its own day', () async {
    final repo = await newRepo();
    await repo.createEvent(
      title: 'Late call',
      startAt: DateTime(2026, 10, 4, 22, 30),
      endAt: DateTime(2026, 10, 4, 23, 30),
    );

    expect(await repo.eventsForDay(DateTime(2026, 10, 4)), hasLength(1));
    expect(await repo.eventsForDay(DateTime(2026, 10, 5)), isEmpty);
  });

  test('the day list and the dots agree on the day', () async {
    final repo = await newRepo();
    await repo.createEvent(
      title: 'Early start',
      startAt: DateTime(2026, 10, 5, 0, 30),
      endAt: DateTime(2026, 10, 5, 1),
    );

    final counts = await repo.eventCountsInRange(
      DateTime(2026, 10, 1),
      DateTime(2026, 11, 1),
    );
    expect(counts, {DateTime(2026, 10, 5): 1});
  });

  test('an event spanning midnight is listed on both days', () async {
    final repo = await newRepo();
    await repo.createEvent(
      title: 'Overnight',
      startAt: DateTime(2026, 10, 4, 23),
      endAt: DateTime(2026, 10, 5, 1),
    );

    expect(await repo.eventsForDay(DateTime(2026, 10, 4)), hasLength(1));
    expect(await repo.eventsForDay(DateTime(2026, 10, 5)), hasLength(1));
    expect(await repo.eventsForDay(DateTime(2026, 10, 6)), isEmpty);
  });
}
