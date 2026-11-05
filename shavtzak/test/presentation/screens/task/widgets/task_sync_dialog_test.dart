import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/services/task_import_files.dart';
import 'package:shavtzak/core/utils/crud_action_result.dart';
import 'package:shavtzak/core/utils/task_import/task_import_diff.dart';
import 'package:shavtzak/core/utils/task_progress.dart';
import 'package:shavtzak/domain/entities/stage_sync_plan.dart';
import 'package:shavtzak/domain/entities/subtask.dart';
import 'package:shavtzak/presentation/screens/task/widgets/task_sync_dialog.dart';

import '../../../../support/fake_task_import_files.dart';
import '../../../../support/import_workbook.dart';
import '../../../../support/task_fixtures.dart';

void main() {
  final event = buildEvent(
    id: 'e1',
    startDate: DateTime(2026, 6, 15),
    endDate: DateTime(2026, 6, 16),
  );
  final omer = buildMember(id: 'm1', name: 'עומר');
  final stage = buildStage(id: 's1', title: 'קליטה', date: DateTime(2026, 6, 15));
  final board = eventTaskBoard(event, stages: [
    stage
  ], tasks: [
    buildTask(
      id: 't1',
      stage: stage,
      title: 'הקמת עמדה',
      assignees: [omer],
      subtasks: const [Subtask(id: 'a', title: 'מדפסת', isDone: true)],
    ),
  ]);

  PickedImportFile file(List<int> bytes) =>
      PickedImportFile(name: 'מעודכן.xlsx', bytes: Uint8List.fromList(bytes));

  final same = file(buildImportWorkbook(
    stageRows: [stageRow(title: 'קליטה')],
    taskRows: [taskRow(title: 'הקמת עמדה', subtasks: 'מדפסת')],
  ));
  final changed = file(buildImportWorkbook(
    stageRows: [stageRow(title: 'קליטה'), stageRow(title: 'ערב')],
    taskRows: [taskRow(stage: 'ערב', title: 'סגירה')],
  ));

  late List<StageSyncPlan> sent;
  late Completer<CrudActionResult> backend;
  TaskImportDiff? returned;

  Future<void> open(WidgetTester tester, PickedImportFile picked) async {
    sent = [];
    backend = Completer<CrudActionResult>();
    returned = null;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              returned = await showTaskSyncDialog(
                context,
                file: picked,
                board: board,
                files: FakeTaskImportFiles(),
                assignees: Stream.value([omer]),
                onSync: (plan) {
                  sent.add(plan);
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
      tester.widget<FilledButton>(find.byKey(const Key('task-sync-confirm')));

  String textOf(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(Key(key))).data!;

  testWidgets('the same file has nothing to update', (tester) async {
    await open(tester, same);
    expect(find.byKey(const Key('task-sync-no-changes')), findsOneWidget);
    expect(confirm(tester).onPressed, isNull);
  });

  testWidgets('changes are counted, warned about and saved on confirm',
      (tester) async {
    await open(tester, changed);
    expect(textOf(tester, 'task-sync-stage-counts'), 'שלבים: 1 חדש');
    expect(
      textOf(tester, 'task-sync-task-counts'),
      'משימות: 1 חדשה · 1 נמחקת',
    );
    // The removed task had a ticked subtask.
    expect(find.byKey(const Key('task-sync-lost-warning')), findsOneWidget);
    expect(find.text('יימחק: סומנו 1 מתוך 1 תתי משימות'), findsOneWidget);

    await tester.tap(find.byKey(const Key('task-sync-confirm')));
    await tester.pump();
    expect(sent.single.taskIdsToDelete, ['t1']);
    expect(sent.single.stagesToCreate.single.title, 'ערב');

    backend.complete(const CrudActionResult.success());
    await tester.pumpAndSettle();
    expect(returned, isNotNull);
    expect(find.byKey(const Key('task-sync-confirm')), findsNothing);
  });

  testWidgets('a failed save keeps the dialog with the message',
      (tester) async {
    await open(tester, changed);
    await tester.tap(find.byKey(const Key('task-sync-confirm')));
    await tester.pump();
    backend.complete(const CrudActionResult.failure('השתנה בינתיים'));
    await tester.pump();
    expect(textOf(tester, 'task-sync-error'), 'השתנה בינתיים');
    expect(confirm(tester).onPressed, isNotNull);
  });
}
