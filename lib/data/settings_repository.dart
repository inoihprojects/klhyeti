import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:sqflite/sqflite.dart';

/// User preferences, stored in the `settings` table of the same local
/// database. Settings are deliberately *not* synced between devices: a
/// phone and a desktop want different things.
class SettingsRepository extends ChangeNotifier {
  final Database _db;

  ThemeMode _themeMode = ThemeMode.system;
  bool _weekStartsMonday = false;
  bool _colourWeekends = true;
  bool _reverseMonthScroll = false;
  bool? _continuousMonths; // null = the platform's default
  bool? _use24HourTime; // null = follow the system
  String _deviceName = '';
  bool _autoSync = false;

  SettingsRepository(this._db);

  ThemeMode get themeMode => _themeMode;
  bool get weekStartsMonday => _weekStartsMonday;
  bool get colourWeekends => _colourWeekends;

  /// False: scrolling down or swiping left goes to the next month. True
  /// flips both, for people whose system scrolls the other way.
  bool get reverseMonthScroll => _reverseMonthScroll;

  /// True: weeks scroll continuously, with no month boundaries. False:
  /// one month at a time. Phones default to continuous, where a thumb
  /// scrolls; desktops to one month at a time, where a wheel steps.
  bool get continuousMonths => _continuousMonths ?? _defaultContinuous();
  bool? get use24HourTime => _use24HourTime;
  String get deviceName => _deviceName;

  /// Off unless the user turns it on: syncing stays something they ask
  /// for until they say otherwise.
  bool get autoSync => _autoSync;

  static const String _kThemeMode = 'theme_mode';
  static const String _kWeekStartsMonday = 'week_starts_monday';
  static const String _kColourWeekends = 'colour_weekends';
  static const String _kReverseMonthScroll = 'reverse_month_scroll';
  static const String _kContinuousMonths = 'continuous_months';
  static const String _kUse24HourTime = 'use_24_hour_time';
  static const String _kDeviceName = 'device_name';
  static const String _kAutoSync = 'auto_sync';

  Future<void> load() async {
    final rows = await _db.query('settings');
    final map = <String, String>{
      for (final row in rows) row['key']! as String: row['value']! as String,
    };

    _themeMode = switch (map[_kThemeMode]) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    _weekStartsMonday = map[_kWeekStartsMonday] == '1';
    _colourWeekends = map[_kColourWeekends] != '0';
    _reverseMonthScroll = map[_kReverseMonthScroll] == '1';
    _continuousMonths = switch (map[_kContinuousMonths]) {
      '1' => true,
      '0' => false,
      _ => null,
    };
    _use24HourTime = switch (map[_kUse24HourTime]) {
      '1' => true,
      '0' => false,
      _ => null,
    };
    _deviceName = map[_kDeviceName] ?? _defaultDeviceName();
    _autoSync = map[_kAutoSync] == '1';
    notifyListeners();
  }

  static bool _defaultContinuous() => Platform.isAndroid || Platform.isIOS;

  static String _defaultDeviceName() {
    if (Platform.isAndroid || Platform.isIOS) return 'My phone';
    return 'My computer';
  }

  Future<void> _put(String key, String? value) async {
    if (value == null) {
      await _db.delete('settings', where: 'key = ?', whereArgs: [key]);
    } else {
      await _db.insert(
        'settings',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _put(_kThemeMode, mode.name);
  }

  Future<void> setWeekStartsMonday(bool value) async {
    _weekStartsMonday = value;
    await _put(_kWeekStartsMonday, value ? '1' : '0');
  }

  Future<void> setColourWeekends(bool value) async {
    _colourWeekends = value;
    await _put(_kColourWeekends, value ? '1' : '0');
  }

  Future<void> setReverseMonthScroll(bool value) async {
    _reverseMonthScroll = value;
    await _put(_kReverseMonthScroll, value ? '1' : '0');
  }

  Future<void> setContinuousMonths(bool value) async {
    _continuousMonths = value;
    await _put(_kContinuousMonths, value ? '1' : '0');
  }

  Future<void> setUse24HourTime(bool? value) async {
    _use24HourTime = value;
    await _put(_kUse24HourTime, value == null ? null : (value ? '1' : '0'));
  }

  Future<void> setAutoSync(bool value) async {
    _autoSync = value;
    await _put(_kAutoSync, value ? '1' : '0');
  }

  Future<void> setDeviceName(String value) async {
    final trimmed = value.trim();
    _deviceName = trimmed.isEmpty ? _defaultDeviceName() : trimmed;
    await _put(_kDeviceName, _deviceName);
  }
}
