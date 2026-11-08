import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sqflite/sqflite.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/calendar_event.dart';
import '../widgets/event_list.dart' show clockText;
import 'event_repository.dart';
import 'settings_repository.dart';

/// Reminders: a notification some time before an event, on Android only.
///
/// Which events have one, and how long before, is this device's own
/// choice and is never synced: a phone can remind while a computer stays
/// quiet. Android delivers them itself, on the minute, with Klhyeti
/// closed and after a restart. Klhyeti hands Android the next ones within
/// [_horizon] whenever events or reminders change, and each time it
/// opens.
///
/// A reminder is a number of minutes before the event's start. For an
/// all-day event it counts from the start of its day instead, so the
/// day before at 9:00 is 900 and that day at 9:00 is -540.
class Reminders {
  final Database _db;
  final EventRepository repo;
  final SettingsRepository settings;

  Reminders(this._db, {required this.repo, required this.settings});

  /// Only Android gets reminders; elsewhere this does nothing.
  static bool get supported => Platform.isAndroid;

  /// The choices offered, in minutes, with null for none.
  static const List<int?> timedChoices = [null, 0, 10, 60, 1440];
  static const List<int?> allDayChoices = [null, -540, 900];

  static const Duration _horizon = Duration(days: 60);
  static const int _maxScheduled = 250;

  final Map<String, int> _minutes = {};
  FlutterLocalNotificationsPlugin? _plugin;
  Timer? _pending;

  int? minutesFor(String eventId) => _minutes[eventId];

  Future<void> start() async {
    if (!supported) return;
    try {
      for (final row in await _db.query('reminders')) {
        _minutes[row['event_id']! as String] = row['minutes']! as int;
      }
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_notification'),
        ),
      );
      _plugin = plugin;
      repo.addListener(_rescheduleSoon);
      await _reschedule();
    } catch (_) {
      // Without notifications the calendar still works; reminders stay
      // stored for when they can be shown again.
    }
  }

  /// Sets or, with null, removes [eventId]'s reminder. The first reminder
  /// asks Android for permission to notify.
  Future<void> set(String eventId, int? minutes) async {
    if (!supported || _minutes[eventId] == minutes) return;
    if (minutes == null) {
      _minutes.remove(eventId);
      await _db.delete('reminders', where: 'event_id = ?', whereArgs: [eventId]);
    } else {
      _minutes[eventId] = minutes;
      await _db.insert('reminders', {'event_id': eventId, 'minutes': minutes},
          conflictAlgorithm: ConflictAlgorithm.replace);
      await _android?.requestNotificationsPermission();
    }
    await _reschedule();
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin?.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// Events change in bursts (a sync writes many); wait for it to end.
  void _rescheduleSoon() {
    _pending?.cancel();
    _pending = Timer(const Duration(seconds: 2), _reschedule);
  }

  /// When the reminder for [event] (one date of it, for a schedule) is
  /// due. Counted on the clock, so a day with a clock change still puts
  /// "a day before" at the same time of day.
  static DateTime dueAt(CalendarEvent event, int minutes) {
    final start = event.startAt.toLocal();
    return event.allDay
        ? DateTime(start.year, start.month, start.day, 0, -minutes)
        : DateTime(start.year, start.month, start.day, start.hour,
            start.minute - minutes);
  }

  Future<void> _reschedule() async {
    final plugin = _plugin;
    if (plugin == null) return;
    final now = DateTime.now();
    final until = now.add(_horizon);
    final due = <(DateTime, CalendarEvent)>[];
    for (final entry in _minutes.entries.toList()) {
      final event = await repo.getById(entry.key);
      if (event == null || event.deleted) {
        // Its event is gone; so is the reminder.
        _minutes.remove(entry.key);
        await _db.delete('reminders',
            where: 'event_id = ?', whereArgs: [entry.key]);
        continue;
      }
      // A day's margin either side: a reminder can come a day before.
      final dates = event.rrule == null
          ? [event]
          : event.occurrencesOverlapping(
              now, until.add(const Duration(days: 2)));
      for (final date in dates) {
        final at = dueAt(date, entry.value);
        if (at.isAfter(now) && at.isBefore(until)) due.add((at, date));
      }
    }
    due.sort((a, b) => a.$1.compareTo(b.$1));

    await plugin.cancelAll();
    final bool exact = await _android?.canScheduleExactNotifications() ?? false;
    final bool twentyFour = settings.use24HourTime ??
        WidgetsBinding.instance.platformDispatcher.alwaysUse24HourFormat;
    var id = 0;
    for (final (at, event) in due.take(_maxScheduled)) {
      await plugin.zonedSchedule(
        id: id++,
        title: event.title,
        body: _body(event, twentyFour),
        scheduledDate: tz.TZDateTime.from(at, tz.UTC),
        notificationDetails: _details,
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  static String _body(CalendarEvent event, bool twentyFour) {
    final start = event.startAt.toLocal();
    final end = event.endAt.toLocal();
    final when = event.allDay
        ? 'All day, ${start.day}/${start.month}'
        : '${clockText(start, twentyFour)}–${clockText(end, twentyFour)}';
    final location = event.location;
    return location == null || location.isEmpty ? when : '$when · $location';
  }

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Reminders',
      channelDescription: 'Before the events you set a reminder for',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );
}
