import 'dart:convert';

import '../models/calendar_event.dart';

/// The one message format both sync transports speak, the sync file and
/// direct sync (see ARCHITECTURE.md). Neither transport nor the
/// reconciler that consumes this needs to know about the other.
///
/// Format 2 (Klhyeti 1.1) adds repeating events. Its events travel under
/// "events2", not 1.0's "events": Klhyeti 1.0 then finds nothing to
/// import in a newer file, instead of taking schedules as one-off events
/// and dropping their repeats on its next edit. Files without a format
/// are from 1.0 and earlier, and still load.
class SyncPayload {
  static const int format = 2;

  final String deviceId;

  /// What the user calls the sending device, for the conflict screen.
  /// Absent in files written before 0.3.
  final String? deviceName;
  final DateTime generatedAt;
  final List<CalendarEvent> events;

  const SyncPayload({
    required this.deviceId,
    this.deviceName,
    required this.generatedAt,
    required this.events,
  });

  Map<String, Object?> toJson() => {
        'format': format,
        'deviceId': deviceId,
        if (deviceName != null) 'deviceName': deviceName,
        'generatedAt': generatedAt.toUtc().toIso8601String(),
        'events2': events.map((e) => e.toJson()).toList(),
      };

  factory SyncPayload.fromJson(Map<String, Object?> json) {
    final Object? version = json['format'];
    if (version != null && version != format) throw const NewerSyncFormat();
    final rawEvents =
        json[version == null ? 'events' : 'events2']! as List<dynamic>;
    return SyncPayload(
      deviceId: json['deviceId']! as String,
      deviceName: json['deviceName'] as String?,
      generatedAt: DateTime.parse(json['generatedAt']! as String),
      events: rawEvents
          .map((e) => CalendarEvent.fromJson((e as Map).cast<String, Object?>()))
          .toList(),
    );
  }

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory SyncPayload.decode(String source) {
    final decoded = jsonDecode(source) as Map;
    return SyncPayload.fromJson(decoded.cast<String, Object?>());
  }
}

/// A sync file written by a later version of Klhyeti than this one.
class NewerSyncFormat implements Exception {
  const NewerSyncFormat();

  @override
  String toString() =>
      'This sync file is from a newer Klhyeti. Update this device first.';
}
