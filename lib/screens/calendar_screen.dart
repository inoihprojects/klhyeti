import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/event_repository.dart';
import '../data/holiday_repository.dart';
import '../data/settings_repository.dart';
import '../models/calendar_event.dart';
import '../sync/sync_reconciler.dart';
import '../sync/sync_service.dart';
import '../theme/tokens.dart';
import '../widgets/continuous_month_grid.dart';
import '../widgets/event_list.dart';
import '../widgets/event_sheet.dart';
import '../widgets/month_grid.dart';
import '../widgets/tap_fade.dart';
import 'conflict_resolution_screen.dart';
import 'event_edit_screen.dart';
import 'settings_screen.dart';
import 'sync_screen.dart';
import 'year_screen.dart';

/// The sheet's resting height on a day with events: the handle, the date
/// and about two events.
const double _peekWithEvents = 200;

/// On an empty day the sheet rests as a slim bar (handle and date only),
/// out of the calendar's way.
const double _peekEmpty = 72;

/// The resting height never takes more than this share of the space
/// below the month bar, however short the window.
const double _peekMaxFraction = 0.4;

const double _sheetMaxFraction = 0.92;
const double _wideLayoutBreakpoint = 900;

class CalendarScreen extends StatefulWidget {
  final EventRepository repo;
  final SettingsRepository settings;
  final HolidayRepository holidays;
  final SyncService sync;

  const CalendarScreen({
    super.key,
    required this.repo,
    required this.settings,
    required this.holidays,
    required this.sync,
  });

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with SingleTickerProviderStateMixin {
  late DateTime _focusedMonth;
  late DateTime _selectedDay;
  late DateTime _today;

  Map<DateTime, int> _counts = const {};
  List<CalendarEvent>? _events;

  /// Whether the sheet rests at its taller height. Follows the selected
  /// day's events once they have loaded, and holds still while loading so
  /// the sheet doesn't dip and rise on every tap.
  bool _restTall = true;

  int _lastDirection = 1;
  DateTime _lastWheelAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// For the continuous grid: a new object whenever a month should be
  /// brought into view (arrows, Today, the year view).
  MonthJump? _monthJump;

  /// 0 = the sheet at rest, 1 = fully open.
  late final AnimationController _sheetOpen = AnimationController(vsync: this);
  final ScrollController _sheetList = ScrollController();

  bool get _continuous => widget.settings.continuousMonths;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _today = dayOnly(now);
    _selectedDay = _today;
    _focusedMonth = DateTime(now.year, now.month);
    // Redraw as soon as a setting or the holiday regions change, even
    // while another screen is on top.
    widget.settings.addListener(_redraw);
    widget.holidays.addListener(_redraw);
    // Events can change under the calendar: a sync running in the
    // background, started by this device or another.
    widget.repo.addListener(_reload);
    widget.sync.addListener(_redraw);
    _reload();
  }

  @override
  void dispose() {
    widget.settings.removeListener(_redraw);
    widget.holidays.removeListener(_redraw);
    widget.repo.removeListener(_reload);
    widget.sync.removeListener(_redraw);
    _sheetOpen.dispose();
    _sheetList.dispose();
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  Future<void> _reload() async {
    await Future.wait([_loadCounts(), _loadEvents()]);
  }

  Future<void> _loadCounts() async {
    // A month either side, so the neighbouring days shown in the grid also
    // get their dots.
    final month = _focusedMonth;
    final start = DateTime(month.year, month.month - 1, 1);
    final end = DateTime(month.year, month.month + 2, 1);
    final counts = await widget.repo.eventCountsInRange(start, end);
    // While scrolling, several loads overlap; only the newest counts.
    if (!mounted || month != _focusedMonth) return;
    setState(() => _counts = counts);
  }

  Future<void> _loadEvents() async {
    final day = _selectedDay;
    final events = await widget.repo.eventsForDay(day);
    if (!mounted || day != _selectedDay) return;
    setState(() {
      _events = events;
      _restTall = events.isNotEmpty;
    });
  }

  void _goToMonth(DateTime month, {int? direction}) {
    final target = DateTime(month.year, month.month);
    // The continuous grid scrolls even to the month already named, so
    // Today or an arrow press re-aligns a list scrolled partway.
    if (target == _focusedMonth && !_continuous) return;
    final bool changed = target != _focusedMonth;
    setState(() {
      _lastDirection = direction ?? (target.isAfter(_focusedMonth) ? 1 : -1);
      _focusedMonth = target;
      if (_continuous) _monthJump = MonthJump(target);
    });
    if (changed) _loadCounts();
  }

  void _stepMonth(int delta) {
    _goToMonth(
      DateTime(_focusedMonth.year, _focusedMonth.month + delta),
      direction: delta,
    );
  }

  /// The continuous grid names the month that fills most of the screen.
  void _onVisibleMonthChanged(DateTime month) {
    if (month == _focusedMonth) return;
    setState(() => _focusedMonth = month);
    _loadCounts();
  }

  void _selectDay(DateTime day) {
    final normalised = dayOnly(day);
    // Paged, a day from a neighbouring month turns the page to it.
    // Continuous, it is already on screen; the grid scrolls by itself if
    // the selection walks off the edge.
    if (!_continuous &&
        (normalised.year != _focusedMonth.year ||
            normalised.month != _focusedMonth.month)) {
      _goToMonth(DateTime(normalised.year, normalised.month));
    }
    setState(() {
      _selectedDay = normalised;
      _events = null;
    });
    if (_sheetList.hasClients) _sheetList.jumpTo(0);
    _loadEvents();
  }

  void _goToToday() {
    final now = DateTime.now();
    _today = dayOnly(now);
    _selectDay(_today);
    _goToMonth(DateTime(_today.year, _today.month));
  }

  Future<void> _openEditor(CalendarEvent? event) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EventEditScreen(
          repo: widget.repo,
          settings: widget.settings,
          existing: event,
          initialDay: _selectedDay,
        ),
      ),
    );
    if (changed == true) await _reload();
  }

  Future<void> _openYearView() async {
    final month = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute(
        builder: (_) => YearScreen(
          repo: widget.repo,
          settings: widget.settings,
          holidays: widget.holidays,
          year: _focusedMonth.year,
          today: _today,
        ),
      ),
    );
    if (month != null) _goToMonth(month);
  }

  Future<void> _openRoute(Widget screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) await _reload();
  }

  /// The sync button: syncs with every paired device it can reach, or,
  /// with none paired yet, opens the screen where pairing is done.
  Future<void> _syncNow() async {
    final sync = widget.sync;
    final paired = await sync.peers.all();
    if (!mounted) return;
    if (paired.isEmpty) {
      await _openRoute(SyncScreen(
        repo: widget.repo,
        settings: widget.settings,
        sync: sync,
      ));
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final report = await sync.syncAll(settle: _settle);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(report.describe())));
  }

  /// The user pressed Sync and is here, so conflicts are shown at once.
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

  /// 1, or -1 when the user has reversed paging in Settings.
  int get _scrollSign => widget.settings.reverseMonthScroll ? -1 : 1;

  void _handleWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final now = DateTime.now();
    if (now.difference(_lastWheelAt).inMilliseconds < 90) return;
    if (event.scrollDelta.dy.abs() < 1) return;
    _lastWheelAt = now;
    _stepMonth((event.scrollDelta.dy > 0 ? 1 : -1) * _scrollSign);
  }

  void _handleSwipeEnd(DragEndDetails details) {
    final double vx = details.primaryVelocity ?? 0;
    final double vy = details.velocity.pixelsPerSecond.dy;
    if (vx.abs() < 200 || vx.abs() < vy.abs()) return;
    _stepMonth((vx < 0 ? 1 : -1) * _scrollSign);
  }

  /// Component arithmetic, not Duration: adding 24 hours across a
  /// daylight-saving change can land on the same day again.
  void _shiftSelection(int days) {
    _selectDay(DateTime(
        _selectedDay.year, _selectedDay.month, _selectedDay.day + days));
  }

  void _settleSheet(double target) {
    settleSheet(context, _sheetOpen, target);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _shiftSelection(-1);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _shiftSelection(1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _shiftSelection(-7);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _shiftSelection(7);
    } else if (key == LogicalKeyboardKey.pageUp) {
      _stepMonth(-1);
    } else if (key == LogicalKeyboardKey.pageDown) {
      _stepMonth(1);
    } else if (key == LogicalKeyboardKey.keyN) {
      _openEditor(null);
    } else if (key == LogicalKeyboardKey.keyT) {
      _goToToday();
    } else if (key == LogicalKeyboardKey.escape && _sheetOpen.value > 0) {
      _settleSheet(0);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final bool wide =
        MediaQuery.sizeOf(context).width >= _wideLayoutBreakpoint;

    return Scaffold(
      // This screen has no text fields. Left to resize, it would re-lay
      // out the whole calendar on every frame of a keyboard sliding in on
      // a screen above it.
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Focus(
          autofocus: true,
          onKeyEvent: _handleKey,
          child: Column(
            children: [
              _header(c),
              if (widget.sync.unsettledWith.isNotEmpty) _conflictBar(c),
              _monthBar(c),
              Divider(height: 1, thickness: 1, color: c.line),
              Expanded(child: wide ? _wideBody(c) : _narrowBody(c)),
            ],
          ),
        ),
      ),
    );
  }

  /// Shown while an automatic sync has left conflicts. A tap syncs again,
  /// with the conflict screen this time.
  Widget _conflictBar(KlhyetiColors c) {
    final names = widget.sync.unsettledWith.map((n) => '"$n"').join(', ');
    return TapFade(
      onTap: widget.sync.busy ? null : _syncNow,
      child: Container(
        width: double.infinity,
        color: c.surfaceAlt,
        padding: const EdgeInsets.symmetric(
            horizontal: Insets.md, vertical: Insets.sm),
        child: Row(
          children: [
            Icon(Icons.call_split, size: 18, color: c.ink2),
            const SizedBox(width: Insets.sm),
            Expanded(
              child: Text(
                'Conflicts with $names to settle',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: c.ink),
              ),
            ),
            Text(
              'Settle',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(KlhyetiColors c) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          const SizedBox(width: Insets.md),
          Text(
            'Kl̥h₁yéti',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: c.ink,
            ),
          ),
          const Spacer(),
          IconButton(
            // A chain link, not a refresh arrow: this links two devices.
            icon: const Icon(Icons.link),
            tooltip: widget.sync.busy ? 'Syncing…' : 'Sync now',
            onPressed: widget.sync.busy ? null : _syncNow,
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Settings',
            onPressed: () => _openRoute(
              SettingsScreen(
                repo: widget.repo,
                settings: widget.settings,
                holidays: widget.holidays,
                sync: widget.sync,
              ),
            ),
          ),
          const SizedBox(width: Insets.sm),
        ],
      ),
    );
  }

  Widget _monthBar(KlhyetiColors c) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          const SizedBox(width: Insets.md),
          TapFade(
            onTap: _openYearView,
            semanticLabel: 'Show the whole year',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Insets.sm),
              child: Text(
                '${_focusedMonth.year} '
                '${monthNames[_focusedMonth.month - 1]}',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  color: c.ink,
                  fontFeatures: tabularFigures,
                ),
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous month',
            onPressed: () => _stepMonth(-1),
          ),
          IconButton(
            icon: const Icon(Icons.circle, size: 8),
            tooltip: 'Today',
            onPressed: _goToToday,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next month',
            onPressed: () => _stepMonth(1),
          ),
          const SizedBox(width: Insets.sm),
        ],
      ),
    );
  }

  /// [rowHeight] is used by the continuous grid only; the paged grid
  /// divides whatever height it is given into six rows.
  Widget _grid(double rowHeight) {
    if (_continuous) {
      return ContinuousMonthGrid(
        focusedMonth: _focusedMonth,
        selectedDay: _selectedDay,
        today: _today,
        eventCounts: _counts,
        weekStartsMonday: widget.settings.weekStartsMonday,
        colourWeekends: widget.settings.colourWeekends,
        holidays: widget.holidays.namesOn,
        rowHeight: rowHeight,
        jump: _monthJump,
        onSelect: _selectDay,
        onFocusedMonthChanged: _onVisibleMonthChanged,
      );
    }

    final grid = MonthGrid(
      // The key is what tells AnimatedSwitcher a different month arrived.
      key: ValueKey<DateTime>(_focusedMonth),
      month: _focusedMonth,
      selectedDay: _selectedDay,
      today: _today,
      eventCounts: _counts,
      weekStartsMonday: widget.settings.weekStartsMonday,
      colourWeekends: widget.settings.colourWeekends,
      holidays: widget.holidays.namesOn,
      onSelect: _selectDay,
    );

    return Listener(
      onPointerSignal: _handleWheel,
      child: GestureDetector(
        onHorizontalDragEnd: _handleSwipeEnd,
        // Claims vertical drags so they do nothing. With only a horizontal
        // recogniser listening, it won every drag, and the slight sideways
        // drift of a vertical thumb swipe changed the month.
        onVerticalDragUpdate: (_) {},
        child: AnimatedSwitcher(
          duration: Motion.of(context, Motion.month),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeOutCubic,
          layoutBuilder: (current, previous) => Stack(
            fit: StackFit.expand,
            children: [...previous, if (current != null) current],
          ),
          transitionBuilder: (child, animation) {
            final incoming = child.key == ValueKey<DateTime>(_focusedMonth);
            final dx = (incoming ? 1 : -1) * _lastDirection * 0.03;
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: Offset(dx, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: grid,
        ),
      ),
    );
  }

  Widget _wideBody(KlhyetiColors c) {
    return Row(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              children: [
                Positioned.fill(
                  child: _grid(math.max(
                    24.0,
                    (constraints.maxHeight - WeekdayHeader.height) / 6,
                  )),
                ),
                Positioned(
                  right: Insets.md,
                  bottom: Insets.md,
                  child: _fab(),
                ),
              ],
            ),
          ),
        ),
        VerticalDivider(width: 1, thickness: 1, color: c.line),
        SizedBox(
          width: 360,
          child: Container(
            color: c.surface,
            child: DayEventList(
              day: _selectedDay,
              events: _events,
              use24HourTime: widget.settings.use24HourTime,
              holidays: widget.holidays.namesOn(_selectedDay),
              onOpenEvent: _openEditor,
              onAddEvent: () => _openEditor(null),
            ),
          ),
        ),
      ],
    );
  }

  /// Phones and narrow windows: the grid on top, the sheet below it.
  ///
  /// At rest the sheet never covers the grid: the grid gets the height
  /// above the sheet's resting height. Only when dragged open does the
  /// sheet float over the grid, which dims behind it.
  Widget _narrowBody(KlhyetiColors c) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double h = constraints.maxHeight;
        final double tallPeek = math.min(_peekWithEvents, h * _peekMaxFraction);
        final double shortPeek = math.min(_peekEmpty, tallPeek);
        final double expanded = h * _sheetMaxFraction;
        // Continuous rows are sized so exactly six weeks fit above the
        // taller resting sheet. They keep that height when the sheet rests
        // low, which then simply shows more weeks.
        final double rowHeight =
            math.max(24.0, (h - tallPeek - WeekdayHeader.height) / 6);

        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: _restTall ? tallPeek : shortPeek),
          duration: Motion.of(context, Motion.sheet),
          curve: Curves.easeOutCubic,
          builder: (context, peek, _) => Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: h - peek,
                child: _grid(rowHeight),
              ),
              _dimmer(c),
              _floatingFab(peek, expanded, h),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: EventSheet(
                  open: _sheetOpen,
                  peekHeight: peek,
                  expandedHeight: expanded,
                  scrollController: _sheetList,
                  child: _sheetBody(c),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Dims the grid in step with how far the sheet is open; a tap on it
  /// closes the sheet.
  ///
  /// While present it takes every touch meant for the grid, so it must be
  /// gone whenever the sheet is closed. "Closed" is anything under 1 %:
  /// an exact 0 is not guaranteed, and a near-zero value once left it in
  /// place, invisible, and the calendar stopped scrolling.
  Widget _dimmer(KlhyetiColors c) {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _sheetOpen,
        builder: (context, _) {
          final double t = _sheetOpen.value;
          if (t < 0.01) return const SizedBox.shrink();
          return GestureDetector(
            onTap: () => _settleSheet(0),
            child: ColoredBox(color: c.ink.withValues(alpha: 0.18 * t)),
          );
        },
      ),
    );
  }

  /// The add button rides just above the sheet and fades out once the
  /// sheet is more than half open.
  Widget _floatingFab(double peek, double expanded, double h) {
    return AnimatedBuilder(
      animation: _sheetOpen,
      child: _fab(),
      builder: (context, child) {
        final double t = _sheetOpen.value;
        final double sheetTop = peek + (expanded - peek) * t;
        final bool hidden = t > 0.5;
        return Positioned(
          right: Insets.md,
          bottom: math.min(sheetTop + Insets.md, h - 72),
          child: IgnorePointer(
            ignoring: hidden,
            child: AnimatedOpacity(
              opacity: hidden ? 0 : 1,
              duration: Motion.of(context, Motion.press),
              child: child,
            ),
          ),
        );
      },
    );
  }

  Widget _sheetBody(KlhyetiColors c) {
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Radii.sheet),
        ),
        border: Border(top: BorderSide(color: c.line)),
        boxShadow: Theme.of(context).brightness == Brightness.light
            ? [
                BoxShadow(
                  color: c.ink.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, -2),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: DayEventList(
        day: _selectedDay,
        events: _events,
        use24HourTime: widget.settings.use24HourTime,
        controller: _sheetList,
        physics: const SheetScrollPhysics(),
        onOpenEvent: _openEditor,
        onAddEvent: () => _openEditor(null),
        header: _sheetHeader(c),
        showDateHeading: false,
      ),
    );
  }

  /// The grab bar, then the date (and any holiday) with the open/close
  /// button beside it. Exactly [_peekEmpty] tall, so on an empty day the
  /// resting sheet is this bar and nothing else.
  Widget _sheetHeader(KlhyetiColors c) {
    final holidays = widget.holidays.namesOn(_selectedDay);
    return SizedBox(
      height: _peekEmpty,
      child: Column(
        children: [
          const SizedBox(height: Insets.sm),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: c.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dayHeading(_selectedDay),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: c.ink,
                        ),
                      ),
                      if (holidays.isNotEmpty)
                        Text(
                          holidays.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: c.vermilion),
                        ),
                    ],
                  ),
                ),
                // For people who would rather press a button than drag.
                AnimatedBuilder(
                  animation: _sheetOpen,
                  builder: (context, _) {
                    final bool open = _sheetOpen.value > 0.5;
                    return IconButton(
                      icon: Transform.rotate(
                        angle: math.pi * _sheetOpen.value,
                        child: const Icon(Icons.keyboard_arrow_up),
                      ),
                      tooltip: open ? 'Collapse' : 'Expand',
                      onPressed: () => _settleSheet(open ? 0 : 1),
                    );
                  },
                ),
                const SizedBox(width: Insets.sm),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fab() {
    return FloatingActionButton(
      onPressed: () => _openEditor(null),
      tooltip: 'Add event',
      child: const Icon(Icons.add),
    );
  }
}
