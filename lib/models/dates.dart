/// Calendar-date helpers shared by the model, the data layer and the
/// grids. A "day" here is a local date at midnight.
library;

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

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

/// A date as yyyymmdd: how holidays and a schedule's skipped dates are
/// stored.
int ymd(DateTime date) => date.year * 10000 + date.month * 100 + date.day;

/// The local date a yyyymmdd stands for.
DateTime fromYmd(int value) =>
    DateTime(value ~/ 10000, value ~/ 100 % 100, value % 100);
