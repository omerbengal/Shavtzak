import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/utils/native_field_rules.dart';
import '../../core/web/native_text_field.dart';
import 'rtl_arrow_keys.dart';

/// The app's text field. On the web it is the browser's own field (an
/// `<input>`, or a contenteditable block per line for several lines) inside
/// Flutter's [InputDecorator], so the label, icons, border, error and counter
/// look exactly like a [TextField]'s while typing, the caret, the loupe and
/// selection are the browser's (the iPhone's caret on an empty Hebrew line
/// was on the left in Flutter's field, 25/11/2026). Off the web, in tests,
/// with [useNative] false, or with `flutterfields` in the address, it is a
/// plain [TextField] (wrapped in [RtlArrowKeys]).
///
/// Every browser field is a platform view, a layer of its own over the
/// canvas. It stays one while it is on screen (not only while focused): an
/// iPhone opens the keyboard only for a field focused inside the tap itself,
/// and a field made on the tap would be focused a frame later, so a lazily
/// created field never got the keyboard. Screens with dozens of fields
/// always on show should keep the read-only text as plain text and open the
/// field on demand, as the editing screen's [TextValueEditor] does.
///
/// Fields that must stay Flutter's own (the @-mention fields, which follow
/// the caret with a list of names; passcodes; numbers and phones with their
/// formatters; pickers) keep using [TextField].
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.decoration = const InputDecoration(),
    this.style,
    this.textAlign = TextAlign.start,
    this.autofocus = false,
    this.readOnly = false,
    this.enabled,
    this.minLines,
    this.maxLines = 1,
    this.maxLength,
    this.textInputAction,
    this.keyboardType,
    this.onChanged,
    this.onSubmitted,
    this.onSubmitShortcut,
    this.onTapOutside,
    this.validator,
    this.autovalidateMode,
    this.useNative = true,
    this.fallbackSelectionWidthStyle = ui.BoxWidthStyle.tight,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final InputDecoration? decoration;
  final TextStyle? style;
  final TextAlign textAlign;
  final bool autofocus;
  final bool readOnly;
  final bool? enabled;
  final int? minLines;

  /// 1 = a single line; null or more = several lines (Enter = a new line).
  final int? maxLines;
  final int? maxLength;
  final TextInputAction? textInputAction;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  /// Enter in a single line.
  final ValueChanged<String>? onSubmitted;

  /// Ctrl/Cmd+Enter in several lines.
  final VoidCallback? onSubmitShortcut;
  final TapRegionCallback? onTapOutside;

  /// As a [TextFormField]'s: the field joins the [Form] around it, and
  /// `Form.validate()` shows the message under it.
  final FormFieldValidator<String>? validator;
  final AutovalidateMode? autovalidateMode;

  /// False keeps Flutter's own field even on the web.
  final bool useNative;

  /// Flutter's field only: how a selection is highlighted. Tight by default:
  /// on an iPhone and in Safari the default stretched a selected Hebrew word
  /// up to the field's left edge.
  final ui.BoxWidthStyle fallbackSelectionWidthStyle;

  bool get multiline =>
      maxLines == null || maxLines! > 1 || (minLines ?? 1) > 1;

  /// Whether this build draws the browser's field ([useNative] on the web).
  static bool usesNative({bool useNative = true}) =>
      kIsWeb && useNative && nativeTextFieldsAvailable;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  TextEditingController? _ownController;
  FocusNode? _ownFocus;
  bool _focused = false;

  TextEditingController get _controller =>
      widget.controller ?? (_ownController ??= TextEditingController());
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  bool get _native => AppTextField.usesNative(useNative: widget.useNative);

  @override
  void initState() {
    super.initState();
    if (_native) {
      _controller.addListener(_rebuild);
      _focus.addListener(_onFocus);
    }
  }

  @override
  void didUpdateWidget(AppTextField old) {
    super.didUpdateWidget(old);
    if (!_native) return;
    if (old.controller != widget.controller) {
      (old.controller ?? _ownController)?.removeListener(_rebuild);
      _controller.addListener(_rebuild);
    }
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownFocus)?.removeListener(_onFocus);
      _focus.addListener(_onFocus);
    }
  }

  @override
  void dispose() {
    if (_native) {
      _controller.removeListener(_rebuild);
      _focus.removeListener(_onFocus);
    }
    _ownController?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _onFocus() {
    if (mounted && _focus.hasFocus != _focused) {
      setState(() => _focused = _focus.hasFocus);
    }
  }

  bool get _enabled => widget.enabled ?? widget.decoration?.enabled ?? true;

  @override
  Widget build(BuildContext context) {
    if (widget.validator == null) return _field(context, null, null);
    return FormField<String>(
      initialValue: _controller.text,
      validator: (_) => widget.validator!(_controller.text),
      autovalidateMode: widget.autovalidateMode,
      enabled: _enabled,
      builder: (state) => _field(context, state.errorText, state.didChange),
    );
  }

  Widget _field(
    BuildContext context,
    String? formError,
    ValueChanged<String>? formChanged,
  ) {
    void changed(String text) {
      formChanged?.call(text);
      widget.onChanged?.call(text);
    }

    var decoration = widget.decoration ?? const InputDecoration();
    if (formError != null) {
      decoration = decoration.copyWith(errorText: formError);
    }
    return _native
        ? _nativeField(context, decoration, changed)
        : _flutterField(decoration, changed);
  }

  Widget _flutterField(
    InputDecoration decoration,
    ValueChanged<String> changed,
  ) {
    Widget field = TextField(
      controller: _controller,
      focusNode: _focus,
      decoration: decoration,
      style: widget.style,
      textAlign: widget.textAlign,
      autofocus: widget.autofocus,
      readOnly: widget.readOnly,
      enabled: widget.enabled,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      maxLength: widget.maxLength,
      textInputAction: widget.textInputAction,
      keyboardType:
          widget.keyboardType ??
          (widget.multiline ? TextInputType.multiline : TextInputType.text),
      selectionWidthStyle: widget.fallbackSelectionWidthStyle,
      onChanged: changed,
      onSubmitted: widget.onSubmitted,
      onTapOutside: widget.onTapOutside,
    );
    field = RtlArrowKeys(multiline: widget.multiline, child: field);
    if (widget.multiline && widget.onSubmitShortcut != null) {
      field = CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true):
              widget.onSubmitShortcut!,
          const SingleActivator(LogicalKeyboardKey.enter, meta: true):
              widget.onSubmitShortcut!,
        },
        child: field,
      );
    }
    return field;
  }

  Widget _nativeField(
    BuildContext context,
    InputDecoration decoration,
    ValueChanged<String> changed,
  ) {
    final theme = Theme.of(context);
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    // As TextField: the theme's body text, then the field's own style.
    var style = theme.textTheme.bodyLarge!.merge(widget.style);
    if (!_enabled) {
      style = style.copyWith(color: theme.disabledColor);
    }
    style = style.copyWith(fontSize: scaler.scale(style.fontSize ?? 16));
    final lineHeight = (TextPainter(
      text: TextSpan(text: 'א', style: style),
      textDirection: direction,
    )..layout()).preferredLineHeight;
    final effective = decoration
        .applyDefaults(theme.inputDecorationTheme)
        .copyWith(
          enabled: _enabled,
          counterText: nativeCounterText(
            length: _controller.text.characters.length,
            maxLength: widget.maxLength,
            counterText: decoration.counterText,
          ),
        );
    return TapRegion(
      onTapOutside: (event) {
        if (widget.onTapOutside != null) {
          widget.onTapOutside!(event);
        } else if (event.kind != PointerDeviceKind.touch && _focus.hasFocus) {
          // As Flutter's field on the web: a click elsewhere leaves it, a
          // touch (scrolling the page) does not.
          _focus.unfocus();
        }
      },
      child: MouseRegion(
        cursor: _enabled ? SystemMouseCursors.text : SystemMouseCursors.basic,
        child: GestureDetector(
          // A tap on the label, an icon or the padding focuses the field too.
          behavior: HitTestBehavior.translucent,
          onTap: _enabled && !_focus.hasFocus ? _focus.requestFocus : null,
          child: InputDecorator(
            decoration: effective,
            baseStyle: style,
            textAlign: widget.textAlign,
            isFocused: _focused,
            isEmpty: _controller.text.isEmpty,
            child: NativeEditable(
              controller: _controller,
              focusNode: _focus,
              style: style,
              lineHeight: lineHeight,
              textDirection: direction,
              textAlign: widget.textAlign,
              multiline: widget.multiline,
              minLines: widget.minLines ?? 1,
              maxLines: widget.maxLines,
              cursorColor:
                  theme.textSelectionTheme.cursorColor ??
                  theme.colorScheme.primary,
              maxLength: widget.maxLength,
              readOnly: widget.readOnly,
              enabled: _enabled,
              autofocus: widget.autofocus,
              textInputAction: widget.textInputAction,
              keyboardType: widget.keyboardType,
              onChanged: changed,
              onSubmitted: widget.onSubmitted,
              onSubmitShortcut: widget.onSubmitShortcut,
            ),
          ),
        ),
      ),
    );
  }
}
