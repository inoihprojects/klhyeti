/// Repeating events: every N days, weeks, months or years.
///
/// Stored and synced as a small subset of iCalendar's RRULE, always
/// written the same way so that two copies of one event compare equal:
///
///   FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,TH;WKST=MO;UNTIL=20271231
///
/// BYDAY and WKST appear only in weekly rules, UNTIL only when the
/// schedule ends. Dates are calendar dates on the device, like the times
/// the calendar shows.
///
/// A date that doesn't exist (the 31st in a 30-day month, 29 February
/// outside leap years) is skipped, as in iCalendar.
library;

import 'dates.dart';

export 'dates.dart' show fromYmd, ymd;

enum RepeatUnit { day, week, month, year }

class Recurrence {
  final RepeatUnit unit;

  /// Every [interval] units; at least 1.
  final int interval;

  /// Weekly only: the weekdays it falls on, as DateTime.monday to
  /// DateTime.sunday.
  final Set<int> weekdays;

  /// Weekly only: whether weeks count from Monday rather than Sunday.
  /// "Every 2 weeks" depends on where a week begins, so the rule carries
  /// the choice of whoever made it, and every device counts alike.
  final bool weekStartsMonday;

  /// The last day it may fall on, as yyyymmdd; null for never.
  final int? until;

  const Recurrence({
    required this.unit,
    this.interval = 1,
    this.weekdays = const {},
    this.weekStartsMonday = true,
    this.until,
  });

  Recurrence copyWith({
    RepeatUnit? unit,
    int? interval,
    Set<int>? weekdays,
    bool clearUntil = false,
    int? until,
  }) {
    return Recurrence(
      unit: unit ?? this.unit,
      interval: interval ?? this.interval,
      weekdays: weekdays ?? this.weekdays,
      weekStartsMonday: weekStartsMonday,
      until: clearUntil ? null : (until ?? this.until),
    );
  }

  static const Map<RepeatUnit, String> _freq = {
    RepeatUnit.day: 'DAILY',
    RepeatUnit.week: 'WEEKLY',
    RepeatUnit.month: 'MONTHLY',
    RepeatUnit.year: 'YEARLY',
  };

  static const List<String> _days = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

  /// The stored form, the same on every device for the same rule.
  String format() {
    final parts = <String>['FREQ=${_freq[unit]}', 'INTERVAL=$interval'];
    if (unit == RepeatUnit.week) {
      final days = weekdays.toList()..sort();
      parts.add('BYDAY=${days.map((d) => _days[d - 1]).join(',')}');
      parts.add('WKST=${weekStartsMonday ? 'MO' : 'SU'}');
    }
    if (until != null) parts.add('UNTIL=$until');
    return parts.join(';');
  }

  /// Null for no rule, or one this version can't read.
  static Recurrence? parse(String? rule) {
    if (rule == null || rule.isEmpty) return null;
    final fields = <String, String>{};
    for (final part in rule.split(';')) {
      final eq = part.indexOf('=');
      if (eq > 0) fields[part.substring(0, eq)] = part.substring(eq + 1);
    }
    RepeatUnit? unit;
    _freq.forEach((u, name) {
      if (fields['FREQ'] == name) unit = u;
    });
    final interval = int.tryParse(fields['INTERVAL'] ?? '1');
    if (unit == null || interval == null || interval < 1) return null;
    final weekdays = <int>{};
    if (unit == RepeatUnit.week) {
      for (final day in (fields['BYDAY'] ?? '').split(',')) {
        final index = _days.indexOf(day);
        if (index >= 0) weekdays.add(index + 1);
      }
      if (weekdays.isEmpty) return null;
    }
    final untilText = fields['UNTIL'];
    final until = untilText == null ? null : int.tryParse(untilText);
    if (untilText != null && (until == null || untilText.length != 8)) {
      return null;
    }
    return Recurrence(
      unit: unit!,
      interval: interval,
      weekdays: weekdays,
      weekStartsMonday: fields['WKST'] != 'SU',
      until: until,
    );
  }

  /// The days it falls on from [from] up to, not including, [to], for a
  /// schedule starting on [start]. All three are local dates (midnight).
  Iterable<DateTime> datesBetween(
      DateTime start, DateTime from, DateTime to) sync* {
    final DateTime first = from.isBefore(start) ? start : from;
    if (!first.isBefore(to)) return;
    final int? last = until;

    bool fits(DateTime date) =>
        !date.isBefore(first) &&
        date.isBefore(to) &&
        (last == null || ymd(date) <= last);

    switch (unit) {
      case RepeatUnit.day:
        // Jump straight to the first occurrence on or after [first].
        final int gap = daysBetween(start, first);
        var k = (gap + interval - 1) ~/ interval;
        while (true) {
          final date = DateTime(start.year, start.month, start.day + k * interval);
          if (!date.isBefore(to) || (last != null && ymd(date) > last)) return;
          if (fits(date)) yield date;
          k++;
        }
      case RepeatUnit.week:
        final int weekStart = weekStartsMonday ? DateTime.monday : DateTime.sunday;
        int offset(int weekday) => (weekday - weekStart + 7) % 7;
        final DateTime week0 = weekStartOf(start, weekStartsMonday);
        final days = weekdays.toList()
          ..sort((a, b) => offset(a).compareTo(offset(b)));
        var k = (daysBetween(week0, first) ~/ 7) ~/ interval * interval;
        while (true) {
          final weekBegins =
              DateTime(week0.year, week0.month, week0.day + 7 * k);
          if (!weekBegins.isBefore(to)) return;
          if (last != null && ymd(weekBegins) > last) return;
          for (final weekday in days) {
            final date = DateTime(weekBegins.year, weekBegins.month,
                weekBegins.day + offset(weekday));
            if (!date.isBefore(start)) {
              if (fits(date)) yield date;
            }
          }
          k += interval;
        }
      case RepeatUnit.month:
      case RepeatUnit.year:
        final int step = unit == RepeatUnit.month ? interval : 12 * interval;
        final int monthsIn =
            (first.year - start.year) * 12 + first.month - start.month;
        var k = monthsIn <= 0 ? 0 : monthsIn ~/ step;
        while (true) {
          final monthBegins = DateTime(start.year, start.month + k * step);
          if (!monthBegins.isBefore(to)) return;
          if (last != null && ymd(monthBegins) > last) return;
          final date =
              DateTime(monthBegins.year, monthBegins.month, start.day);
          // DateTime rolls 31 April over into May: that month is skipped.
          if (date.month == monthBegins.month && fits(date)) yield date;
          k++;
        }
    }
  }
}
