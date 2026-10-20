import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

import '../models/revision.dart' show randomBytes;

/// This device's TLS certificate and private key, made once on the device
/// and never sent anywhere except, for the certificate, to a device being
/// paired.
///
/// Direct sync runs over TLS from `dart:io`. TLS needs a certificate, and
/// with no authority to issue one each device signs its own. A paired
/// device remembers the exact certificate and accepts no other, so what
/// the certificate *says* is irrelevant: it names nobody and carries no
/// date of creation. Every device's reads "klhyeti", valid 2000 to 2099.
class TlsIdentity {
  final String certPem;
  final String keyPem;

  const TlsIdentity({required this.certPem, required this.keyPem});

  /// The certificate as raw bytes: what a paired device stores and
  /// compares against.
  Uint8List get certDer => pemToDer(certPem);

  /// A context for accepting connections as this device.
  SecurityContext serverContext() {
    return SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(certPem))
      ..usePrivateKeyBytes(utf8.encode(keyPem));
  }

  /// Makes a new P-256 key and a certificate signed with it.
  ///
  /// The key generation and the signature come from pointycastle; the
  /// X.509 and PKCS#8 wrapping around them is written out by hand below,
  /// byte for byte, because it is short and fixed and the alternative was
  /// a package that pulls an HTTP client in with it.
  static TlsIdentity generate() {
    final random = pc.FortunaRandom()..seed(pc.KeyParameter(randomBytes(32)));

    final generator = pc.ECKeyGenerator()
      ..init(pc.ParametersWithRandom(
        pc.ECKeyGeneratorParameters(pc.ECCurve_prime256v1()),
        random,
      ));
    final pair = generator.generateKeyPair();
    final pc.ECPrivateKey privateKey = pair.privateKey;
    final pc.ECPublicKey publicKey = pair.publicKey;

    // 0x04, then X and Y: 65 bytes.
    final Uint8List point = publicKey.Q!.getEncoded(false);
    final List<int> publicBits = _tlv(0x03, [0, ...point]);
    final List<int> keyAlgorithm = _seq([_oidEcPublicKey, _oidPrime256v1]);
    final List<int> signatureAlgorithm = _seq([_oidEcdsaSha256]);

    final List<int> name = _seq([
      _tlv(0x31, _seq([_oidCommonName, _tlv(0x0C, utf8.encode('klhyeti'))])),
    ]);
    final Uint8List serialBytes = randomBytes(8);
    serialBytes[0] = (serialBytes[0] & 0x7f) | 0x01; // positive, never zero
    final List<int> serial = _tlv(0x02, serialBytes);
    final List<int> validity = _seq([
      _tlv(0x17, ascii.encode('000101000000Z')),
      _tlv(0x18, ascii.encode('20991231235959Z')),
    ]);

    final Uint8List toBeSigned = Uint8List.fromList(_seq([
      _tlv(0xA0, _integer(BigInt.two)), // version 3
      serial,
      signatureAlgorithm,
      name, // issuer
      validity,
      name, // subject: the same, it signs itself
      _seq([keyAlgorithm, publicBits]),
    ]));

    final signer = pc.ECDSASigner(pc.SHA256Digest())
      ..init(
        true,
        pc.ParametersWithRandom(
          pc.PrivateKeyParameter<pc.ECPrivateKey>(privateKey),
          random,
        ),
      );
    final signature = signer.generateSignature(toBeSigned) as pc.ECSignature;
    final List<int> signatureBits = _tlv(0x03, [
      0,
      ..._seq([_integer(signature.r), _integer(signature.s)]),
    ]);

    final List<int> certificate =
        _seq([toBeSigned, signatureAlgorithm, signatureBits]);

    final List<int> key = _seq([
      _integer(BigInt.zero),
      keyAlgorithm,
      _tlv(
        0x04,
        _seq([
          _integer(BigInt.one),
          _tlv(0x04, _fixedBytes(privateKey.d!, 32)),
          _tlv(0xA1, publicBits),
        ]),
      ),
    ]);

    return TlsIdentity(
      certPem: _pem('CERTIFICATE', certificate),
      keyPem: _pem('PRIVATE KEY', key),
    );
  }
}

/// The bytes inside a PEM block.
Uint8List pemToDer(String pem) {
  final body = pem
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('-----'))
      .join();
  return base64.decode(body);
}

String _pem(String label, List<int> der) {
  final encoded = base64.encode(der);
  final buffer = StringBuffer('-----BEGIN $label-----\n');
  for (var i = 0; i < encoded.length; i += 64) {
    final end = i + 64 < encoded.length ? i + 64 : encoded.length;
    buffer.write(encoded.substring(i, end));
    buffer.write('\n');
  }
  buffer.write('-----END $label-----\n');
  return buffer.toString();
}

// --- DER, the little of it a certificate needs ------------------------

// Object identifiers, already encoded (tag 0x06 and length included).
const List<int> _oidEcdsaSha256 = [
  0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x02, //
];
const List<int> _oidEcPublicKey = [
  0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01, //
];
const List<int> _oidPrime256v1 = [
  0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, //
];
const List<int> _oidCommonName = [0x06, 0x03, 0x55, 0x04, 0x03];

/// Tag, length, value. Nothing here is longer than 65535 bytes.
List<int> _tlv(int tag, List<int> content) {
  final int length = content.length;
  return [
    tag,
    if (length < 0x80)
      length
    else if (length < 0x100) ...[0x81, length]
    else ...[0x82, length >> 8, length & 0xff],
    ...content,
  ];
}

List<int> _seq(List<List<int>> parts) {
  return _tlv(0x30, [for (final part in parts) ...part]);
}

/// A non-negative INTEGER: big-endian, as short as possible, with a
/// leading zero when the top bit would otherwise read as a minus sign.
List<int> _integer(BigInt value) {
  final bytes = _fixedBytes(value, 0);
  return _tlv(0x02, [if ((bytes[0] & 0x80) != 0) 0, ...bytes]);
}

/// [value] big-endian, left-padded with zeros to at least [length] bytes.
List<int> _fixedBytes(BigInt value, int length) {
  var hex = value.toRadixString(16);
  if (hex.length.isOdd) hex = '0$hex';
  final bytes = <int>[
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
  return [
    for (var i = bytes.length; i < length; i++) 0,
    ...bytes,
  ];
}
