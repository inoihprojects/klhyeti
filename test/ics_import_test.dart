// .ics files come from anywhere, so the reader is tested on the shapes
// holiday calendars actually use: all-day dates, timed dates, folded
// lines, escaped text, yearly repeats and "n-th weekday" rules.

import 'package:flutter_test/flutter_test.dart';
import 'package:klhyeti/data/ics_import.dart';

String ics(String events) => 'BEGIN:VCALENDAR\r\n'
    'VERSION:2.0\r\n'
    'X-WR-CALNAME:Test Holidays\r\n'
    '$events'
    'END:VCALENDAR\r\n';

void main() {
  test('reads all-day and timed events, and the calendar name', () {
    final result = parseIcs(ics('BEGIN:VEVENT\r\n'
        'DTSTART;VALUE=DATE:20261225\r\n'
        'SUMMARY:Christmas Day\r\n'
        'END:VEVENT\r\n'
        'BEGIN:VEVENT\r\n'
        'DTSTART;TZID=Europe/London:20260704T090000\r\n'
        'SUMMARY:Picnic\r\n'
        'END:VEVENT\r\n'));
    expect(result.name, 'Test Holidays');
    expect(result.days, const [
      IcsDay(20260704, 'Picnic'),
      IcsDay(20261225, 'Christmas Day'),
    ]);
  });

  test('unfolds long lines and unescapes text', () {
    final result = parseIcs(ics('BEGIN:VEVENT\r\n'
        'DTSTART;VALUE=DATE:20260101\r\n'
        'SUMMARY:New Year\\, the\r\n'
        '  first day\r\n'
        'END:VEVENT\r\n'));
    expect(result.days.single, const IcsDay(20260101, 'New Year, the first day'));
  });

  test('an all-day event spanning days lists each day', () {
    final result = parseIcs(ics('BEGIN:VEVENT\r\n'
        'DTSTART;VALUE=DATE:20260216\r\n'
        'DTEND;VALUE=DATE:20260219\r\n'
        'SUMMARY:Festival\r\n'
        'END:VEVENT\r\n'));
    expect(result.days.map((d) => d.day), [20260216, 20260217, 20260218]);
  });

  test('yearly repeats honour COUNT and skip missing dates', () {
    final counted = parseIcs(ics('BEGIN:VEVENT\r\n'
        'DTSTART;VALUE=DATE:20260301\r\n'
        'RRULE:FREQ=YEARLY;COUNT=3\r\n'
        'SUMMARY:Spring\r\n'
        'END:VEVENT\r\n'));
    expect(counted.days.map((d) => d.day), [20260301, 20270301, 20280301]);

    final leap = parseIcs(
        ics('BEGIN:VEVENT\r\n'
            'DTSTART;VALUE=DATE:20280229\r\n'
            'RRULE:FREQ=YEARLY;UNTIL=20330101\r\n'
            'SUMMARY:Leap day\r\n'
            'END:VEVENT\r\n'),
        lastYear: 2040);
    expect(leap.days.map((d) => d.day), [20280229, 20320229]);
  });

  test('n-th and last weekday rules', () {
    final result = parseIcs(
        ics('BEGIN:VEVENT\r\n'
            'DTSTART;VALUE=DATE:20260119\r\n'
            'RRULE:FREQ=YEARLY;BYMONTH=1;BYDAY=3MO\r\n'
            'SUMMARY:Third Monday\r\n'
            'END:VEVENT\r\n'
            'BEGIN:VEVENT\r\n'
            'DTSTART;VALUE=DATE:20260525\r\n'
            'RRULE:FREQ=YEARLY;BYMONTH=5;BYDAY=-1MO\r\n'
            'SUMMARY:Last Monday\r\n'
            'END:VEVENT\r\n'),
        lastYear: 2027);
    expect(result.days.map((d) => '${d.day} ${d.name}'), [
      '20260119 Third Monday',
      '20260525 Last Monday',
      '20270118 Third Monday',
      '20270531 Last Monday',
    ]);
  });

  test('cancelled events and events without a date are skipped', () {
    final result = parseIcs(ics('BEGIN:VEVENT\r\n'
        'DTSTART;VALUE=DATE:20260101\r\n'
        'STATUS:CANCELLED\r\n'
        'SUMMARY:Gone\r\n'
        'END:VEVENT\r\n'
        'BEGIN:VEVENT\r\n'
        'SUMMARY:No date\r\n'
        'END:VEVENT\r\n'));
    expect(result.days, isEmpty);
  });
}
