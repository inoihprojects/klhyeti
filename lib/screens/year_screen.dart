import 'package:flutter/material.dart';

import '../data/event_repository.dart';
import '../data/holiday_repository.dart';
import '../data/settings_repository.dart';
import '../theme/tokens.dart';
import '../widgets/month_grid.dart';

/// Twelve months at a glance; tapping one returns it to the calendar
/// screen, which then shows that month.
class YearScreen extends StatefulWidget {
  final EventRepository repo;
  final SettingsRepository settings;
  final HolidayRepository holidays;
  final int year;
  final DateTime today;

  const YearScreen({
    super.key,
    required this.repo,
    required this.settings,
    required this.holidays,
    required this.year,
    required this.today,
  });

  @override
  State<YearScreen> createState() => _YearScreenState();
}

class _YearScreenState extends State<YearScreen> {
  late int _year = widget.year;
  Map<DateTime, int> _counts = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final year = _year;
    final counts = await widget.repo.eventCountsInRange(
      DateTime(year, 1, 1),
      DateTime(year + 1, 1, 1),
    );
    if (!mounted || year != _year) return;
    setState(() => _counts = counts);
  }

  void _stepYear(int delta) {
    setState(() => _year += delta);
    _load();
  }

  /// Four columns on wide windows, three on phones, two on the narrowest,
  /// where three would squeeze eleven-point numbers into each other.
  static int _columns(double width) {
    if (width >= 720) return 4;
    if (width >= 340) return 3;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final int columns = _columns(MediaQuery.sizeOf(context).width);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '$_year',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            color: c.ink,
            fontFeatures: tabularFigures,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous year',
            onPressed: () => _stepYear(-1),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next year',
            onPressed: () => _stepYear(1),
          ),
          const SizedBox(width: Insets.sm),
        ],
      ),
      body: SafeArea(
        child: GridView.builder(
          padding: const EdgeInsets.all(Insets.sm),
          itemCount: 12,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            // Drawn at their real size, never shrunk to fit: shrinking is
            // what made the months too small to tell apart.
            mainAxisExtent: MiniMonth.height,
            mainAxisSpacing: Insets.sm,
            crossAxisSpacing: Insets.sm,
          ),
          itemBuilder: (context, index) {
            final month = DateTime(_year, index + 1);
            return MiniMonth(
              month: month,
              today: widget.today,
              eventCounts: _counts,
              weekStartsMonday: widget.settings.weekStartsMonday,
              colourWeekends: widget.settings.colourWeekends,
              holidays: widget.holidays.namesOn,
              onTap: () => Navigator.of(context).pop(month),
            );
          },
        ),
      ),
    );
  }
}
