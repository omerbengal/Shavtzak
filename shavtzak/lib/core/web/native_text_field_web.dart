import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

Widget? nativeTextField({
  required String initial,
  required ValueChanged<String> onChanged,
  required VoidCallback onSubmit,
  required bool multiline,
  String? hint,
}) =>
    _NativeTextField(
      initial: initial,
      onChanged: onChanged,
      onSubmit: onSubmit,
      multiline: multiline,
      hint: hint,
    );

class _NativeTextField extends StatefulWidget {
  const _NativeTextField({
    required this.initial,
    required this.onChanged,
    required this.onSubmit,
    required this.multiline,
    this.hint,
  });

  final String initial;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;
  final bool multiline;
  final String? hint;

  @override
  State<_NativeTextField> createState() => _NativeTextFieldState();
}

class _NativeTextFieldState extends State<_NativeTextField> {
  static const double _lineHeight = 24;
  static const double _padV = 10;
  static const double _maxHeight = 340;

  web.HTMLElement? _el;
  late double _height =
      widget.multiline ? _lineHeight * 3 + _padV * 2 : _lineHeight + _padV * 2;

  void _created(Object element) {
    final el = element as web.HTMLElement;
    _el = el;
    final color = Theme.of(context).colorScheme.onSurface;
    String css(Color c) =>
        'rgba(${(c.r * 255).round()},${(c.g * 255).round()},${(c.b * 255).round()},${c.a})';
    // Right to left like the app's own fields (Directionality is RTL in the
    // whole app): every line starts at the right, whatever its first letter.
    el.setAttribute('dir', 'rtl');
    el.setAttribute('lang', 'he');
    el.setAttribute('data-native-field', '');
    if (widget.hint != null) el.setAttribute('placeholder', widget.hint!);
    // 16px: below it the iPhone zooms the page in on focus.
    el.style.cssText = 'width:100%;height:100%;box-sizing:border-box;'
        'margin:0;border:0;outline:none;resize:none;background:transparent;'
        'padding:${_padV}px 12px;font:16px/${_lineHeight}px Rubik, -apple-system, sans-serif;'
        'color:${css(color)};caret-color:#1565C0;direction:rtl;unicode-bidi:isolate;text-align:right;'
        '-webkit-user-select:text;user-select:text;touch-action:pan-y;'
        'overflow-y:${widget.multiline ? 'auto' : 'hidden'};';
    if (widget.multiline) {
      (el as web.HTMLTextAreaElement).value = widget.initial;
    } else {
      final input = el as web.HTMLInputElement;
      input.type = 'text';
      input.value = widget.initial;
      input.enterKeyHint = 'done';
    }
    el.addEventListener(
        'input',
        ((web.Event _) {
          widget.onChanged(_value);
          _fit();
        }).toJS);
    el.addEventListener(
        'keydown',
        ((web.KeyboardEvent e) {
          final submit = widget.multiline
              ? (e.key == 'Enter' && (e.ctrlKey || e.metaKey))
              : e.key == 'Enter';
          if (submit) {
            e.preventDefault();
            widget.onSubmit();
          }
        }).toJS);
    // The element is in the page only after this frame; measure then, and
    // once more after the font arrives.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markParentRtl();
      _fit();
    });
    Future<void>.delayed(const Duration(milliseconds: 300), _fit);
    Future<void>.delayed(const Duration(milliseconds: 1200), _fit);
  }

  // Safari takes a form control's direction partly from its container: the
  // platform view's wrapper is marked right to left too.
  void _markParentRtl() {
    var node = _el?.parentElement;
    for (var i = 0; i < 2 && node != null; i++) {
      node.setAttribute('dir', 'rtl');
      node = node.parentElement;
    }
  }

  String get _value {
    final el = _el;
    if (el == null) return widget.initial;
    return widget.multiline
        ? (el as web.HTMLTextAreaElement).value
        : (el as web.HTMLInputElement).value;
  }

  // A textarea grows with its text up to _maxHeight, then scrolls inside.
  void _fit() {
    final el = _el;
    if (el == null || !widget.multiline || !mounted) return;
    final prev = el.style.height;
    el.style.height = '0px';
    final needed = el.scrollHeight.toDouble();
    el.style.height = prev;
    final h = needed.clamp(_lineHeight * 3 + _padV * 2, _maxHeight).toDouble();
    if ((h - _height).abs() > 0.5) setState(() => _height = h);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      // + the 2 px border above and below.
      height: _height + 4,
      decoration: BoxDecoration(
        border: Border.all(color: scheme.primary, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: HtmlElementView.fromTagName(
        tagName: widget.multiline ? 'textarea' : 'input',
        onElementCreated: _created,
      ),
    );
  }
}
