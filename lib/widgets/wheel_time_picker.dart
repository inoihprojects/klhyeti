import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

const int kMinuteStep = 5;

/// A time picker whose minutes move in 5-minute steps, because a calendar
/// doesn't need 09:37, with a keypad button for the rare time that does.
/// Flutter's own picker can't do intervals.
Future<TimeOfDay?> showWheelTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  required bool use24HourFormat,
  String title = 'Choose a time',
}) {
  return showDialog<TimeOfDay>(
    context: context,
    builder: (context) => _WheelTimePickerDialog(
      initialTime: initialTime,
      use24HourFormat: use24HourFormat,
      title: title,
    ),
  );
}

class _WheelTimePickerDialog extends StatefulWidget {
  final TimeOfDay initialTime;
  final bool use24HourFormat;
  final String title;

  const _WheelTimePickerDialog({
    required this.initialTime,
    required this.use24HourFormat,
    required this.title,
  });

  @override
  State<_WheelTimePickerDialog> createState() => _WheelTimePickerDialogState();
}

class _WheelTimePickerDialogState extends State<_WheelTimePickerDialog> {
  late int _hour = widget.initialTime.hour;
  late int _minute = _snapMinute(widget.initialTime.minute);

  bool _typing = false;
  late final TextEditingController _hourField =
      TextEditingController(text: _hour.toString().padLeft(2, '0'));
  late final TextEditingController _minuteField =
      TextEditingController(text: _minute.toString().padLeft(2, '0'));

  late final FixedExtentScrollController _hourWheel =
      FixedExtentScrollController(initialItem: _hour);
  late final FixedExtentScrollController _minuteWheel =
      FixedExtentScrollController(initialItem: _minute ~/ kMinuteStep);

  static int _snapMinute(int minute) {
    final snapped = (minute / kMinuteStep).round() * kMinuteStep;
    return snapped >= 60 ? 0 : snapped;
  }

  @override
  void dispose() {
    _hourField.dispose();
    _minuteField.dispose();
    _hourWheel.dispose();
    _minuteWheel.dispose();
    super.dispose();
  }

  String _label(int hour) {
    if (widget.use24HourFormat) return hour.toString().padLeft(2, '0');
    final h = hour % 12 == 0 ? 12 : hour % 12;
    return '$h ${hour < 12 ? 'am' : 'pm'}';
  }

  void _commitTyped() {
    final h = int.tryParse(_hourField.text);
    final m = int.tryParse(_minuteField.text);
    if (h != null && h >= 0 && h <= 23) _hour = h;
    if (m != null && m >= 0 && m <= 59) _minute = m;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(
              widget.title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
          ),
          IconButton(
            icon: Icon(_typing ? Icons.schedule : Icons.keyboard),
            tooltip: _typing ? 'Use the wheels' : 'Type an exact time',
            onPressed: () {
              setState(() {
                if (_typing) {
                  _commitTyped();
                } else {
                  _hourField.text = _hour.toString().padLeft(2, '0');
                  _minuteField.text = _minute.toString().padLeft(2, '0');
                }
                _typing = !_typing;
              });
            },
          ),
        ],
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: Insets.lg),
      content: SizedBox(
        width: 260,
        height: 140,
        child: _typing ? _typedFields(c) : _wheels(c),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_typing) _commitTyped();
            Navigator.of(context).pop(TimeOfDay(hour: _hour, minute: _minute));
          },
          child: const Text('Done'),
        ),
      ],
    );
  }

  Widget _typedFields(KlhyetiColors c) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 72,
          child: TextField(
            controller: _hourField,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 2,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(counterText: '', hintText: 'HH'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
          child: Text(':', style: TextStyle(fontSize: 20, color: c.ink)),
        ),
        SizedBox(
          width: 72,
          child: TextField(
            controller: _minuteField,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 2,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(counterText: '', hintText: 'MM'),
          ),
        ),
      ],
    );
  }

  Widget _wheels(KlhyetiColors c) {
    return Stack(
      children: [
        // The band marking the selected row.
        Center(
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(Radii.cell),
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _wheel(
                c,
                controller: _hourWheel,
                itemCount: 24,
                labelAt: _label,
                onSelected: (i) => setState(() => _hour = i),
              ),
            ),
            Expanded(
              child: _wheel(
                c,
                controller: _minuteWheel,
                itemCount: 60 ~/ kMinuteStep,
                labelAt: (i) =>
                    (i * kMinuteStep).toString().padLeft(2, '0'),
                onSelected: (i) => setState(() => _minute = i * kMinuteStep),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _wheel(
    KlhyetiColors c, {
    required FixedExtentScrollController controller,
    required int itemCount,
    required String Function(int index) labelAt,
    required ValueChanged<int> onSelected,
  }) {
    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: 40,
      perspective: 0.002,
      diameterRatio: 1.6,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: (index) {
        HapticFeedback.selectionClick();
        onSelected(index);
      },
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: itemCount,
        builder: (context, index) => Center(
          child: Text(
            labelAt(index),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: c.ink,
              fontFeatures: tabularFigures,
            ),
          ),
        ),
      ),
    );
  }
}
