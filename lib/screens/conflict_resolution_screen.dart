import 'package:flutter/material.dart';

import '../data/event_repository.dart';
import '../data/settings_repository.dart';
import '../models/calendar_event.dart';
import '../sync/sync_reconciler.dart';
import '../theme/tokens.dart';
import '../widgets/event_list.dart' show formatTimeOfDay;
import '../widgets/tap_fade.dart';

/// Shown when a sync finds events that both devices changed since they
/// last agreed. Nothing is merged or guessed (ARCHITECTURE.md): the two
/// devices' versions sit side by side and the user picks.
///
/// The main choice is a whole device: "Keep newest" takes every conflict
/// from whichever device was edited most recently. "Choose manually"
/// starts from the same choice and lets single events be flipped.
///
/// Pops with `true` once the choices are written. Leaving any other way
/// changes nothing, and the same conflicts come back on the next sync.
class ConflictResolutionScreen extends StatefulWidget {
  final EventRepository repo;
  final SettingsRepository settings;
  final ReconcileResult result;

  const ConflictResolutionScreen({
    super.key,
    required this.repo,
    required this.settings,
    required this.result,
  });

  @override
  State<ConflictResolutionScreen> createState() =>
      _ConflictResolutionScreenState();
}

class _ConflictResolutionScreenState extends State<ConflictResolutionScreen> {
  late final List<SyncConflict> _conflicts = widget.result.conflicts;
  late final bool _localIsNewest = localIsNewest(_conflicts);

  /// One entry per conflict: true keeps this device's version.
  late final List<bool> _keepLocal =
      List<bool>.filled(_conflicts.length, _localIsNewest);

  bool _manual = false;
  bool _busy = false;

  String get _localName => widget.settings.deviceName;

  /// Sync files from before 0.3 carry no name, and two devices left on
  /// the default would both read "My phone".
  String get _peerName {
    final name = widget.result.peerDeviceName;
    if (name == null || name.isEmpty || name == _localName) {
      return 'Other device';
    }
    return name;
  }

  String _caption({required bool local}) {
    final parts = <String>[
      if (local) 'this device',
      if (local == _localIsNewest) 'newest',
      if (_manual) 'tap to keep all',
    ];
    if (parts.isEmpty) return '';
    final text = parts.join(' · ');
    return text[0].toUpperCase() + text.substring(1);
  }

  void _choose(int index, bool keepLocal) {
    setState(() => _keepLocal[index] = keepLocal);
  }

  void _chooseAll(bool keepLocal) {
    setState(() => _keepLocal.fillRange(0, _keepLocal.length, keepLocal));
  }

  void _toggleManual() {
    setState(() {
      _manual = !_manual;
      if (!_manual) {
        _keepLocal.fillRange(0, _keepLocal.length, _localIsNewest);
      }
    });
  }

  Future<void> _apply() async {
    setState(() => _busy = true);
    try {
      for (var i = 0; i < _conflicts.length; i++) {
        final conflict = _conflicts[i];
        await widget.repo.resolveConflict(
          keep: _keepLocal[i] ? conflict.local : conflict.incoming,
          other: _keepLocal[i] ? conflict.incoming : conflict.local,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not finish: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final count = _conflicts.length;
    final newestName = _localIsNewest ? _localName : _peerName;

    return Scaffold(
      appBar: AppBar(
        title: Text(count == 1 ? '1 conflict' : '$count conflicts'),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Insets.md, Insets.sm, Insets.md, Insets.md),
              child: Text(
                _manual
                    ? 'Tap the version of each event you want to keep, or a '
                        'device name to keep everything from it.'
                    : 'Both devices changed these events since they last '
                        'synced. Nothing changes until you choose.',
                style: TextStyle(fontSize: 14, color: c.ink2, height: 1.45),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.md),
              child: Row(
                children: [
                  Expanded(
                    child: _ColumnHeader(
                      name: _localName,
                      caption: _caption(local: true),
                      onTap: _manual && !_busy ? () => _chooseAll(true) : null,
                    ),
                  ),
                  const SizedBox(width: Insets.sm),
                  Expanded(
                    child: _ColumnHeader(
                      name: _peerName,
                      caption: _caption(local: false),
                      onTap:
                          _manual && !_busy ? () => _chooseAll(false) : null,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Insets.sm),
            const Divider(),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(Insets.md),
                itemCount: count,
                separatorBuilder: (_, __) => const SizedBox(height: Insets.sm),
                itemBuilder: (context, index) => _row(index),
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(Insets.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: _busy ? null : _apply,
                    child: Text(
                      _manual ? 'Keep selected' : 'Keep newest: $newestName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: Insets.xs),
                  TextButton(
                    onPressed: _busy ? null : _toggleManual,
                    child: Text(_manual ? 'Back to newest' : 'Choose manually'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(int index) {
    final conflict = _conflicts[index];
    final keepLocal = _keepLocal[index];
    final tappable = _manual && !_busy;
    // IntrinsicHeight so the two versions of one event are equally tall
    // however differently their text wraps.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _VersionCell(
              event: conflict.local,
              kept: keepLocal,
              use24HourTime: widget.settings.use24HourTime,
              onTap: tappable ? () => _choose(index, true) : null,
            ),
          ),
          const SizedBox(width: Insets.sm),
          Expanded(
            child: _VersionCell(
              event: conflict.incoming,
              kept: !keepLocal,
              use24HourTime: widget.settings.use24HourTime,
              onTap: tappable ? () => _choose(index, false) : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  final String name;
  final String caption;
  final VoidCallback? onTap;

  const _ColumnHeader({
    required this.name,
    required this.caption,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return TapFade(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Insets.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
            Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: c.ink3),
            ),
          ],
        ),
      ),
    );
  }
}

/// One device's version of a conflicting event. The kept one has an ink
/// outline and a tick; the other is dimmed.
class _VersionCell extends StatelessWidget {
  final CalendarEvent event;
  final bool kept;
  final bool? use24HourTime;
  final VoidCallback? onTap;

  const _VersionCell({
    required this.event,
    required this.kept,
    required this.use24HourTime,
    required this.onTap,
  });

  String _date(DateTime local) =>
      '${local.day} ${monthNames[local.month - 1]} ${local.year}';

  String get _title {
    if (event.deleted) return 'Deleted';
    return event.title.isEmpty ? 'Untitled' : event.title;
  }

  List<String> _details(BuildContext context) {
    if (event.deleted) return const [];
    final start = event.startAt.toLocal();
    final end = event.endAt.toLocal();
    final String when;
    if (event.allDay) {
      when = _date(start);
    } else {
      final from = formatTimeOfDay(context, start, use24HourTime);
      final to = formatTimeOfDay(context, end, use24HourTime);
      when = '${_date(start)}, $from–$to';
    }
    final location = event.location;
    return [
      when,
      if (location != null && location.isNotEmpty) location,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final edited = event.updatedAt.toLocal();
    final editedText = 'Edited ${edited.day} ${monthNames[edited.month - 1]}, '
        '${formatTimeOfDay(context, edited, use24HourTime)}';

    return TapFade(
      onTap: onTap,
      selected: kept,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kept ? c.surface : Colors.transparent,
          border: Border.all(color: kept ? c.ink : c.line),
          borderRadius: BorderRadius.circular(Radii.cell),
        ),
        child: Opacity(
          opacity: kept ? 1 : 0.55,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      _title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                  ),
                  if (kept) Icon(Icons.check, size: 16, color: c.ink),
                ],
              ),
              for (final line in _details(context))
                Text(
                  line,
                  style: TextStyle(fontSize: 13, color: c.ink2, height: 1.4),
                ),
              const SizedBox(height: Insets.xs),
              Text(
                editedText,
                style: TextStyle(
                  fontSize: 12,
                  color: c.ink3,
                  fontFeatures: tabularFigures,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
