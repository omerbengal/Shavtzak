import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/presentation/widgets/rtl_arrow_keys.dart';

bool? forwardOf(Intent? intent) => switch (intent) {
      ExtendSelectionByCharacterIntent(:final forward) => forward,
      ExtendSelectionToNextWordBoundaryIntent(:final forward) => forward,
      ExtendSelectionToNextWordBoundaryOrCaretLocationIntent(:final forward) =>
        forward,
      ExtendSelectionToLineBreakIntent(:final forward) => forward,
      ExpandSelectionToLineBreakIntent(:final forward) => forward,
      _ => null,
    };

/// The intent [map] gives for [key] with exactly these modifiers.
Intent? lookup(Map<ShortcutActivator, Intent> map, SingleActivator key) {
  for (final entry in map.entries) {
    final a = entry.key as SingleActivator;
    if (a.trigger == key.trigger &&
        a.shift == key.shift &&
        a.control == key.control &&
        a.alt == key.alt &&
        a.meta == key.meta) {
      return entry.value;
    }
  }
  return null;
}

void main() {
  const left = LogicalKeyboardKey.arrowLeft;
  const right = LogicalKeyboardKey.arrowRight;

  group('rtlArrowShortcuts', () {
    test('← goes forward in the text, → back', () {
      final map = rtlArrowShortcuts(TargetPlatform.windows);
      expect(forwardOf(lookup(map, const SingleActivator(left))), isTrue);
      expect(forwardOf(lookup(map, const SingleActivator(right))), isFalse);
      final shiftLeft = lookup(map, const SingleActivator(left, shift: true));
      expect(forwardOf(shiftLeft), isTrue);
      expect((shiftLeft as ExtendSelectionByCharacterIntent).collapseSelection,
          isFalse);
    });

    test('word jumps use Ctrl on Windows and Alt on the Mac', () {
      final windows = rtlArrowShortcuts(TargetPlatform.windows);
      expect(
          forwardOf(
              lookup(windows, const SingleActivator(left, control: true))),
          isTrue);
      expect(lookup(windows, const SingleActivator(left, alt: true)), isNull);

      final mac = rtlArrowShortcuts(TargetPlatform.macOS);
      expect(forwardOf(lookup(mac, const SingleActivator(left, alt: true))),
          isTrue);
      expect(forwardOf(lookup(mac, const SingleActivator(right, meta: true))),
          isFalse);
      expect(lookup(mac, const SingleActivator(left, control: true)), isNull);
    });

    test('up and down are left alone', () {
      final map = rtlArrowShortcuts(TargetPlatform.windows);
      expect(lookup(map, const SingleActivator(LogicalKeyboardKey.arrowUp)),
          isNull);
      expect(lookup(map, const SingleActivator(LogicalKeyboardKey.arrowDown)),
          isNull);
    });
  });

  testWidgets('off the web it is the child itself', (tester) async {
    const child = SizedBox(key: Key('child'));
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.rtl,
      child: RtlArrowKeys(child: child),
    ));
    expect(kIsWeb, isFalse);
    expect(find.byType(Shortcuts), findsNothing);
    expect(find.byKey(const Key('child')), findsOneWidget);
  });
}
