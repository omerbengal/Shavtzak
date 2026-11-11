import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Makes the arrow keys move the caret the way they point inside a Hebrew
/// (right-to-left) text field.
///
/// In the browser build Flutter hands the arrow keys to the browser's hidden
/// input, which moves the caret backwards in Hebrew text: ← steps one letter
/// back in the text, which on screen is one letter to the RIGHT. A user who
/// presses ← to reach a letter watches the caret run the other way, and the
/// next Backspace deletes a letter they never aimed at.
///
/// Wrapped round a text field, this catches the arrow keys first and turns
/// them into Flutter's own caret moves with the direction swapped, so ← goes
/// forward in the text (left on screen) and → goes back (right on screen).
/// Character, word and line moves, with and without Shift, are all covered.
///
/// With [multiline], ↑ and ↓ become Flutter's own moves too. The hidden input
/// lays the text out in its own font and direction, so its lines are not the
/// lines on screen, and left to it ↓ lands the caret in a column the user
/// never aimed at. In a field of one line they are left alone, as are Home
/// and End everywhere.
///
/// Only on the web and only under a right-to-left [Directionality]; elsewhere
/// it is the child itself.
class RtlArrowKeys extends StatelessWidget {
  const RtlArrowKeys({super.key, required this.child, this.multiline = false});

  final Widget child;

  /// Whether the field holds several lines.
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || Directionality.maybeOf(context) != TextDirection.rtl) {
      return child;
    }
    return Shortcuts(
      shortcuts: rtlArrowShortcuts(defaultTargetPlatform, multiline: multiline),
      child: child,
    );
  }
}

/// The arrow keys, mirrored, for [platform] (the word and line modifiers
/// differ between the Mac and everything else), plus ↑ and ↓ when
/// [multiline]. Public for tests.
Map<ShortcutActivator, Intent> rtlArrowShortcuts(
  TargetPlatform platform, {
  bool multiline = false,
}) {
  const left = LogicalKeyboardKey.arrowLeft;
  const right = LogicalKeyboardKey.arrowRight;
  // On screen, ← is forward in a right-to-left text.
  Map<ShortcutActivator, Intent> pair(
    SingleActivator Function(LogicalKeyboardKey key) activator,
    Intent Function(bool forward) intent,
  ) =>
      {
        activator(left): intent(true),
        activator(right): intent(false),
      };

  final mac =
      platform == TargetPlatform.macOS || platform == TargetPlatform.iOS;
  return {
    ...pair(
      (k) => SingleActivator(k),
      (f) =>
          ExtendSelectionByCharacterIntent(forward: f, collapseSelection: true),
    ),
    ...pair(
      (k) => SingleActivator(k, shift: true),
      (f) => ExtendSelectionByCharacterIntent(
          forward: f, collapseSelection: false),
    ),
    if (mac) ...{
      ...pair(
        (k) => SingleActivator(k, alt: true),
        (f) => ExtendSelectionToNextWordBoundaryIntent(
            forward: f, collapseSelection: true),
      ),
      ...pair(
        (k) => SingleActivator(k, alt: true, shift: true),
        (f) =>
            ExtendSelectionToNextWordBoundaryOrCaretLocationIntent(forward: f),
      ),
      ...pair(
        (k) => SingleActivator(k, meta: true),
        (f) => ExtendSelectionToLineBreakIntent(
            forward: f, collapseSelection: true),
      ),
      ...pair(
        (k) => SingleActivator(k, meta: true, shift: true),
        (f) => ExpandSelectionToLineBreakIntent(forward: f),
      ),
    } else ...{
      ...pair(
        (k) => SingleActivator(k, control: true),
        (f) => ExtendSelectionToNextWordBoundaryIntent(
            forward: f, collapseSelection: true),
      ),
      ...pair(
        (k) => SingleActivator(k, control: true, shift: true),
        (f) => ExtendSelectionToNextWordBoundaryIntent(
            forward: f, collapseSelection: false),
      ),
    },
    if (multiline)
      for (final shift in const [false, true]) ...{
        SingleActivator(LogicalKeyboardKey.arrowUp, shift: shift):
            ExtendSelectionVerticallyToAdjacentLineIntent(
                forward: false, collapseSelection: !shift),
        SingleActivator(LogicalKeyboardKey.arrowDown, shift: shift):
            ExtendSelectionVerticallyToAdjacentLineIntent(
                forward: true, collapseSelection: !shift),
      },
  };
}
