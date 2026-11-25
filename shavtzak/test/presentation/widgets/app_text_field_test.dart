import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/presentation/widgets/app_text_field.dart';

/// Off the web (tests) AppTextField is Flutter's own TextField: these check
/// that fallback keeps every option the forms rely on.
void main() {
  Future<void> pump(WidgetTester tester, Widget field) => tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: Center(child: field)),
          ),
        ),
      );

  Finder textField() => find.byType(TextField);

  testWidgets('off the web it is a TextField, never the browser field',
      (tester) async {
    expect(AppTextField.usesNative(), isFalse);
    await pump(tester, const AppTextField(key: Key('f')));
    expect(find.descendant(of: find.byKey(const Key('f')), matching: textField()),
        findsOneWidget);
  });

  testWidgets('label, hint and icons come from the decoration', (tester) async {
    await pump(
      tester,
      const AppTextField(
        decoration: InputDecoration(
          labelText: 'כותרת',
          hintText: 'משהו',
          prefixIcon: Icon(Icons.title),
          border: OutlineInputBorder(),
        ),
      ),
    );
    expect(find.text('כותרת'), findsOneWidget);
    expect(find.byIcon(Icons.title), findsOneWidget);
    final decoration = tester.widget<TextField>(textField()).decoration!;
    expect(decoration.hintText, 'משהו');
  });

  testWidgets('typing reaches the outside controller and onChanged',
      (tester) async {
    final controller = TextEditingController();
    final changes = <String>[];
    await pump(tester,
        AppTextField(controller: controller, onChanged: changes.add));
    await tester.enterText(textField(), 'שלום');
    expect(controller.text, 'שלום');
    expect(changes, ['שלום']);
  });

  testWidgets('the outside controller changes what the field shows',
      (tester) async {
    final controller = TextEditingController(text: 'ישן');
    await pump(tester, AppTextField(controller: controller));
    expect(find.text('ישן'), findsOneWidget);
    controller.text = 'חדש';
    await tester.pump();
    expect(find.text('חדש'), findsOneWidget);
    controller.clear();
    await tester.pump();
    expect(find.text('חדש'), findsNothing);
  });

  testWidgets('Enter in a single line calls onSubmitted with the text',
      (tester) async {
    String? submitted;
    await pump(tester, AppTextField(onSubmitted: (v) => submitted = v));
    await tester.enterText(textField(), 'נושא');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(submitted, 'נושא');
  });

  testWidgets('Ctrl+Enter in several lines calls onSubmitShortcut',
      (tester) async {
    var shortcut = 0;
    await pump(
      tester,
      AppTextField(
        minLines: 2,
        maxLines: null,
        onSubmitShortcut: () => shortcut++,
      ),
    );
    await tester.tap(textField());
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(shortcut, 1);
  });

  testWidgets('several lines: minLines and maxLines reach the field',
      (tester) async {
    await pump(tester, const AppTextField(minLines: 2, maxLines: 5));
    final field = tester.widget<TextField>(textField());
    expect(field.minLines, 2);
    expect(field.maxLines, 5);
    expect(field.keyboardType, TextInputType.multiline);
  });

  testWidgets('maxLength shows the counter and stops at the limit',
      (tester) async {
    final controller = TextEditingController();
    await pump(tester, AppTextField(controller: controller, maxLength: 5));
    expect(find.text('0/5'), findsOneWidget);
    await tester.enterText(textField(), 'אבגדהוז');
    await tester.pump();
    expect(controller.text, 'אבגדה');
    expect(find.text('5/5'), findsOneWidget);
  });

  testWidgets('errorText from the decoration shows under the field',
      (tester) async {
    await pump(
      tester,
      const AppTextField(decoration: InputDecoration(errorText: 'חובה')),
    );
    expect(find.text('חובה'), findsOneWidget);
  });

  testWidgets('a validator joins the Form around it', (tester) async {
    final form = GlobalKey<FormState>();
    final controller = TextEditingController();
    await pump(
      tester,
      Form(
        key: form,
        child: AppTextField(
          controller: controller,
          validator: (v) => (v ?? '').trim().isEmpty ? 'חובה למלא' : null,
        ),
      ),
    );
    expect(form.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('חובה למלא'), findsOneWidget);
    await tester.enterText(textField(), 'יש');
    expect(form.currentState!.validate(), isTrue);
    await tester.pump();
    expect(find.text('חובה למלא'), findsNothing);
  });

  testWidgets('readOnly and enabled reach the field', (tester) async {
    await pump(tester, const AppTextField(readOnly: true, enabled: false));
    final field = tester.widget<TextField>(textField());
    expect(field.readOnly, isTrue);
    expect(field.enabled, isFalse);
  });

  testWidgets('autofocus and an outside focus node', (tester) async {
    final focus = FocusNode();
    await pump(tester, AppTextField(focusNode: focus, autofocus: true));
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    focus.unfocus();
    await tester.pump();
    expect(focus.hasFocus, isFalse);
  });
}
