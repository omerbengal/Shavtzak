import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/domain/entities/subtask.dart';
import 'package:shavtzak/presentation/screens/task/edit/editable_value.dart';
import 'package:shavtzak/presentation/screens/task/edit/value_editors.dart';

void main() {
  late List<String> commits;

  setUp(() => commits = []);

  Future<void> pump(
    WidgetTester tester, {
    bool wide = true,
    String? Function(String)? validate,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Column(
            children: [
              const SizedBox(key: Key('outside'), height: 100, width: 300),
              SizedBox(
                width: 300,
                child: EditableValue<String>(
                  key: const Key('value'),
                  value: 'ישן',
                  display: const Text('ישן'),
                  sheetTitle: 'שם המשימה',
                  wide: wide,
                  validate: validate,
                  editor: (context, draft, onChanged, onSubmit) =>
                      TextValueEditor(
                    initial: draft,
                    onChanged: onChanged,
                    onSubmit: onSubmit,
                  ),
                  onCommit: commits.add,
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }

  Future<void> startEditing(WidgetTester tester) async {
    await tester.tap(find.text('ישן'));
    await tester.pumpAndSettle();
  }

  testWidgets('click turns the value into an editor (wide)', (tester) async {
    await pump(tester);
    await startEditing(tester);
    expect(find.byKey(const Key('edit-value-editor')), findsOneWidget);
    expect(find.byKey(const Key('edit-text')), findsOneWidget);
  });

  testWidgets('Enter commits the typed text', (tester) async {
    await pump(tester);
    await startEditing(tester);
    await tester.enterText(find.byKey(const Key('edit-text')), 'חדש');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(commits, ['חדש']);
    expect(find.byKey(const Key('edit-value-editor')), findsNothing);
  });

  testWidgets('Esc cancels without commit', (tester) async {
    await pump(tester);
    await startEditing(tester);
    await tester.enterText(find.byKey(const Key('edit-text')), 'חדש');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(commits, isEmpty);
    expect(find.byKey(const Key('edit-value-editor')), findsNothing);
  });

  testWidgets('tap outside saves', (tester) async {
    await pump(tester);
    await startEditing(tester);
    await tester.enterText(find.byKey(const Key('edit-text')), 'חדש');
    await tester.tapAt(tester.getCenter(find.byKey(const Key('outside'))));
    await tester.pumpAndSettle();
    expect(commits, ['חדש']);
  });

  testWidgets('unchanged value does not commit', (tester) async {
    await pump(tester);
    await startEditing(tester);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(commits, isEmpty);
    expect(find.byKey(const Key('edit-value-editor')), findsNothing);
  });

  testWidgets('validate error keeps the editor open', (tester) async {
    await pump(tester, validate: (v) => v.trim().isEmpty ? 'חובה' : null);
    await startEditing(tester);
    await tester.enterText(find.byKey(const Key('edit-text')), '  ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(commits, isEmpty);
    expect(find.text('חובה'), findsOneWidget);
    expect(find.byKey(const Key('edit-value-editor')), findsOneWidget);
  });

  testWidgets('narrow tap opens a sheet and שמירה commits', (tester) async {
    await pump(tester, wide: false);
    await startEditing(tester);
    expect(find.byKey(const Key('edit-value-sheet')), findsOneWidget);
    expect(find.text('שם המשימה'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('edit-text')), 'חדש');
    await tester.tap(find.byKey(const Key('edit-value-save')));
    await tester.pumpAndSettle();
    expect(commits, ['חדש']);
    expect(find.byKey(const Key('edit-value-sheet')), findsNothing);
  });

  testWidgets('subtasks editor: Enter adds a line, renamed line keeps its id',
      (tester) async {
    final reported = <List<String>>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SubtasksEditor(
          initial: const [],
          onChanged: (list) => reported.add([for (final s in list) s.title]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('edit-subtask-0')), 'א');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edit-subtask-1')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('edit-subtask-1')), 'ב');
    expect(reported.last, ['א', 'ב']);
  });

  testWidgets(
      'subtasks editor: dragging the first line below the second '
      'swaps them', (tester) async {
    final reported = <List<String>>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SubtasksEditor(
          initial: const [
            Subtask(id: 'a', title: 'א'),
            Subtask(id: 'b', title: 'ב'),
            Subtask(id: 'c', title: 'ג'),
          ],
          onChanged: (list) => reported.add([for (final s in list) s.title]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final handle = find.byIcon(Icons.drag_indicator).first;
    final rowHeight =
        tester.getSize(find.byKey(const Key('edit-subtask-0'))).height;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(Offset(0, rowHeight * 0.2));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(reported.last, ['ב', 'א', 'ג']);
  });
}
