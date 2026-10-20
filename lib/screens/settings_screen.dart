import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/event_repository.dart';
import '../data/holiday_repository.dart';
import '../data/settings_repository.dart';
import '../sync/sync_service.dart';
import '../theme/tokens.dart';
import '../widgets/tap_fade.dart';
import 'sync_screen.dart';

class SettingsScreen extends StatefulWidget {
  final EventRepository repo;
  final SettingsRepository settings;
  final HolidayRepository holidays;
  final SyncService sync;

  const SettingsScreen({
    super.key,
    required this.repo,
    required this.settings,
    required this.holidays,
    required this.sync,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SettingsRepository get s => widget.settings;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          children: [
            _section(c, 'Appearance'),
            _row(
              c,
              title: 'Theme',
              value: switch (s.themeMode) {
                ThemeMode.light => 'Light',
                ThemeMode.dark => 'Dark',
                ThemeMode.system => 'Follow the system',
              },
              onTap: _pickTheme,
            ),
            _section(c, 'Calendar'),
            _segmentedRow<bool>(
              c,
              title: 'Week starts on',
              value: s.weekStartsMonday,
              options: const {false: 'Sunday', true: 'Monday'},
              onChanged: (value) async {
                await s.setWeekStartsMonday(value);
                if (mounted) setState(() {});
              },
            ),
            _segmentedRow<bool>(
              c,
              title: 'Months',
              subtitle: s.continuousMonths
                  ? 'Weeks scroll on without breaks'
                  : 'One month at a time',
              value: s.continuousMonths,
              options: const {true: 'Continuous', false: 'Paged'},
              onChanged: (value) async {
                await s.setContinuousMonths(value);
                if (mounted) setState(() {});
              },
            ),
            // Direction only means something when a gesture turns a page;
            // continuous scrolling simply follows the finger or wheel.
            if (!s.continuousMonths)
              _segmentedRow<bool>(
                c,
                title: 'Paging direction',
                subtitle: s.reverseMonthScroll
                    ? 'Scroll up or swipe right for the next month'
                    : 'Scroll down or swipe left for the next month',
                value: s.reverseMonthScroll,
                options: const {false: 'Standard', true: 'Reversed'},
                onChanged: (value) async {
                  await s.setReverseMonthScroll(value);
                  if (mounted) setState(() {});
                },
              ),
            _switchRow(
              c,
              title: 'Colour Saturdays and Sundays',
              subtitle: 'Sundays vermilion, Saturdays indigo',
              value: s.colourWeekends,
              onChanged: (value) async {
                await s.setColourWeekends(value);
                setState(() {});
              },
            ),
            _row(
              c,
              title: 'Time format',
              value: switch (s.use24HourTime) {
                true => '24-hour',
                false => '12-hour',
                null => 'Follow the system',
              },
              onTap: _pickTimeFormat,
            ),
            ..._holidaySection(c),
            _section(c, 'Sync'),
            _row(
              c,
              title: 'This device is called',
              value: s.deviceName,
              onTap: _editDeviceName,
            ),
            _row(
              c,
              title: 'Paired devices and sync files',
              value: '',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SyncScreen(
                    repo: widget.repo,
                    settings: s,
                    sync: widget.sync,
                  ),
                ),
              ),
            ),
            _switchRow(
              c,
              title: 'Automatic sync',
              subtitle: 'With paired devices, when Klhyeti opens and after '
                  'each change, while it is open',
              value: s.autoSync,
              onChanged: (value) async {
                await s.setAutoSync(value);
                if (mounted) setState(() {});
              },
            ),
            _section(c, 'About'),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Insets.md, Insets.sm, Insets.md, Insets.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The asterisk marks a reconstructed word, never attested
                  // in writing. Only here: the main header stays bare.
                  Text(
                    '*kl̥h₁yéti',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: Insets.xs),
                  Text(
                    'A reconstructed Proto-Indo-European '
                    'zero-grade -yé- present of '
                    '*kelh₁- "to call", the root behind Latin calāre, '
                    'Kalendae, and eventually English "calendar".',
                    style: TextStyle(fontSize: 13, color: c.ink2, height: 1.4),
                  ),
                  const SizedBox(height: Insets.md),
                  Text(
                    'Klhyeti never connects to the internet. It uses the local '
                    'network only when it pairs or syncs devices. Events stay '
                    'on the devices, and sync only when asked.',
                    style: TextStyle(fontSize: 13, color: c.ink2, height: 1.4),
                  ),
                  const SizedBox(height: Insets.md),
                  Text(
                    'Free software under the GNU General Public License, '
                    'version 3 or later.\n'
                    'github.com/inoihprojects/klhyeti',
                    style: TextStyle(fontSize: 13, color: c.ink3, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(KlhyetiColors c, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Insets.md, Insets.lg, Insets.md, Insets.sm),
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

  Widget _row(
    KlhyetiColors c, {
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return TapFade(
      onTap: onTap,
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(
            horizontal: Insets.md, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(title, style: TextStyle(fontSize: 15, color: c.ink)),
            ),
            Text(value, style: TextStyle(fontSize: 14, color: c.ink2)),
            const SizedBox(width: Insets.sm),
            Icon(Icons.chevron_right, size: 18, color: c.ink3),
          ],
        ),
      ),
    );
  }

  Widget _switchRow(
    KlhyetiColors c, {
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: Insets.md, vertical: Insets.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 15, color: c.ink)),
                if (subtitle != null)
                  Text(subtitle,
                      style: TextStyle(fontSize: 13, color: c.ink3)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  /// Holidays: opt-in, one switch per bundled region, then
  /// any imported .ics calendars, each removable.
  List<Widget> _holidaySection(KlhyetiColors c) {
    final h = widget.holidays;
    return [
      _section(c, 'Holidays'),
      for (final region in holidayRegions)
        _switchRow(
          c,
          title: region.name,
          value: h.enabledRegions.contains(region.code),
          onChanged: (value) async {
            await h.setRegionEnabled(region.code, value);
            if (mounted) setState(() {});
          },
        ),
      for (final calendar in h.imported)
        Padding(
          padding: const EdgeInsets.only(left: Insets.md, right: Insets.xs),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(calendar.name,
                        style: TextStyle(fontSize: 15, color: c.ink)),
                    Text(
                      'Imported, ${calendar.dayCount} '
                      '${calendar.dayCount == 1 ? 'day' : 'days'}',
                      style: TextStyle(fontSize: 13, color: c.ink3),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Remove ${calendar.name}',
                onPressed: () async {
                  await h.removeImported(calendar.id);
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),
        ),
      _row(
        c,
        title: 'Import an .ics file',
        value: '',
        onTap: _importIcs,
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
            Insets.md, Insets.xs, Insets.md, Insets.sm),
        child: Text(
          'Worked out from each country\'s holiday rules for 2000 to 2099 '
          'and bundled with the app, so nothing is downloaded. Days off '
          'announced year by year, one-off holidays and election days '
          'aren\'t included; an imported calendar can add them.',
          style: TextStyle(fontSize: 13, color: c.ink3, height: 1.4),
        ),
      ),
    ];
  }

  Future<void> _importIcs() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Choose a calendar (.ics) file',
        type: FileType.custom,
        allowedExtensions: ['ics'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) return;
      final name = file.name.replaceAll(RegExp(r'\.ics$', caseSensitive: false), '');
      final count = await widget.holidays
          .importIcs(name, utf8.decode(bytes, allowMalformed: true));
      messenger.showSnackBar(SnackBar(
        content: Text(count == 0
            ? 'No dates found in that file.'
            : 'Imported $count ${count == 1 ? 'day' : 'days'}.'),
      ));
      if (mounted) setState(() {});
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  /// A setting with two values, both shown at once: the choice is visible
  /// without opening anything. A tap anywhere on the control flips it,
  /// including on the side already chosen, so it works like a switch.
  Widget _segmentedRow<T>(
    KlhyetiColors c, {
    required String title,
    String? subtitle,
    required T value,
    required Map<T, String> options,
    required ValueChanged<T> onChanged,
  }) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: Insets.md, vertical: Insets.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 15, color: c.ink)),
                if (subtitle != null)
                  Text(subtitle,
                      style: TextStyle(fontSize: 13, color: c.ink3)),
              ],
            ),
          ),
          const SizedBox(width: Insets.sm),
          SegmentedButton<T>(
            segments: [
              for (final entry in options.entries)
                ButtonSegment<T>(value: entry.key, label: Text(entry.value)),
            ],
            selected: {value},
            showSelectedIcon: false,
            // Tapping the chosen side would normally do nothing. Allowing
            // an empty selection turns that tap into an empty set, which
            // is read here as "the other one".
            emptySelectionAllowed: true,
            onSelectionChanged: (selection) => onChanged(
              selection.isEmpty
                  ? options.keys.firstWhere((key) => key != value)
                  : selection.first,
            ),
            style: SegmentedButton.styleFrom(
              foregroundColor: c.ink2,
              selectedForegroundColor: c.bg,
              selectedBackgroundColor: c.ink,
              side: BorderSide(color: c.line),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Radii.cell),
              ),
              textStyle:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickTheme() async {
    final chosen = await _choose<ThemeMode>(
      title: 'Theme',
      options: const {
        ThemeMode.system: 'Follow the system',
        ThemeMode.light: 'Light',
        ThemeMode.dark: 'Dark',
      },
      current: s.themeMode,
    );
    if (chosen == null) return;
    await s.setThemeMode(chosen);
    if (mounted) setState(() {});
  }

  Future<void> _pickTimeFormat() async {
    final chosen = await _choose<String>(
      title: 'Time format',
      options: const {
        'system': 'Follow the system',
        '24': '24-hour',
        '12': '12-hour',
      },
      current: switch (s.use24HourTime) {
        true => '24',
        false => '12',
        null => 'system',
      },
    );
    if (chosen == null) return;
    await s.setUse24HourTime(switch (chosen) {
      '24' => true,
      '12' => false,
      _ => null,
    });
    if (mounted) setState(() {});
  }

  Future<T?> _choose<T>({
    required String title,
    required Map<T, String> options,
    required T current,
  }) {
    return showDialog<T>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(title),
        children: [
          for (final entry in options.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(entry.key),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Insets.sm),
                child: Row(
                  children: [
                    Icon(
                      entry.key == current
                          ? Icons.check
                          : Icons.check_box_outline_blank,
                      size: 18,
                      color: entry.key == current
                          ? context.c.ink
                          : Colors.transparent,
                    ),
                    const SizedBox(width: Insets.md),
                    Text(entry.value),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _editDeviceName() async {
    final controller = TextEditingController(text: s.deviceName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Name this device'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'My phone'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    await s.setDeviceName(name);
    if (mounted) setState(() {});
  }
}
