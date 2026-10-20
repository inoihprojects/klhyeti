import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'tap_fade.dart';

/// Shared date helpers.
bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// The 42 days (6 rows x 7 columns) drawn for [month], starting with the
/// week that contains its 1st.
List<DateTime> monthGridDays(DateTime month, bool weekStartsMonday) {
  final start = weekStartOf(DateTime(month.year, month.month, 1),
      weekStartsMonday);
  return List<DateTime>.generate(
    42,
    // DateTime normalises out-of-range days, so this walks into the
    // neighbouring months correctly, including across year boundaries.
    (i) => DateTime(start.year, start.month, start.day + i),
  );
}

/// The first day of the week that contains [day].
DateTime weekStartOf(DateTime day, bool weekStartsMonday) {
  // DateTime.weekday runs Monday == 1 ... Sunday == 7.
  final back = weekStartsMonday ? day.weekday - 1 : day.weekday % 7;
  return DateTime(day.year, day.month, day.day - back);
}

/// Whole calendar days from [a] to [b]. Counted between UTC midnights of
/// the same dates, so a 23- or 25-hour daylight-saving day still counts
/// as exactly one.
int daysBetween(DateTime a, DateTime b) {
  return DateTime.utc(b.year, b.month, b.day)
      .difference(DateTime.utc(a.year, a.month, a.day))
      .inDays;
}

/// Weekday initials in display order, starting Sunday or Monday.
List<String> weekdayHeaders(bool weekStartsMonday) {
  const labels = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  return weekStartsMonday ? labels : [labels[6], ...labels.take(6)];
}

/// The month calendar: full-bleed cells, six rows always, so the grid is
/// the same height every month.
class MonthGrid extends StatelessWidget {
  final DateTime month;
  final DateTime selectedDay;
  final DateTime today;
  final Map<DateTime, int> eventCounts;
  final bool weekStartsMonday;
  final bool colourWeekends;
  final HolidayNames holidays;
  final ValueChanged<DateTime> onSelect;

  const MonthGrid({
    super.key,
    required this.month,
    required this.selectedDay,
    required this.today,
    required this.eventCounts,
    required this.weekStartsMonday,
    required this.colourWeekends,
    this.holidays = noHolidays,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final days = monthGridDays(month, weekStartsMonday);

    return Column(
      children: [
        WeekdayHeader(
          weekStartsMonday: weekStartsMonday,
          colourWeekends: colourWeekends,
        ),
        Expanded(
          child: Column(
            children: [
              for (int row = 0; row < 6; row++)
                Expanded(
                  child: Row(
                    children: [
                      for (int col = 0; col < 7; col++)
                        Expanded(
                          child: DayCell(
                            day: days[row * 7 + col],
                            inMonth: days[row * 7 + col].month == month.month,
                            selected: isSameDay(days[row * 7 + col],
                                selectedDay),
                            isToday: isSameDay(days[row * 7 + col], today),
                            eventCount:
                                eventCounts[dayOnly(days[row * 7 + col])] ?? 0,
                            colourWeekends: colourWeekends,
                            holidays: holidays(days[row * 7 + col]),
                            onTap: () => onSelect(days[row * 7 + col]),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The SUN…SAT row above the grid, plus the hairline under it. Its height
/// is [WeekdayHeader.height], which layouts subtract when sizing rows.
class WeekdayHeader extends StatelessWidget {
  final bool weekStartsMonday;
  final bool colourWeekends;

  const WeekdayHeader({
    super.key,
    required this.weekStartsMonday,
    required this.colourWeekends,
  });

  /// 28 for the labels and 1 for the hairline.
  static const double height = 29;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 28,
          child: Row(
            children: [
              for (final label in weekdayHeaders(weekStartsMonday))
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                        color: colourWeekends && label == 'SUN'
                            ? c.vermilion
                            : colourWeekends && label == 'SAT'
                                ? c.indigo
                                : c.ink3,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: c.line),
      ],
    );
  }
}

/// The holidays on a day, empty when there are none.
typedef HolidayNames = List<String> Function(DateTime day);

List<String> noHolidays(DateTime day) => const [];

/// One day in the month grid. [inMonth] false draws it faded, as a day
/// belonging to a neighbouring month. A holiday's number is vermilion, and
/// its name is shown under it when the cell is tall enough.
class DayCell extends StatelessWidget {
  final DateTime day;
  final bool inMonth;
  final bool selected;
  final bool isToday;
  final int eventCount;
  final bool colourWeekends;
  final List<String> holidays;
  final VoidCallback onTap;

  const DayCell({
    super.key,
    required this.day,
    required this.inMonth,
    required this.selected,
    required this.isToday,
    required this.eventCount,
    required this.colourWeekends,
    this.holidays = const [],
    required this.onTap,
  });

  /// Below this height there's no room for a holiday's name under the
  /// number and dots; the vermilion number alone marks it.
  static const double _nameMinHeight = 64;

  Color _numberColour(KlhyetiColors c) {
    if (selected) return c.bg;
    if (!inMonth) return c.ink3;
    if (holidays.isNotEmpty) return c.vermilion;
    if (colourWeekends && day.weekday == DateTime.sunday) return c.vermilion;
    if (colourWeekends && day.weekday == DateTime.saturday) return c.indigo;
    return c.ink;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final colour = _numberColour(c);

    return TapFade(
      onTap: onTap,
      selected: selected,
      semanticLabel: '${weekdayNames[day.weekday - 1]} ${day.day} '
          '${monthNames[day.month - 1]}'
          '${eventCount == 0 ? '' : ', $eventCount events'}'
          '${isToday ? ', today' : ''}'
          '${holidays.isEmpty ? '' : ', holiday: ${holidays.join(', ')}'}',
      // The whole cell is the tap target; only the marker inside is small.
      child: LayoutBuilder(
        builder: (context, constraints) => Container(
          color: Colors.transparent,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? c.ink
                      : (isToday ? c.surfaceAlt : Colors.transparent),
                  borderRadius: BorderRadius.circular(Radii.cell),
                ),
                child: Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: (isToday || selected)
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: colour,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              SizedBox(
                height: 6,
                child: eventCount == 0 ? null : _dots(c),
              ),
              if (isToday && selected)
                Container(
                  width: 18,
                  height: 2,
                  margin: const EdgeInsets.only(top: 2),
                  color: c.vermilion,
                ),
              if (holidays.isNotEmpty &&
                  constraints.maxHeight >= _nameMinHeight)
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
                  child: Text(
                    holidays.first,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9,
                      height: 1.2,
                      color: inMonth ? c.vermilion : c.ink3,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dots(KlhyetiColors c) {
    final Color colour = selected ? c.bg : c.ink2;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < (eventCount > 3 ? 3 : eventCount); i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.5),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(shape: BoxShape.circle, color: colour),
            ),
          ),
        if (eventCount > 3)
          Text(
            '+',
            style: TextStyle(
              fontSize: 9,
              height: 1,
              fontWeight: FontWeight.w700,
              color: colour,
            ),
          ),
      ],
    );
  }
}

/// The small month used twelve times over in the year view.
///
/// Sized to be read at a glance: a 15 pt month name and 11 pt days. The
/// current month is a filled card with its name in vermilion, and today a
/// solid ink square, so both stand out from across the room.
class MiniMonth extends StatelessWidget {
  final DateTime month;
  final DateTime today;
  final Map<DateTime, int> eventCounts;
  final bool weekStartsMonday;
  final bool colourWeekends;
  final HolidayNames holidays;
  final VoidCallback onTap;

  const MiniMonth({
    super.key,
    required this.month,
    required this.today,
    required this.eventCounts,
    required this.weekStartsMonday,
    required this.colourWeekends,
    this.holidays = noHolidays,
    required this.onTap,
  });

  /// The height a MiniMonth needs; the year view lays its grid out by it.
  static const double height = 156;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final days = monthGridDays(month, weekStartsMonday);
    final isCurrentMonth =
        month.year == today.year && month.month == today.month;

    return TapFade(
      onTap: onTap,
      semanticLabel: '${monthNames[month.month - 1]} ${month.year}'
          '${isCurrentMonth ? ', this month' : ''}',
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
        decoration: BoxDecoration(
          color: isCurrentMonth ? c.surfaceAlt : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.cell),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Text(
                monthNames[month.month - 1],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: isCurrentMonth ? c.vermilion : c.ink,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                for (final label in weekdayHeaders(weekStartsMonday))
                  Expanded(
                    child: Center(
                      child: Text(
                        label.substring(0, 1),
                        style: TextStyle(
                          fontSize: 10,
                          height: 1.2,
                          color: c.ink3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            for (int row = 0; row < 6; row++)
              Row(
                children: [
                  for (int col = 0; col < 7; col++)
                    Expanded(
                      child: _MiniDay(
                        day: days[row * 7 + col],
                        inMonth: days[row * 7 + col].month == month.month,
                        isToday: isSameDay(days[row * 7 + col], today),
                        hasEvents:
                            (eventCounts[dayOnly(days[row * 7 + col])] ?? 0) >
                                0,
                        isHoliday: holidays(days[row * 7 + col]).isNotEmpty,
                        colourWeekends: colourWeekends,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _MiniDay extends StatelessWidget {
  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final bool hasEvents;
  final bool isHoliday;
  final bool colourWeekends;

  const _MiniDay({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.hasEvents,
    required this.isHoliday,
    required this.colourWeekends,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // Days of the neighbouring months are left blank: at this size they
    // only blur where one month ends.
    if (!inMonth) return const SizedBox(height: 18);

    Color colour = c.ink;
    if (isToday) {
      colour = c.bg;
    } else if (isHoliday) {
      colour = c.vermilion;
    } else if (colourWeekends && day.weekday == DateTime.sunday) {
      colour = c.vermilion;
    } else if (colourWeekends && day.weekday == DateTime.saturday) {
      colour = c.indigo;
    }

    return SizedBox(
      height: 18,
      child: Column(
        children: [
          Container(
            width: 18,
            height: 15,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isToday ? c.ink : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${day.day}',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                color: colour,
                fontFeatures: tabularFigures,
              ),
            ),
          ),
          SizedBox(
            height: 3,
            child: hasEvents
                ? Center(
                    child: Container(
                      width: 3,
                      height: 3,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.ink2,
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
