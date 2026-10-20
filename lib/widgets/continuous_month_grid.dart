import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

import '../theme/tokens.dart';
import 'month_grid.dart';

/// A request for [ContinuousMonthGrid] to bring a month into view, with
/// its first week at the top.
///
/// The grid acts whenever it is handed a different MonthJump object, not a
/// different month, so asking for the month already shown (pressing Today
/// after scrolling away a little) still scrolls. Create a new one per
/// request; never reuse or const-construct one.
class MonthJump {
  final DateTime month;
  MonthJump(this.month);
}

/// Weeks as one continuous vertical list, with no month boundaries.
///
/// The month owning most of the visible rows is reported through
/// [onFocusedMonthChanged]; the parent names it in the header and passes
/// it back as [focusedMonth], whose days are drawn at full strength and
/// the rest faded. Rows are a fixed [rowHeight] and scrolling settles on
/// a row boundary, so a week is never left cut in half at the top.
class ContinuousMonthGrid extends StatefulWidget {
  final DateTime focusedMonth;
  final DateTime selectedDay;
  final DateTime today;
  final Map<DateTime, int> eventCounts;
  final bool weekStartsMonday;
  final bool colourWeekends;
  final HolidayNames holidays;
  final double rowHeight;
  final MonthJump? jump;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<DateTime> onFocusedMonthChanged;

  const ContinuousMonthGrid({
    super.key,
    required this.focusedMonth,
    required this.selectedDay,
    required this.today,
    required this.eventCounts,
    required this.weekStartsMonday,
    required this.colourWeekends,
    this.holidays = noHolidays,
    required this.rowHeight,
    required this.jump,
    required this.onSelect,
    required this.onFocusedMonthChanged,
  });

  @override
  State<ContinuousMonthGrid> createState() => _ContinuousMonthGridState();
}

class _ContinuousMonthGridState extends State<ContinuousMonthGrid> {
  // The scrollable range. Wide enough that nobody reaches an end, finite
  // so the list has a length and a week's position is plain arithmetic.
  static final DateTime _rangeStart = DateTime(1900, 1, 1);
  static final DateTime _rangeEnd = DateTime(2200, 1, 1);

  late DateTime _origin; // first day of week 0
  late int _weekCount;
  late final ScrollController _scroll;
  late DateTime _reportedMonth;
  double? _lastViewport;

  @override
  void initState() {
    super.initState();
    _setOrigin();
    _reportedMonth = widget.focusedMonth;
    _scroll = ScrollController(
      initialScrollOffset: _offsetForMonth(widget.focusedMonth),
    );
    _scroll.addListener(_reportMonth);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _setOrigin() {
    _origin = weekStartOf(_rangeStart, widget.weekStartsMonday);
    _weekCount = daysBetween(_origin, _rangeEnd) ~/ 7;
  }

  DateTime _weekStart(int index) =>
      DateTime(_origin.year, _origin.month, _origin.day + 7 * index);

  int _weekIndexOf(DateTime day) {
    final index = daysBetween(_origin, day) ~/ 7;
    return math.max(0, math.min(_weekCount - 1, index));
  }

  double _offsetForMonth(DateTime month) =>
      _weekIndexOf(DateTime(month.year, month.month, 1)) * widget.rowHeight;

  @override
  void didUpdateWidget(ContinuousMonthGrid oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.weekStartsMonday != widget.weekStartsMonday ||
        oldWidget.rowHeight != widget.rowHeight) {
      // Every row moved: keep the same month in view.
      _setOrigin();
      final keep = _reportedMonth;
      _afterFrame(() {
        if (_scroll.hasClients) _scroll.jumpTo(_clamp(_offsetForMonth(keep)));
      });
    }

    if (!identical(oldWidget.jump, widget.jump) && widget.jump != null) {
      final target = widget.jump!.month;
      _afterFrame(() => _scrollToMonth(target));
    } else if (!isSameDay(oldWidget.selectedDay, widget.selectedDay)) {
      // Arrow keys can walk the selection off screen; follow it.
      _afterFrame(() => _ensureVisible(widget.selectedDay, animate: true));
    }
  }

  void _afterFrame(VoidCallback action) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) action();
    });
  }

  double _clamp(double offset) {
    final position = _scroll.position;
    return math.max(
        position.minScrollExtent, math.min(position.maxScrollExtent, offset));
  }

  bool get _animate => Motion.of(context, Motion.month) != Duration.zero;

  void _scrollToMonth(DateTime month) {
    if (!_scroll.hasClients) return;
    final target = _clamp(_offsetForMonth(month));
    final distance = (target - _scroll.offset).abs();
    // A long way off (the year view, a far jump) is a cut, not a ride
    // through dozens of weeks.
    if (!_animate || distance > widget.rowHeight * 12) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(
        target,
        duration: Motion.monthScroll,
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// Scrolls the least distance that shows [day]'s whole week. Targets are
  /// row boundaries, because the snapping physics would otherwise round a
  /// part-row target and could push the week half out again.
  void _ensureVisible(DateTime day, {required bool animate}) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final double h = widget.rowHeight;
    final double top = _weekIndexOf(day) * h;
    final double bottom = top + h;

    double? target;
    if (top < position.pixels) {
      target = top;
    } else if (bottom > position.pixels + position.viewportDimension) {
      target = ((bottom - position.viewportDimension) / h).ceilToDouble() * h;
    }
    if (target == null) return;
    target = _clamp(target);

    if (animate && _animate) {
      _scroll.animateTo(target,
          duration: Motion.month, curve: Curves.easeOutCubic);
    } else {
      _scroll.jumpTo(target);
    }
  }

  /// The grid's height changes when the event sheet's resting height does,
  /// which follows the selected day. Keep that day's week in view.
  bool _onMetrics(ScrollMetricsNotification notification) {
    final double viewport = notification.metrics.viewportDimension;
    final double? last = _lastViewport;
    _lastViewport = viewport;
    if (last != null && viewport != last) {
      _ensureVisible(widget.selectedDay, animate: false);
    }
    return false;
  }

  void _reportMonth() {
    if (!_scroll.hasClients) return;
    // The listener can fire while a frame is being laid out (a jump that
    // clamps); the parent can't rebuild then, so report after the frame.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      _afterFrame(_reportMonth);
      return;
    }
    final month = _majorityMonth(_scroll.position);
    if (month == _reportedMonth) return;
    _reportedMonth = month;
    widget.onFocusedMonthChanged(month);
  }

  /// The month with the most visible days, each row weighted by how much
  /// of it is on screen. On a tie the month already shown stays, so the
  /// header doesn't flicker at the exact midpoint.
  DateTime _majorityMonth(ScrollPosition position) {
    final double h = widget.rowHeight;
    final double top = position.pixels;
    final double bottom = top + position.viewportDimension;
    final int first = math.max(0, (top / h).floor());
    final int last = math.min(_weekCount - 1, ((bottom - 0.5) / h).floor());

    final weight = <DateTime, double>{};
    for (int i = first; i <= last; i++) {
      final double shown =
          (math.min(bottom, (i + 1) * h) - math.max(top, i * h)) / h;
      if (shown <= 0) continue;
      final start = _weekStart(i);
      for (int d = 0; d < 7; d++) {
        final day = DateTime(start.year, start.month, start.day + d);
        final month = DateTime(day.year, day.month);
        weight[month] = (weight[month] ?? 0) + shown;
      }
    }

    DateTime best = _reportedMonth;
    double bestWeight = weight[_reportedMonth] ?? -1;
    weight.forEach((month, w) {
      if (w > bestWeight) {
        best = month;
        bestWeight = w;
      }
    });
    return best;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        WeekdayHeader(
          weekStartsMonday: widget.weekStartsMonday,
          colourWeekends: widget.colourWeekends,
        ),
        Expanded(
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: _onMetrics,
            child: ListView.builder(
              controller: _scroll,
              padding: EdgeInsets.zero,
              physics: WeekSnapPhysics(rowHeight: () => widget.rowHeight),
              itemExtent: widget.rowHeight,
              itemCount: _weekCount,
              itemBuilder: (context, index) => _week(index),
            ),
          ),
        ),
      ],
    );
  }

  Widget _week(int index) {
    final start = _weekStart(index);
    return Row(
      children: [
        for (int d = 0; d < 7; d++)
          Expanded(
            child: _day(DateTime(start.year, start.month, start.day + d)),
          ),
      ],
    );
  }

  Widget _day(DateTime day) {
    return DayCell(
      day: day,
      inMonth: day.year == widget.focusedMonth.year &&
          day.month == widget.focusedMonth.month,
      selected: isSameDay(day, widget.selectedDay),
      isToday: isSameDay(day, widget.today),
      eventCount: widget.eventCounts[day] ?? 0,
      colourWeekends: widget.colourWeekends,
      holidays: widget.holidays(day),
      onTap: () => widget.onSelect(day),
    );
  }
}

/// Lets a fling run its natural distance, then settles on the nearest
/// row boundary, so the list always rests with a whole week at the top.
///
/// [rowHeight] is read when needed rather than copied: a list keeps its
/// first physics object until the physics *type* changes, so a copied
/// height would go stale when the rows are resized.
class WeekSnapPhysics extends ScrollPhysics {
  final ValueGetter<double> rowHeight;

  const WeekSnapPhysics({required this.rowHeight, super.parent});

  @override
  WeekSnapPhysics applyTo(ScrollPhysics? ancestor) {
    return WeekSnapPhysics(rowHeight: rowHeight, parent: buildParent(ancestor));
  }

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    // Past either end, the platform's own overscroll behaviour applies.
    if ((velocity <= 0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }

    // Where the platform's fling would stop, rounded to a row.
    final Simulation? natural =
        super.createBallisticSimulation(position, velocity);
    final double projected = natural?.x(10.0) ?? position.pixels;
    final double h = rowHeight();
    final double target = math.max(
      position.minScrollExtent,
      math.min(position.maxScrollExtent, (projected / h).roundToDouble() * h),
    );

    final Tolerance tolerance = toleranceFor(position);
    if ((target - position.pixels).abs() < tolerance.distance &&
        velocity.abs() < tolerance.velocity) {
      return null;
    }
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: tolerance,
    );
  }
}
