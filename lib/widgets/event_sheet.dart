import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../theme/tokens.dart';

/// How fast a flick has to be to commit to the next state regardless of
/// how far the sheet travelled, in logical pixels (dp) per second. Low,
/// so a small flick is enough, as in a short-video feed.
const double kSheetFlickVelocity = 350;

/// The sheet's settle: critically damped, so it never bounces, and it
/// looks finished in about 170 ms.
const SpringDescription kSheetSpring =
    SpringDescription(mass: 1, stiffness: 800, damping: 56.6);

/// Moves [open] to [target] (0 = resting, 1 = expanded) on the sheet's
/// spring, carrying on at [velocity] (in `open` units per second).
void settleSheet(
  BuildContext context,
  AnimationController open,
  double target, {
  double velocity = 0,
}) {
  if (Motion.of(context, Motion.sheet) == Duration.zero) {
    open.value = target;
    return;
  }
  // A spring stops when it is merely close to its target (0.0003 open,
  // say), and a sheet that isn't exactly closed kept the invisible dimmer
  // over the calendar, swallowing every touch. Land exactly once it has
  // finished; a settle interrupted by a new drag never completes, so this
  // doesn't fight the finger.
  open
      .animateWith(SpringSimulation(kSheetSpring, open.value, target, velocity))
      .then((_) {
    open.value = target;
  });
}

/// Scroll physics for the list inside an [EventSheet]: the list never
/// reads drags itself (the sheet does, and passes on what it doesn't use),
/// but still coasts with the platform's own fling when handed one.
class SheetScrollPhysics extends ScrollPhysics {
  const SheetScrollPhysics({super.parent});

  @override
  SheetScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return SheetScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) => false;
}

/// The day's events, floating over the bottom of the calendar on phones.
///
/// Its height runs from [peekHeight] (resting) to [expandedHeight] as
/// [open] goes from 0 to 1. The parent owns [open] so it can dim the grid
/// and move the add button in step.
///
/// One vertical drag drives both the sheet and the list inside it: going
/// up, the sheet opens fully before the list scrolls; going down, the list
/// returns to its top before the sheet closes. On release a flick faster
/// than [kSheetFlickVelocity] commits in its direction whatever the
/// distance; anything slower settles to the nearer state.
///
/// [child] must be a scrollable using [scrollController] and
/// [SheetScrollPhysics].
class EventSheet extends StatefulWidget {
  final AnimationController open;
  final double peekHeight;
  final double expandedHeight;
  final ScrollController scrollController;
  final Widget child;

  const EventSheet({
    super.key,
    required this.open,
    required this.peekHeight,
    required this.expandedHeight,
    required this.scrollController,
    required this.child,
  });

  @override
  State<EventSheet> createState() => _EventSheetState();
}

class _EventSheetState extends State<EventSheet> {
  double get _range =>
      math.max(1.0, widget.expandedHeight - widget.peekHeight);

  ScrollPosition? get _list => widget.scrollController.hasClients
      ? widget.scrollController.position
      : null;

  double get _listOffset {
    final list = _list;
    return list == null ? 0 : list.pixels - list.minScrollExtent;
  }

  void _scrollListBy(double delta) {
    final list = _list;
    if (list == null) return;
    final target = math.max(list.minScrollExtent,
        math.min(list.maxScrollExtent, list.pixels + delta));
    if (target != list.pixels) list.jumpTo(target);
  }

  void _onDragStart(DragStartDetails details) {
    widget.open.stop();
    // Catch a list that is still coasting from the last fling.
    final list = _list;
    if (list != null) list.jumpTo(list.pixels);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    double dy = details.primaryDelta ?? 0; // positive = finger moving down
    if (dy < 0) {
      final double room = (1 - widget.open.value) * _range;
      final double used = math.min(-dy, room);
      if (used > 0) {
        widget.open.value += used / _range;
        dy += used;
      }
      if (dy < 0) _scrollListBy(-dy);
    } else if (dy > 0) {
      final double used = math.min(dy, _listOffset);
      if (used > 0) {
        _scrollListBy(-used);
        dy -= used;
      }
      if (dy > 0) {
        widget.open.value = math.max(0.0, widget.open.value - dy / _range);
      }
    }
  }

  void _onDragEnd(DragEndDetails details) {
    final double v = details.primaryVelocity ?? 0; // positive = downwards

    // Fully open with the list in play: the fling belongs to the list.
    // The one exception is a downward flick with the list at its top,
    // which closes the sheet.
    final bool fullyOpen = widget.open.value >= 0.999;
    if (fullyOpen && (_listOffset > 0 || v < 0)) {
      final list = _list;
      if (list is ScrollPositionWithSingleContext) list.goBallistic(-v);
      return;
    }

    final double target;
    if (v.abs() >= kSheetFlickVelocity) {
      target = v < 0 ? 1 : 0;
    } else {
      target = widget.open.value >= 0.5 ? 1 : 0;
    }
    settleSheet(context, widget.open, target, velocity: -v / _range);
  }

  /// Also called for a tap that never became a drag (on an event row, say),
  /// so a settle already under way is left alone.
  void _onDragCancel() {
    if (widget.open.isAnimating) return;
    final double target = widget.open.value >= 0.5 ? 1 : 0;
    if (widget.open.value != target) settleSheet(context, widget.open, target);
  }

  /// A mouse wheel over the sheet scrolls its list; the list can't take
  /// wheel events itself, since its physics refuse user scrolling.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) _scrollListBy(event.scrollDelta.dy);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _onPointerSignal,
      child: GestureDetector(
        onVerticalDragStart: _onDragStart,
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        onVerticalDragCancel: _onDragCancel,
        child: AnimatedBuilder(
          animation: widget.open,
          child: widget.child,
          builder: (context, child) => SizedBox(
            height: widget.peekHeight + _range * widget.open.value,
            child: child,
          ),
        ),
      ),
    );
  }
}
