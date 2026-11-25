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

  // The multi-line field is NOT a <textarea> but a contenteditable <div>
  // whose every line is its own right-to-left block (25/11/2026, Omer's
  // iPhone, boxes 10 / 12 of web/caret_test.html). In a textarea iOS draws
  // the caret of a tapped EMPTY line on the left whatever its dir; in a
  // block of its own marked rtl it sits on the right. No invisible marks and
  // no script moving the caret or the selection: the browser does Enter,
  // Backspace (joining lines), selection, the loupe and the IME by itself.
  // Lines are made rtl by CSS (the rule below) and by a dir attribute set
  // only where it is missing, never by moving nodes.
  static bool _styleAdded = false;
  static void _addStyle() {
    if (_styleAdded) return;
    _styleAdded = true;
    final style = web.document.createElement('style');
    style.textContent = '[data-native-ce]>div,[data-native-ce]>p'
        '{direction:rtl;text-align:right;margin:0;}'
        '[data-native-ce][data-empty]::before{content:attr(data-placeholder);'
        'color:rgba(0,0,0,0.45);pointer-events:none;position:absolute;}';
    web.document.head?.appendChild(style);
  }

  void _created(Object element) {
    // The platform view's root is OUR own <div>, marked right to left, with
    // the field inside it. Never Flutter's wrappers above it: dir="rtl" on
    // the glass pane moved the whole canvas off the screen (a white page,
    // 25/11/2026).
    final host = element as web.HTMLElement;
    host.setAttribute('dir', 'rtl');
    host.setAttribute('lang', 'he');
    host.style.cssText = 'width:100%;height:100%;margin:0;padding:0;'
        'direction:rtl;text-align:right;';
    final el = web.document
        .createElement(widget.multiline ? 'div' : 'input') as web.HTMLElement;
    host.appendChild(el);
    _el = el;
    final color = Theme.of(context).colorScheme.onSurface;
    String css(Color c) =>
        'rgba(${(c.r * 255).round()},${(c.g * 255).round()},${(c.b * 255).round()},${c.a})';
    el.setAttribute('dir', 'rtl');
    el.setAttribute('lang', 'he');
    el.setAttribute('data-native-field', '');
    // 16px: below it the iPhone zooms the page in on focus.
    el.style.cssText = 'width:100%;height:100%;box-sizing:border-box;'
        'margin:0;border:0;outline:none;resize:none;background:transparent;'
        'padding:${_padV}px 12px;font:16px/${_lineHeight}px Rubik, -apple-system, sans-serif;'
        'color:${css(color)};caret-color:#1565C0;direction:rtl;text-align:right;'
        '-webkit-user-select:text;user-select:text;touch-action:pan-y;'
        'overflow-y:${widget.multiline ? 'auto' : 'hidden'};'
        '${widget.multiline ? 'white-space:pre-wrap;overflow-wrap:break-word;' : ''}';
    if (widget.multiline) {
      _addStyle();
      el.setAttribute('data-native-ce', '');
      // contenteditable="true", as in boxes 10 / 12: the browser makes a
      // <div> per line on Enter. (plaintext-only, box 11, keeps one text
      // node with line breaks inside and the empty-line caret went back to the
      // left.) Pasted formatting is kept out by the paste handler below.
      el.setAttribute('contenteditable', 'true');
      if (widget.hint != null) el.setAttribute('data-placeholder', widget.hint!);
      _setLines(widget.initial);
      _markEmpty();
      el.addEventListener(
          'paste',
          ((web.ClipboardEvent e) {
            final text = e.clipboardData?.getData('text/plain') ?? '';
            e.preventDefault();
            web.document.execCommand('insertText', false, text);
          }).toJS);
      el.addEventListener(
          'beforeinput',
          ((web.InputEvent e) {
            // No bold / italic / dropped HTML in a plain-text field.
            if (e.inputType.startsWith('format')) e.preventDefault();
          }).toJS);
      el.addEventListener(
          'compositionend', ((web.Event _) => _changed()).toJS);
    } else {
      final input = el as web.HTMLInputElement;
      if (widget.hint != null) input.setAttribute('placeholder', widget.hint!);
      input.type = 'text';
      input.value = widget.initial;
      input.enterKeyHint = 'done';
    }
    el.addEventListener(
        'input',
        ((web.InputEvent e) {
          // Mid-composition the text is not final; compositionend reports it.
          if (widget.multiline && e.isComposing) return;
          _changed();
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
    Future<void>.delayed(const Duration(milliseconds: 300), _fit);
    Future<void>.delayed(const Duration(milliseconds: 1200), _fit);
  }

  void _changed() {
    if (!mounted) return;
    if (widget.multiline) {
      _markLines();
      _markEmpty();
    }
    widget.onChanged(_value);
    _fit();
  }

  // Every line block the browser made gets dir="rtl" if it has none. Only an
  // attribute: no node is moved, so the caret and the selection stay put.
  void _markLines() {
    final kids = _el!.children;
    for (var i = 0; i < kids.length; i++) {
      final k = kids.item(i)!;
      if (k.getAttribute('dir') != 'rtl') k.setAttribute('dir', 'rtl');
    }
  }

  // The hint shows only while the field holds no text (a lone <br> or an
  // empty block the browser leaves behind still counts as empty).
  void _markEmpty() {
    final el = _el!;
    if (_value.isEmpty) {
      if (!el.hasAttribute('data-empty')) el.setAttribute('data-empty', '');
    } else if (el.hasAttribute('data-empty')) {
      el.removeAttribute('data-empty');
    }
  }

  void _setLines(String plain) {
    final el = _el!;
    el.textContent = '';
    if (plain.isEmpty) return;
    for (final line in plain.split('\n')) {
      final div = web.document.createElement('div');
      div.setAttribute('dir', 'rtl');
      if (line.isEmpty) {
        div.appendChild(web.document.createElement('br'));
      } else {
        div.textContent = line;
      }
      el.appendChild(div);
    }
  }

  String get _value {
    final el = _el;
    if (el == null) return widget.initial;
    if (!widget.multiline) return (el as web.HTMLInputElement).value;
    return _plainOf(el);
  }

  // The field's text as plain lines joined by \n. Top-level text (the first
  // line typed into an empty field) is a line of its own; each block is a
  // line; a <br> inside a line breaks it, except the <br> that only keeps an
  // empty line open. No invisible characters ever leave the field.
  static String _plainOf(web.Element root) {
    final lines = <String>[];
    var loose = StringBuffer();
    var hasLoose = false;

    String blockText(web.Node n) {
      final b = StringBuffer();
      void walk(web.Node x) {
        if (x.nodeType == web.Node.TEXT_NODE) {
          b.write(x.textContent ?? '');
        } else if (x.nodeName == 'BR') {
          if (x.nextSibling != null) b.write('\n');
        } else {
          final cs = x.childNodes;
          for (var i = 0; i < cs.length; i++) {
            walk(cs.item(i)!);
          }
          if ((x.nodeName == 'DIV' || x.nodeName == 'P') &&
              x != n &&
              x.nextSibling != null) {
            b.write('\n');
          }
        }
      }

      walk(n);
      return b.toString();
    }

    void flushLoose() {
      if (hasLoose) lines.add(loose.toString());
      loose = StringBuffer();
      hasLoose = false;
    }

    final cs = root.childNodes;
    for (var i = 0; i < cs.length; i++) {
      final n = cs.item(i)!;
      final name = n.nodeName;
      if (name == 'DIV' || name == 'P') {
        flushLoose();
        lines.add(blockText(n));
      } else if (name == 'BR') {
        hasLoose = true;
        flushLoose();
      } else {
        hasLoose = true;
        loose.write(n.nodeType == web.Node.TEXT_NODE
            ? (n.textContent ?? '')
            : blockText(n));
      }
    }
    flushLoose();
    final text = lines
        .join('\n')
        .replaceAll(RegExp('[​‎‏﻿]'), '')
        .replaceAll(' ', ' ');
    return text;
  }

  // The field grows with its text up to _maxHeight, then scrolls inside.
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
