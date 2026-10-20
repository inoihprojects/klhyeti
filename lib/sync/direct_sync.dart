import 'dart:convert';
import 'dart:io';

import '../data/event_repository.dart';
import '../data/peer_repository.dart';
import 'lan_address.dart';
import 'sync_payload.dart';
import 'sync_reconciler.dart';
import 'wire.dart';

// Sync between two paired devices over the local network.
//
// One device connects; the other is listening (Klhyeti is open on it).
// TLS encrypts the connection. The connecting device accepts only the
// certificate it stored for this device at pairing, and then sends the
// secret the two share, which is how the listening device knows who is
// calling.
//
//   connecting device                      listening device
//   sync: id, secret                ->
//                                   <-  payload: everything it has
//     reconciles; its user may settle conflicts now
//   merged: everything it has now   ->
//                                   <-  done: how many events changed
//
// The listening device takes from "merged" every version made on top of
// its own (see acceptMerged). Conflicts left unsettled stay conflicts on
// both devices until someone settles them, on either.
//
// A device already busy with a sync answers "busy" instead, and the
// caller tries again a moment later.
//
// Messages are one JSON object per line.

class DirectSyncFailure implements Exception {
  final String message;
  const DirectSyncFailure(this.message);

  @override
  String toString() => message;
}

/// The other device was in the middle of another sync.
class DirectSyncBusy extends DirectSyncFailure {
  const DirectSyncBusy() : super('The other device is busy syncing.');
}

class DirectSyncOutcome {
  final String peerId;
  final String peerName;

  /// Events that changed on this device.
  final int changedHere;

  /// Events that changed on the other device; null on the listening
  /// device, which isn't told.
  final int? changedThere;

  /// Conflicts with this device still unsettled after the sync, and the
  /// reconcile result that found them (for showing them later).
  final ReconcileResult? unsettled;

  const DirectSyncOutcome({
    required this.peerId,
    required this.peerName,
    required this.changedHere,
    this.changedThere,
    this.unsettled,
  });
}

/// Runs a sync as the connecting device.
///
/// [settle], when given, is shown any conflicts and completes with true
/// once the user has settled them, or false if the user left them. Left
/// out (automatic sync), conflicts are only reported in the outcome.
///
/// Throws [SocketException] if nothing answers at [endpoint],
/// [HandshakeException] if something answers that is not [peer],
/// [DirectSyncBusy] if [peer] is busy, and [DirectSyncFailure] if [peer]
/// answers but the sync cannot be done.
Future<DirectSyncOutcome> syncWithPeer({
  required EventRepository repo,
  required String deviceName,
  required PairedDevice peer,
  required LanEndpoint endpoint,
  Future<bool> Function(ReconcileResult result)? settle,
  Duration connectTimeout = const Duration(seconds: 8),
}) async {
  final socket = await SecureSocket.connect(
    endpoint.address,
    endpoint.port,
    context: SecurityContext(withTrustedRoots: false),
    // No certificate authority vouches for a device's certificate, so
    // TLS always asks here. The answer is yes for exactly one
    // certificate: the one stored when the two devices were paired.
    onBadCertificate: (certificate) =>
        sameBytes(certificate.der, peer.certDer),
    timeout: connectTimeout,
  );
  final wire =
      Wire(socket, limit: _maxSyncBytes, failure: DirectSyncFailure.new);
  try {
    final presented = socket.peerCertificate?.der;
    if (presented == null || !sameBytes(presented, peer.certDer)) {
      throw const DirectSyncFailure('That device is not the paired one.');
    }

    wire.send({
      't': 'sync',
      'v': 1,
      'id': repo.deviceId,
      'secret': base64.encode(peer.secret),
    });

    final first = await wire.read(_stepTimeout);
    if (first['t'] == 'busy') throw const DirectSyncBusy();
    if (first['t'] == 'refused') {
      throw const DirectSyncFailure(
          'The other device no longer has this one paired. Pair them again.');
    }
    final theirs = _payload(first, 'payload');
    if (theirs.deviceId != peer.deviceId) {
      throw const DirectSyncFailure('That device is not the paired one.');
    }

    final result = await reconcile(repo, theirs);
    var settled = result.conflicts.isEmpty;
    if (!settled && settle != null) settled = await settle(result);

    final mine = SyncPayload(
      deviceId: repo.deviceId,
      deviceName: deviceName,
      generatedAt: DateTime.now().toUtc(),
      events: await repo.allEventsForExport(),
    );
    wire.send({'t': 'merged', 'payload': mine.toJson()});

    final done = await wire.read(_stepTimeout);
    if (done['t'] != 'done') {
      throw const DirectSyncFailure('The other device did not finish.');
    }
    final changedThere = done['applied'];
    await wire.close();
    return DirectSyncOutcome(
      peerId: peer.deviceId,
      peerName: peer.name,
      changedHere: result.totalApplied +
          (settled ? result.conflicts.length : 0),
      changedThere: changedThere is int ? changedThere : null,
      unsettled: settled ? null : result,
    );
  } catch (_) {
    await wire.abandon();
    rethrow;
  }
}

/// Answers one incoming connection as the listening device.
///
/// With [busy], only says so and hangs up. Completes with null when no
/// sync took place (busy, or called off by an older version), and throws
/// if the caller is not a paired device or the exchange breaks. Records
/// the caller's address, so this device can reach it next time.
Future<DirectSyncOutcome?> serveSync({
  required SecureSocket socket,
  required EventRepository repo,
  required String deviceName,
  required PeerRepository peers,
  bool busy = false,
}) async {
  // Until the caller has proved who it is, it gets to send very little.
  final wire =
      Wire(socket, limit: _maxHelloBytes, failure: DirectSyncFailure.new);
  try {
    if (busy) {
      // Read the greeting first: hanging up on unread data can make the
      // connection reset before "busy" is read at the other end.
      try {
        await wire.read(_stepTimeout);
      } catch (_) {
        // Whatever it was, the answer is the same.
      }
      wire.send({'t': 'busy'});
      await wire.close();
      return null;
    }

    final hello = await wire.read(_stepTimeout);
    final id = hello['id'];
    final secret = hello['secret'];
    if (hello['t'] != 'sync' ||
        hello['v'] != 1 ||
        id is! String ||
        secret is! String) {
      throw const DirectSyncFailure('Not a sync this version understands.');
    }

    PairedDevice? peer;
    for (final device in await peers.all()) {
      if (device.deviceId == id) peer = device;
    }
    List<int> offered;
    try {
      offered = base64.decode(secret);
    } on FormatException {
      offered = const [];
    }
    if (peer == null || !sameBytes(offered, peer.secret)) {
      wire.send({'t': 'refused'});
      await wire.close();
      throw const DirectSyncFailure(
          'A device that is not paired tried to sync.');
    }
    wire.limit = _maxSyncBytes;
    final String callerAddress = socket.remoteAddress.address;

    final sent = SyncPayload(
      deviceId: repo.deviceId,
      deviceName: deviceName,
      generatedAt: DateTime.now().toUtc(),
      events: await repo.allEventsForExport(),
    );
    wire.send({'t': 'payload', 'payload': sent.toJson()});

    // The other device's user may be looking at conflicts now.
    final next = await wire.read(_decisionTimeout);
    if (next['t'] != 'merged') {
      await wire.close();
      return null;
    }
    final merged = _payload(next, 'merged');
    if (merged.deviceId != peer.deviceId) {
      throw const DirectSyncFailure('The other device changed its identity.');
    }

    final applied = await acceptMerged(repo, merged);
    wire.send({'t': 'done', 'applied': applied});
    await wire.close();
    // A device listens on the usual port, so its address alone will do.
    await peers.setAddress(peer.deviceId, callerAddress);
    return DirectSyncOutcome(
      peerId: peer.deviceId,
      peerName: peer.name,
      changedHere: applied,
    );
  } catch (_) {
    await wire.abandon();
    rethrow;
  }
}

const Duration _stepTimeout = Duration(seconds: 30);
const Duration _decisionTimeout = Duration(minutes: 10);
const int _maxHelloBytes = 4 * 1024;
const int _maxSyncBytes = 64 * 1024 * 1024;

SyncPayload _payload(Map<String, Object?> message, String type) {
  final body = message['payload'];
  if (message['t'] != type || body is! Map) {
    throw const DirectSyncFailure(
        'The other device sent something unexpected.');
  }
  try {
    return SyncPayload.fromJson(body.cast<String, Object?>());
  } catch (_) {
    throw const DirectSyncFailure(
        'The other device sent something unexpected.');
  }
}
