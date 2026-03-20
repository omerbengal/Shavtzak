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
