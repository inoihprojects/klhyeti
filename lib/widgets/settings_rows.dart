import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'tap_fade.dart';

/// The rows Settings and the screens under it are built from, and the
/// dialog for picking one of a few choices.

/// A section's label: small, uppercase, quiet. Without [inset], for a
/// list that already has its own side margins.
Widget sectionLabel(KlhyetiColors c, String title, {bool inset = true}) {
  final side = inset ? Insets.md : 0.0;
  return Padding(
    padding: EdgeInsets.fromLTRB(side, Insets.lg, side, Insets.sm),
    child: Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
        color: c.ink3,
      ),
    ),
  );
}

/// A row that opens something: its title, its current value, a chevron.
Widget tapRow(
  KlhyetiColors c, {
  required String title,
  required String value,
  required VoidCallback onTap,
}) {
  return TapFade(
    onTap: onTap,
    child: Container(
      color: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: TextStyle(fontSize: 15, color: c.ink)),
          ),
          Text(value, style: TextStyle(fontSize: 14, color: c.ink2)),
          const SizedBox(width: Insets.sm),
          Icon(Icons.chevron_right, size: 18, color: c.ink3),
        ],
      ),
    ),
  );
}

/// A row with a switch, and an optional line under the title.
Widget switchRow(
  KlhyetiColors c, {
  required String title,
  String? subtitle,
  required bool value,
  required ValueChanged<bool> onChanged,
}) {
  return Padding(
    padding:
        const EdgeInsets.symmetric(horizontal: Insets.md, vertical: Insets.sm),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 15, color: c.ink)),
              if (subtitle != null)
                Text(subtitle, style: TextStyle(fontSize: 13, color: c.ink3)),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    ),
  );
}

/// A dialog listing [options], with [current] ticked. Returns the choice
/// wrapped in a record, so that choosing an option whose value is null
/// ("None", "Never") differs from closing the dialog, which returns null.
Future<(T,)?> chooseOne<T>(
  BuildContext context, {
  required String title,
  required Map<T, String> options,
  T? current,
}) {
  return showDialog<(T,)>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(title),
      children: [
        for (final entry in options.entries)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop((entry.key,)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Insets.sm),
              child: Row(
                children: [
                  Icon(
                    Icons.check,
                    size: 18,
                    color: entry.key == current
                        ? context.c.ink
                        : Colors.transparent,
                  ),
                  const SizedBox(width: Insets.md),
                  Expanded(child: Text(entry.value)),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
