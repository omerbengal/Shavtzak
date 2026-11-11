import 'package:flutter/widgets.dart';

class RtlCursorFixedFocusNode extends FocusNode {
  bool _isDisposed = false;

  bool get isDisposed => _isDisposed;

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}

/// Fixes RTL cursor positioning for text fields with mixed Hebrew/number content.
///
/// Flutter's BiDi cursor mapping can place the cursor at the wrong logical
/// position when text contains both RTL (Hebrew) and LTR (numbers/Latin)
/// characters. This causes backspace to delete the wrong character.
///
/// This function adds a listener that forces the cursor to the actual end
/// of the text when the field gains focus, overriding Flutter's incorrect
/// BiDi cursor position mapping.
///
/// Call this in initState() or when creating the FocusNode.
/// The listener only fires on focus gain (not on every tap), so subsequent
/// taps within the text while already focused use normal positioning.
void addRtlCursorFix(FocusNode focusNode, TextEditingController controller) {
  focusNode.addListener(() {
    final trackedFocusNode =
        focusNode is RtlCursorFixedFocusNode ? focusNode : null;
    if (trackedFocusNode?.isDisposed == true) {
      return;
    }

    if (focusNode.hasFocus && controller.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (trackedFocusNode?.isDisposed == true) {
          return;
        }

        if (focusNode.hasFocus && controller.text.isNotEmpty) {
          controller.selection = TextSelection.collapsed(
            offset: controller.text.length,
          );
        }
      });
    }
  });
}

/// Creates a new FocusNode with the RTL cursor fix pre-attached.
/// The caller is responsible for disposing the returned FocusNode.
FocusNode createRtlCursorFixedFocusNode(TextEditingController controller) {
  final focusNode = RtlCursorFixedFocusNode();
  addRtlCursorFix(focusNode, controller);
  return focusNode;
}

/// A text controller for a right-to-left field of several lines.
///
/// A click in the empty space past the end of a right-to-left line (to its
/// left) belongs at the end of that line. Flutter's text engine answers
/// "right after the line's line break" instead, which is the start of the
/// NEXT line, and the caret jumps there. See [keepCaretOnItsLine].
class RtlTextEditingController extends TextEditingController {
  RtlTextEditingController({super.text});

  @override
  set value(TextEditingValue newValue) {
    super.value = keepCaretOnItsLine(newValue);
  }
}

/// [value] with a caret that the engine put right after a line break, for a
/// click past the end of the line before it, stepped back before that line
/// break.
///
/// The engine marks that answer as leaning back towards the clicked line
/// ([TextAffinity.upstream]). Nothing else puts a caret right after a line
/// break leaning back: the arrow keys, typing and a click on the next line
/// itself all lean forward. So that mark alone tells the two apart.
TextEditingValue keepCaretOnItsLine(TextEditingValue value) {
  const lineFeed = 0x0A;
  final selection = value.selection;
  if (!selection.isValid ||
      !selection.isCollapsed ||
      selection.affinity != TextAffinity.upstream) {
    return value;
  }
  final offset = selection.extentOffset;
  if (offset < 1 ||
      offset > value.text.length ||
      value.text.codeUnitAt(offset - 1) != lineFeed) {
    return value;
  }
  return value.copyWith(
    selection: TextSelection.collapsed(offset: offset - 1),
  );
}
