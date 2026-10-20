import 'dart:convert';

import '../models/calendar_event.dart';

/// The one message format both sync transports speak (file export/import
/// today, direct local-network sync later — see ARCHITECTURE.md). Neither
/// transport nor the reconciler that consumes this needs to know about the
/// other.
class SyncPayload {
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
        'deviceId': deviceId,
        if (deviceName != null) 'deviceName': deviceName,
        'generatedAt': generatedAt.toUtc().toIso8601String(),
        'events': events.map((e) => e.toJson()).toList(),
      };

  factory SyncPayload.fromJson(Map<String, Object?> json) {
    final rawEvents = json['events']! as List<dynamic>;
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
