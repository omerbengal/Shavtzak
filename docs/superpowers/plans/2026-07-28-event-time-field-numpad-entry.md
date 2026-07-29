# Event Time Field Numpad Entry — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the five time fields in the event create/edit modal typable on a numpad, with the Cupertino wheel picker moved behind a clock button at the far-left edge of each field.

**Architecture:** Two pure helpers (an input formatter and a blur-completion function) plus an optional-time validator, consumed by a new `EventTimeField` widget extracted out of the 2793-line `event_form_modal.dart`. The modal keeps only its five call sites. Extraction is what makes the field testable without mounting the modal and its BLoCs.

**Tech Stack:** Flutter Web, Dart 3.6, `flutter_test`. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-07-28-event-time-field-numpad-entry-design.md`

## Global Constraints

- Run every Flutter command from the `shavtzak/` subdirectory, never the repo root.
- All UI text is Hebrew; code comments are English.
- The event modal is wrapped in `Directionality(textDirection: TextDirection.rtl)`. **Under RTL the `prefixIcon` slot renders at the far right of a field and the `suffixIcon` slot at the far left.** Every "left"/"right" below means the physical on-screen position.
- `flutter analyze` carries ~107 pre-existing infos. "Clean" means **zero new** findings, not zero findings. An unused import introduced by this work counts as a new finding.
- All five time fields are **optional**. Empty must always validate.
- Existing test suite must stay green (486 tests as of 2026-07-27).
- Do not touch the `showTimePicker` / `TimeOfDay` usages in `constraints_screen.dart` or `team_list_screen.dart`. Out of scope.
- Working directory for this plan: `/Users/omerbengal/Documents/Github Projects/Shavtzak/.claude/worktrees/feat-time-field-numpad-entry` (branch `worktree-feat-time-field-numpad-entry`).

---

## File Structure

| File | Responsibility |
|---|---|
| `lib/core/utils/time_input_formatter.dart` **(create)** | `TimeTextInputFormatter` — masks typed digits into `HH:mm`. `completePartialTime` — fills in a partial entry on blur. Both pure, no Flutter widgets. |
| `lib/core/utils/validators.dart` **(modify)** | Add `validateOptionalTime` beside the existing `validateTime`. |
| `lib/presentation/screens/event/widgets/event_time_field.dart` **(create)** | `EventTimeField` widget + the Cupertino wheel dialog moved out of the modal. |
| `lib/presentation/screens/event/widgets/event_form_modal.dart` **(modify)** | Delete `_buildTimeField` and `_showTimePickerFor`; point the five call sites at `EventTimeField`. |
| `test/core/utils/time_input_formatter_test.dart` **(create)** | Unit tests for the formatter and the completion helper. |
| `test/core/utils/validators_optional_time_test.dart` **(create)** | Unit tests for `validateOptionalTime`. |
| `test/presentation/screens/event/widgets/event_time_field_test.dart` **(create)** | Widget tests for `EventTimeField`, following the `ParticipantGroupRows` host pattern (direct construction, no BLoCs). |

---

## Task 1: Time input formatter and blur completion

**Files:**
- Create: `shavtzak/lib/core/utils/time_input_formatter.dart`
- Test: `shavtzak/test/core/utils/time_input_formatter_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `class TimeTextInputFormatter extends TextInputFormatter` — default constructor, no arguments.
  - `String completePartialTime(String raw)` — top-level function.

- [ ] **Step 1: Write the failing tests**

Create `shavtzak/test/core/utils/time_input_formatter_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/time_input_formatter.dart';

/// A `TextEditingValue` with the caret parked at the end, which is where it
/// sits during ordinary typing.
TextEditingValue _at(String text) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );

/// Replay [keystrokes] one character at a time through the formatter and
/// return what the field ends up showing.
String _type(String keystrokes) {
  final formatter = TimeTextInputFormatter();
  var value = TextEditingValue.empty;
  for (final char in keystrokes.split('')) {
    value = formatter.formatEditUpdate(value, _at(value.text + char));
  }
  return value.text;
}

/// One backspace against a field currently showing [current].
String _backspace(String current) {
  final shortened =
      current.isEmpty ? '' : current.substring(0, current.length - 1);
  return TimeTextInputFormatter()
      .formatEditUpdate(_at(current), _at(shortened))
      .text;
}

void main() {
  group('TimeTextInputFormatter', () {
    test('lays typed digits into HH:mm, colon appearing on the third digit',
        () {
      expect(_type('1'), '1');
      expect(_type('18'), '18');
      expect(_type('180'), '18:0');
      expect(_type('1800'), '18:00');
    });

    test('lets an impossible time be typed — save-time validation catches it',
        () {
      expect(_type('2570'), '25:70');
      expect(_type('1875'), '18:75');
    });

    test('drops digits past the fourth', () {
      expect(_type('180099'), '18:00');
    });

    test('strips everything that is not a digit', () {
      final formatter = TimeTextInputFormatter();
      expect(
        formatter.formatEditUpdate(TextEditingValue.empty, _at('a1b8c0d0')).text,
        '18:00',
      );
    });

    test('accepts a pasted time, with or without its colon', () {
      final formatter = TimeTextInputFormatter();
      expect(
        formatter.formatEditUpdate(TextEditingValue.empty, _at('18:00')).text,
        '18:00',
      );
      expect(
        formatter.formatEditUpdate(TextEditingValue.empty, _at('1800')).text,
        '18:00',
      );
    });

    test('backspace walks back down the same ladder', () {
      expect(_backspace('18:00'), '18:0');
      expect(_backspace('18:0'), '18');
      expect(_backspace('18'), '1');
      expect(_backspace('1'), '');
    });

    test('leaves the caret at the end of the formatted text', () {
      final formatter = TimeTextInputFormatter();
      final result =
          formatter.formatEditUpdate(_at('18'), _at('180'));
      expect(result.text, '18:0');
      expect(result.selection.baseOffset, 4);
    });
  });

  group('completePartialTime', () {
    test('leaves an empty field empty — every time field is optional', () {
      expect(completePartialTime(''), '');
      expect(completePartialTime('   '), '');
    });

    test('fills in the minutes when only an hour was typed', () {
      expect(completePartialTime('18'), '18:00');
      expect(completePartialTime('9'), '09:00');
      expect(completePartialTime('0'), '00:00');
    });

    test('reads a lone minute digit as the tens place', () {
      expect(completePartialTime('18:3'), '18:30');
      expect(completePartialTime('183'), '18:30');
    });

    test('returns an already-valid time untouched', () {
      expect(completePartialTime('18:00'), '18:00');
      expect(completePartialTime('00:00'), '00:00');
      expect(completePartialTime('23:59'), '23:59');
    });

    test('does not rewrite a stored unpadded time such as 9:05', () {
      // Three digits, so the tens-first rule would otherwise turn this into
      // 90:50. Hydrated values never pass through the input formatter, so the
      // already-valid guard is the only thing protecting them.
      expect(completePartialTime('9:05'), '9:05');
    });

    test('keeps the raw text when completing it would not be a real time', () {
      // 93 would complete to 93:00. Better to leave 93 on screen and let the
      // validator flag it than to invent a wrong time.
      expect(completePartialTime('93'), '93');
      expect(completePartialTime('99'), '99');
    });

    test('leaves a full but impossible time alone', () {
      expect(completePartialTime('25:70'), '25:70');
      expect(completePartialTime('24:00'), '24:00');
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd shavtzak && flutter test test/core/utils/time_input_formatter_test.dart
```

Expected: FAIL — `Error: Couldn't resolve the package 'shavtzak/core/utils/time_input_formatter.dart'` / target of URI doesn't exist.

- [ ] **Step 3: Write the implementation**

Create `shavtzak/lib/core/utils/time_input_formatter.dart`:

```dart
import 'package:flutter/services.dart';

/// The `HH:mm` shape a finished time field must hold. Accepts an unpadded hour
/// (`9:05`) because values stored before this field became typable may not be
/// padded.
final RegExp _validTime = RegExp(r'^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$');

/// Masks free typing into an `HH:mm` shape for the event time fields.
///
/// Digits only, capped at four, with the colon inserted once a third digit
/// arrives: `1` → `1`, `18` → `18`, `180` → `18:0`, `1800` → `18:00`.
///
/// Impossible times are deliberately allowed through — `25:70` is typable — so
/// the formatter never fights the keyboard. `Validators.validateOptionalTime`
/// catches them when the form is saved.
class TimeTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 4) {
      digits = digits.substring(0, 4);
    }

    final formatted = digits.length > 2
        ? '${digits.substring(0, 2)}:${digits.substring(2)}'
        : digits;

    // The field is five characters wide and the mask is rebuilt from the digits
    // on every edit, so parking the caret at the end is both simpler and what
    // typing and backspacing both want.
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Fills in what the admin did not type, once they leave the field.
///
/// `9` → `09:00`, `18` → `18:00`, `18:3` → `18:30`. Minutes are typed
/// tens-first, so a lone minute digit is the tens place.
///
/// Two guards keep this from corrupting a value:
///   * text that is already a valid time is returned untouched, so a stored
///     `9:05` is not re-read as three digits and rewritten to `90:50`;
///   * a completion that would not itself be a valid time is discarded and the
///     raw text kept, so `93` stays `93` and is flagged on save rather than
///     silently becoming `93:00`.
String completePartialTime(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return '';
  if (_validTime.hasMatch(text)) return text;

  final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return text;

  final completed = switch (digits.length) {
    1 || 2 => '${digits.padLeft(2, '0')}:00',
    3 => '${digits.substring(0, 2)}:${digits.substring(2)}0',
    _ => '${digits.substring(0, 2)}:${digits.substring(2, 4)}',
  };

  return _validTime.hasMatch(completed) ? completed : text;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd shavtzak && flutter test test/core/utils/time_input_formatter_test.dart
```

Expected: PASS — 7 tests in the `TimeTextInputFormatter` group, 7 in the `completePartialTime` group.

- [ ] **Step 5: Check for new analyzer findings**

```bash
cd shavtzak && flutter analyze lib/core/utils/time_input_formatter.dart
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add shavtzak/lib/core/utils/time_input_formatter.dart shavtzak/test/core/utils/time_input_formatter_test.dart
git commit -m "feat(event-form): add HH:mm input formatter and blur completion

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Optional-time validator

**Files:**
- Modify: `shavtzak/lib/core/utils/validators.dart` (insert after `validateTime`, which ends at line 74)
- Test: `shavtzak/test/core/utils/validators_optional_time_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `static String? Validators.validateOptionalTime(String? value)` — returns `null` when valid (including empty), otherwise the Hebrew string `'פורמט שעה לא תקין'`. Its signature matches `FormFieldValidator<String>` so it can be passed straight to `TextFormField.validator`.

The existing `Validators.validateTime` cannot be reused: it returns `'שעה היא שדה חובה'` for an empty value, and all five event time fields are optional.

- [ ] **Step 1: Write the failing tests**

Create `shavtzak/test/core/utils/validators_optional_time_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/validators.dart';

void main() {
  group('Validators.validateOptionalTime', () {
    test('an empty value passes — the event time fields are all optional', () {
      expect(Validators.validateOptionalTime(null), isNull);
      expect(Validators.validateOptionalTime(''), isNull);
      expect(Validators.validateOptionalTime('   '), isNull);
    });

    test('a real time passes', () {
      expect(Validators.validateOptionalTime('18:00'), isNull);
      expect(Validators.validateOptionalTime('00:00'), isNull);
      expect(Validators.validateOptionalTime('23:59'), isNull);
    });

    test('an unpadded hour passes, for values stored before this change', () {
      expect(Validators.validateOptionalTime('9:05'), isNull);
    });

    test('surrounding whitespace is ignored', () {
      expect(Validators.validateOptionalTime(' 18:00 '), isNull);
    });

    test('an out-of-range hour or minute is rejected', () {
      expect(Validators.validateOptionalTime('24:00'), 'פורמט שעה לא תקין');
      expect(Validators.validateOptionalTime('25:70'), 'פורמט שעה לא תקין');
      expect(Validators.validateOptionalTime('18:60'), 'פורמט שעה לא תקין');
    });

    test('an incomplete or non-numeric value is rejected', () {
      expect(Validators.validateOptionalTime('18'), 'פורמט שעה לא תקין');
      expect(Validators.validateOptionalTime('93'), 'פורמט שעה לא תקין');
      expect(Validators.validateOptionalTime('18:'), 'פורמט שעה לא תקין');
      expect(Validators.validateOptionalTime('abc'), 'פורמט שעה לא תקין');
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd shavtzak && flutter test test/core/utils/validators_optional_time_test.dart
```

Expected: FAIL — "The method 'validateOptionalTime' isn't defined for the class 'Validators'".

- [ ] **Step 3: Write the implementation**

In `shavtzak/lib/core/utils/validators.dart`, insert directly after the closing brace of `validateTime` (currently line 74, immediately before the `/// Validate date range` comment):

```dart

  /// Validate an optional time field (HH:mm).
  ///
  /// Unlike [validateTime], an empty value passes: the five event time fields
  /// are all optional. Used as the `validator` on `EventTimeField`, so a time
  /// the admin typed but never completed blocks the save with a red field.
  static String? validateOptionalTime(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return null;
    }

    final timeRegex = RegExp(r'^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$');
    if (!timeRegex.hasMatch(text)) {
      return 'פורמט שעה לא תקין';
    }

    return null;
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd shavtzak && flutter test test/core/utils/validators_optional_time_test.dart
```

Expected: PASS, all 6 tests.

- [ ] **Step 5: Commit**

```bash
git add shavtzak/lib/core/utils/validators.dart shavtzak/test/core/utils/validators_optional_time_test.dart
git commit -m "feat(event-form): add optional-time validator

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: The EventTimeField widget

**Files:**
- Create: `shavtzak/lib/presentation/screens/event/widgets/event_time_field.dart`
- Test: `shavtzak/test/presentation/screens/event/widgets/event_time_field_test.dart`

**Interfaces:**
- Consumes: `TimeTextInputFormatter` and `completePartialTime` (Task 1); `Validators.validateOptionalTime` (Task 2).
- Produces:

```dart
class EventTimeField extends StatefulWidget {
  const EventTimeField({
    super.key,
    required TextEditingController controller,
    required String label,
    required String hint,
    required String logKey,
    required VoidCallback onChanged,
    void Function(String value)? onTimeSet,
  });
}
```

`onTimeSet` replaces the old `onPicked` parameter of `_buildTimeField` and fires from **both** input paths. The controller is owned by the host and must not be disposed here.

- [ ] **Step 1: Write the failing tests**

Create `shavtzak/test/presentation/screens/event/widgets/event_time_field_test.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/presentation/screens/event/widgets/event_time_field.dart';

void main() {
  group('EventTimeField', () {
    testWidgets('typing four digits lays them out as HH:mm', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(_host(controller: controller));

      await tester.enterText(find.byType(TextFormField), '1800');
      await tester.pump();

      expect(controller.text, '18:00');
    });

    testWidgets('leaving a half-typed hour completes it', (tester) async {
      final controller = TextEditingController();
      final set = <String>[];
      await tester.pumpWidget(
        _host(controller: controller, onTimeSet: set.add),
      );

      await tester.enterText(find.byType(TextFormField), '18');
      await tester.pump();
      expect(controller.text, '18', reason: 'not completed until blur');

      await _unfocus(tester);

      expect(controller.text, '18:00');
      expect(set, ['18:00']);
    });

    testWidgets('a value that cannot be completed is left as typed',
        (tester) async {
      final controller = TextEditingController();
      final set = <String>[];
      await tester.pumpWidget(
        _host(controller: controller, onTimeSet: set.add),
      );

      await tester.enterText(find.byType(TextFormField), '93');
      await tester.pump();
      await _unfocus(tester);

      expect(controller.text, '93');
      expect(set, isEmpty, reason: '93 is not a time, nothing to hand on');
    });

    testWidgets('onTimeSet does not fire per keystroke', (tester) async {
      final controller = TextEditingController();
      final set = <String>[];
      await tester.pumpWidget(
        _host(controller: controller, onTimeSet: set.add),
      );

      await tester.enterText(find.byType(TextFormField), '1');
      await tester.pump();
      await tester.enterText(find.byType(TextFormField), '18');
      await tester.pump();
      await tester.enterText(find.byType(TextFormField), '1800');
      await tester.pump();

      expect(set, isEmpty);

      await _unfocus(tester);
      expect(set, ['18:00']);
    });

    testWidgets('the clock button opens the wheel', (tester) async {
      final controller = TextEditingController(text: '18:00');
      await tester.pumpWidget(_host(controller: controller));

      expect(find.byType(CupertinoDatePicker), findsNothing);

      await tester.tap(find.byTooltip('בחירת שעה'));
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoDatePicker), findsOneWidget);
      expect(find.text('אישור'), findsOneWidget);
      expect(find.text('ביטול'), findsOneWidget);
    });

    testWidgets('confirming the wheel writes the value and calls onTimeSet',
        (tester) async {
      final controller = TextEditingController(text: '18:00');
      final set = <String>[];
      await tester.pumpWidget(
        _host(controller: controller, onTimeSet: set.add),
      );

      await tester.tap(find.byTooltip('בחירת שעה'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('אישור'));
      await tester.pumpAndSettle();

      // The wheel opened on the field's own 18:00 and was confirmed untouched.
      expect(controller.text, '18:00');
      expect(set, ['18:00']);
    });

    testWidgets('the clear button appears only once the field has a value',
        (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(_host(controller: controller));

      expect(find.byTooltip('נקה שעה'), findsNothing);

      await tester.enterText(find.byType(TextFormField), '1800');
      await tester.pump();

      expect(find.byTooltip('נקה שעה'), findsOneWidget);

      await tester.tap(find.byTooltip('נקה שעה'));
      await tester.pump();

      expect(controller.text, '');
      expect(find.byTooltip('נקה שעה'), findsNothing);
    });

    testWidgets('an incomplete value fails validation and shows the error',
        (tester) async {
      final formKey = GlobalKey<FormState>();
      final controller = TextEditingController(text: '25:70');
      await tester.pumpWidget(_host(controller: controller, formKey: formKey));

      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();

      expect(find.text('פורמט שעה לא תקין'), findsOneWidget);
    });

    testWidgets('an empty field passes validation', (tester) async {
      final formKey = GlobalKey<FormState>();
      final controller = TextEditingController();
      await tester.pumpWidget(_host(controller: controller, formKey: formKey));

      expect(formKey.currentState!.validate(), isTrue);
    });

    testWidgets('onChanged fires so the host can rebuild its derive arrows',
        (tester) async {
      final controller = TextEditingController();
      var changes = 0;
      await tester.pumpWidget(
        _host(controller: controller, onChanged: () => changes++),
      );

      await tester.enterText(find.byType(TextFormField), '1800');
      await tester.pump();

      expect(changes, greaterThan(0));
    });
  });
}

/// Drop focus the way tapping elsewhere in the form would.
Future<void> _unfocus(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

Widget _host({
  required TextEditingController controller,
  GlobalKey<FormState>? formKey,
  void Function(String value)? onTimeSet,
  VoidCallback? onChanged,
}) {
  return MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Form(
          key: formKey ?? GlobalKey<FormState>(),
          child: EventTimeField(
            controller: controller,
            label: 'שעת התייצבות (אופציונלי)',
            hint: 'לדוגמה: 17:00',
            logKey: 'assembly',
            onChanged: onChanged ?? () {},
            onTimeSet: onTimeSet,
          ),
        ),
      ),
    ),
  );
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd shavtzak && flutter test test/presentation/screens/event/widgets/event_time_field_test.dart
```

Expected: FAIL — target of URI doesn't exist for `event_time_field.dart`.

- [ ] **Step 3: Write the implementation**

Create `shavtzak/lib/presentation/screens/event/widgets/event_time_field.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/debug/logger.dart';
import '../../../../core/utils/time_input_formatter.dart';
import '../../../../core/utils/validators.dart';

/// One of the five optional time fields in the event form.
///
/// Typing is the primary path: the field raises a numpad and a formatter lays
/// the digits into `HH:mm`. The Cupertino wheel is still there, behind the clock
/// button — which RTL renders at the far *left* edge of the field, because the
/// `suffixIcon` slot is the trailing one.
class EventTimeField extends StatefulWidget {
  /// Owned by the host form, which also disposes it.
  final TextEditingController controller;
  final String label;
  final String hint;

  /// Suffix for this field's `Logger.action` keys, e.g. `assembly`.
  final String logKey;

  /// Fires on every edit, so the host form can mark itself dirty and rebuild.
  /// The two derive arrows read the controllers' text at build time, so without
  /// this they would go stale as soon as the admin typed instead of picked.
  final VoidCallback onChanged;

  /// Fires once the field holds a complete, valid time — from the wheel, or
  /// from blur completion after typing. Never fires per keystroke, and never
  /// when the value is unchanged since the field gained focus.
  final void Function(String value)? onTimeSet;

  const EventTimeField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.logKey,
    required this.onChanged,
    this.onTimeSet,
  });

  @override
  State<EventTimeField> createState() => _EventTimeFieldState();
}

class _EventTimeFieldState extends State<EventTimeField> {
  late final FocusNode _focusNode;
  late bool _hasValue;
  String _valueOnFocusGain = '';

  @override
  void initState() {
    super.initState();
    _hasValue = widget.controller.text.isNotEmpty;
    _focusNode = FocusNode()..addListener(_handleFocusChange);
    widget.controller.addListener(_handleControllerChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChange);
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    // The controller belongs to the host form — do not dispose it here.
    super.dispose();
  }

  /// Drives the ✕ button's visibility without depending on the host rebuilding.
  void _handleControllerChange() {
    final hasValue = widget.controller.text.isNotEmpty;
    if (hasValue != _hasValue) {
      setState(() => _hasValue = hasValue);
    }
  }

  void _handleFocusChange() {
    if (_focusNode.hasFocus) {
      _valueOnFocusGain = widget.controller.text;
      return;
    }
    _completeOnBlur();
  }

  /// Fill in a partial entry now that the admin has moved on.
  void _completeOnBlur() {
    final raw = widget.controller.text;
    final completed = completePartialTime(raw);
    if (completed != raw) {
      widget.controller.text = completed;
    }
    if (completed == _valueOnFocusGain) {
      return; // Focused and left without changing anything.
    }
    widget.onChanged();
    if (completed.isNotEmpty &&
        Validators.validateOptionalTime(completed) == null) {
      widget.onTimeSet?.call(completed);
    }
  }

  Future<void> _showWheelPicker() async {
    final now = DateTime.now();
    var initialTime = now;
    final parts = widget.controller.text.trim().split(':');
    if (parts.length == 2) {
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      // The range check matters now that the field is typable: DateTime would
      // silently roll 25:70 over into the next day rather than reject it.
      if (hour != null &&
          minute != null &&
          hour >= 0 &&
          hour <= 23 &&
          minute >= 0 &&
          minute <= 59) {
        initialTime = DateTime(now.year, now.month, now.day, hour, minute);
      }
    }

    var selectedTime = initialTime;

    final result = await showDialog<DateTime>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: 280,
          height: 220,
          child: Column(
            children: [
              // Cupertino time picker wheel
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  initialDateTime: initialTime,
                  use24hFormat: true,
                  onDateTimeChanged: (DateTime newTime) {
                    selectedTime = newTime;
                  },
                ),
              ),
              // Footer with cancel/confirm buttons
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      child: const Text('ביטול'),
                      onPressed: () {
                        Logger.action('tap:cancel:timePicker');
                        Navigator.of(context).pop();
                      },
                    ),
                    TextButton(
                      child: const Text('אישור'),
                      onPressed: () {
                        Logger.action('tap:confirm:timePicker');
                        Navigator.of(context).pop(selectedTime);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (result == null) return;

    final value = '${result.hour.toString().padLeft(2, '0')}:'
        '${result.minute.toString().padLeft(2, '0')}';
    widget.controller.text = value;
    widget.onChanged();
    widget.onTimeSet?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      focusNode: _focusNode,
      keyboardType: TextInputType.number,
      inputFormatters: [TimeTextInputFormatter()],
      // Keep the digits and the caret LTR inside the RTL form — mixed-direction
      // content is what makes Flutter's BiDi caret mapping misplace backspace.
      // textAlign keeps the value hugging the right edge, where it has always
      // sat.
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.right,
      validator: Validators.validateOptionalTime,
      onChanged: (_) => widget.onChanged(),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        border: const OutlineInputBorder(),
        // RTL renders the suffix slot at the far left of the field.
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.access_time),
              tooltip: 'בחירת שעה',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                Logger.action('open:timePicker:${widget.logKey}');
                _showWheelPicker();
              },
            ),
            if (_hasValue)
              IconButton(
                icon: const Icon(Icons.clear, color: Colors.grey),
                tooltip: 'נקה שעה',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  Logger.action('tap:clearTime:${widget.logKey}');
                  widget.controller.clear();
                  widget.onChanged();
                },
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd shavtzak && flutter test test/presentation/screens/event/widgets/event_time_field_test.dart
```

Expected: PASS, all 10 tests.

If the two icon buttons overflow the suffix slot, the failure will be a `RenderFlex overflowed` exception rather than a logic failure. Fix it by adding `suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0)` to the `InputDecoration` and tightening the buttons with `padding: const EdgeInsets.symmetric(horizontal: 4)` and `constraints: const BoxConstraints()`. Do not change the widget's behavior to work around a layout problem.

- [ ] **Step 5: Check for new analyzer findings**

```bash
cd shavtzak && flutter analyze lib/presentation/screens/event/widgets/event_time_field.dart
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add shavtzak/lib/presentation/screens/event/widgets/event_time_field.dart shavtzak/test/presentation/screens/event/widgets/event_time_field_test.dart
git commit -m "feat(event-form): add EventTimeField with numpad entry

Typing is now the primary path; the Cupertino wheel moves behind a
clock button at the far-left edge of the field.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Wire EventTimeField into the event form modal

**Files:**
- Modify: `shavtzak/lib/presentation/screens/event/widgets/event_form_modal.dart`
  - delete `_showTimePickerFor` (lines 286-365) and `_buildTimeField` (lines 389-425)
  - replace the five call sites (lines 2187-2299)
  - remove the now-unused `package:flutter/cupertino.dart` import (line 3)
  - add the `event_time_field.dart` import
  - add a `_markTimeFieldDirty` helper

**Interfaces:**
- Consumes: `EventTimeField` (Task 3).
- Produces: nothing new. This task removes `_buildTimeField` and `_showTimePickerFor` from the modal's private surface.

There is no unit test for this task — it is pure wiring, verified by the existing suite plus `flutter analyze`. The behavior it wires is already covered by Task 3.

- [ ] **Step 1: Add the import and remove the Cupertino one**

In `shavtzak/lib/presentation/screens/event/widgets/event_form_modal.dart`, delete line 3:

```dart
import 'package:flutter/cupertino.dart';
```

`CupertinoDatePicker` at lines 315-318 was its only user, and that code leaves in Step 2. Leaving the import would be a **new** analyzer finding.

Then add, next to the existing `import 'participant_group_rows.dart';` (line 16):

```dart
import 'event_time_field.dart';
```

- [ ] **Step 2: Delete the two methods that moved**

Delete `_showTimePickerFor` in its entirety — from the `Future<void> _showTimePickerFor(` signature at line 286 through its closing brace at line 365.

Delete `_buildTimeField` in its entirety — from its doc comment at line 389 (`/// A read-only time-picker field (tap opens the wheel picker). Extracted so`) through its closing brace at line 425.

Leave `_deriveTime` (lines 373-387) and `_buildDeriveArrow` (lines 430-469) exactly as they are.

- [ ] **Step 3: Add the dirty-marking helper**

Insert immediately before `Future<void> _saveEvent() async {`:

```dart
  /// Rebuild the form after a time field edit. The two derive arrows
  /// (שעתיים לפני / שעה אחרי) are computed from the controllers' text at
  /// build time, so a typed change has to repaint them the way a picked one
  /// always did. (The ✕ button needs no help here — `EventTimeField` drives
  /// its own visibility from a controller listener.)
  void _markTimeFieldDirty() {
    setState(() {
      _isDirty = true;
    });
  }
```

- [ ] **Step 4: Replace the five call sites**

Replace the `_buildTimeField(...)` call for **assembly** with:

```dart
                                        EventTimeField(
                                          controller: _assemblyTimeController,
                                          label: 'שעת התייצבות (אופציונלי)',
                                          hint: 'לדוגמה: 17:00',
                                          logKey: 'assembly',
                                          onChanged: _markTimeFieldDirty,
                                        ),
```

Replace the one for **start** with:

```dart
                                        EventTimeField(
                                          controller: _startTimeController,
                                          label: 'שעת התכנסות קהל (אופציונלי)',
                                          hint: 'לדוגמה: 18:00',
                                          logKey: 'start',
                                          onChanged: _markTimeFieldDirty,
                                          onTimeSet: (value) {
                                            // Live auto-fill: if התייצבות is
                                            // still empty, default it to 2h
                                            // before the gathering time.
                                            if (_assemblyTimeController.text
                                                .trim()
                                                .isEmpty) {
                                              final derived =
                                                  app_date_utils.DateUtils
                                                      .shiftHmByMinutes(
                                                          value, -120);
                                              if (derived != null) {
                                                _assemblyTimeController.text =
                                                    derived;
                                              }
                                            }
                                          },
                                        ),
```

Replace the one for **actual show start** with:

```dart
                                        EventTimeField(
                                          controller:
                                              _actualShowStartTimeController,
                                          label:
                                              'שעת תחילת המופע בפועל (אופציונלי)',
                                          hint: 'לדוגמה: 19:00',
                                          logKey: 'actualShowStart',
                                          onChanged: _markTimeFieldDirty,
                                        ),
```

Replace the one for **end** with:

```dart
                                        EventTimeField(
                                          controller: _endTimeController,
                                          label:
                                              'שעת סיום משוערת של המופע (אופציונלי)',
                                          hint: 'לדוגמה: 23:00',
                                          logKey: 'end',
                                          onChanged: _markTimeFieldDirty,
                                          onTimeSet: (value) {
                                            // Live auto-fill: if סיום הצוות is
                                            // still empty, default it to 1h
                                            // after the show end time.
                                            if (_teamEndTimeController.text
                                                .trim()
                                                .isEmpty) {
                                              final derived = app_date_utils
                                                      .DateUtils
                                                  .shiftHmByMinutes(value, 60);
                                              if (derived != null) {
                                                _teamEndTimeController.text =
                                                    derived;
                                              }
                                            }
                                          },
                                        ),
```

Replace the one for **team end** with:

```dart
                                        EventTimeField(
                                          controller: _teamEndTimeController,
                                          label:
                                              'שעת סיום משוערת של הצוות (אופציונלי)',
                                          hint: 'לדוגמה: 00:00',
                                          logKey: 'teamEnd',
                                          onChanged: _markTimeFieldDirty,
                                        ),
```

Note what changed at each site: `prefixIcon:` is gone entirely, `onPicked:` became `onTimeSet:`, and `onChanged: _markTimeFieldDirty` is new. The two `_buildDeriveArrow(...)` calls between them are untouched.

- [ ] **Step 5: Verify the analyzer is clean**

```bash
cd shavtzak && flutter analyze
```

Expected: the pre-existing ~107 infos, and **no new** warnings or errors. The check is that no finding names any file this plan touched:

```bash
cd shavtzak && flutter analyze 2>&1 | grep -E "event_form_modal|event_time_field|time_input_formatter|validators"
```

Expected: no output. The most likely regression here is an `unused_import` on `package:flutter/cupertino.dart` if Step 1 was skipped.

- [ ] **Step 6: Run the full test suite**

```bash
cd shavtzak && flutter test
```

Expected: all tests pass — the pre-existing suite (486 as of 2026-07-27) plus the 30 added by Tasks 1-3 (14 + 6 + 10).

- [ ] **Step 7: Commit**

```bash
git add shavtzak/lib/presentation/screens/event/widgets/event_form_modal.dart
git commit -m "feat(event-form): type event times on a numpad

The five time fields were read-only, settable only by spinning a
Cupertino wheel. They now take typed input, with the wheel behind a
clock button at the far-left edge of each field.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Manual smoke test

Automated tests cannot see the RTL layout. Run the app and check the event **create** modal and the event **edit** modal:

- [ ] The clock button sits at the far **left** edge of each of the five fields; there is no icon at the far right.
- [ ] Tapping the number area raises the numpad, not the wheel. Typing `1800` shows `18:00`.
- [ ] Typing `18` and tapping away gives `18:00`.
- [ ] Typing `93` and tapping away leaves `93`; pressing Save turns the field red with `פורמט שעה לא תקין` and does not save.
- [ ] The clock button opens the wheel; אישור writes the picked time.
- [ ] The ✕ appears once a field has a value and clears it.
- [ ] Typing a time into התכנסות קהל auto-fills התייצבות at −2h **when it is empty**, and typing into סיום המופע auto-fills סיום הצוות at +1h.
- [ ] The שעתיים לפני / שעה אחרי arrows grey out as you type, not only after using the wheel.
- [ ] Editing an existing event hydrates all five fields with their stored values, unchanged.

The app is running from the worktree at
`/Users/omerbengal/Documents/Github Projects/Shavtzak/.claude/worktrees/feat-time-field-numpad-entry` — `cd` into it, then `cd shavtzak` before `flutter run`.

## Deployment

None beyond the usual. This is Flutter-only — no Cloud Functions, no Firestore rules, no indexes. Web auto-builds and deploys to GitHub Pages on push to `main`.
