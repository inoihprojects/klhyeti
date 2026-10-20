import '../data/event_repository.dart';
import '../models/calendar_event.dart';
import 'sync_payload.dart';

/// A same-id event edited independently on this device and on the peer:
/// neither copy was made on top of the other, so the user has to pick
/// (see ARCHITECTURE.md; this app never silently auto-merges).
class SyncConflict {
  final CalendarEvent local;
  final CalendarEvent incoming;
  const SyncConflict({required this.local, required this.incoming});
}

class ReconcileResult {
  /// Who the payload came from, and when they made it.
  final String peerDeviceId;
  final String? peerDeviceName;
  final DateTime generatedAt;

  final int inserted;
  final int fastForwarded;
  final int unchanged;
  final List<SyncConflict> conflicts;

  const ReconcileResult({
    required this.peerDeviceId,
    this.peerDeviceName,
    required this.generatedAt,
    required this.inserted,
    required this.fastForwarded,
    required this.unchanged,
    required this.conflicts,
  });

  int get totalApplied => inserted + fastForwarded;
}

/// Applies an incoming [SyncPayload] to [repo], judging each event by its
/// revisions (see revision.dart), never by clocks:
///
///  - not known here -> insert it.
///  - the same revision -> nothing to do.
///  - theirs was made on top of ours -> take theirs.
///  - ours was made on top of theirs -> keep ours; it reaches them on
///    their next sync with this device.
///  - neither, but the content agrees -> both made the same edit; keep
///    ours and remember theirs as an ancestor.
///  - neither -> a conflict, returned for the user to settle.
///
/// Unsettled conflicts change nothing, so the next sync finds them again.
Future<ReconcileResult> reconcile(
    EventRepository repo, SyncPayload payload) async {
  int inserted = 0;
  int fastForwarded = 0;
  int unchanged = 0;
  final conflicts = <SyncConflict>[];

  for (final incoming in payload.events) {
    final local = await repo.getById(incoming.id);

    if (local == null) {
      await repo.applyIncoming(incoming);
      inserted++;
    } else if (local.rev == incoming.rev || local.descendsFrom(incoming)) {
      unchanged++;
    } else if (incoming.descendsFrom(local)) {
      await repo.applyIncoming(incoming);
      fastForwarded++;
    } else if (local.sameContentAs(incoming)) {
      await repo.absorb(local, incoming);
      unchanged++;
    } else {
      conflicts.add(SyncConflict(local: local, incoming: incoming));
    }
  }

  return ReconcileResult(
    peerDeviceId: payload.deviceId,
    peerDeviceName: payload.deviceName,
    generatedAt: payload.generatedAt,
    inserted: inserted,
    fastForwarded: fastForwarded,
    unchanged: unchanged,
    conflicts: conflicts,
  );
}

/// The listening half of a direct sync.
///
/// The connecting device has reconciled everything this device sent,
/// settled the conflicts its user chose to settle, and sent back
/// everything it now has ([merged]). This device takes each version that
/// was made on top of its own. Everything else is left: versions older
/// than its own, conflicts still unsettled, and events edited here while
/// the sync was running. Those take part in the next sync.
///
/// Returns how many events changed here.
Future<int> acceptMerged(EventRepository repo, SyncPayload merged) async {
  var applied = 0;
  for (final incoming in merged.events) {
    final local = await repo.getById(incoming.id);
    if (local == null || incoming.descendsFrom(local)) {
      await repo.applyIncoming(incoming);
      applied++;
    } else if (local.rev != incoming.rev &&
        !local.descendsFrom(incoming) &&
        local.sameContentAs(incoming)) {
      await repo.absorb(local, incoming);
    }
  }
  return applied;
}

/// Whether this device, rather than the peer, holds the most recent edit
/// among [conflicts]. "Keep newest" gives every conflict to that device.
/// It trusts both devices' clocks, which is fine for a suggestion the
/// user sees before accepting; a tie goes to this device.
bool localIsNewest(List<SyncConflict> conflicts) {
  DateTime? local;
  DateTime? incoming;
  for (final conflict in conflicts) {
    final l = conflict.local.updatedAt;
    final i = conflict.incoming.updatedAt;
    if (local == null || l.isAfter(local)) local = l;
    if (incoming == null || i.isAfter(incoming)) incoming = i;
  }
  if (local == null || incoming == null) return true;
  return !incoming.isAfter(local);
}
