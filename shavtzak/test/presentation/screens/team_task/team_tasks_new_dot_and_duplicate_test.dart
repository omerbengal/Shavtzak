import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/team_task_rules.dart';
import 'package:shavtzak/domain/entities/team_task.dart';
import 'package:shavtzak/presentation/bloc/team_task/team_task_bloc.dart';
import 'package:shavtzak/presentation/screens/team_task/widgets/duplicate_picker_dialog.dart';
import 'package:shavtzak/presentation/screens/team_task/widgets/team_task_style.dart';

import '../../../support/task_fixtures.dart';
import '../../../support/team_task_fixtures.dart';

void main() {
  group('the "new" dot (Omer, msg 4581)', () {
    final created = DateTime.utc(2026, 11, 17, 10);
    final task = buildTeamTask(id: 'a', createdAt: created);

    Future<void> pump(WidgetTester tester, DateTime Function() clock) =>
        tester.pumpWidget(MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Center(child: TeamTaskCreatedText(task: task, clock: clock)),
          ),
        ));

    testWidgets('shows within two hours of the creation, and goes by itself', (tester) async {
      var now = created.add(const Duration(hours: 1, minutes: 59));
      await pump(tester, () => now);
      expect(find.byKey(const Key('team-task-new-dot-a')), findsOneWidget);
      expect(find.textContaining('נוצרה'), findsOneWidget);
      // No new data, no rebuild from outside: only the time passes.
      now = created.add(const Duration(hours: 2, seconds: 1));
      await tester.pump(const Duration(minutes: 1, seconds: 1));
      expect(find.byKey(const Key('team-task-new-dot-a')), findsNothing);
      expect(find.textContaining('נוצרה'), findsOneWidget);
    });

    testWidgets('none on an older task', (tester) async {
      await pump(tester, () => created.add(const Duration(hours: 3)));
      expect(find.byKey(const Key('team-task-new-dot-a')), findsNothing);
    });

    test('isTeamTaskNew: under two hours only', () {
      expect(isTeamTaskNew(task, created.add(const Duration(minutes: 119))), isTrue);
      expect(isTeamTaskNew(task, created.add(const Duration(hours: 2))), isFalse);
    });
  });

  group('the duplicate picker (Omer, msg 4581)', () {
    final dana = buildMember(id: 'm1', name: 'דנה');
    final yossi = buildMember(id: 'm2', name: 'יוסי');
    final category = buildCategory(id: 'c1', name: 'אירועי חנוכה', colorValue: 0xFF1E88E5);
    final event = buildEvent(id: 'e1', name: 'הדלקת נרות').copyWith(categoryId: 'c1');
    const topic = TaskLink(TaskLinkType.topic, 'p1');
    final current =
        buildTeamTask(id: 'cur', title: 'להזמין אולם', link: topic).copyWith(owners: [dana]);
    final sameTopic = buildTeamTask(
      id: 'other',
      title: 'להזמין אולם גדול',
      link: topic,
      assigneeIds: ['m1', 'm2'],
      status: TeamTaskStatus.inProgress,
    ).copyWith(owners: [dana, yossi], topic: () => buildTopic());
    final onEvent = buildTeamTask(
      id: 'ev',
      title: 'לקנות סופגניות',
      link: const TaskLink(TaskLinkType.event, 'e1'),
      assigneeIds: ['m2'],
    ).copyWith(owners: [yossi], event: () => event);
    final dup =
        buildTeamTask(id: 'dup', title: 'כפולה', link: topic, status: TeamTaskStatus.duplicate);

    TeamTasksLoaded state() => TeamTasksLoaded(
          viewer: dana,
          all: [current, sameTopic, onEvent, dup],
          mine: const [],
          allGroups: const [],
          mineGroups: const [],
          filter: TeamTaskFilter.initial,
          canManage: true,
          events: [event],
          categories: [category],
        );

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DuplicatePickerDialog(
            state: state(),
            task: current,
            now: DateTime.utc(2026, 11, 15, 8),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('grouped like the list, without the task itself and duplicates',
        (tester) async {
      await pump(tester);
      expect(find.byKey(const Key('duplicate-original-cur')), findsNothing);
      expect(find.byKey(const Key('duplicate-original-dup')), findsNothing);
      expect(find.byKey(const Key('duplicate-card-category:c1')), findsOneWidget);
      expect(find.byKey(const Key('duplicate-section-category:c1/event:e1')), findsOneWidget);
      expect(find.text('קטגוריה · אירועי חנוכה'), findsOneWidget);
      expect(
        find.descendant(
            of: find.byKey(const Key('duplicate-card-category:c1')),
            matching: find.byKey(const Key('duplicate-original-ev'))),
        findsOneWidget,
      );
      // Owners and the status on the row.
      expect(find.text('דנה, יוסי'), findsOneWidget);
      expect(
        find.descendant(
            of: find.byKey(const Key('duplicate-original-other')),
            matching: find.text(TeamTaskStatus.inProgress.hebrewLabel)),
        findsOneWidget,
      );
    });

    testWidgets('the search matches as the list does: owners, quotes ignored', (tester) async {
      await pump(tester);
      await tester.enterText(find.byKey(const Key('duplicate-search')), 'סופגני"ות');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('duplicate-original-ev')), findsOneWidget);
      expect(find.byKey(const Key('duplicate-original-other')), findsNothing);
      await tester.enterText(find.byKey(const Key('duplicate-search')), 'יוסי');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('duplicate-original-ev')), findsOneWidget);
      expect(find.byKey(const Key('duplicate-original-other')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('duplicate-search')), 'אין כזה');
      await tester.pumpAndSettle();
      expect(find.text('לא נמצאו משימות'), findsOneWidget);
    });
  });

  testWidgets('the urgency picker stays on one line at 360 px (msg 4581)', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Padding(
            // A sheet's own side padding.
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TeamTaskUrgencyPicker(value: TeamTaskUrgency.high, onChanged: (_) {}),
          ),
        ),
      ),
    ));
    for (final urgency in TeamTaskUrgency.values) {
      final label = find.byKey(Key('team-task-urgency-${urgency.key}'));
      // One line of the label's text, not two.
      expect(tester.getSize(label).height, lessThan(24), reason: urgency.hebrewLabel);
    }
    expect(tester.takeException(), isNull);
  });
}
