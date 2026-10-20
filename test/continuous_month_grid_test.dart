// The continuous grid's positions are arithmetic over a very long list,
// and the month it names comes from what is on screen. Both are easy to
// get subtly wrong and only show on a phone, so they are pinned down here.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klhyeti/theme/app_theme.dart';
import 'package:klhyeti/widgets/continuous_month_grid.dart';
import 'package:klhyeti/widgets/month_grid.dart';

const double rowHeight = 60;

ContinuousMonthGrid grid({
  MonthJump? jump,
  ValueChanged<DateTime>? onMonth,
}) {
  return ContinuousMonthGrid(
    focusedMonth: DateTime(2026, 9),
    selectedDay: DateTime(2026, 9, 15),
    today: DateTime(2026, 9, 15),
    eventCounts: const {},
    weekStartsMonday: false,
    colourWeekends: true,
    rowHeight: rowHeight,
    jump: jump,
    onSelect: (_) {},
    onFocusedMonthChanged: onMonth ?? (_) {},
  );
}

/// Exactly six rows tall, at the top of the test screen.
Widget host(ContinuousMonthGrid child) {
  return MaterialApp(
    theme: buildKlhyetiTheme(Brightness.light),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 420,
          height: WeekdayHeader.height + 6 * rowHeight,
          child: child,
        ),
      ),
    ),
  );
}

Finder cell(DateTime day) => find.byWidgetPredicate(
      (widget) => widget is DayCell && widget.day == day,
    );

void main() {
  testWidgets('opens with the focused month\'s first week at the top',
      (tester) async {
    await tester.pumpWidget(host(grid()));
    // September 2026 begins on a Tuesday; with Sunday first, its first
    // week starts on Sunday 30 August.
    expect(tester.getTopLeft(cell(DateTime(2026, 8, 30))).dy,
        closeTo(WeekdayHeader.height, 0.5));
  });

  testWidgets('scrolling names the month that fills most of the screen',
      (tester) async {
    DateTime? reported;
    await tester.pumpWidget(host(grid(onMonth: (m) => reported = m)));
    expect(reported, isNull, reason: 'nothing to report before scrolling');

    // About five weeks up, slowly, so the fling adds little.
    await tester.timedDrag(find.byType(ListView), const Offset(0, -300),
        const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(reported, DateTime(2026, 10));
    // And it came to rest on a row boundary.
    final double top = tester.getTopLeft(find.byType(ListView)).dy;
    final double firstRow = tester.getTopLeft(cell(DateTime(2026, 10, 4))).dy;
    final double offRow = (firstRow - top) % rowHeight;
    expect(math.min(offRow, rowHeight - offRow), closeTo(0, 0.5));
  });

  testWidgets('a jump brings the month\'s first week to the top',
      (tester) async {
    await tester.pumpWidget(host(grid()));
    await tester.pumpWidget(host(grid(jump: MonthJump(DateTime(2027, 1)))));
    await tester.pumpAndSettle();
    // Friday 1 January 2027: its week starts on Sunday 27 December.
    expect(tester.getTopLeft(cell(DateTime(2026, 12, 27))).dy,
        closeTo(WeekdayHeader.height, 0.5));
  });
}
