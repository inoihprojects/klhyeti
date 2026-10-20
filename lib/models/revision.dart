import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

/// Revisions: how sync tells a newer copy of an event from a conflicting
/// one without trusting any device's clock.
///
/// Every edit of an event (creating, changing, deleting, settling a
/// conflict) gives it a new random revision id and pushes the old one
/// onto its history. When two devices hold different copies:
///
///  - if one copy's history contains the other's revision, the first was
///    made on top of the second and simply replaces it;
///  - if neither does, they were edited independently: a real conflict.
///
/// Settling a conflict makes a revision whose history holds *both* sides,
/// so every device, holding either side, sees it as newer.
///
/// The history keeps the last [maxHistory] revisions. An event edited
/// more often than that between two syncs loses the trail, and the next
/// sync asks the user rather than guessing.
const int maxHistory = 32;

final Random _random = Random.secure();

/// [count] bytes from the system's secure random source: for ids here,
/// and for the keys, secrets and numbers of pairing and sync.
Uint8List randomBytes(int count) {
  final bytes = Uint8List(count);
  for (var i = 0; i < count; i++) {
    bytes[i] = _random.nextInt(256);
  }
  return bytes;
}

String _hex(List<int> bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

/// A new revision id: 64 random bits as 16 hex characters.
String newRevision() => _hex(randomBytes(8));

/// A new id for an event or a device: a random (version 4) UUID in its
/// usual lowercase form, e.g. `110ec58a-a0f2-4ac4-8393-c866d813b8d1`.
String newUuid() {
  final bytes = randomBytes(16);
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
  final hex = _hex(bytes);
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// The revision of an event saved before revisions existed, or received
/// from a device that doesn't send them. Worked out from what every copy
/// of that version shares, its id and its edit time, so two devices
/// holding the same old version give it the same revision.
String legacyRevision(String id, DateTime updatedAt) {
  final digest = pc.SHA256Digest().process(Uint8List.fromList(utf8.encode(
      'klhyeti legacy revision|$id|${updatedAt.toUtc().millisecondsSinceEpoch}')));
  return _hex(digest.sublist(0, 8));
}

/// [lists] joined in order, without repeats, cut to [maxHistory].
List<String> mergeHistories(List<List<String>> lists) {
  final seen = <String>{};
  final merged = <String>[];
  for (final list in lists) {
    for (final revision in list) {
      if (merged.length == maxHistory) return merged;
      if (seen.add(revision)) merged.add(revision);
    }
  }
  return merged;
}
