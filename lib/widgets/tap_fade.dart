import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A tap target that dims briefly instead of splashing. Used everywhere a
/// Material ripple would be too loud.
class TapFade extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final bool selected;

  const TapFade({
    super.key,
    required this.child,
    this.onTap,
    this.semanticLabel,
    this.selected = false,
  });

  @override
  State<TapFade> createState() => _TapFadeState();
}

class _TapFadeState extends State<TapFade> {
  bool _down = false;

  void _set(bool value) {
    if (_down != value && mounted) setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: enabled,
      selected: widget.selected,
      label: widget.semanticLabel,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTapDown: enabled ? (_) => _set(true) : null,
          onTapUp: enabled ? (_) => _set(false) : null,
          onTapCancel: enabled ? () => _set(false) : null,
          child: AnimatedOpacity(
            opacity: _down ? 0.72 : 1,
            duration: Motion.of(context, Motion.press),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
