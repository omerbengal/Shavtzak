import 'package:flutter/services.dart';

/// Pure rules of the browser's own text field (`AppTextField` on the web),
/// kept apart from the DOM so they run in tests.

/// Characters that never leave the field: zero-width marks a browser or an
/// earlier RTL hack may leave in the text.
final RegExp _invisible = RegExp('[​‎‏﻿]');

/// The field's text as the app stores it: invisible marks out, the
/// browser's non-breaking spaces (a contenteditable turns a typed space at a
/// line's end into one) back to plain spaces.
String cleanNativeText(String raw) =>
    raw.replaceAll(_invisible, '').replaceAll(' ', ' ');

/// The lines a multi-line field shows for [text], one block per line.
/// '' is no line at all (an empty field, so the hint shows).
List<String> nativeFieldLines(String text) =>
    text.isEmpty ? const [] : text.split('\n');

/// The `enterkeyhint` of the phone keyboard's Enter key for an action.
String nativeEnterKeyHint(TextInputAction? action, {required bool multiline}) {
  switch (action) {
    case TextInputAction.search:
      return 'search';
    case TextInputAction.send:
      return 'send';
    case TextInputAction.next:
      return 'next';
    case TextInputAction.go:
      return 'go';
    case TextInputAction.previous:
      return 'previous';
    case TextInputAction.newline:
      return 'enter';
    case null:
      return multiline ? 'enter' : 'done';
    default:
      return 'done';
  }
}

/// The `inputmode` (which phone keyboard opens) for a keyboard type.
String nativeInputMode(TextInputType? type) {
  if (type == TextInputType.emailAddress) return 'email';
  if (type == TextInputType.url) return 'url';
  if (type == TextInputType.phone) return 'tel';
  if (type == TextInputType.number) return 'numeric';
  return 'text';
}

/// The height of a multi-line field's text area: the text's own height,
/// at least [minLines] lines, at most [maxLines] lines ([maxLines] null =
/// grows up to [maxHeightWithoutLimit], then scrolls inside).
double nativeFieldHeight({
  required double contentHeight,
  required double lineHeight,
  required int minLines,
  required int? maxLines,
  double maxHeightWithoutLimit = 340,
}) {
  final min = lineHeight * (minLines < 1 ? 1 : minLines);
  final max = maxLines == null
      ? maxHeightWithoutLimit
      : lineHeight * (maxLines < 1 ? 1 : maxLines);
  final top = max < min ? min : max;
  return contentHeight.clamp(min, top).toDouble();
}

/// Whether typing [inserted] over [selected] characters of a text of
/// [length] characters would pass [maxLength] (null = no limit).
bool nativeExceedsMaxLength({
  required int length,
  required int selected,
  required int inserted,
  required int? maxLength,
}) => maxLength != null && length - selected + inserted > maxLength;

/// The counter under a field with a [maxLength], as Flutter's own `TextField`
/// writes it ("12/200"), or null when there is no counter.
String? nativeCounterText({
  required int length,
  required int? maxLength,
  String? counterText,
}) {
  if (counterText != null) return counterText;
  if (maxLength == null || maxLength <= 0) return null;
  return '$length/$maxLength';
}

/// The keys the browser field keeps for itself. Flutter's shortcuts see every
/// key the page gets (the engine listens on the window); left to them, an
/// arrow key scrolls the dialog and Space activates, and the caret never
/// moves. Only Tab (focus traversal) and Escape (closing a dialog) go on.
bool nativeFieldKeepsKey(LogicalKeyboardKey key) =>
    key != LogicalKeyboardKey.tab && key != LogicalKeyboardKey.escape;
