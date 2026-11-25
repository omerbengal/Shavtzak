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
    // The platform view's root is OUR own <div>, marked right to left, with
    // the field inside it. iOS Safari draws the caret of an empty line (and
    // of an empty field) from the direction of the field's container, not the
    // field's own dir, so a dir="rtl" field inside Flutter's LTR wrapper still
    // put that caret on the left (25/11/2026). This div is ours, so marking it
    // is safe (unlike Flutter's glass pane, see below).
    final host = element as web.HTMLElement;
    host.setAttribute('dir', 'rtl');
    host.setAttribute('lang', 'he');
    host.style.cssText = 'width:100%;height:100%;margin:0;padding:0;'
        'direction:rtl;text-align:right;';
    final el =
        web.document.createElement(widget.multiline ? 'textarea' : 'input')
            as web.HTMLElement;
    host.appendChild(el);
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
        'color:${css(color)};caret-color:#1565C0;direction:rtl;text-align:right;'
        '-webkit-user-select:text;user-select:text;touch-action:pan-y;'
        'overflow-y:${widget.multiline ? 'auto' : 'hidden'};';
    if (widget.multiline) {
      (el as web.HTMLTextAreaElement).value =
          widget.initial.replaceAll('\n', '\n$_rlm');
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
            return;
          }
          if (widget.multiline && _rtlLineMark(e)) e.preventDefault();
        }).toJS);
    // Backup for a keyboard that sends no Enter keydown: the line break
    // itself, before the browser inserts it.
    if (widget.multiline) {
      el.addEventListener(
          'beforeinput',
          ((web.InputEvent e) {
            if (e.inputType != 'insertLineBreak' &&
                e.inputType != 'insertParagraph') {
              return;
            }
            final ta = el as web.HTMLTextAreaElement;
            e.preventDefault();
            ta.setRangeText(
                '\n$_rlm', ta.selectionStart, ta.selectionEnd, 'end');
            widget.onChanged(_value);
            _fit();
          }).toJS);
    }
    // The element is in the page only after this frame; measure then, and
    // once more after the font arrives.
    WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
    Future<void>.delayed(const Duration(milliseconds: 300), _fit);
    Future<void>.delayed(const Duration(milliseconds: 1200), _fit);
  }

  // Only the field itself is marked right to left. Never its wrappers: the
  // one above it is Flutter's own glass pane, and dir="rtl" there moved the
  // whole canvas off the screen (a white page, 25/11/2026).

  String get _value {
    final el = _el;
    if (el == null) return widget.initial;
    return widget.multiline
        ? (el as web.HTMLTextAreaElement).value.replaceAll(_rlm, '')
        : (el as web.HTMLInputElement).value;
  }

  // The iPhone draws the caret of an EMPTY line on the left even in a
  // dir="rtl" textarea with text-align:right (25/11/2026, Omer's iPhone; the
  // same page in WebKit on the PC puts it on the right, so it is iOS's own
  // caret). An empty line has no letter to take a direction from, so every
  // new line starts with an invisible right-to-left mark (U+200F): the line
  // is then right to left and its caret sits on the right. The marks never
  // leave the field (_value drops them). Backspace right after a mark that
  // opens a line removes the mark and the line break together, so it still
  // takes one press.
  static const String _rlm = '\u200F';

  bool _rtlLineMark(web.KeyboardEvent e) {
    if (e.isComposing || e.ctrlKey || e.metaKey || e.altKey) return false;
    final ta = _el as web.HTMLTextAreaElement;
    final start = ta.selectionStart;
    final end = ta.selectionEnd;
    final text = ta.value;
    if (e.key == 'Enter' && !e.shiftKey) {
      ta.setRangeText('\n$_rlm', start, end, 'end');
    } else if (e.key == 'Backspace' &&
        start == end &&
        start >= 2 &&
        text.substring(start - 2, start) == '\n$_rlm') {
      ta.setRangeText('', start - 2, start, 'end');
    } else {
      return false;
    }
    widget.onChanged(_value);
    _fit();
    return true;
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
        tagName: 'div',
        onElementCreated: _created,
      ),
    );
  }
}
