import 'package:flutter/material.dart';

import '../data/event_repository.dart';
import '../data/holiday_repository.dart';
import '../data/settings_repository.dart';
import '../sync/sync_service.dart';
import '../theme/tokens.dart';
import '../widgets/settings_rows.dart';
import 'holidays_screen.dart';
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
            sectionLabel(c, 'Appearance'),
            tapRow(
              c,
              title: 'Theme',
              value: switch (s.themeMode) {
                ThemeMode.light => 'Light',
                ThemeMode.dark => 'Dark',
                ThemeMode.system => 'Follow the system',
              },
              onTap: _pickTheme,
            ),
            sectionLabel(c, 'Calendar'),
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
            switchRow(
              c,
              title: 'Colour Saturdays and Sundays',
              subtitle: 'Sundays vermilion, Saturdays indigo',
              value: s.colourWeekends,
              onChanged: (value) async {
                await s.setColourWeekends(value);
                setState(() {});
              },
            ),
            tapRow(
              c,
              title: 'Time format',
              value: switch (s.use24HourTime) {
                true => '24-hour',
                false => '12-hour',
                null => 'Follow the system',
              },
              onTap: _pickTimeFormat,
            ),
            tapRow(
              c,
              title: 'Holidays',
              value: switch (widget.holidays.enabledRegions.length +
                  widget.holidays.imported.length) {
                0 => 'None',
                final n => '$n on',
              },
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => HolidaysScreen(holidays: widget.holidays),
                ));
                if (mounted) setState(() {});
              },
            ),
            sectionLabel(c, 'Sync'),
            tapRow(
              c,
              title: 'This device is called',
              value: s.deviceName,
              onTap: _editDeviceName,
            ),
            tapRow(
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
            switchRow(
              c,
              title: 'Automatic sync',
              subtitle: 'With paired devices, when Klhyeti opens and '
                  'after each change',
              value: s.autoSync,
              onChanged: (value) async {
                await s.setAutoSync(value);
                if (mounted) setState(() {});
              },
            ),
            sectionLabel(c, 'About'),
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
                    'Klhyeti never connects to the internet. It uses the '
                    'local network only to pair and sync devices.',
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
    final chosen = await chooseOne<ThemeMode>(
      context,
      title: 'Theme',
      options: const {
        ThemeMode.system: 'Follow the system',
        ThemeMode.light: 'Light',
        ThemeMode.dark: 'Dark',
      },
      current: s.themeMode,
    );
    if (chosen == null) return;
    await s.setThemeMode(chosen.$1);
    if (mounted) setState(() {});
  }

  Future<void> _pickTimeFormat() async {
    final chosen = await chooseOne<bool?>(
      context,
      title: 'Time format',
      options: const {
        null: 'Follow the system',
        true: '24-hour',
        false: '12-hour',
      },
      current: s.use24HourTime,
    );
    if (chosen == null) return;
    await s.setUse24HourTime(chosen.$1);
    if (mounted) setState(() {});
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
