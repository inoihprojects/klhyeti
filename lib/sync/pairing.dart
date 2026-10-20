import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

import '../data/peer_repository.dart';
import '../models/revision.dart' show randomBytes;
import 'lan_address.dart';
import 'wire.dart';

/// Pairing: two devices that have never met agree, once, on who the other
/// is. Afterwards each holds the other's TLS certificate and a shared
/// secret, and sync connections are checked against both.
///
/// The connection is already encrypted by TLS when this starts, but with
/// nothing yet to check the certificate against, someone on the same
/// network could sit in the middle holding a connection to each side.
/// The six-character code closes that gap: it is worked out from both
/// certificates and a random number from each device, so the two screens
/// only agree if both devices are looking at the same connection.
///
/// The order of messages matters. The connecting device first sends only
/// a hash of its random number, and reveals the number after the other
/// device has sent its own. Neither side can then choose its number after
/// seeing the other's, which is what would let a device in the middle
/// hunt for numbers that make two different connections show one code.
///
///   connecting device                      listening device
///   pair: id, name, cert, hash(n1)  ->
///                                   <-  pair: id, name, n2
///   reveal: n1                      ->
///            both show the code; each user confirms
///   confirm: secret                 ->
///                                   <-  confirm
///
/// Messages are one JSON object per line.
class PairingSession {
  final SecureSocket _socket;
  final Wire _wire;
  final bool _connected; // true on the device that made the connection

  /// What both screens should show.
  final String code;
  final String peerId;
  final String peerName;
  final Uint8List peerCert;

  late final Future<Map<String, Object?>?> _peerAnswer;

  /// Where the other device can be reached for a sync later: read now,
  /// because a closed socket no longer knows.
  late final String? _peerAddress;

  PairingSession._(
    this._socket,
    this._wire,
    this._connected, {
    required this.code,
    required this.peerId,
    required this.peerName,
    required this.peerCert,
  }) {
    String? address;
    try {
      final host = _socket.remoteAddress.address;
      // The device that was connected to only sees the temporary port the
      // other one called from; assume it listens on the usual one.
      final port = _connected ? _socket.remotePort : defaultSyncPort;
      address = port == defaultSyncPort ? host : '$host:$port';
    } catch (_) {
      address = null; // it can be typed in when the first sync is made
    }
    _peerAddress = address;

    // Start listening for the other user's answer straight away: it may
    // come before this user has decided.
    _peerAnswer = _readAnswer();
  }

  /// Runs the exchange on the device that made the connection.
  static Future<PairingSession> connect(
    SecureSocket socket, {
    required String deviceId,
    required String deviceName,
    required Uint8List ownCert,
  }) async {
    final wire = Wire(socket, limit: _maxBytes, failure: PairingFailure.new);
    try {
      final Uint8List? peerCert = socket.peerCertificate?.der;
      if (peerCert == null) {
        throw const PairingFailure('The other device sent no certificate.');
      }
      final nonce = randomBytes(32);
      wire.send({
        't': 'pair',
        'v': 1,
        'id': deviceId,
        'name': deviceName,
        'cert': base64.encode(ownCert),
        'commit': base64.encode(_sha256(nonce)),
      });
      final reply = await wire.read(_stepTimeout);
      _expect(reply, 'pair');
      final peerNonce = _bytes(reply['nonce'], 32);
      final peerId = _text(reply['id']);
      if (peerId == deviceId) {
        throw const PairingFailure('That address is this device.');
      }
      wire.send({'t': 'reveal', 'nonce': base64.encode(nonce)});
      return PairingSession._(
        socket,
        wire,
        true,
        code: pairingCode(
          listenerCert: peerCert,
          connectorCert: ownCert,
          connectorNonce: nonce,
          listenerNonce: peerNonce,
        ),
        peerId: peerId,
        peerName: _text(reply['name']),
        peerCert: peerCert,
      );
    } catch (_) {
      await wire.abandon();
      rethrow;
    }
  }

  /// Runs the exchange on the device that was connected to.
  static Future<PairingSession> accept(
    SecureSocket socket, {
    required String deviceId,
    required String deviceName,
    required Uint8List ownCert,
  }) async {
    final wire = Wire(socket, limit: _maxBytes, failure: PairingFailure.new);
    try {
      final hello = await wire.read(_stepTimeout);
      _expect(hello, 'pair');
      final peerCert = _bytes(hello['cert'], null);
      final commitment = _bytes(hello['commit'], 32);
      final peerId = _text(hello['id']);
      if (peerId == deviceId) {
        throw const PairingFailure('That address is this device.');
      }
      final nonce = randomBytes(32);
      wire.send({
        't': 'pair',
        'v': 1,
        'id': deviceId,
        'name': deviceName,
        'nonce': base64.encode(nonce),
      });
      final reveal = await wire.read(_stepTimeout);
      _expect(reveal, 'reveal');
      final peerNonce = _bytes(reveal['nonce'], 32);
      if (!sameBytes(_sha256(peerNonce), commitment)) {
        throw const PairingFailure(
            'The other device did not follow the pairing steps.');
      }
      return PairingSession._(
        socket,
        wire,
        false,
        code: pairingCode(
          listenerCert: ownCert,
          connectorCert: peerCert,
          connectorNonce: peerNonce,
          listenerNonce: nonce,
        ),
        peerId: peerId,
        peerName: _text(hello['name']),
        peerCert: peerCert,
      );
    } catch (_) {
      await wire.abandon();
      rethrow;
    }
  }

  /// Call when this device's user says the codes match. Completes with
  /// the paired device once the other user has said the same, or with
  /// null if they declined, the codes were never confirmed in time, or
  /// the connection dropped. Nothing is stored here; the caller does it.
  Future<PairedDevice?> confirm() async {
    // The connecting device makes the secret, and sends it only now, when
    // its user has vouched for the connection.
    final Uint8List? ownSecret = _connected ? randomBytes(32) : null;
    try {
      _wire.send({
        't': 'confirm',
        if (ownSecret != null) 'secret': base64.encode(ownSecret),
      });
      await _socket.flush();
    } catch (_) {
      await _wire.abandon();
      return null;
    }

    final answer = await _peerAnswer;
    Uint8List? secret = ownSecret;
    if (answer != null && !_connected) {
      try {
        secret = _bytes(answer['secret'], 32);
      } on PairingFailure {
        secret = null;
      }
    }
    await _finish();
    if (answer == null || secret == null) return null;
    return PairedDevice(
      deviceId: peerId,
      name: peerName,
      certDer: peerCert,
      secret: secret,
      address: _peerAddress,
    );
  }

  /// Call when the user says the codes differ, or leaves.
  Future<void> cancel() async {
    try {
      _wire.send({'t': 'cancel'});
      await _socket.flush();
    } catch (_) {
      // Already gone; nothing to tell it.
    }
    await _finish();
  }

  Future<Map<String, Object?>?> _readAnswer() async {
    try {
      final message = await _wire.read(_decisionTimeout);
      return message['t'] == 'confirm' ? message : null;
    } catch (_) {
      // Closed, timed out or nonsense: each means "not paired".
      return null;
    }
  }

  /// A polite close, so the last message sent is delivered first.
  Future<void> _finish() => _wire.close();
}

class PairingFailure implements Exception {
  final String message;
  const PairingFailure(this.message);

  @override
  String toString() => message;
}

/// The six hexadecimal characters both screens show: 24 bits, so a
/// device in the middle has one chance in about 16.8 million of going
/// unnoticed, and one try per pairing the users attempt.
String pairingCode({
  required Uint8List listenerCert,
  required Uint8List connectorCert,
  required Uint8List connectorNonce,
  required Uint8List listenerNonce,
}) {
  final digest = _sha256([
    ...utf8.encode('klhyeti pairing v1'),
    for (final part in [
      listenerCert,
      connectorCert,
      connectorNonce,
      listenerNonce,
    ]) ...[
      // Each part's length first, so no two sets of parts run together
      // into the same bytes.
      (part.length >> 24) & 0xff,
      (part.length >> 16) & 0xff,
      (part.length >> 8) & 0xff,
      part.length & 0xff,
      ...part,
    ],
  ]);
  final int number = (digest[0] << 16) | (digest[1] << 8) | digest[2];
  return number.toRadixString(16).toUpperCase().padLeft(6, '0');
}

// A step of the exchange between two machines, and the time the two
// people have to compare the codes.
const Duration _stepTimeout = Duration(seconds: 20);
const Duration _decisionTimeout = Duration(minutes: 5);

// Pairing messages are a few hundred bytes. Anything connecting to the
// open port and sending more than this is not pairing.
const int _maxBytes = 16 * 1024;
const int _maxCertBytes = 4096;
const int _maxTextLength = 64;

Uint8List _sha256(List<int> data) {
  return pc.SHA256Digest().process(Uint8List.fromList(data));
}

void _expect(Map<String, Object?> message, String type) {
  if (message['t'] != type || (type == 'pair' && message['v'] != 1)) {
    throw const PairingFailure(
        'The other device is not a Klhyeti this version can pair with.');
  }
}

/// A base64 field of exactly [length] bytes, or, with no [length], of a
/// certificate's plausible size.
Uint8List _bytes(Object? value, int? length) {
  if (value is String && value.length <= _maxCertBytes * 2) {
    try {
      final bytes = base64.decode(value);
      final bool sized = length == null
          ? bytes.isNotEmpty && bytes.length <= _maxCertBytes
          : bytes.length == length;
      if (sized) return bytes;
    } on FormatException {
      // Falls through to the failure below.
    }
  }
  throw const PairingFailure('The other device sent something unexpected.');
}

String _text(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value.length <= _maxTextLength
        ? value
        : value.substring(0, _maxTextLength);
  }
  throw const PairingFailure('The other device sent something unexpected.');
}
