// Pairing, end to end, between two "devices" in one process talking TLS
// over the loopback address. Nothing leaves the machine running the test.
//
// This is also the only place the hand-written certificate encoding in
// tls_identity.dart meets a real TLS library: if a byte of it were wrong,
// the handshake below would fail.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:klhyeti/models/revision.dart' show randomBytes;
import 'package:klhyeti/sync/lan_address.dart';
import 'package:klhyeti/sync/pairing.dart';
import 'package:klhyeti/sync/tls_identity.dart';

class _Pair {
  final PairingSession phone;
  final PairingSession desk;
  final TlsIdentity phoneIdentity;
  final TlsIdentity deskIdentity;
  _Pair(this.phone, this.desk, this.phoneIdentity, this.deskIdentity);
}

/// The desk listens, the phone connects, and both get as far as showing
/// the code.
Future<_Pair> startPairing() async {
  final deskIdentity = TlsIdentity.generate();
  final phoneIdentity = TlsIdentity.generate();

  final server = await SecureServerSocket.bind(
    InternetAddress.loopbackIPv4,
    0,
    deskIdentity.serverContext(),
  );
  final int port = server.port;
  final deskSide = server.first.then(
    (socket) => PairingSession.accept(
      socket,
      deviceId: 'desk-id',
      deviceName: 'Desk',
      ownCert: deskIdentity.certDer,
    ),
  );

  final socket = await SecureSocket.connect(
    InternetAddress.loopbackIPv4,
    port,
    context: SecurityContext(withTrustedRoots: false),
    onBadCertificate: (_) => true,
  );
  final phone = await PairingSession.connect(
    socket,
    deviceId: 'phone-id',
    deviceName: 'Phone',
    ownCert: phoneIdentity.certDer,
  );
  return _Pair(phone, await deskSide, phoneIdentity, deskIdentity);
}

void main() {
  test('only private IPv4 addresses count as the local network', () {
    for (final ok in [
      '10.0.0.5',
      '172.16.0.1',
      '172.31.255.254',
      '192.168.1.20',
      '169.254.10.10',
      '127.0.0.1',
    ]) {
      expect(isPrivateLanAddress(InternetAddress(ok)), isTrue, reason: ok);
    }
    for (final no in [
      '8.8.8.8',
      '172.15.0.1',
      '172.32.0.1',
      '192.169.1.1',
      '100.64.0.1',
      '::1',
      'fe80::1',
    ]) {
      expect(isPrivateLanAddress(InternetAddress(no)), isFalse, reason: no);
    }
  });

  test('a typed address is accepted only if private and numeric', () {
    final plain = parseLanEndpoint(' 192.168.1.20 ')!;
    expect(plain.address.address, '192.168.1.20');
    expect(plain.port, defaultSyncPort);

    expect(parseLanEndpoint('192.168.1.20:5000')!.port, 5000);

    expect(parseLanEndpoint('8.8.8.8'), isNull);
    expect(parseLanEndpoint('example.com'), isNull);
    expect(parseLanEndpoint('192.168.1.20:0'), isNull);
    expect(parseLanEndpoint('192.168.1.20:99999'), isNull);
    expect(parseLanEndpoint(''), isNull);
  });

  test('each device gets its own certificate, and it says nothing', () {
    final a = TlsIdentity.generate();
    final b = TlsIdentity.generate();
    expect(a.certDer, isNot(equals(b.certDer)));
    expect(a.keyPem, isNot(equals(b.keyPem)));
    expect(a.certPem, startsWith('-----BEGIN CERTIFICATE-----\n'));
    expect(a.keyPem, startsWith('-----BEGIN PRIVATE KEY-----\n'));
  });

  test('two devices pair over TLS and agree on the code', () async {
    final pair = await startPairing();

    expect(pair.phone.code, matches(RegExp(r'^[0-9A-F]{6}$')));
    expect(pair.phone.code, pair.desk.code);
    expect(pair.phone.peerName, 'Desk');
    expect(pair.phone.peerId, 'desk-id');
    expect(pair.desk.peerName, 'Phone');
    expect(pair.desk.peerId, 'phone-id');

    final results = await Future.wait([
      pair.phone.confirm(),
      pair.desk.confirm(),
    ]);
    final onPhone = results[0]!;
    final onDesk = results[1]!;

    // Each ends up holding the other's certificate and the same secret.
    expect(onPhone.deviceId, 'desk-id');
    expect(onPhone.certDer, pair.deskIdentity.certDer);
    expect(onDesk.deviceId, 'phone-id');
    expect(onDesk.certDer, pair.phoneIdentity.certDer);
    expect(onPhone.secret, hasLength(32));
    expect(onPhone.secret, onDesk.secret);
  });

  test('if one user says the codes differ, neither device is paired',
      () async {
    final pair = await startPairing();

    final onDesk = pair.desk.confirm();
    await pair.phone.cancel();

    expect(await onDesk, isNull);
  });

  test('the code depends on every part that goes into it', () {
    final a = randomBytes(40);
    final b = randomBytes(40);
    final n1 = randomBytes(32);
    final n2 = randomBytes(32);
    final code = pairingCode(
      listenerCert: a,
      connectorCert: b,
      connectorNonce: n1,
      listenerNonce: n2,
    );
    expect(code, matches(RegExp(r'^[0-9A-F]{6}$')));
    // The same inputs give the same code...
    expect(
      pairingCode(
        listenerCert: a,
        connectorCert: b,
        connectorNonce: n1,
        listenerNonce: n2,
      ),
      code,
    );
    // ...and at least one of four different swaps changes it. (Any single
    // one has a 1 in 16.8 million chance of landing on the same six
    // characters, which would make a stricter test fail at random.)
    final others = {
      pairingCode(
          listenerCert: b,
          connectorCert: a,
          connectorNonce: n1,
          listenerNonce: n2),
      pairingCode(
          listenerCert: a,
          connectorCert: b,
          connectorNonce: n2,
          listenerNonce: n1),
      pairingCode(
          listenerCert: a,
          connectorCert: a,
          connectorNonce: n1,
          listenerNonce: n2),
      pairingCode(
          listenerCert: a,
          connectorCert: b,
          connectorNonce: n1,
          listenerNonce: n1),
    };
    expect(others.length > 1 || !others.contains(code), isTrue);
  });
}
