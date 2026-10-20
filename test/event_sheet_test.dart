// The calendar is only reachable while the sheet is exactly closed: any
// leftover open fraction keeps a touch-swallowing dimmer over it. A spring
// on its own stops merely near its target, so settles must land exactly.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klhyeti/widgets/event_sheet.dart';

void main() {
  testWidgets('a settle ends exactly on its target, even after a flick',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        context = c;
        return const SizedBox.shrink();
      }),
    ));

    final open = AnimationController(vsync: const TestVSync());
    addTearDown(open.dispose);

    // Hard flicks, both ways, from part-way and from the far end.
    for (final (start, target, velocity) in [
      (0.4, 0.0, -8.0),
      (0.0, 0.0, -8.0),
      (0.6, 1.0, 8.0),
      (1.0, 1.0, 8.0),
      (0.02, 0.0, 0.0),
    ]) {
      open.value = start;
      settleSheet(context, open, target, velocity: velocity);
      await tester.pumpAndSettle();
      expect(open.value, target, reason: 'from $start at $velocity');
    }
  });
}
