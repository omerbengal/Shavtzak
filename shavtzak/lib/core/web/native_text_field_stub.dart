import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Off the web there is no browser field.
bool get nativeTextFieldsAvailable => false;

/// Never built off the web (`nativeTextFieldsAvailable` is false); the
/// constructor matches the web one so `AppTextField` compiles everywhere.
class NativeEditable extends StatelessWidget {
  const NativeEditable({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.style,
    required this.lineHeight,
    required this.textDirection,
    required this.onChanged,
    this.textAlign = TextAlign.start,
    this.multiline = false,
    this.minLines = 1,
    this.maxLines = 1,
    this.cursorColor,
    this.maxLength,
    this.readOnly = false,
    this.enabled = true,
    this.autofocus = false,
    this.textInputAction,
    this.keyboardType,
    this.onSubmitted,
    this.onSubmitShortcut,
    this.onFocusChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final TextStyle style;
  final double lineHeight;
  final TextDirection textDirection;
  final TextAlign textAlign;
  final bool multiline;
  final int minLines;
  final int? maxLines;
  final Color? cursorColor;
  final int? maxLength;
  final bool readOnly;
  final bool enabled;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final TextInputType? keyboardType;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onSubmitShortcut;
  final ValueChanged<bool>? onFocusChanged;

  @override
  Widget build(BuildContext context) =>
      throw UnsupportedError('The browser text field exists only on the web');
}
