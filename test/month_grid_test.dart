// The month grid is drawn from plain date arithmetic, so it's worth
// pinning down: off-by-one here means every date in the app is wrong.

import 'package:flutter_test/flutter_test.dart';
import 'package:klhyeti/widgets/month_grid.dart';

void main() {
  test('a month starting on Sunday has no leading days (Sunday start)', () {
    // 1 February 2026 is a Sunday.
    expect(monthGridDays(DateTime(2026, 2), false).first, DateTime(2026, 2, 1));
    expect(monthGridDays(DateTime(2026, 2), true).first, DateTime(2026, 1, 26));
  });

  test('September 2026 starts on a Tuesday', () {
    expect(DateTime(2026, 9, 1).weekday, DateTime.tuesday);
    expect(monthGridDays(DateTime(2026, 9), false).first, DateTime(2026, 8, 30));
    expect(monthGridDays(DateTime(2026, 9), true).first, DateTime(2026, 8, 31));
  });

  test('the grid is always 42 days and starts on the right weekday', () {
    for (int month = 1; month <= 12; month++) {
      for (final mondayStart in [true, false]) {
        final days = monthGridDays(DateTime(2026, month), mondayStart);
        expect(days, hasLength(42));
        expect(
          days.first.weekday,
          mondayStart ? DateTime.monday : DateTime.sunday,
          reason: 'month $month, mondayStart=$mondayStart',
        );
        // Consecutive days, including across month and year boundaries.
        // Compared by components, so a daylight-saving jump (23- or
        // 25-hour days) can't make this flaky.
        for (int i = 1; i < days.length; i++) {
          final previous = days[i - 1];
          expect(
            days[i],
            DateTime(previous.year, previous.month, previous.day + 1),
          );
        }
      }
    }
  });

  test('January grids reach back into the previous year', () {
    final days = monthGridDays(DateTime(2027, 1), false);
    expect(days.first.year, 2026);
    expect(days.first.month, 12);
    expect(days.where((d) => d.month == 1 && d.year == 2027), hasLength(31));
  });

  test('weekday headers follow the week-start setting', () {
    expect(weekdayHeaders(false).first, 'SUN');
    expect(weekdayHeaders(false).last, 'SAT');
    expect(weekdayHeaders(true).first, 'MON');
    expect(weekdayHeaders(true).last, 'SUN');
    expect(weekdayHeaders(true), hasLength(7));
  });

  test('isSameDay ignores the time of day', () {
    expect(isSameDay(DateTime(2026, 9, 23, 8), DateTime(2026, 9, 23, 22)),
        isTrue);
    expect(isSameDay(DateTime(2026, 9, 23), DateTime(2026, 9, 24)), isFalse);
  });

  test('weekStartOf finds the Sunday or Monday on or before a day', () {
    // Wednesday 23 September 2026.
    final wednesday = DateTime(2026, 9, 23);
    expect(weekStartOf(wednesday, false), DateTime(2026, 9, 20));
    expect(weekStartOf(wednesday, true), DateTime(2026, 9, 21));
    // A week start is its own week start.
    expect(weekStartOf(DateTime(2026, 9, 20), false), DateTime(2026, 9, 20));
    expect(weekStartOf(DateTime(2026, 9, 21), true), DateTime(2026, 9, 21));
    // Across a year boundary: Friday 1 January 2027.
    expect(weekStartOf(DateTime(2027, 1, 1), false), DateTime(2026, 12, 27));
    expect(weekStartOf(DateTime(2027, 1, 1), true), DateTime(2026, 12, 28));
  });

  test('daysBetween counts calendar days, ignoring the time of day', () {
    expect(daysBetween(DateTime(2026, 9, 23), DateTime(2026, 9, 23)), 0);
    expect(daysBetween(DateTime(2026, 9, 23, 23), DateTime(2026, 9, 24, 1)),
        1);
    expect(daysBetween(DateTime(2026, 9, 24), DateTime(2026, 9, 23)), -1);
    expect(daysBetween(DateTime(2026, 1, 1), DateTime(2027, 1, 1)), 365);
    expect(daysBetween(DateTime(2028, 1, 1), DateTime(2029, 1, 1)), 366);
    // A whole year of local days, whatever daylight saving does to hours.
    for (int d = 0; d < 366; d++) {
      expect(daysBetween(DateTime(2026, 1, 1), DateTime(2026, 1, 1 + d)), d);
    }
  });
}
