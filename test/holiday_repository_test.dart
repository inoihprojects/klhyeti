// Holidays are opt-in, come from the bundled tables and imported .ics
// files, and switching either redraws from the merged lookup. Runs against
// the real bundled assets and an in-memory database.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show inMemoryDatabasePath;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:klhyeti/data/app_database.dart';
import 'package:klhyeti/data/holiday_repository.dart';

Future<HolidayRepository> newRepo() async {
  final db =
      await openAppDatabase(path: inMemoryDatabasePath, singleInstance: false);
  final repo = HolidayRepository(db);
  await repo.load();
  return repo;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('nothing is a holiday until a region is switched on', () async {
    final repo = await newRepo();
    expect(repo.enabledRegions, isEmpty);
    expect(repo.namesOn(DateTime(2026, 12, 25)), isEmpty);
  });

  test('a region adds its holidays, and removing it takes them away',
      () async {
    final repo = await newRepo();
    await repo.setRegionEnabled('us', true);
    expect(repo.namesOn(DateTime(2026, 7, 4)), ['Independence Day']);
    expect(repo.namesOn(DateTime(2026, 7, 3)),
        ['Independence Day (observed)']);
    expect(repo.namesOn(DateTime(2026, 7, 5)), isEmpty);

    await repo.setRegionEnabled('us', false);
    expect(repo.namesOn(DateTime(2026, 7, 4)), isEmpty);
  });

  test('lunar holidays land on their dates', () async {
    final repo = await newRepo();
    await repo.setRegionEnabled('kr', true);
    await repo.setRegionEnabled('cn', true);
    // Chuseok and the Mid-Autumn Festival: 15th of the 8th lunar month.
    expect(repo.namesOn(DateTime(2026, 9, 25)),
        containsAll(['Chuseok', 'Mid-Autumn Festival']));
    // Korea's new year falls a day after China's in 2027: the new moon
    // is just after midnight in Korea and just before it in China.
    expect(repo.namesOn(DateTime(2027, 2, 6)), contains('Spring Festival'));
    expect(repo.namesOn(DateTime(2027, 2, 7)), contains('Seollal'));
  });

  test('the choice of regions is remembered', () async {
    final db = await openAppDatabase(
        path: inMemoryDatabasePath, singleInstance: false);
    final first = HolidayRepository(db);
    await first.load();
    await first.setRegionEnabled('jp', true);

    final second = HolidayRepository(db);
    await second.load();
    expect(second.enabledRegions, {'jp'});
    expect(second.namesOn(DateTime(2026, 9, 22)), ["Citizens' Holiday"]);
  });

  test('an imported calendar adds its days and can be removed', () async {
    final repo = await newRepo();
    final count = await repo.importIcs(
      'my-days',
      'BEGIN:VCALENDAR\r\n'
          'BEGIN:VEVENT\r\n'
          'DTSTART;VALUE=DATE:20261102\r\n'
          'SUMMARY:Local festival\r\n'
          'END:VEVENT\r\n'
          'END:VCALENDAR\r\n',
    );
    expect(count, 1);
    expect(repo.imported.single.name, 'my-days');
    expect(repo.imported.single.dayCount, 1);
    expect(repo.namesOn(DateTime(2026, 11, 2)), ['Local festival']);

    await repo.removeImported(repo.imported.single.id);
    expect(repo.imported, isEmpty);
    expect(repo.namesOn(DateTime(2026, 11, 2)), isEmpty);
  });

  test('a file with no dates imports nothing', () async {
    final repo = await newRepo();
    expect(await repo.importIcs('empty', 'BEGIN:VCALENDAR\r\nEND:VCALENDAR'),
        0);
    expect(repo.imported, isEmpty);
  });
}
