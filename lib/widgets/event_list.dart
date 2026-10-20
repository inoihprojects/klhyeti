import 'package:flutter/material.dart';

import '../models/calendar_event.dart';
import '../theme/tokens.dart';
import 'tap_fade.dart';

String formatTimeOfDay(BuildContext context, DateTime local, bool? use24h) {
  final bool twentyFour =
      use24h ?? MediaQuery.alwaysUse24HourFormatOf(context);
  String two(int n) => n.toString().padLeft(2, '0');
  if (twentyFour) return '${two(local.hour)}:${two(local.minute)}';
  final int h12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final String suffix = local.hour < 12 ? 'am' : 'pm';
  return '$h12:${two(local.minute)}$suffix';
}

/// "Wednesday 23 September": how a day is named above its events.
String dayHeading(DateTime day) =>
    '${weekdayNames[day.weekday - 1]} ${day.day} ${monthNames[day.month - 1]}';

/// One day's events: time in a fixed column, a thin rule, then title and a
/// second line with location and description.
class EventRow extends StatelessWidget {
  final CalendarEvent event;
  final bool? use24HourTime;
  final VoidCallback onTap;

  const EventRow({
    super.key,
    required this.event,
    required this.use24HourTime,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final start = event.startAt.toLocal();
    final end = event.endAt.toLocal();

    final meta = <String>[
      if ((event.location ?? '').trim().isNotEmpty) event.location!.trim(),
      if ((event.description ?? '').trim().isNotEmpty)
        event.description!.trim().replaceAll('\n', ' '),
    ].join(' · ');

    return TapFade(
      onTap: onTap,
      child: Container(
        color: Colors.transparent,
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 56,
              child: event.allDay
                  ? Text(
                      'All day',
                      style: TextStyle(fontSize: 11, color: c.ink2),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formatTimeOfDay(context, start, use24HourTime),
                          style: TextStyle(
                            fontSize: 13,
                            color: c.ink,
                            fontFeatures: tabularFigures,
                          ),
                        ),
                        Text(
                          formatTimeOfDay(context, end, use24HourTime),
                          style: TextStyle(
                            fontSize: 11,
                            color: c.ink3,
                            fontFeatures: tabularFigures,
                          ),
                        ),
                      ],
                    ),
            ),
            Container(
              width: 2,
              height: 32,
              margin: const EdgeInsets.only(right: Insets.md, top: 2),
              color: c.ink2,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: c.ink,
                    ),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: c.ink2),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The scrolling body shared by the phone sheet and the desktop side panel.
class DayEventList extends StatelessWidget {
  final DateTime day;
  final List<CalendarEvent>? events; // null while loading
  final bool? use24HourTime;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final ValueChanged<CalendarEvent> onOpenEvent;
  final VoidCallback onAddEvent;
  final Widget? header;

  /// False when [header] already names the day, as the phone sheet's does.
  final bool showDateHeading;

  /// The day's holidays, shown in vermilion under the date heading.
  final List<String> holidays;

  const DayEventList({
    super.key,
    required this.day,
    required this.events,
    required this.use24HourTime,
    required this.onOpenEvent,
    required this.onAddEvent,
    this.controller,
    this.physics,
    this.header,
    this.showDateHeading = true,
    this.holidays = const [],
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final list = events;

    return CustomScrollView(
      controller: controller,
      physics: physics,
      slivers: [
        if (header != null) SliverToBoxAdapter(child: header!),
        if (showDateHeading)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  Insets.md, Insets.xs, Insets.md, Insets.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dayHeading(day),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                  if (holidays.isNotEmpty)
                    Text(
                      holidays.join(' · '),
                      style: TextStyle(fontSize: 13, color: c.vermilion),
                    ),
                ],
              ),
            ),
          ),
        if (list == null)
          const SliverToBoxAdapter(child: SizedBox.shrink())
        else if (list.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Insets.lg),
              child: Column(
                children: [
                  Text(
                    'Nothing scheduled',
                    style: TextStyle(fontSize: 14, color: c.ink3),
                  ),
                  TextButton(
                    onPressed: onAddEvent,
                    child: const Text('Add event'),
                  ),
                ],
              ),
            ),
          )
        else
          SliverList.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, thickness: 1, color: c.line),
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.md),
              child: EventRow(
                event: list[i],
                use24HourTime: use24HourTime,
                onTap: () => onOpenEvent(list[i]),
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }
}
