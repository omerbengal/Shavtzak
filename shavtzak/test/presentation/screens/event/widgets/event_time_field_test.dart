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
