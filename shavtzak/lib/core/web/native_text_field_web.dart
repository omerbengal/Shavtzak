import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../utils/native_field_rules.dart';

/// On the web, unless the address carries `flutterfields` (a switch back to
/// Flutter's own fields, for comparing on a phone or as a quick way out).
final bool _available = !web.window.location.href.contains('flutterfields');

bool get nativeTextFieldsAvailable => _available;

/// The bare browser field: no border, label or icons (the `InputDecorator`
/// around it in `AppTextField` draws those, as for a `TextField`). Its text
/// follows [controller] both ways; its focus follows [focusNode] both ways.
class NativeEditable extends StatefulWidget {
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

  /// Enter in a single line (and in several lines whose action is not
  /// "newline", e.g. a comment that sends on Enter).
  final ValueChanged<String>? onSubmitted;

  /// Ctrl/Cmd+Enter in several lines (Enter itself starts a new line).
  final VoidCallback? onSubmitShortcut;
  final ValueChanged<bool>? onFocusChanged;

  @override
  State<NativeEditable> createState() => _NativeEditableState();
}

class _NativeEditableState extends State<NativeEditable> {
  web.HTMLElement? _el;
  bool _domFocused = false;
  bool _focusWhenCreated = false;
  late String _shown = widget.controller.text;
  late double _height = _minHeight;

  double get _minHeight =>
      widget.lineHeight *
      (widget.multiline ? widget.minLines.clamp(1, 1000) : 1);

  String get _dir => widget.textDirection == TextDirection.rtl ? 'rtl' : 'ltr';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
    widget.focusNode.addListener(_onFocusNode);
  }

  @override
  void didUpdateWidget(NativeEditable old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
      _onController();
    }
    if (old.focusNode != widget.focusNode) {
      old.focusNode.removeListener(_onFocusNode);
      widget.focusNode.addListener(_onFocusNode);
    }
    if (_el != null) {
      _applyAttributes();
      _applyStyle();
      if (old.minLines != widget.minLines ||
          old.maxLines != widget.maxLines ||
          old.lineHeight != widget.lineHeight) {
        _fit();
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    widget.focusNode.removeListener(_onFocusNode);
    _el = null;
    super.dispose();
  }

  // ---------------------------------------------------------------- styling

  static bool _styleAdded = false;

  // Once per page: the app's font for the page itself (Flutter loads it for
  // its canvas only), and every line block of a multi-line field in the
  // field's direction, with no gap between lines.
  static void _addPageStyle() {
    if (_styleAdded) return;
    _styleAdded = true;
    final style = web.document.createElement('style');
    final faces =
        [
          (400, 'Rubik-Regular'),
          (500, 'Rubik-Medium'),
          (600, 'Rubik-Medium'),
          (700, 'Rubik-Bold'),
        ].map(
          (f) =>
              "@font-face{font-family:'Rubik';font-weight:${f.$1};"
              "src:url('assets/assets/fonts/${f.$2}.ttf') format('truetype');}",
        );
    style.textContent =
        '${faces.join()}'
        '[data-native-ce]>div,[data-native-ce]>p{margin:0;}'
        '[data-native-ce][dir=rtl]>div,[data-native-ce][dir=rtl]>p'
        '{direction:rtl;text-align:right;}'
        '[data-native-ce][dir=ltr]>div,[data-native-ce][dir=ltr]>p'
        '{direction:ltr;text-align:left;}';
    web.document.head?.appendChild(style);
  }

  static String _css(Color c) =>
      'rgba(${(c.r * 255).round()},'
      '${(c.g * 255).round()},${(c.b * 255).round()},${c.a.toStringAsFixed(3)})';

  String get _align {
    final rtl = widget.textDirection == TextDirection.rtl;
    switch (widget.textAlign) {
      case TextAlign.center:
        return 'center';
      case TextAlign.left:
        return 'left';
      case TextAlign.right:
        return 'right';
      case TextAlign.end:
        return rtl ? 'left' : 'right';
      case TextAlign.justify:
      case TextAlign.start:
        return rtl ? 'right' : 'left';
    }
  }

  void _applyStyle() {
    final el = _el;
    if (el == null) return;
    final style = widget.style;
    final color = style.color ?? Colors.black;
    final shown = widget.enabled
        ? color
        : color.withValues(alpha: color.a * 0.6);
    final weight = (style.fontWeight ?? FontWeight.w400).value;
    final family = style.fontFamily ?? 'Rubik';
    // Below 16 px an iPhone zooms the page in on focus, unless the page
    // forbids zooming, which index.html does (maximum-scale=1).
    el.style.cssText =
        'width:100%;height:100%;box-sizing:border-box;'
        'margin:0;padding:0;border:0;outline:none;resize:none;'
        'background:transparent;box-shadow:none;border-radius:0;'
        '-webkit-appearance:none;appearance:none;'
        "font:$weight ${style.fontSize ?? 16}px/${widget.lineHeight}px '$family', -apple-system, sans-serif;"
        '${style.letterSpacing != null ? 'letter-spacing:${style.letterSpacing}px;' : ''}'
        'color:${_css(shown)};caret-color:${_css(widget.cursorColor ?? color)};'
        '-webkit-text-fill-color:${_css(shown)};'
        'direction:$_dir;text-align:$_align;'
        '-webkit-user-select:text;user-select:text;touch-action:pan-y;'
        '${widget.multiline ? 'overflow-y:auto;overflow-x:hidden;white-space:pre-wrap;overflow-wrap:break-word;' : 'overflow:hidden;'}';
  }

  void _applyAttributes() {
    final el = _el;
    if (el == null) return;
    el.setAttribute('dir', _dir);
    el.setAttribute(
      'enterkeyhint',
      nativeEnterKeyHint(widget.textInputAction, multiline: widget.multiline),
    );
    el.setAttribute('inputmode', nativeInputMode(widget.keyboardType));
    final editable = widget.enabled && !widget.readOnly;
    if (widget.multiline) {
      el.setAttribute('contenteditable', editable ? 'true' : 'false');
      el.setAttribute('aria-multiline', 'true');
    } else {
      final input = el as web.HTMLInputElement;
      input.readOnly = widget.readOnly;
      input.disabled = !widget.enabled;
      if (widget.maxLength != null && widget.maxLength! > 0) {
        input.maxLength = widget.maxLength!;
      } else {
        input.removeAttribute('maxlength');
      }
    }
  }

  // --------------------------------------------------------------- creation

  void _created(Object element) {
    if (!mounted) return;
    _addPageStyle();
    // The platform view's root is OUR own <div>, marked in the text's
    // direction, with the field inside it. Never Flutter's wrappers above
    // it: dir="rtl" on the glass pane moved the whole canvas off the screen
    // (a white page, 25/11/2026).
    final host = element as web.HTMLElement;
    host.setAttribute('dir', _dir);
    host.setAttribute('lang', 'he');
    host.style.cssText =
        'width:100%;height:100%;margin:0;padding:0;direction:$_dir;';
    final el = web.document.createElement(
      widget.multiline ? 'div' : 'input',
    ) as web.HTMLElement;
    host.appendChild(el);
    _el = el;
    el.setAttribute('lang', 'he');
    el.setAttribute('data-native-field', '');
    el.setAttribute('autocomplete', 'off');
    el.setAttribute('spellcheck', 'true');
    _applyStyle();
    _applyAttributes();
    if (widget.multiline) {
      // A contenteditable <div>, NOT a <textarea> (25/11/2026, Omer's
      // iPhone, boxes 10 / 12 of the caret test): in a textarea iOS draws
      // the caret of a tapped EMPTY line on the left whatever its dir; in a
      // block of its own marked rtl it sits on the right. No invisible marks
      // and no script moving the caret: the browser does Enter, Backspace,
      // selection, the loupe and the IME; lines get dir by CSS and by an
      // attribute set only where it is missing, never by moving nodes.
      el.setAttribute('data-native-ce', '');
      _setLines(widget.controller.text);
      el.addEventListener(
        'paste',
        ((web.ClipboardEvent e) {
          // Plain text only, through the browser's own insert (it goes
          // through beforeinput, so the length limit holds).
          final text = e.clipboardData?.getData('text/plain') ?? '';
          e.preventDefault();
          web.document.execCommand('insertText', false, text);
        }).toJS,
      );
      el.addEventListener(
        'beforeinput',
        ((web.InputEvent e) {
          // No bold / italic / dropped HTML in a plain-text field.
          if (e.inputType.startsWith('format')) {
            e.preventDefault();
            return;
          }
          if (widget.maxLength == null || !e.inputType.startsWith('insert')) {
            return;
          }
          final inserted =
              e.data?.length ??
              (e.inputType == 'insertParagraph' ||
                      e.inputType == 'insertLineBreak'
                  ? 1
                  : 0);
          final selected = web.window.getSelection()?.toString().length ?? 0;
          if (nativeExceedsMaxLength(
            length: _read().length,
            selected: selected,
            inserted: inserted,
            maxLength: widget.maxLength,
          )) {
            e.preventDefault();
          }
        }).toJS,
      );
      el.addEventListener('compositionend', ((web.Event _) => _changed()).toJS);
    } else {
      final input = el as web.HTMLInputElement;
      input.type = 'text';
      input.value = widget.controller.text;
    }
    el.addEventListener(
      'input',
      ((web.InputEvent e) {
        // Mid-composition the text is not final; compositionend reports it.
        if (widget.multiline && e.isComposing) return;
        _changed();
      }).toJS,
    );
    el.addEventListener('keydown', ((web.KeyboardEvent e) => _onKey(e)).toJS);
    el.addEventListener('focus', ((web.Event _) => _onDomFocus(true)).toJS);
    el.addEventListener('blur', ((web.Event _) => _onDomFocus(false)).toJS);
    if (_focusWhenCreated || widget.focusNode.hasPrimaryFocus) {
      _focusWhenCreated = false;
      el.focus();
    }
    // The element is in the page only after this frame; measure then, and
    // once more after the font arrives.
    WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
    Future<void>.delayed(const Duration(milliseconds: 300), _fit);
    Future<void>.delayed(const Duration(milliseconds: 1200), _fit);
  }

  // ------------------------------------------------------------------- text

  String _read() {
    final el = _el;
    if (el == null) return _shown;
    if (!widget.multiline) {
      return cleanNativeText((el as web.HTMLInputElement).value);
    }
    return cleanNativeText(_plainOf(el));
  }

  void _changed() {
    if (!mounted || _el == null) return;
    if (widget.multiline) _markLines();
    final text = _read();
    if (text != _shown) {
      _shown = text;
      widget.controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      widget.onChanged(text);
    }
    _fit();
  }

  // The app changed the text (cleared it after sending, filled it again):
  // show it. The field's own typing is already [_shown], so it never writes
  // back into the element under the caret.
  void _onController() {
    final text = widget.controller.text;
    if (text == _shown) return;
    _shown = text;
    final el = _el;
    if (el == null) return;
    if (widget.multiline) {
      _setLines(text);
    } else {
      (el as web.HTMLInputElement).value = text;
    }
    _fit();
  }

  // Every line block the browser made gets the field's dir if it has none.
  // Only an attribute: no node is moved, so the caret and selection stay.
  void _markLines() {
    final kids = _el!.children;
    for (var i = 0; i < kids.length; i++) {
      final k = kids.item(i)!;
      if (k.getAttribute('dir') != _dir) k.setAttribute('dir', _dir);
    }
  }

  void _setLines(String plain) {
    final el = _el!;
    el.textContent = '';
    for (final line in nativeFieldLines(plain)) {
      final div = web.document.createElement('div');
      div.setAttribute('dir', _dir);
      if (line.isEmpty) {
        div.appendChild(web.document.createElement('br'));
      } else {
        div.textContent = line;
      }
      el.appendChild(div);
    }
  }

  // The field's text as plain lines joined by \n. Top-level text (the first
  // line typed into an empty field) is a line of its own; each block is a
  // line; a <br> inside a line breaks it, except the <br> that only keeps an
  // empty line open.
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
        loose.write(
          n.nodeType == web.Node.TEXT_NODE
              ? (n.textContent ?? '')
              : blockText(n),
        );
      }
    }
    flushLoose();
    return lines.join('\n');
  }

  // A multi-line field grows with its text between its min and max lines,
  // then scrolls inside.
  void _fit() {
    final el = _el;
    if (el == null || !widget.multiline || !mounted) return;
    final prev = el.style.height;
    el.style.height = '0px';
    final needed = el.scrollHeight.toDouble();
    el.style.height = prev;
    final h = nativeFieldHeight(
      contentHeight: needed,
      lineHeight: widget.lineHeight,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
    );
    if ((h - _height).abs() > 0.5) setState(() => _height = h);
  }

  // ------------------------------------------------------------------ keys

  void _onKey(web.KeyboardEvent e) {
    if (e.key != 'Enter' || e.isComposing) return;
    if (widget.multiline) {
      if ((e.ctrlKey || e.metaKey) && widget.onSubmitShortcut != null) {
        e.preventDefault();
        widget.onSubmitShortcut!();
        return;
      }
      final sends =
          widget.textInputAction != null &&
          widget.textInputAction != TextInputAction.newline &&
          widget.onSubmitted != null;
      if (!sends || e.shiftKey) return;
    }
    e.preventDefault();
    widget.onSubmitted?.call(_read());
    if (!mounted) return;
    // As Flutter's own field does after its action.
    switch (widget.textInputAction) {
      case TextInputAction.next:
        widget.focusNode.nextFocus();
      case TextInputAction.previous:
        widget.focusNode.previousFocus();
      case TextInputAction.newline:
        break;
      default:
        if (!widget.multiline) widget.focusNode.unfocus();
    }
  }

  // ----------------------------------------------------------------- focus

  void _onDomFocus(bool focused) {
    if (!mounted) return;
    _domFocused = focused;
    if (focused) {
      // Flutter learns of it, so a Flutter field that had the focus lets go
      // and [focusNode] answers hasFocus. Requesting it does not take the
      // page's focus back from this element (the engine moves the focus to
      // its view only when nothing inside the view has it).
      if (!widget.focusNode.hasPrimaryFocus) widget.focusNode.requestFocus();
    } else if (widget.focusNode.hasPrimaryFocus && web.document.hasFocus()) {
      // Left for somewhere else on the page (another browser field, a tap
      // the browser treats as leaving). Switching apps keeps it.
      widget.focusNode.unfocus();
    }
    widget.onFocusChanged?.call(focused);
  }

  void _onFocusNode() {
    final el = _el;
    if (widget.focusNode.hasPrimaryFocus) {
      if (el == null) {
        _focusWhenCreated = true;
      } else if (!_domFocused) {
        el.focus();
      }
    } else if (!widget.focusNode.hasFocus) {
      _focusWhenCreated = false;
      if (el != null && _domFocused) el.blur();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      // The engine hands every key to Flutter (it listens on the window);
      // the field's keys must not reach the app's shortcuts, which would
      // scroll on an arrow and mark it handled, so the caret never moved.
      onKeyEvent: (_, event) => nativeFieldKeepsKey(event.logicalKey)
          ? KeyEventResult.skipRemainingHandlers
          : KeyEventResult.ignored,
      child: SizedBox(
        height: widget.multiline ? _height : widget.lineHeight,
        child: HtmlElementView.fromTagName(
          tagName: 'div',
          onElementCreated: _created,
        ),
      ),
    );
  }
}
