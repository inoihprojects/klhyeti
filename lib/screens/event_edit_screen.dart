import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/event_repository.dart';
import '../data/reminders.dart';
import '../data/settings_repository.dart';
import '../models/calendar_event.dart';
import '../models/recurrence.dart';
import '../theme/tokens.dart';
import '../widgets/event_list.dart'
    show clockText, dayHeading, formatTimeOfDay, ordinal;
import '../widgets/settings_rows.dart' show chooseOne;
import '../widgets/tap_fade.dart';
import '../widgets/wheel_time_picker.dart';

class EventEditScreen extends StatefulWidget {
  final EventRepository repo;
  final SettingsRepository settings;
  final CalendarEvent? existing;
  final DateTime initialDay;

  /// [existing] is one date of a repeating event, and only that date
  /// changes: saving makes it an event of its own, and deleting leaves it
  /// out of the schedule.
  final bool onlyThisDate;

  /// Shown as a Reminder field on Android only; null where nothing
  /// reminds.
  final Reminders? reminders;

  const EventEditScreen({
    super.key,
    required this.repo,
    required this.settings,
    required this.initialDay,
    this.existing,
    this.onlyThisDate = false,
    this.reminders,
  });

  @override
  State<EventEditScreen> createState() => _EventEditScreenState();
}

class _EventEditScreenState extends State<EventEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final FocusNode _titleFocus = FocusNode();
  final FocusNode _locationFocus = FocusNode();
  final FocusNode _descriptionFocus = FocusNode();
  final ScrollController _scroll = ScrollController();
  final GlobalKey _endsKey = GlobalKey();
  final GlobalKey _repeatKey = GlobalKey();
  final GlobalKey _locationKey = GlobalKey();
  final GlobalKey _descriptionKey = GlobalKey();
  late final TextEditingController _titleController;
  late final TextEditingController _locationController;
  late final TextEditingController _descriptionController;

  late DateTime _start;
  late DateTime _end;
  late bool _allDay;
  String? _timeError;

  /// Null: a one-off.
  Recurrence? _repeat;
  String? _repeatError;

  /// Minutes before (see Reminders); null for none.
  int? _reminder;

  bool get _remindable =>
      widget.reminders != null && Reminders.supported;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _titleController = TextEditingController(text: existing?.title ?? '');
    _locationController = TextEditingController(text: existing?.location ?? '');
    _descriptionController =
        TextEditingController(text: existing?.description ?? '');
    _allDay = existing?.allDay ?? false;
    _start = existing?.startAt.toLocal() ??
        DateTime(widget.initialDay.year, widget.initialDay.month,
            widget.initialDay.day, 9, 0);
    _end = existing?.endAt.toLocal() ?? _start.add(const Duration(hours: 1));
    _repeat = widget.onlyThisDate ? null : existing?.recurrence;
    _reminder = existing == null ? null : widget.reminders?.minutesFor(existing.id);
    _locationFocus.addListener(() {
      if (_locationFocus.hasFocus) _keepAboveKeyboard(_locationKey);
    });
    _descriptionFocus.addListener(() {
      if (_descriptionFocus.hasFocus) _keepAboveKeyboard(_descriptionKey);
    });
    // The description grows as it is typed into; keep its end in sight.
    _descriptionController.addListener(() {
      if (_descriptionFocus.hasFocus) {
        _keepAboveKeyboard(_descriptionKey, after: Duration.zero);
      }
    });
  }

  /// The page doesn't shrink for the keyboard (see [build]), so a field
  /// lower down that the keyboard would cover is scrolled up by hand,
  /// once the keyboard has risen.
  void _keepAboveKeyboard(GlobalKey field,
      {Duration after = const Duration(milliseconds: 350)}) {
    Future<void>.delayed(after, () {
      if (!mounted || !_scroll.hasClients) return;
      final box = field.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) return;
      // Read from the view, not MediaQuery: depending on the keyboard's
      // height would rebuild this screen on every frame of its rise.
      final view = View.of(context);
      final keyboardTop =
          (view.physicalSize.height - view.viewInsets.bottom) /
              view.devicePixelRatio;
      final fieldBottom =
          box.localToGlobal(Offset(0, box.size.height)).dy + Insets.md;
      final overlap = fieldBottom - keyboardTop;
      if (overlap <= 0) return;
      _scroll.animateTo(
        math.min(_scroll.offset + overlap, _scroll.position.maxScrollExtent),
        duration: Motion.of(context, Motion.page),
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// Scrolls to a field whose problem stops the save.
  void _reveal(GlobalKey field) {
    final target = field.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      alignment: 0.2,
      duration: Motion.of(context, Motion.page),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _titleFocus.dispose();
    _locationFocus.dispose();
    _descriptionFocus.dispose();
    _scroll.dispose();
    _titleController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  bool get _use24Hour =>
      widget.settings.use24HourTime ??
      MediaQuery.alwaysUse24HourFormatOf(context);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final isEditing = widget.existing != null;

    return Scaffold(
      // The keyboard slides over the page instead of shrinking it: a page
      // that shrinks re-lays out every field on each frame of the
      // keyboard's rise, and the rise stutters. Fields it would cover are
      // scrolled into sight instead (_keepAboveKeyboard).
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(widget.onlyThisDate
            ? 'Edit this date'
            : (isEditing ? 'Edit event' : 'New event')),
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
              onPressed: _delete,
            ),
          const SizedBox(width: Insets.sm),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Form(
          key: _formKey,
          // Every field built at once, not lazily as a ListView would: a
          // field scrolled far out of sight would be dropped, and a Form
          // doesn't check a dropped field, so an empty title could save.
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.all(Insets.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _label(c, 'Title'),
                TextFormField(
                  controller: _titleController,
                  focusNode: _titleFocus,
                  autofocus: !isEditing,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'What is it?'),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'A title is required'
                      : null,
                ),
                const SizedBox(height: Insets.lg),
                _AllDayRow(
                  value: _allDay,
                  onChanged: (value) => setState(() {
                    _allDay = value;
                    // The two kinds of event offer different reminders;
                    // keep the nearest.
                    final r = _reminder;
                    if (r != null) {
                      _reminder = value ? (r >= 1440 ? 900 : -540)
                          : (r == 900 ? 1440 : 0);
                    }
                  }),
                ),
                const SizedBox(height: Insets.sm),
                _label(c, 'Starts'),
                _DateTimeRow(
                  date: _start,
                  allDay: _allDay,
                  use24Hour: _use24Hour,
                  onPickDate: () => _pickDate(isStart: true),
                  onPickTime: () => _pickTime(isStart: true),
                ),
                const SizedBox(height: Insets.md),
                _label(c, 'Ends'),
                _DateTimeRow(
                  key: _endsKey,
                  date: _end,
                  allDay: _allDay,
                  use24Hour: _use24Hour,
                  onPickDate: () => _pickDate(isStart: false),
                  onPickTime: () => _pickTime(isStart: false),
                ),
                if (_timeError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Insets.sm),
                    child: Text(
                      _timeError!,
                      style: TextStyle(fontSize: 13, color: c.vermilion),
                    ),
                  ),
                if (!widget.onlyThisDate) ...[
                  const SizedBox(height: Insets.lg),
                  _label(c, 'Repeat'),
                  _RepeatEditor(
                    key: _repeatKey,
                    rule: _repeat,
                    start: _start,
                    weekStartsMonday: widget.settings.weekStartsMonday,
                    error: _repeatError,
                    onChanged: (rule) => setState(() {
                      _repeat = rule;
                      _repeatError = null;
                    }),
                  ),
                ],
                if (_remindable) ...[
                  const SizedBox(height: Insets.lg),
                  _label(c, 'Reminder'),
                  _FieldBox(
                    text: _reminderText(_reminder),
                    onTap: _pickReminder,
                  ),
                ],
                const SizedBox(height: Insets.lg),
                _label(c, 'Location'),
                TextFormField(
                  key: _locationKey,
                  focusNode: _locationFocus,
                  controller: _locationController,
                  decoration: const InputDecoration(hintText: 'Where?'),
                ),
                const SizedBox(height: Insets.lg),
                _label(c, 'Description'),
                TextFormField(
                  key: _descriptionKey,
                  focusNode: _descriptionFocus,
                  controller: _descriptionController,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(hintText: 'Anything else'),
                ),
                const SizedBox(height: Insets.xl),
                FilledButton(onPressed: _save, child: const Text('Save')),
                // Room to scroll the lowest fields above a keyboard, which
                // covers the page rather than shrinking it.
                SizedBox(height: MediaQuery.sizeOf(context).height * 0.4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _reminderText(int? minutes) {
    final nine = clockText(DateTime(2000, 1, 1, 9), _use24Hour);
    return switch (minutes) {
      null => 'None',
      0 => 'At the start',
      10 => '10 minutes before',
      60 => '1 hour before',
      1440 => '1 day before',
      -540 => 'At $nine that day',
      900 => 'At $nine the day before',
      final m => '$m minutes before',
    };
  }

  Future<void> _pickReminder() async {
    final choices = _allDay ? Reminders.allDayChoices : Reminders.timedChoices;
    final picked = await chooseOne<int?>(
      context,
      title: 'Reminder',
      options: {for (final minutes in choices) minutes: _reminderText(minutes)},
      current: _reminder,
    );
    if (picked == null || !mounted) return;
    setState(() => _reminder = picked.$1);
  }

  Widget _label(KlhyetiColors c, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.xs),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: c.ink3,
        ),
      ),
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final base = isStart ? _start : _end;
    final picked = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    _apply(
      isStart: isStart,
      value: DateTime(
          picked.year, picked.month, picked.day, base.hour, base.minute),
    );
  }

  Future<void> _pickTime({required bool isStart}) async {
    final base = isStart ? _start : _end;
    final picked = await showWheelTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
      use24HourFormat: _use24Hour,
      title: isStart ? 'Starts at' : 'Ends at',
    );
    if (picked == null || !mounted) return;
    _apply(
      isStart: isStart,
      value: DateTime(
          base.year, base.month, base.day, picked.hour, picked.minute),
    );
  }

  void _apply({required bool isStart, required DateTime value}) {
    setState(() {
      _timeError = null;
      // A weekly schedule on the start's weekday alone follows the start
      // to its new weekday.
      final repeat = _repeat;
      if (isStart &&
          repeat != null &&
          repeat.unit == RepeatUnit.week &&
          repeat.weekdays.length == 1 &&
          repeat.weekdays.contains(_start.weekday)) {
        _repeat = repeat.copyWith(weekdays: {value.weekday});
      }
      if (isStart) {
        // Moving the start carries the end with it, keeping the duration —
        // which is what you want almost every time.
        final duration = _end.difference(_start);
        _start = value;
        _end = value.add(duration.isNegative ? const Duration(hours: 1) : duration);
      } else {
        _end = value;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      // The empty title is at the top, and Save may be far below it.
      _titleFocus.requestFocus();
      if (_scroll.hasClients) {
        _scroll.animateTo(0,
            duration: Motion.of(context, Motion.page),
            curve: Curves.easeOutCubic);
      }
      return;
    }
    if (!_allDay && !_end.isAfter(_start)) {
      setState(() => _timeError = 'The end has to come after the start.');
      _reveal(_endsKey);
      return;
    }
    final repeat = _repeat;
    final until = repeat?.until;
    if (until != null && until < ymd(_start)) {
      setState(() => _repeatError = 'It has to end on or after its first date.');
      _reveal(_repeatKey);
      return;
    }

    final existing = widget.existing;
    final title = _titleController.text.trim();
    final description = _emptyToNull(_descriptionController.text);
    final location = _emptyToNull(_locationController.text);

    final int? day = existing?.occurrenceDay;
    final String id;
    if (existing != null && widget.onlyThisDate && day != null) {
      id = await widget.repo.detachDate(
        existing.id,
        day,
        title: title,
        description: description,
        location: location,
        startAt: _start,
        endAt: _end,
        allDay: _allDay,
      );
    } else if (existing == null) {
      id = await widget.repo.createEvent(
        title: title,
        description: description,
        location: location,
        startAt: _start,
        endAt: _end,
        allDay: _allDay,
        rrule: repeat?.format(),
      );
    } else {
      await widget.repo.updateEvent(
        existing,
        title: title,
        description: description,
        location: location,
        startAt: _start,
        endAt: _end,
        allDay: _allDay,
        rrule: repeat?.format(),
      );
      id = existing.id;
    }
    if (_remindable) await widget.reminders!.set(id, _reminder);

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final int? day = existing.occurrenceDay;
    final bool oneDate = widget.onlyThisDate && day != null;
    final String question;
    if (oneDate) {
      question = 'Delete "${existing.title}" on '
          '${dayHeading(existing.startAt.toLocal())}? The rest of the '
          'schedule stays.';
    } else {
      question = 'Delete "${existing.title}"'
          '${existing.rrule != null ? ' and all its dates' : ''}? It also '
          'goes from your other devices when they next sync.';
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(oneDate ? 'Delete this date?' : 'Delete event?'),
        content: Text(question),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (widget.onlyThisDate && day != null) {
      await widget.repo.skipDate(existing.id, day);
    } else {
      await widget.repo.softDelete(existing.id);
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  String? _emptyToNull(String value) =>
      value.trim().isEmpty ? null : value.trim();
}

class _AllDayRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _AllDayRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      children: [
        Expanded(
          child: Text(
            'All day',
            style: TextStyle(fontSize: 15, color: c.ink),
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _DateTimeRow extends StatelessWidget {
  final DateTime date;
  final bool allDay;
  final bool use24Hour;
  final VoidCallback onPickDate;
  final VoidCallback onPickTime;

  const _DateTimeRow({
    super.key,
    required this.date,
    required this.allDay,
    required this.use24Hour,
    required this.onPickDate,
    required this.onPickTime,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    Widget chip(String text, VoidCallback onTap, {bool wide = false}) {
      return TapFade(
        onTap: onTap,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: Insets.md),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: BorderRadius.circular(Radii.cell),
            border: Border.all(color: c.line),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 15,
              color: c.ink,
              fontFeatures: tabularFigures,
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(flex: 3, child: chip(_dateText(date), onPickDate)),
        if (!allDay) ...[
          const SizedBox(width: Insets.sm),
          Expanded(
            flex: 2,
            child: chip(
              formatTimeOfDay(context, date, use24Hour),
              onPickTime,
            ),
          ),
        ],
      ],
    );
  }
}

/// The Repeat field: "Never" until tapped. Once repeating, the details
/// show below it: how often, which weekdays (weekly), and until when.
class _RepeatEditor extends StatelessWidget {
  final Recurrence? rule;
  final DateTime start;
  final bool weekStartsMonday;
  final String? error;
  final ValueChanged<Recurrence?> onChanged;

  const _RepeatEditor({
    super.key,
    required this.rule,
    required this.start,
    required this.weekStartsMonday,
    required this.error,
    required this.onChanged,
  });

  static const Map<RepeatUnit, String> _every = {
    RepeatUnit.day: 'Daily',
    RepeatUnit.week: 'Weekly',
    RepeatUnit.month: 'Monthly',
    RepeatUnit.year: 'Yearly',
  };

  static String _unitName(RepeatUnit unit, int n) {
    final name = unit.name; // day, week, month, year
    return n == 1 ? name : '${name}s';
  }

  Future<void> _pickUnit(BuildContext context) async {
    final current = rule;
    final chosen = await chooseOne<RepeatUnit?>(
      context,
      title: 'Repeat',
      options: {null: 'Never', ..._every},
      current: current?.unit,
    );
    if (chosen == null) return;
    final unit = chosen.$1;
    if (unit == null) {
      onChanged(null);
    } else if (unit != current?.unit) {
      onChanged(Recurrence(
        unit: unit,
        weekdays: {start.weekday},
        weekStartsMonday: weekStartsMonday,
        until: current?.until,
      ));
    }
  }

  Future<void> _pickUntil(BuildContext context, Recurrence r) async {
    final firstDay = DateTime(start.year, start.month, start.day);
    final until = r.until;
    final picked = await showDatePicker(
      context: context,
      initialDate: until == null
          ? DateTime(start.year, start.month + 3, start.day)
          : fromYmd(until),
      firstDate: firstDay,
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    onChanged(r.copyWith(until: ymd(picked)));
  }

  /// Said when the schedule names a date some months or years lack.
  String? _note(Recurrence r) {
    if (r.unit == RepeatUnit.month && start.day > 28) {
      return 'Months without a ${ordinal(start.day)} are skipped.';
    }
    if (r.unit == RepeatUnit.year && start.month == 2 && start.day == 29) {
      return 'Only in leap years.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final r = rule;
    final small = TextStyle(fontSize: 13, color: c.ink3, height: 1.4);
    final body = TextStyle(fontSize: 15, color: c.ink);

    if (r == null) {
      return _FieldBox(text: 'Never', onTap: () => _pickUnit(context));
    }
    final note = _note(r);
    final until = r.until;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldBox(text: _every[r.unit]!, onTap: () => _pickUnit(context)),
        const SizedBox(height: Insets.xs),
        Row(
          children: [
            Text('Every', style: body),
            IconButton(
              icon: const Icon(Icons.remove),
              tooltip: 'Less often',
              onPressed: r.interval > 1
                  ? () => onChanged(r.copyWith(interval: r.interval - 1))
                  : null,
            ),
            SizedBox(
              width: 28,
              child: Text(
                '${r.interval}',
                textAlign: TextAlign.center,
                style: body.copyWith(fontFeatures: tabularFigures),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'More apart',
              onPressed: r.interval < 99
                  ? () => onChanged(r.copyWith(interval: r.interval + 1))
                  : null,
            ),
            Text(_unitName(r.unit, r.interval), style: body),
          ],
        ),
        if (r.unit == RepeatUnit.week) ...[
          const SizedBox(height: Insets.xs),
          _WeekdayPicker(
            selected: r.weekdays,
            weekStartsMonday: r.weekStartsMonday,
            onChanged: (days) => onChanged(r.copyWith(weekdays: days)),
          ),
        ],
        const SizedBox(height: Insets.md),
        Row(
          children: [
            SizedBox(width: 48, child: Text('Until', style: body)),
            Expanded(
              child: _FieldBox(
                text: 'Forever',
                selected: until == null,
                onTap: () => onChanged(r.copyWith(clearUntil: true)),
              ),
            ),
            const SizedBox(width: Insets.sm),
            Expanded(
              child: _FieldBox(
                text: until == null ? 'A date' : _dateText(fromYmd(until)),
                selected: until != null,
                onTap: () => _pickUntil(context, r),
              ),
            ),
          ],
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: Insets.sm),
            child: Text(note, style: small),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: Insets.sm),
            child: Text(
              error!,
              style: TextStyle(fontSize: 13, color: c.vermilion),
            ),
          ),
      ],
    );
  }
}

/// "2026-11-08": dates in the editor's fields.
String _dateText(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}'
    '-${date.day.toString().padLeft(2, '0')}';

/// Seven toggles, in the order the week runs. At least one stays on.
class _WeekdayPicker extends StatelessWidget {
  final Set<int> selected;
  final bool weekStartsMonday;
  final ValueChanged<Set<int>> onChanged;

  const _WeekdayPicker({
    required this.selected,
    required this.weekStartsMonday,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final first = weekStartsMonday ? DateTime.monday : DateTime.sunday;
    final days = [for (var i = 0; i < 7; i++) (first - 1 + i) % 7 + 1];
    return Row(
      children: [
        for (final day in days)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: TapFade(
                semanticLabel: weekdayNames[day - 1],
                selected: selected.contains(day),
                onTap: () {
                  final next = {...selected};
                  if (!next.remove(day)) next.add(day);
                  if (next.isNotEmpty) onChanged(next);
                },
                child: Container(
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected.contains(day) ? c.ink : c.surfaceAlt,
                    borderRadius: BorderRadius.circular(Radii.cell),
                    border: Border.all(
                        color: selected.contains(day) ? c.ink : c.line),
                  ),
                  child: Text(
                    weekdayNames[day - 1].substring(0, 2),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected.contains(day) ? c.bg : c.ink2,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A tappable field in the editor's style: [surfaceAlt], a hairline, and
/// with [selected], an ink outline.
class _FieldBox extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  final bool selected;

  const _FieldBox({
    required this.text,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return TapFade(
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: Insets.md),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          borderRadius: BorderRadius.circular(Radii.cell),
          border: Border.all(color: selected ? c.ink : c.line),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            color: c.ink,
            fontFeatures: tabularFigures,
          ),
        ),
      ),
    );
  }
}
