import 'package:flutter/material.dart';

import '../data/event_repository.dart';
import '../data/settings_repository.dart';
import '../models/calendar_event.dart';
import '../theme/tokens.dart';
import '../widgets/event_list.dart' show formatTimeOfDay;
import '../widgets/tap_fade.dart';
import '../widgets/wheel_time_picker.dart';

class EventEditScreen extends StatefulWidget {
  final EventRepository repo;
  final SettingsRepository settings;
  final CalendarEvent? existing;
  final DateTime initialDay;

  const EventEditScreen({
    super.key,
    required this.repo,
    required this.settings,
    required this.initialDay,
    this.existing,
  });

  @override
  State<EventEditScreen> createState() => _EventEditScreenState();
}

class _EventEditScreenState extends State<EventEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _locationController;
  late final TextEditingController _descriptionController;

  late DateTime _start;
  late DateTime _end;
  late bool _allDay;
  String? _timeError;

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
  }

  @override
  void dispose() {
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
      appBar: AppBar(
        title: Text(isEditing ? 'Edit event' : 'New event'),
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
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(Insets.md),
            children: [
              _label(c, 'Title'),
              TextFormField(
                controller: _titleController,
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
                onChanged: (value) => setState(() => _allDay = value),
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
              const SizedBox(height: Insets.lg),
              _label(c, 'Location'),
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(hintText: 'Where?'),
              ),
              const SizedBox(height: Insets.lg),
              _label(c, 'Description'),
              TextFormField(
                controller: _descriptionController,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(hintText: 'Anything else'),
              ),
              const SizedBox(height: Insets.xl),
              FilledButton(onPressed: _save, child: const Text('Save')),
              const SizedBox(height: Insets.md),
            ],
          ),
        ),
      ),
    );
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
    if (!_formKey.currentState!.validate()) return;
    if (!_allDay && !_end.isAfter(_start)) {
      setState(() => _timeError = 'The end has to come after the start.');
      return;
    }

    final existing = widget.existing;
    final title = _titleController.text.trim();
    final description = _emptyToNull(_descriptionController.text);
    final location = _emptyToNull(_locationController.text);

    if (existing == null) {
      await widget.repo.createEvent(
        title: title,
        description: description,
        location: location,
        startAt: _start,
        endAt: _end,
        allDay: _allDay,
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
      );
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete event?'),
        content: Text(
          'Delete "${existing.title}"? It will also disappear from your '
          'other device the next time you sync.',
        ),
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
    await widget.repo.softDelete(existing.id);
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

    final dateText = '${date.year}-${date.month.toString().padLeft(2, '0')}'
        '-${date.day.toString().padLeft(2, '0')}';

    return Row(
      children: [
        Expanded(flex: 3, child: chip(dateText, onPickDate)),
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
