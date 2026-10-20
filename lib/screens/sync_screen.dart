import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../data/event_repository.dart';
import '../data/peer_repository.dart';
import '../data/settings_repository.dart';
import '../sync/direct_sync.dart';
import '../sync/file_sync_service.dart';
import '../sync/lan_address.dart';
import '../sync/sync_reconciler.dart';
import '../sync/sync_service.dart';
import '../theme/tokens.dart';
import 'conflict_resolution_screen.dart';
import 'pair_screen.dart';

/// Managing sync (Settings → Sync): paired devices, pairing, syncing with
/// one device at a typed address, and the sync file.
class SyncScreen extends StatefulWidget {
  final EventRepository repo;
  final SettingsRepository settings;
  final SyncService sync;

  const SyncScreen({
    super.key,
    required this.repo,
    required this.settings,
    required this.sync,
  });

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  late final FileSyncService _fileSync = FileSyncService(widget.repo);
  PeerRepository get _peers => widget.sync.peers;

  List<PairedDevice> _paired = const [];
  bool _working = false;

  bool get _busy => _working || widget.sync.busy;

  @override
  void initState() {
    super.initState();
    widget.sync.addListener(_redraw);
    _loadPaired();
  }

  @override
  void dispose() {
    widget.sync.removeListener(_redraw);
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  Future<void> _loadPaired() async {
    final paired = await _peers.all();
    if (!mounted) return;
    setState(() => _paired = paired);
  }

  void _setWorking(bool value) {
    if (mounted) setState(() => _working = value);
  }

  String _events(int count) => count == 1 ? '1 event' : '$count events';

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final body = TextStyle(fontSize: 14, color: c.ink2, height: 1.45);
    final sync = widget.sync;
    final String listening;
    if (_paired.isEmpty) {
      listening = '';
    } else if (!sync.listening) {
      listening = 'Not listening for syncs just now. This device can still '
          'start one.';
    } else if (sync.addresses.isEmpty) {
      listening = 'Paired devices can sync with this one while Klhyeti is '
          'open.';
    } else {
      listening = 'Paired devices can sync with this one at '
          '${sync.addresses.join(' or ')} while Klhyeti is open.';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Sync')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Insets.md),
          children: [
            Row(
              children: [
                Icon(Icons.link, size: 18, color: c.ink3),
                const SizedBox(width: Insets.sm),
                Expanded(
                  child: Text(
                    'This device is "${widget.settings.deviceName}"',
                    style: TextStyle(fontSize: 14, color: c.ink2),
                  ),
                ),
              ],
            ),
            if (listening.isNotEmpty) ...[
              const SizedBox(height: Insets.sm),
              Text(listening, style: body),
            ],
            _heading(c, 'Paired devices'),
            if (_paired.isEmpty)
              Text('None yet.', style: body)
            else
              for (final device in _paired)
                Padding(
                  padding: const EdgeInsets.only(bottom: Insets.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              device.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 15, color: c.ink),
                            ),
                            Text(
                              device.address ?? 'Address not known yet',
                              style: TextStyle(
                                fontSize: 13,
                                color: c.ink3,
                                fontFeatures: tabularFigures,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: _busy ? null : () => _unpair(device),
                        child: const Text('Remove'),
                      ),
                      const SizedBox(width: Insets.sm),
                      OutlinedButton(
                        onPressed: _busy ? null : () => _syncWith(device),
                        child: const Text('Sync'),
                      ),
                    ],
                  ),
                ),
            if (_paired.isNotEmpty) ...[
              Text(
                'The sync button on the calendar syncs with every paired '
                'device it can reach. Sync here to sync with one, or to '
                'give a new address when a device has moved.',
                style: body,
              ),
              const SizedBox(height: Insets.md),
            ],
            const SizedBox(height: Insets.sm),
            OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Pair a device'),
              onPressed: _busy ? null : _pair,
            ),
            _heading(c, 'Sync file'),
            Text(
              'For when the two devices can\'t reach each other. Export a '
              'sync file here and move it to your other device with '
              'LocalSend, Syncthing, a USB cable — anything. Then import it '
              'there.',
              style: body,
            ),
            const SizedBox(height: Insets.md),
            OutlinedButton.icon(
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('Export a sync file'),
              onPressed: _busy ? null : _export,
            ),
            const SizedBox(height: Insets.sm),
            OutlinedButton.icon(
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('Import a sync file'),
              onPressed: _busy ? null : _import,
            ),
          ],
        ),
      ),
    );
  }

  Widget _heading(KlhyetiColors c, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: Insets.lg, bottom: Insets.sm),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: c.ink3,
        ),
      ),
    );
  }

  void _say(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Shows the conflict screen; true once the user has settled them.
  Future<bool> _settle(ReconcileResult result) async {
    if (!mounted) return false;
    final settled = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ConflictResolutionScreen(
          repo: widget.repo,
          settings: widget.settings,
          result: result,
        ),
      ),
    );
    return settled == true;
  }

  // --- Paired devices ---------------------------------------------------

  Future<void> _pair() async {
    // The pairing screen listens on the same port.
    await widget.sync.pauseForPairing();
    if (!mounted) return;
    final name = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => PairScreen(
          repo: widget.repo,
          settings: widget.settings,
          peers: _peers,
        ),
      ),
    );
    await widget.sync.resumeAfterPairing();
    if (!mounted) return;
    if (name != null) _say('Paired with "$name".');
    await _loadPaired();
  }

  Future<void> _unpair(PairedDevice device) async {
    final bool? sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove "${device.name}"?'),
        content: const Text(
          'The two devices will no longer sync directly until they are '
          'paired again. No events are deleted. Remove this device on the '
          'other one as well.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    await _peers.remove(device.deviceId);
    await widget.sync.refresh();
    await _loadPaired();
  }

  /// Asks where [device] is. Null if the user backed out.
  Future<String?> _askAddress(PairedDevice device, String? known) {
    // Not disposed: the dialog is still animating away, and still showing
    // this text, for a moment after it returns.
    final controller = TextEditingController(text: known ?? '');
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Where is "${device.name}"?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Open Klhyeti\'s Sync screen on that device: its address is '
              'shown near the top.',
            ),
            const SizedBox(height: Insets.md),
            TextField(
              controller: controller,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(hintText: '192.168.1.20'),
              onSubmitted: (text) => Navigator.of(context).pop(text),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Sync'),
          ),
        ],
      ),
    );
  }

  Future<void> _syncWith(PairedDevice device) async {
    _setWorking(true);
    try {
      String? text = device.address;
      // First the address it was last reached at; if that fails, ask,
      // since addresses on a local network change.
      for (var attempt = 0; attempt < 2; attempt++) {
        if (!mounted) return;
        if (text == null || attempt == 1) {
          text = await _askAddress(device, text);
          if (!mounted || text == null) return;
        }
        final endpoint = parseLanEndpoint(text);
        if (endpoint == null) {
          _say('That is not an address on the local network.');
          return;
        }
        try {
          final outcome = await widget.sync.syncWith(
            device,
            endpoint,
            settle: _settle,
          );
          if (!mounted) return;
          final there = outcome.changedThere;
          if (outcome.unsettled != null) {
            _say('Synced with "${device.name}". Conflicts left for later.');
          } else if (outcome.changedHere == 0 && there == 0) {
            _say('"${device.name}" and this device already match.');
          } else {
            _say('Synced with "${device.name}": '
                '${_events(outcome.changedHere)} changed here'
                '${there == null ? '' : ', ${_events(there)} there'}.');
          }
          return;
        } on IOException catch (e) {
          // Nothing there, or something that isn't this device (a
          // HandshakeException: it showed the wrong certificate). Either
          // way the address is wrong, so ask once before giving up.
          if (attempt == 1) {
            if (mounted) {
              _say(e is HandshakeException
                  ? 'Something answered at that address, but it is not '
                      '"${device.name}". Nothing was sent.'
                  : 'Could not reach "${device.name}". Is Klhyeti open '
                      'there, on the same network?');
            }
            return;
          }
        }
      }
    } on TimeoutException {
      if (mounted) _say('"${device.name}" stopped answering.');
    } catch (e) {
      if (mounted) {
        _say(e is DirectSyncFailure ? e.message : 'Sync failed: $e');
      }
    } finally {
      _setWorking(false);
      await _loadPaired();
    }
  }

  // --- Sync file --------------------------------------------------------

  Future<void> _export() async {
    _setWorking(true);
    try {
      final path = await _fileSync.exportToFile(
        deviceName: widget.settings.deviceName,
      );
      if (!mounted || path == null) return;
      _say('Saved to $path');
    } catch (e) {
      if (!mounted) return;
      _say('Export failed: $e');
    } finally {
      _setWorking(false);
    }
  }

  Future<void> _import() async {
    _setWorking(true);
    try {
      final result = await _fileSync.importFromFile();
      if (!mounted || result == null) return;
      if (result.totalApplied > 0) widget.repo.markSynced();
      if (result.conflicts.isEmpty) {
        _say(
          'Synced: ${result.totalApplied} changed, '
          '${result.unchanged} unchanged.',
        );
      } else {
        final count = result.conflicts.length;
        final settled = await _settle(result);
        if (!mounted) return;
        final String what = count == 1 ? '1 conflict' : '$count conflicts';
        _say(
          settled
              ? 'Synced: $what settled.'
              : '$what left for later. Those events were not changed.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      _say('Import failed: $e');
    } finally {
      _setWorking(false);
    }
  }
}
