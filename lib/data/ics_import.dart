/// Reads the days out of an iCalendar (.ics) file, for importing a
/// holiday calendar someone publishes as .ics.
///
/// Only what a holiday calendar needs: each event's date (or dates, for
/// one spanning several days), its name, and yearly repetition, including
/// "the n-th weekday of a month" rules such as a third Monday. Times of
/// day are dropped. Anything else in the file is ignored.
library;

/// A day from an .ics file: [day] as yyyymmdd, and the event's name.
class IcsDay {
  final int day;
  final String name;

  const IcsDay(this.day, this.name);

  @override
  bool operator ==(Object other) =>
      other is IcsDay && other.day == day && other.name == name;

  @override
  int get hashCode => Object.hash(day, name);

  @override
  String toString() => 'IcsDay($day, $name)';
}

/// The result of reading a file: its own name for itself, if it gives
/// one, and the days found.
class IcsCalendar {
  final String? name;
  final List<IcsDay> days;

  const IcsCalendar(this.name, this.days);
}

/// Repeating events are expanded up to [lastYear]; a single event spanning
/// more than [maxSpanDays] days is cut short, so a malformed file can't
/// produce an absurd number of rows.
IcsCalendar parseIcs(
  String source, {
  int lastYear = 2099,
  int maxSpanDays = 31,
}) {
  final lines = _unfold(source);
  String? calendarName;
  final days = <IcsDay>{};

  Map<String, _Property>? event;
  for (final line in lines) {
    final property = _Property.parse(line);
    if (property == null) continue;

    if (property.name == 'BEGIN' && property.value.toUpperCase() == 'VEVENT') {
      event = {};
    } else if (property.name == 'END' &&
        property.value.toUpperCase() == 'VEVENT') {
      if (event != null) {
        days.addAll(_expand(event, lastYear: lastYear, maxSpan: maxSpanDays));
      }
      event = null;
    } else if (event != null) {
      // First occurrence wins; well-formed files have one of each.
      event.putIfAbsent(property.name, () => property);
    } else if (property.name == 'X-WR-CALNAME') {
      calendarName = _unescape(property.value).trim();
    }
  }

  final sorted = days.toList()
    ..sort((a, b) =>
        a.day != b.day ? a.day.compareTo(b.day) : a.name.compareTo(b.name));
  return IcsCalendar(
    (calendarName == null || calendarName.isEmpty) ? null : calendarName,
    sorted,
  );
}

/// Joins folded lines: a line starting with a space or tab continues the
/// one before it.
List<String> _unfold(String source) {
  final raw = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final lines = <String>[];
  for (final line in raw) {
    if ((line.startsWith(' ') || line.startsWith('\t')) && lines.isNotEmpty) {
      lines[lines.length - 1] += line.substring(1);
    } else {
      lines.add(line);
    }
  }
  return lines;
}

class _Property {
  final String name;
  final Map<String, String> params;
  final String value;

  _Property(this.name, this.params, this.value);

  /// `NAME;PARAM=x;PARAM="y:z":value`. The value starts at the first colon
  /// outside double quotes.
  static _Property? parse(String line) {
    bool quoted = false;
    int colon = -1;
    for (int i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') quoted = !quoted;
      if (ch == ':' && !quoted) {
        colon = i;
        break;
      }
    }
    if (colon <= 0) return null;
    final head = line.substring(0, colon).split(';');
    final params = <String, String>{};
    for (final part in head.skip(1)) {
      final eq = part.indexOf('=');
      if (eq > 0) {
        params[part.substring(0, eq).toUpperCase()] =
            part.substring(eq + 1).replaceAll('"', '');
      }
    }
    return _Property(
        head.first.trim().toUpperCase(), params, line.substring(colon + 1));
  }
}

String _unescape(String text) {
  final out = StringBuffer();
  for (int i = 0; i < text.length; i++) {
    final ch = text[i];
    if (ch == r'\' && i + 1 < text.length) {
      final next = text[i + 1];
      out.write(next == 'n' || next == 'N' ? ' ' : next);
      i++;
    } else {
      out.write(ch);
    }
  }
  return out.toString();
}

/// yyyymmdd from the date part of a DATE or DATE-TIME value.
DateTime? _date(String value) {
  final digits = value.trim();
  if (digits.length < 8) return null;
  final y = int.tryParse(digits.substring(0, 4));
  final m = int.tryParse(digits.substring(4, 6));
  final d = int.tryParse(digits.substring(6, 8));
  if (y == null || m == null || d == null) return null;
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  return DateTime.utc(y, m, d);
}

int _ymd(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

Iterable<IcsDay> _expand(
  Map<String, _Property> event, {
  required int lastYear,
  required int maxSpan,
}) sync* {
  if (event['STATUS']?.value.trim().toUpperCase() == 'CANCELLED') return;
  final start = event['DTSTART'] == null ? null : _date(event['DTSTART']!.value);
  if (start == null) return;
  final String name = event['SUMMARY'] == null
      ? 'Holiday'
      : _unescape(event['SUMMARY']!.value).trim();
  if (name.isEmpty) return;

  // All-day events end the day *after* their last day (DTEND is
  // exclusive). A timed event is taken as one day.
  int span = 1;
  final endProperty = event['DTEND'];
  final bool allDay = event['DTSTART']!.params['VALUE'] == 'DATE' ||
      event['DTSTART']!.value.trim().length == 8;
  if (endProperty != null && allDay) {
    final end = _date(endProperty.value);
    if (end != null) {
      span = end.difference(start).inDays.clamp(1, maxSpan).toInt();
    }
  }

  for (final first in _occurrences(start, event['RRULE']?.value, lastYear)) {
    for (int i = 0; i < span; i++) {
      yield IcsDay(
          _ymd(DateTime.utc(first.year, first.month, first.day + i)), name);
    }
  }
}

/// The start dates of an event: just [start], or each year's date for a
/// yearly RRULE. Other frequencies are rare in holiday calendars and are
/// read as a single occurrence.
Iterable<DateTime> _occurrences(
    DateTime start, String? rule, int lastYear) sync* {
  if (rule == null) {
    yield start;
    return;
  }
  final parts = <String, String>{};
  for (final part in rule.split(';')) {
    final eq = part.indexOf('=');
    if (eq > 0) {
      parts[part.substring(0, eq).trim().toUpperCase()] =
          part.substring(eq + 1).trim().toUpperCase();
    }
  }
  if (parts['FREQ'] != 'YEARLY') {
    yield start;
    return;
  }

  final int interval = int.tryParse(parts['INTERVAL'] ?? '') ?? 1;
  final int? count = int.tryParse(parts['COUNT'] ?? '');
  final DateTime? until =
      parts['UNTIL'] == null ? null : _date(parts['UNTIL']!);
  final int month = int.tryParse(parts['BYMONTH'] ?? '') ?? start.month;
  final _NthWeekday? byDay =
      parts['BYDAY'] == null ? null : _NthWeekday.parse(parts['BYDAY']!);

  int produced = 0;
  for (int year = start.year; year <= lastYear; year += interval < 1 ? 1 : interval) {
    final DateTime? date = byDay == null
        ? _validDate(year, month, start.day)
        : byDay.inMonth(year, month);
    if (date == null) continue; // 29 February in a common year
    if (date.isBefore(start)) continue;
    if (until != null && date.isAfter(until)) return;
    yield date;
    produced++;
    if (count != null && produced >= count) return;
  }
}

DateTime? _validDate(int year, int month, int day) {
  final date = DateTime.utc(year, month, day);
  return date.month == month ? date : null;
}

/// BYDAY such as `3MO` (third Monday) or `-1MO` (last Monday).
class _NthWeekday {
  final int n;
  final int weekday; // DateTime.monday ... DateTime.sunday

  _NthWeekday(this.n, this.weekday);

  static const _names = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

  static _NthWeekday? parse(String text) {
    final match = RegExp(r'^([+-]?\d{1,2})?(MO|TU|WE|TH|FR|SA|SU)$')
        .firstMatch(text.split(',').first);
    if (match == null) return null;
    final n = int.tryParse(match.group(1) ?? '') ?? 1;
    if (n == 0) return null;
    return _NthWeekday(n, _names.indexOf(match.group(2)!) + 1);
  }

  DateTime? inMonth(int year, int month) {
    if (n > 0) {
      final first = DateTime.utc(year, month, 1);
      final shift = (weekday - first.weekday) % 7;
      final date = DateTime.utc(year, month, 1 + shift + 7 * (n - 1));
      return date.month == month ? date : null;
    }
    final last = DateTime.utc(year, month + 1, 0);
    final shift = (last.weekday - weekday) % 7;
    final date = DateTime.utc(year, month, last.day - shift + 7 * (n + 1));
    return date.month == month ? date : null;
  }
}
