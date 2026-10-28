import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/services/task_import_files.dart';
import 'package:shavtzak/core/utils/crud_action_result.dart';
import 'package:shavtzak/core/utils/task_import/task_import_parser.dart';
import 'package:shavtzak/domain/entities/imported_stage.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/screens/task/widgets/task_import_dialog.dart';

import '../../../../support/fake_task_import_files.dart';
import '../../../../support/import_workbook.dart';
import '../../../../support/task_fixtures.dart';

void main() {
  final event = buildEvent(
    id: 'e1',
    startDate: DateTime(2026, 6, 15),
    endDate: DateTime(2026, 6, 16),
  );
  final omer = buildMember(id: 'm1', name: 'עומר אליהו');

  PickedImportFile file(List<int> bytes) =>
      PickedImportFile(name: 'משימות.xlsx', bytes: Uint8List.fromList(bytes));

  final clean = file(buildImportWorkbook(
    stageRows: [stageRow(title: 'קליטה'), stageRow(title: 'ערב')],
    taskRows: [taskRow(assignees: 'עומר')],
  ));
  final broken = file(buildImportWorkbook(stageRows: [stageRow(title: null)]));

  late FakeTaskImportFiles files;
  late List<List<ImportedStage>> sent;
  late Completer<CrudActionResult> backend;
  TaskImportResult? returned;

  Future<void> open(
    WidgetTester tester,
    PickedImportFile picked, {
    Stream<List<TeamMember>>? assignees,
  }) async {
    files = FakeTaskImportFiles();
    sent = [];
    backend = Completer<CrudActionResult>();
    returned = null;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              returned = await showTaskImportDialog(
                context,
                file: picked,
                event: event,
                files: files,
                assignees: assignees ?? Stream.value([omer]),
                onImport: (stages) {
                  sent.add(stages);
                  return backend.future;
                },
                currentUserId: 'boss',
                now: DateTime(2026, 6, 1),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump();
  }

  FilledButton confirm(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(const Key('task-import-confirm')));

  testWidgets('a clean file shows the summary and every stage', (tester) async {
    await open(tester, clean);
    expect(
      tester.widget<Text>(find.byKey(const Key('task-import-summary'))).data,
      '2 שלבים · 1 משימות · 0 אנשי קשר',
    );
    expect(find.text('קליטה'), findsOneWidget);
    expect(find.text('ערב'), findsOneWidget);
    expect(confirm(tester).onPressed, isNotNull);
  });

  testWidgets('problems are listed and the import is disabled', (tester) async {
    await open(tester, broken);
    expect(find.text('נמצאה בעיה אחת בקובץ'), findsOneWidget);
    expect(find.text('שלבים, שורה 2: חסר שם לשלב'), findsOneWidget);
    expect(confirm(tester).onPressed, isNull);
  });

  testWidgets('picking another file checks it again', (tester) async {
    await open(tester, broken);
    files.picks.add(clean);
    await tester.tap(find.byKey(const Key('task-import-pick-again')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('task-import-summary')), findsOneWidget);
  });

  testWidgets('a file that cannot be read says so and keeps the dialog',
      (tester) async {
    await open(tester, broken);
    files.failNextPick = StateError('NotReadableError');
    await tester.tap(find.byKey(const Key('task-import-pick-again')));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('task-import-error'))).data,
      importFileReadError,
    );
    expect(find.text('שלבים, שורה 2: חסר שם לשלב'), findsOneWidget);
  });

  testWidgets('importing shows a spinner, sends once, and closes on success',
      (tester) async {
    await open(tester, clean);
    await tester.tap(find.byKey(const Key('task-import-confirm')));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(confirm(tester).onPressed, isNull);
    await tester.tap(
      find.byKey(const Key('task-import-confirm')),
      warnIfMissed: false,
    );
    expect(sent, hasLength(1));
    expect(sent.single, hasLength(2));

    backend.complete(const CrudActionResult.success());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-import-confirm')), findsNothing);
    expect(returned?.stages, hasLength(2));
  });

  testWidgets('a refused import stays open and says why', (tester) async {
    await open(tester, clean);
    await tester.tap(find.byKey(const Key('task-import-confirm')));
    await tester.pump();
    backend.complete(const CrudActionResult.failure('לאירוע כבר יש שלבים'));
    await tester.pump();

    expect(find.text('לאירוע כבר יש שלבים'), findsOneWidget);
    expect(confirm(tester).onPressed, isNotNull);
  });

  testWidgets('a retry after a failure sends the same ids, even if members changed',
      (tester) async {
    final members = StreamController<List<TeamMember>>();
    addTearDown(members.close);
    await open(tester, clean, assignees: members.stream);
    members.add([omer]);
    await tester.pump();

    await tester.tap(find.byKey(const Key('task-import-confirm')));
    await tester.pump();
    backend.complete(const CrudActionResult.failure('בעיית רשת'));
    await tester.pump();

    // Someone edits a team member meanwhile; the stream emits again.
    members.add([omer, buildMember(id: 'm9', name: 'חדש')]);
    await tester.pump();
    await tester.tap(find.byKey(const Key('task-import-confirm')));
    await tester.pump();

    expect(sent, hasLength(2));
    List<String> ids(List<ImportedStage> stages) => [
          for (final s in stages) ...[s.stage.id, for (final t in s.tasks) t.id],
        ];
    expect(ids(sent[1]), ids(sent[0]));
  });

  testWidgets('when the assigned members fail to load, nothing can be imported',
      (tester) async {
    await open(tester, clean, assignees: Stream.error(Exception('denied')));
    expect(find.byKey(const Key('task-import-members-error')), findsOneWidget);
    expect(confirm(tester).onPressed, isNull);
  });
}
