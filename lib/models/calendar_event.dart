import 'revision.dart';

/// A single calendar event.
///
/// [id] is a UUID generated once, on whichever device first created the
/// event, and never changed again — it's how two devices recognize "this is
/// the same event" across a sync. See ARCHITECTURE.md.
class CalendarEvent {
  final String id;
  final String title;
  final String? description;
  final String? location;
  final DateTime startAt; // stored/compared in UTC
  final DateTime endAt;
  final bool allDay;
  final DateTime updatedAt; // UTC, bumped on every local edit
  final bool deleted; // soft-delete tombstone, see ARCHITECTURE.md
  final String originDeviceId; // device that last wrote this row

  /// This version's revision, and the revisions it was made on top of,
  /// newest first. See revision.dart.
  final String rev;
  final List<String> history;

  /// Without a [rev], the event is taken to be a version from before
  /// revisions existed, and gets its [legacyRevision].
  CalendarEvent({
    required this.id,
    required this.title,
    this.description,
    this.location,
    required this.startAt,
    required this.endAt,
    this.allDay = false,
    required this.updatedAt,
    this.deleted = false,
    required this.originDeviceId,
    String? rev,
    this.history = const [],
  }) : rev = rev ?? legacyRevision(id, updatedAt);

  /// Whether this version was made on top of [other]'s, directly or not.
  bool descendsFrom(CalendarEvent other) => history.contains(other.rev);

  /// The history a new edit of this version starts from.
  List<String> historyForNextEdit() => mergeHistories([
        [rev],
        history,
      ]);

  CalendarEvent copyWith({
    String? title,
    String? description,
    String? location,
    DateTime? startAt,
    DateTime? endAt,
    bool? allDay,
    DateTime? updatedAt,
    bool? deleted,
    String? originDeviceId,
    String? rev,
    List<String>? history,
  }) {
    return CalendarEvent(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      location: location ?? this.location,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      allDay: allDay ?? this.allDay,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
      originDeviceId: originDeviceId ?? this.originDeviceId,
      rev: rev ?? this.rev,
      history: history ?? this.history,
    );
  }

  /// The form a deleted event is stored and synced in: only the id, the
  /// deleted flag and the bookkeeping fields survive. Title, description,
  /// location and times are wiped, so a deletion really removes what the
  /// event said instead of leaving it behind in the database and in every
  /// sync file.
  CalendarEvent asTombstone({
    DateTime? updatedAt,
    String? originDeviceId,
    String? rev,
    List<String>? history,
  }) {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return CalendarEvent(
      id: id,
      title: '',
      description: null,
      location: null,
      startAt: epoch,
      endAt: epoch,
      allDay: false,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: true,
      originDeviceId: originDeviceId ?? this.originDeviceId,
      rev: rev ?? this.rev,
      history: history ?? this.history,
    );
  }

  /// Two events are "the same content" when everything except bookkeeping
  /// fields (updatedAt, originDeviceId) matches. Used by the reconciler to
  /// skip pointless no-op conflicts when both sides happen to hold identical
  /// data. Two tombstones of the same event always count as the same.
  bool sameContentAs(CalendarEvent other) {
    if (deleted && other.deleted) return id == other.id;
    return id == other.id &&
        title == other.title &&
        description == other.description &&
        location == other.location &&
        startAt.isAtSameMomentAs(other.startAt) &&
        endAt.isAtSameMomentAs(other.endAt) &&
        allDay == other.allDay &&
        deleted == other.deleted;
  }

  Map<String, Object?> toDbMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'location': location,
      'start_at': startAt.toUtc().millisecondsSinceEpoch,
      'end_at': endAt.toUtc().millisecondsSinceEpoch,
      'all_day': allDay ? 1 : 0,
      'updated_at': updatedAt.toUtc().millisecondsSinceEpoch,
      'deleted': deleted ? 1 : 0,
      'origin_device_id': originDeviceId,
      'rev': rev,
      'history': history.join(' '),
    };
  }

  factory CalendarEvent.fromDbMap(Map<String, Object?> map) {
    return CalendarEvent(
      id: map['id']! as String,
      title: map['title']! as String,
      description: map['description'] as String?,
      location: map['location'] as String?,
      startAt: DateTime.fromMillisecondsSinceEpoch(map['start_at']! as int,
          isUtc: true),
      endAt: DateTime.fromMillisecondsSinceEpoch(map['end_at']! as int,
          isUtc: true),
      allDay: (map['all_day']! as int) != 0,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at']! as int,
          isUtc: true),
      deleted: (map['deleted']! as int) != 0,
      originDeviceId: map['origin_device_id']! as String,
      // Absent in rows saved, and sync files written, before revisions.
      rev: map['rev'] as String?,
      history: [
        for (final revision in ((map['history'] as String?) ?? '').split(' '))
          if (revision.isNotEmpty) revision,
      ],
    );
  }

  Map<String, Object?> toJson() => toDbMap();

  factory CalendarEvent.fromJson(Map<String, Object?> json) =>
      CalendarEvent.fromDbMap(json);
}
