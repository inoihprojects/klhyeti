import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/holiday_repository.dart';
import '../theme/tokens.dart';
import '../widgets/settings_rows.dart';

/// Settings → Holidays: the countries whose holidays the calendar shows,
/// and imported .ics calendars.
///
/// Opt-in: nothing is on until chosen. The countries on come first; the
/// rest are grouped by continent, and a search narrows the list to the
/// names that match.
class HolidaysScreen extends StatefulWidget {
  final HolidayRepository holidays;

  const HolidaysScreen({super.key, required this.holidays});

  @override
  State<HolidaysScreen> createState() => _HolidaysScreenState();
}

class _HolidaysScreenState extends State<HolidaysScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  /// Switched on when the screen opened. Kept, rather than read live, so
  /// a country doesn't jump to the top the moment it is switched on.
  late final Set<String> _onAtStart = widget.holidays.enabledRegions;

  HolidayRepository get h => widget.holidays;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Widget _region(KlhyetiColors c, HolidayRegion region) {
    return switchRow(
      c,
      title: region.name,
      value: h.enabledRegions.contains(region.code),
      onChanged: (value) async {
        await h.setRegionEnabled(region.code, value);
        if (mounted) setState(() {});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final query = _query.trim().toLowerCase();
    final List<Widget> regions;
    if (query.isNotEmpty) {
      final matches = [
        for (final region in holidayRegions)
          if (region.name.toLowerCase().contains(query)) region,
      ];
      regions = [
        for (final region in matches) _region(c, region),
        if (matches.isEmpty)
          Padding(
            padding: const EdgeInsets.all(Insets.md),
            child: Text('No country by that name.',
                style: TextStyle(fontSize: 14, color: c.ink3)),
          ),
      ];
    } else {
      regions = [
        if (_onAtStart.isNotEmpty) ...[
          sectionLabel(c, 'On'),
          for (final region in holidayRegions)
            if (_onAtStart.contains(region.code)) _region(c, region),
        ],
        for (final continent in holidayContinents) ...[
          sectionLabel(c, continent),
          for (final region in holidayRegions)
            if (region.continent == continent &&
                !_onAtStart.contains(region.code))
              _region(c, region),
        ],
      ];
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Holidays')),
      body: SafeArea(
        child: Column(
          children: [
            // Outside the list, so it stays in place while the list scrolls.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Insets.md, Insets.sm, Insets.md, Insets.sm),
              child: TextField(
                controller: _search,
                autocorrect: false,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Search countries',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (text) => setState(() => _query = text),
              ),
            ),
            Divider(height: 1, thickness: 1, color: c.line),
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  ...regions,
                  if (query.isEmpty) ..._imported(c),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _imported(KlhyetiColors c) {
    return [
      sectionLabel(c, 'Imported'),
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
                      '${calendar.dayCount} '
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
      tapRow(c, title: 'Import an .ics file', value: '', onTap: _importIcs),
      Padding(
        padding:
            const EdgeInsets.fromLTRB(Insets.md, Insets.xs, Insets.md, Insets.xl),
        child: Text(
          'National holidays, worked out from each country\'s rules for '
          '2000 to 2099 and bundled with the app, so nothing is downloaded. '
          'Regional holidays, days off set by decree each year and one-off '
          'holidays aren\'t included, and Islamic dates can be a day off. '
          'An imported calendar can add what is missing.',
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
      final name =
          file.name.replaceAll(RegExp(r'\.ics$', caseSensitive: false), '');
      final count = await h.importIcs(
          name, utf8.decode(bytes, allowMalformed: true));
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
}
