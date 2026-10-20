import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/event_repository.dart';
import '../data/peer_repository.dart';
import '../data/settings_repository.dart';
import 'direct_sync.dart';
import 'lan_address.dart';
import 'sync_reconciler.dart';

/// What one press of Sync, or one automatic sync, came to.
class SyncReport {
  final List<DirectSyncOutcome> synced;
  final List<String> unreachable;
  final List<String> failed;
  final bool alreadyRunning;

  const SyncReport({
    this.synced = const [],
    this.unreachable = const [],
    this.failed = const [],
    this.alreadyRunning = false,
  });

  /// One or two sentences for a snackbar.
  String describe() {
    if (alreadyRunning) return 'A sync is already running.';
    final parts = <String>[];
    if (synced.isNotEmpty) {
      parts.add('Synced with ${_names(synced.map((o) => o.peerName))}.');
    }
    final left = [
      for (final o in synced)
        if (o.unsettled != null) o.peerName,
    ];
    if (left.isNotEmpty) parts.add('Conflicts with ${_names(left)} left for later.');
    if (unreachable.isNotEmpty) {
      parts.add('Couldn\'t reach ${_names(unreachable)}: Klhyeti has to be '
          'open there, on the same network.');
    }
    parts.addAll(failed);
    return parts.isEmpty ? 'Nothing to sync with.' : parts.join(' ');
  }

  static String _names(Iterable<String> names) {
    final list = [for (final name in names) '"$name"'];
    if (list.length < 2) return list.join();
    return '${list.sublist(0, list.length - 1).join(', ')} and ${list.last}';
  }
}

/// Direct sync for the whole app, for as long as it runs.
///
/// While Klhyeti is open (on Android: in the foreground) and at least one
/// device is paired, it listens for syncs from paired devices. Nothing
/// else can sync with it: a caller must show the shared secret, and only
/// local network addresses are accepted.
///
/// [syncAll] syncs with every paired device it can reach, at the address
/// each was last seen at. With automatic sync on, that also happens when
/// the app opens and a few seconds after each change made on this device.
/// Automatic syncs never interrupt with the conflict screen: conflicts
/// are kept in [unsettledWith] for the calendar to point out.
///
/// One sync runs at a time. A device that is busy answers "busy", and the
/// caller lets go, waits a random moment and tries again, so two devices
/// that start at the same instant don't keep refusing each other.
class SyncService extends ChangeNotifier {
  final EventRepository repo;
  final SettingsRepository settings;
  final PeerRepository peers;

  SyncService({
    required this.repo,
    required this.settings,
    required this.peers,
  });

  SecureServerSocket? _server;
  StreamSubscription<SecureSocket>? _incoming;
  List<String> _addresses = const [];
  bool _starting = false;
  bool _active = false;
  bool _pausedForPairing = false;
  bool _busy = false;
  bool _autoSyncWasOn = false;
  Timer? _afterEdit;
  final Map<String, ReconcileResult> _unsettled = {};
  final Random _random = Random();

  static const Duration _editDelay = Duration(seconds: 4);
  static const Duration _connectTimeout = Duration(seconds: 4);

  bool get listening => _server != null;
  List<String> get addresses => _addresses;
  bool get busy => _busy;

  /// Devices with conflicts an automatic sync found and left, by name.
  List<String> get unsettledWith => [
        for (final result in _unsettled.values)
          result.peerDeviceName ?? 'another device',
      ];

  Future<void> start() async {
    _active = true;
    _autoSyncWasOn = settings.autoSync;
    repo.edits.addListener(_onLocalEdit);
    settings.addListener(_onSettingsChanged);
    await refresh();
    if (settings.autoSync) unawaited(syncAll());
  }

  @override
  void dispose() {
    _afterEdit?.cancel();
    repo.edits.removeListener(_onLocalEdit);
    settings.removeListener(_onSettingsChanged);
    _incoming?.cancel();
    _server?.close();
    super.dispose();
  }

  /// Android only: the app went to the background, or came back. A
  /// background app can't be relied on to keep a socket open, so it
  /// stops listening until it is back.
  Future<void> setActive(bool active) async {
    if (active == _active) return;
    _active = active;
    if (active) {
      await refresh();
      if (settings.autoSync) unawaited(syncAll());
    } else {
      _afterEdit?.cancel();
      await _stopListening();
      notifyListeners();
    }
  }

  /// Listens, or stops, to match the paired devices. Call after pairing
  /// or removing one.
  Future<void> refresh() async {
    final paired = await peers.all();
    if (paired.isEmpty || !_active || _pausedForPairing) {
      await _stopListening();
    } else {
      await _startListening();
    }
    notifyListeners();
  }

  /// The pairing screen listens on the same port while it is open.
  Future<void> pauseForPairing() async {
    _pausedForPairing = true;
    await _stopListening();
    notifyListeners();
  }

  Future<void> resumeAfterPairing() async {
    _pausedForPairing = false;
    await refresh();
  }

  /// Syncs with every paired device that answers. [settle], when given,
  /// is shown each device's conflicts in turn (the user pressed Sync and
  /// is there to answer); left out, conflicts wait.
  Future<SyncReport> syncAll({
    Future<bool> Function(ReconcileResult result)? settle,
  }) async {
    if (_busy) return const SyncReport(alreadyRunning: true);
    _setBusy(true);
    final synced = <DirectSyncOutcome>[];
    final unreachable = <String>[];
    final failed = <String>[];
    try {
      for (final peer in await peers.all()) {
        final String? address = peer.address;
        final endpoint = address == null ? null : parseLanEndpoint(address);
        if (endpoint == null) {
          unreachable.add(peer.name);
          continue;
        }
        try {
          synced.add(await _syncOne(peer, endpoint, settle));
        } on DirectSyncBusy {
          unreachable.add(peer.name);
        } on DirectSyncFailure catch (e) {
          failed.add('"${peer.name}": ${e.message}');
        } on IOException {
          unreachable.add(peer.name);
        } on TimeoutException {
          unreachable.add(peer.name);
        }
      }
    } finally {
      _setBusy(false);
    }
    return SyncReport(
      synced: synced,
      unreachable: unreachable,
      failed: failed,
    );
  }

  /// Syncs with one device at an address the user gave. Throws as
  /// [syncWithPeer] does, and [DirectSyncBusy] if a sync is already
  /// running here.
  Future<DirectSyncOutcome> syncWith(
    PairedDevice peer,
    LanEndpoint endpoint, {
    Future<bool> Function(ReconcileResult result)? settle,
  }) async {
    if (_busy) throw const DirectSyncBusy();
    _setBusy(true);
    try {
      final outcome = await _syncOne(peer, endpoint, settle);
      await peers.setAddress(peer.deviceId, _format(endpoint));
      return outcome;
    } finally {
      _setBusy(false);
    }
  }

  // --- Internals ----------------------------------------------------------

  void _setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }

  String _format(LanEndpoint endpoint) => endpoint.port == defaultSyncPort
      ? endpoint.address.address
      : '${endpoint.address.address}:${endpoint.port}';

  /// One device, with the busy-retry dance. Call with [_busy] set.
  Future<DirectSyncOutcome> _syncOne(
    PairedDevice peer,
    LanEndpoint endpoint,
    Future<bool> Function(ReconcileResult result)? settle,
  ) async {
    for (var attempt = 0;; attempt++) {
      try {
        final outcome = await syncWithPeer(
          repo: repo,
          deviceName: settings.deviceName,
          peer: peer,
          endpoint: endpoint,
          settle: settle,
          connectTimeout: _connectTimeout,
        );
        final unsettled = outcome.unsettled;
        if (unsettled == null) {
          _unsettled.remove(peer.deviceId);
        } else {
          _unsettled[peer.deviceId] = unsettled;
        }
        if (outcome.changedHere > 0) repo.markSynced();
        return outcome;
      } on DirectSyncBusy {
        if (attempt == 2) rethrow;
        // Both devices may have started at the same instant. Let go, so
        // the other's sync can come in, and try again a moment later.
        _setBusy(false);
        await Future<void>.delayed(
            Duration(milliseconds: 800 + _random.nextInt(2400)));
        while (_busy) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        _setBusy(true);
      }
    }
  }

  void _onLocalEdit() {
    if (!settings.autoSync || !_active) return;
    _afterEdit?.cancel();
    _afterEdit = Timer(_editDelay, _syncAfterEdit);
  }

  Future<void> _syncAfterEdit() async {
    final report = await syncAll();
    // Busy with another sync, which may have started before the edit:
    // try again shortly rather than let the edit wait for the next one.
    if (report.alreadyRunning) _onLocalEdit();
  }

  void _onSettingsChanged() {
    final on = settings.autoSync;
    if (on && !_autoSyncWasOn && _active) unawaited(syncAll());
    _autoSyncWasOn = on;
  }

  Future<void> _startListening() async {
    if (_server != null || _starting) return;
    _starting = true;
    try {
      final identity = await peers.identity();
      _addresses = await localLanAddresses();
      // The pairing screen lets go of the port a moment after it closes,
      // so the first tries can find it still taken.
      for (var attempt = 0;
          attempt < 6 && _server == null && _active && !_pausedForPairing;
          attempt++) {
        try {
          final server = await SecureServerSocket.bind(
            InternetAddress.anyIPv4,
            defaultSyncPort,
            identity.serverContext(),
          );
          if (!_active || _pausedForPairing) {
            await server.close();
            return;
          }
          _server = server;
          // A connection that fails its TLS handshake arrives as an error
          // on this stream; listening carries on.
          _incoming = server.listen(_onIncoming, onError: (Object _) {});
        } on SocketException {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
    } catch (_) {
      // Not listening is not fatal: this device can still start a sync.
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  Future<void> _stopListening() async {
    final incoming = _incoming;
    final server = _server;
    _incoming = null;
    _server = null;
    await incoming?.cancel();
    await server?.close();
  }

  Future<void> _onIncoming(SecureSocket socket) async {
    bool local;
    try {
      local = isPrivateLanAddress(socket.remoteAddress);
    } catch (_) {
      local = false;
    }
    if (!local) {
      socket.destroy();
      return;
    }
    if (_busy) {
      try {
        await serveSync(
          socket: socket,
          repo: repo,
          deviceName: settings.deviceName,
          peers: peers,
          busy: true,
        );
      } catch (_) {
        // It was told, or it went away; either way, nothing to do.
      }
      return;
    }
    _setBusy(true);
    try {
      final outcome = await serveSync(
        socket: socket,
        repo: repo,
        deviceName: settings.deviceName,
        peers: peers,
      );
      if (outcome != null && outcome.changedHere > 0) repo.markSynced();
    } catch (_) {
      // A failed incoming sync changes nothing here, and the device that
      // started it says so to its user.
    } finally {
      _setBusy(false);
    }
  }
}
