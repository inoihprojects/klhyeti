// Direct sync, end to end: two in-memory databases standing in for a
// phone and a desk computer, paired by hand, syncing over TLS on the
// loopback address. The phone connects; the desk listens.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show inMemoryDatabasePath;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:klhyeti/data/event_repository.dart';
import 'package:klhyeti/data/peer_repository.dart';
import 'package:klhyeti/models/calendar_event.dart';
import 'package:klhyeti/models/revision.dart';
import 'package:klhyeti/sync/direct_sync.dart';
import 'package:klhyeti/sync/lan_address.dart';
import 'package:klhyeti/sync/sync_payload.dart';
import 'package:klhyeti/sync/sync_reconciler.dart';
import 'package:klhyeti/sync/sync_service.dart';
import 'package:klhyeti/sync/tls_identity.dart';

final DateTime day = DateTime(2026, 10, 7);

class Devices {
  final EventRepository phone;
  final EventRepository desk;
  final PeerRepository phonePeers;
  final PeerRepository deskPeers;
  final TlsIdentity deskIdentity;

  Devices(this.phone, this.desk, this.phonePeers, this.deskPeers,
      this.deskIdentity);

  /// What pairing would have left behind on both.
  static Future<Devices> paired() async {
    final phone = EventRepository();
    await phone.init(dbPath: inMemoryDatabasePath, singleInstance: false);
    final desk = EventRepository();
    await desk.init(dbPath: inMemoryDatabasePath, singleInstance: false);
    final phonePeers = PeerRepository(phone.database);
    final deskPeers = PeerRepository(desk.database);
    final phoneIdentity = await phonePeers.identity();
    final deskIdentity = await deskPeers.identity();
    final secret = randomBytes(32);
    await phonePeers.save(PairedDevice(
      deviceId: desk.deviceId,
      name: 'Desk',
      certDer: deskIdentity.certDer,
      secret: secret,
    ));
    await deskPeers.save(PairedDevice(
      deviceId: phone.deviceId,
      name: 'Phone',
      certDer: phoneIdentity.certDer,
      secret: secret,
    ));
    return Devices(phone, desk, phonePeers, deskPeers, deskIdentity);
  }

  /// One sync session. Returns what each side made of it: the phone's
  /// outcome, then the desk's.
  Future<(DirectSyncOutcome, DirectSyncOutcome?)> sync({
    Future<bool> Function(ReconcileResult result)? settle,
    bool deskBusy = false,
  }) async {
    final server = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      deskIdentity.serverContext(),
    );
    final int port = server.port;
    // The desk's failure is caught here, the moment it happens. Left
    // until the phone's side has finished, it would count as an error
    // nobody handled, and fail the test even when that failure was the
    // point of it (a refused secret).
    Object? deskError;
    final deskSide = server.first
        .then(
          (socket) => serveSync(
            socket: socket,
            repo: desk,
            deviceName: 'Desk',
            peers: deskPeers,
            busy: deskBusy,
          ),
        )
        .then<DirectSyncOutcome?>(
          (outcome) => outcome,
          onError: (Object error) {
            deskError = error;
            return null;
          },
        );
    final onPhone = await syncWithPeer(
      repo: phone,
      deviceName: 'Phone',
      peer: (await phonePeers.all()).single,
      endpoint: LanEndpoint(InternetAddress.loopbackIPv4, port),
      settle: settle,
    );
    final onDesk = await deskSide;
    final failed = deskError;
    if (failed != null) throw failed;
    return (onPhone, onDesk);
  }

  Future<String> titleOn(EventRepository repo) async =>
      (await repo.eventsForDay(day)).single.title;

  /// One event both devices hold, then edited differently on each.
  Future<void> makeConflict() async {
    await phone.createEvent(
      title: 'Lunch',
      startAt: DateTime(2026, 10, 7, 12),
      endAt: DateTime(2026, 10, 7, 13),
    );
    await sync();
    for (final (repo, title) in [
      (phone, 'Lunch (phone)'),
      (desk, 'Lunch (desk)'),
    ]) {
      final event = (await repo.eventsForDay(day)).single;
      await repo.updateEvent(
        event,
        title: title,
        startAt: event.startAt,
        endAt: event.endAt,
        allDay: false,
      );
    }
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('each device ends up with the other\'s new events', () async {
    final d = await Devices.paired();
    await d.phone.createEvent(
      title: 'From the phone',
      startAt: DateTime(2026, 10, 7, 9),
      endAt: DateTime(2026, 10, 7, 10),
    );
    await d.desk.createEvent(
      title: 'From the desk',
      startAt: DateTime(2026, 10, 7, 14),
      endAt: DateTime(2026, 10, 7, 15),
    );

    final (onPhone, onDesk) = await d.sync();

    expect(onPhone.unsettled, isNull);
    expect(onPhone.changedHere, 1);
    expect(onPhone.changedThere, 1);
    expect(onDesk!.changedHere, 1);
    for (final repo in [d.phone, d.desk]) {
      final titles = (await repo.eventsForDay(day)).map((e) => e.title);
      expect(titles, ['From the phone', 'From the desk']);
    }

    // A second sync finds nothing to do.
    final (again, _) = await d.sync();
    expect(again.changedHere, 0);
    expect(again.changedThere, 0);
  });

  test('a conflict settled on the connecting device reaches the other',
      () async {
    final d = await Devices.paired();
    await d.makeConflict();

    final (onPhone, _) = await d.sync(settle: (result) async {
      expect(result.conflicts, hasLength(1));
      final conflict = result.conflicts.single;
      // What the conflict screen does for "keep this device's".
      await d.phone
          .resolveConflict(keep: conflict.local, other: conflict.incoming);
      return true;
    });

    expect(onPhone.unsettled, isNull);
    expect(await d.titleOn(d.phone), 'Lunch (phone)');
    expect(await d.titleOn(d.desk), 'Lunch (phone)');

    // And it stays settled.
    final (again, _) = await d.sync();
    expect(again.unsettled, isNull);
    expect(await d.titleOn(d.desk), 'Lunch (phone)');
  });

  test('an automatic sync leaves conflicts for later, and syncs the rest',
      () async {
    final d = await Devices.paired();
    await d.makeConflict();
    await d.phone.createEvent(
      title: 'Unrelated',
      startAt: DateTime(2026, 10, 8, 9),
      endAt: DateTime(2026, 10, 8, 10),
    );

    // No settle: nobody is there to ask.
    final (onPhone, onDesk) = await d.sync();

    expect(onPhone.unsettled!.conflicts, hasLength(1));
    expect(onDesk!.changedHere, 1); // the unrelated event
    expect(await d.titleOn(d.phone), 'Lunch (phone)');
    expect(await d.titleOn(d.desk), 'Lunch (desk)');
    expect(
      (await d.desk.eventsForDay(DateTime(2026, 10, 8))).single.title,
      'Unrelated',
    );

    // Settled later, keeping the desk's version this time.
    await d.sync(settle: (result) async {
      final conflict = result.conflicts.single;
      await d.phone
          .resolveConflict(keep: conflict.incoming, other: conflict.local);
      return true;
    });
    expect(await d.titleOn(d.phone), 'Lunch (desk)');
    expect(await d.titleOn(d.desk), 'Lunch (desk)');
  });

  test('a busy device says so, and nothing changes', () async {
    final d = await Devices.paired();
    await d.phone.createEvent(
      title: 'Waiting',
      startAt: DateTime(2026, 10, 7, 9),
      endAt: DateTime(2026, 10, 7, 10),
    );

    await expectLater(
      d.sync(deskBusy: true),
      throwsA(isA<DirectSyncBusy>()),
    );
    expect(await d.desk.eventsForDay(day), isEmpty);
  });

  test('a device with the wrong secret is refused and learns nothing',
      () async {
    final d = await Devices.paired();
    await d.desk.createEvent(
      title: 'Private',
      startAt: DateTime(2026, 10, 7, 9),
      endAt: DateTime(2026, 10, 7, 10),
    );
    final known = (await d.phonePeers.all()).single;
    await d.phonePeers.save(PairedDevice(
      deviceId: known.deviceId,
      name: known.name,
      certDer: known.certDer,
      secret: randomBytes(32),
    ));

    await expectLater(d.sync(), throwsA(isA<DirectSyncFailure>()));
    expect(await d.phone.eventsForDay(day), isEmpty);
  });

  test('a device showing the wrong certificate is not talked to',
      () async {
    final d = await Devices.paired();
    // Something else is listening where the desk used to be.
    final impostor = TlsIdentity.generate();
    final server = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      impostor.serverContext(),
    );
    final accepted = server.listen((socket) => socket.destroy(),
        onError: (Object _) {});

    await expectLater(
      syncWithPeer(
        repo: d.phone,
        deviceName: 'Phone',
        peer: (await d.phonePeers.all()).single,
        endpoint: LanEndpoint(InternetAddress.loopbackIPv4, server.port),
      ),
      throwsA(isA<TlsException>()),
    );
    await accepted.cancel();
    await server.close();
  });

  test('the listening device remembers where the caller is', () async {
    final d = await Devices.paired();
    await d.sync();
    expect((await d.deskPeers.all()).single.address, '127.0.0.1');
  });

  test('an event edited during a sync is not overwritten by it', () async {
    final desk = EventRepository();
    await desk.init(dbPath: inMemoryDatabasePath, singleInstance: false);
    await desk.createEvent(
      title: 'Call',
      startAt: DateTime(2026, 10, 7, 16),
      endAt: DateTime(2026, 10, 7, 17),
    );
    final original = (await desk.eventsForDay(day)).single;

    // The other device comes back with an edit made on top of it...
    final CalendarEvent theirs = original.copyWith(
      title: 'Call (their edit)',
      originDeviceId: 'other',
      rev: newRevision(),
      history: original.historyForNextEdit(),
    );
    final merged = SyncPayload(
      deviceId: 'other',
      generatedAt: DateTime.now().toUtc(),
      events: [theirs],
    );

    // ...but meanwhile it was edited again here.
    await desk.updateEvent(
      original,
      title: 'Call (edited mid-sync)',
      startAt: original.startAt,
      endAt: original.endAt,
      allDay: false,
    );

    expect(await acceptMerged(desk, merged), 0);
    expect((await desk.eventsForDay(day)).single.title,
        'Call (edited mid-sync)');

    // Without that edit, their version is simply taken.
    final fresh = EventRepository();
    await fresh.init(dbPath: inMemoryDatabasePath, singleInstance: false);
    await fresh.applyIncoming(original);
    expect(await acceptMerged(fresh, merged), 1);
    expect((await fresh.eventsForDay(day)).single.title, 'Call (their edit)');
  });

  test('a sync report reads as a sentence', () {
    expect(const SyncReport(alreadyRunning: true).describe(),
        'A sync is already running.');
    expect(
      const SyncReport(unreachable: ['Phone', 'Laptop', 'Tablet']).describe(),
      'Couldn\'t reach "Phone", "Laptop" and "Tablet": Klhyeti has to be '
      'open there, on the same network.',
    );
    expect(const SyncReport().describe(), 'Nothing to sync with.');
  });
}
