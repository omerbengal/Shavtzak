import 'dart:async';

import 'package:flutter/widgets.dart';

/// Scrolls the focused text field back into view when the visible height
/// shrinks — i.e. when the on-screen keyboard opens.
///
/// Flutter only does this itself when the keyboard is reported as a bottom
/// view inset. On Android browsers the keyboard instead *resizes the page*:
/// the inset stays 0, the window just gets shorter, and a field low in a
/// dialog ends up hidden under the keyboard until the user scrolls by hand.
/// Placed once above the app's Navigator, this covers every dialog, sheet
/// and screen.
class KeepFocusedFieldVisible extends StatefulWidget {
  const KeepFocusedFieldVisible({super.key, required this.child});

  final Widget child;

  /// Space kept between the field and the keyboard.
  static const double margin = 16;

  /// The keyboard resizes the page over several frames; act once it settles.
  static const Duration settle = Duration(milliseconds: 120);

  @override
  State<KeepFocusedFieldVisible> createState() =>
      _KeepFocusedFieldVisibleState();
}

class _KeepFocusedFieldVisibleState extends State<KeepFocusedFieldVisible>
    with WidgetsBindingObserver {
  double? _lastVisibleHeight;
  Timer? _settleTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _lastVisibleHeight ??= _visibleHeight();
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  double? _visibleHeight() {
    final view = View.maybeOf(context);
    if (view == null) return null;
    return (view.physicalSize.height - view.viewInsets.bottom) /
        view.devicePixelRatio;
  }

  @override
  void didChangeMetrics() {
    final height = _visibleHeight();
    final previous = _lastVisibleHeight;
    _lastVisibleHeight = height;
    if (height == null || previous == null || height >= previous) return;
    _settleTimer?.cancel();
    _settleTimer = Timer(KeepFocusedFieldVisible.settle, _revealFocusedField);
  }

  void _revealFocusedField() {
    if (!mounted) return;
    final field = FocusManager.instance.primaryFocus?.context
        ?.findAncestorStateOfType<EditableTextState>();
    if (field == null || !field.mounted) return;
    final box = field.context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    box.showOnScreen(
      rect: (Offset.zero & box.size)
          .inflate(KeepFocusedFieldVisible.margin),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
