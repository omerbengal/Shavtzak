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

    testWidgets(
        'a hydrated unpadded value survives focus-then-leave untouched',
        (tester) async {
      // 9:05 is the legacy unpadded shape a value stored before the field
      // became typable may hold. Checking it (focus, then leave without
      // typing) must not rewrite it and must not auto-fill a neighbour.
      final controller = TextEditingController(text: '9:05');
      final set = <String>[];
      await tester.pumpWidget(
        _host(controller: controller, onTimeSet: set.add),
      );

      await tester.tap(find.byType(TextFormField));
      await tester.pump();
      await _unfocus(tester);

      expect(controller.text, '9:05');
      expect(set, isEmpty,
          reason: 'checking an existing value must not fire onTimeSet');
    });

    testWidgets('a hydrated normal value survives focus-then-leave untouched',
        (tester) async {
      final controller = TextEditingController(text: '18:00');
      final set = <String>[];
      await tester.pumpWidget(
        _host(controller: controller, onTimeSet: set.add),
      );

      await tester.tap(find.byType(TextFormField));
      await tester.pump();
      await _unfocus(tester);

      expect(controller.text, '18:00');
      expect(set, isEmpty,
          reason: 'checking an existing value must not fire onTimeSet');
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

    testWidgets(
        'opening the wheel after typing does not fire onTimeSet before confirm',
        (tester) async {
      final controller = TextEditingController();
      final set = <String>[];
      await tester.pumpWidget(
        _host(controller: controller, onTimeSet: set.add),
      );

      // Typing focuses the field; controller now holds 18:00 and
      // _valueOnFocusGain is still '' from before the typing started.
      await tester.enterText(find.byType(TextFormField), '1800');
      await tester.pump();

      // Pushing the wheel dialog steals focus off the field, which used to
      // fire onTimeSet with the pre-adjustment value before the admin had
      // touched the wheel at all.
      await tester.tap(find.byTooltip('בחירת שעה'));
      await tester.pumpAndSettle();

      expect(set, isEmpty,
          reason: 'onTimeSet must not fire before the wheel is confirmed');

      await tester.tap(find.text('אישור'));
      await tester.pumpAndSettle();

      // The wheel itself fires onTimeSet exactly once, on confirm.
      expect(set, ['18:00']);
    });

    testWidgets('the wheel opens seeded from a partially-typed value, not now',
        (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(_host(controller: controller));

      // Only the hour was typed; the field shows "18", not "18:00".
      await tester.enterText(find.byType(TextFormField), '18');
      await tester.pump();

      await tester.tap(find.byTooltip('בחירת שעה'));
      await tester.pumpAndSettle();

      final picker = tester
          .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker));
      expect(picker.initialDateTime.hour, 18);
      expect(picker.initialDateTime.minute, 0);
    });

    // The five tests below pin the full onTimeSet firing matrix for the
    // wheel-cancel seam: whether onTimeSet fires must depend only on
    // "did the value actually change", never on "did the admin detour
    // through the wheel dialog on the way out."
    //
    //   sequence                                    | onTimeSet fires?
    //   1. type a time -> tap away (no wheel)        | yes
    //   2. type a time -> open wheel -> confirm      | yes (wheel's value)
    //   3. type a time -> open wheel -> cancel       | yes (typed value)
    //   4. focus only -> open wheel -> cancel         | no
    //   5. focus only -> tap away (no wheel)          | no
    group('onTimeSet fires exactly when the value actually changed', () {
      testWidgets('row 1: type a time, tap away with no wheel involved',
          (tester) async {
        final controller = TextEditingController();
        final set = <String>[];
        await tester.pumpWidget(
          _host(controller: controller, onTimeSet: set.add),
        );

        await tester.enterText(find.byType(TextFormField), '1800');
        await tester.pump();
        await _unfocus(tester);

        expect(set, ['18:00']);
      });

      testWidgets('row 2: type a time, open the wheel, confirm',
          (tester) async {
        final controller = TextEditingController();
        final set = <String>[];
        await tester.pumpWidget(
          _host(controller: controller, onTimeSet: set.add),
        );

        await tester.enterText(find.byType(TextFormField), '1800');
        await tester.pump();

        await tester.tap(find.byTooltip('בחירת שעה'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('אישור'));
        await tester.pumpAndSettle();

        expect(controller.text, '18:00');
        expect(set, ['18:00'], reason: 'must fire exactly once, on confirm');

        // Same double-fire guard as row 3: focus returning to the field
        // after the dialog closes must not leave a stale _valueOnFocusGain
        // that a later plain blur would see as "changed" all over again.
        await _unfocus(tester);
        expect(set, ['18:00'], reason: 'a later plain blur must not refire');
      });

      testWidgets(
          'row 3: type a time, open the wheel, cancel — onTimeSet must still '
          'fire (the inconsistency being fixed)', (tester) async {
        final controller = TextEditingController();
        final set = <String>[];
        var changes = 0;
        await tester.pumpWidget(
          _host(
            controller: controller,
            onTimeSet: set.add,
            onChanged: () => changes++,
          ),
        );

        await tester.enterText(find.byType(TextFormField), '1800');
        await tester.pump();

        await tester.tap(find.byTooltip('בחירת שעה'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('ביטול'));
        await tester.pumpAndSettle();

        expect(controller.text, '18:00',
            reason: 'cancel must not discard the already-typed value');
        expect(set, ['18:00'],
            reason: 'must fire exactly once, same as tapping away directly');
        // The dialog-opening blur already calls onChanged before it
        // suppresses onTimeSet (see _openingWheel) — the derive arrows must
        // still repaint on this path even though onTimeSet itself is decided
        // later, on cancel.
        expect(changes, greaterThan(0),
            reason: 'the derive arrows must still repaint on this path');

        // Guard against the natural focus-return-on-close accidentally
        // masking a double fire: a genuine later blur, with nothing further
        // typed, must not report the same value again.
        await _unfocus(tester);
        expect(set, ['18:00'], reason: 'a later plain blur must not refire');
      });

      testWidgets('row 4: focus only (no typing), open the wheel, cancel',
          (tester) async {
        final controller = TextEditingController(text: '18:00');
        final set = <String>[];
        await tester.pumpWidget(
          _host(controller: controller, onTimeSet: set.add),
        );

        await tester.tap(find.byType(TextFormField));
        await tester.pump();

        await tester.tap(find.byTooltip('בחירת שעה'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('ביטול'));
        await tester.pumpAndSettle();

        expect(controller.text, '18:00');
        expect(set, isEmpty,
            reason: 'nothing changed, so there is nothing to report');
      });

      testWidgets('row 5: focus only (no typing), tap away with no wheel',
          (tester) async {
        final controller = TextEditingController(text: '18:00');
        final set = <String>[];
        await tester.pumpWidget(
          _host(controller: controller, onTimeSet: set.add),
        );

        await tester.tap(find.byType(TextFormField));
        await tester.pump();
        await _unfocus(tester);

        expect(controller.text, '18:00');
        expect(set, isEmpty,
            reason: 'nothing changed, so there is nothing to report');
      });
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
