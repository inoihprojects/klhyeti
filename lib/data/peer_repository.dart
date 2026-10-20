import 'dart:convert';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../sync/tls_identity.dart';

/// A device this one has been paired with.
class PairedDevice {
  final String deviceId;
  final String name;

  /// Its TLS certificate. When this device connects to it, no other
  /// certificate is accepted.
  final Uint8List certDer;

  /// 32 random bytes both devices hold. The connecting device sends them
  /// inside the encrypted connection to prove which device it is.
  final Uint8List secret;

  /// Where it was last reached, as "192.168.1.20" or with ":port". Only a
  /// first guess for the next sync: addresses on a local network change.
  final String? address;

  const PairedDevice({
    required this.deviceId,
    required this.name,
    required this.certDer,
    required this.secret,
    this.address,
  });
}

/// Pairing data in the local database: this device's own TLS identity and
/// the devices it has been paired with. None of it is ever synced.
class PeerRepository {
  final Database _db;

  PeerRepository(this._db);

  /// This device's certificate and key, made on first use.
  Future<TlsIdentity> identity() async {
    final rows = await _db.query('tls_identity', limit: 1);
    if (rows.isNotEmpty) {
      return TlsIdentity(
        certPem: rows.first['cert_pem']! as String,
        keyPem: rows.first['key_pem']! as String,
      );
    }
    final created = TlsIdentity.generate();
    await _db.insert(
      'tls_identity',
      {'id': 1, 'cert_pem': created.certPem, 'key_pem': created.keyPem},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return created;
  }

  Future<List<PairedDevice>> all() async {
    final rows = await _db.query('paired_devices', orderBy: 'name ASC');
    return [
      for (final row in rows)
        PairedDevice(
          deviceId: row['device_id']! as String,
          name: row['name']! as String,
          certDer: base64.decode(row['cert']! as String),
          secret: base64.decode(row['secret']! as String),
          address: row['address'] as String?,
        ),
    ];
  }

  /// Pairing again with a device already known replaces what was stored.
  Future<void> save(PairedDevice device) async {
    await _db.insert(
      'paired_devices',
      {
        'device_id': device.deviceId,
        'name': device.name,
        'cert': base64.encode(device.certDer),
        'secret': base64.encode(device.secret),
        'address': device.address,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> setAddress(String deviceId, String address) async {
    await _db.update(
      'paired_devices',
      {'address': address},
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
  }

  Future<void> remove(String deviceId) async {
    await _db.delete(
      'paired_devices',
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
  }
}
