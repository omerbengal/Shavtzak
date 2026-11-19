import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/team_task_rules.dart';
import 'package:shavtzak/core/utils/team_task_spotlight.dart';
import 'package:shavtzak/data/repositories/team_task_repository.dart';
import 'package:shavtzak/domain/entities/team_task.dart';
import 'package:shavtzak/presentation/screens/team_task/widgets/team_task_mentions.dart';

import '../../../support/task_fixtures.dart';
import '../../../support/team_task_fixtures.dart';
import '../../../support/team_tasks_harness.dart';

/// Tags ("@") in the update log (Omer, 19/11/2026).
void main() {
  final dana = buildMember(id: 'm1', name: 'דנה');
  final yossi = buildMember(id: 'm2', name: 'יוסי כהן');
  final manager = buildMember(id: 'mgr', name: 'מנהלת', isAdmin: true);

  TeamTaskBoard board(List<TeamTask> tasks) => TeamTaskBoard(
        tasks: tasks,
        members: [dana, yossi, manager],
        topics: [buildTopic()],
        categories: [buildCategory()],
      );

  group('the rules', () {
    test('activeMentionQuery: after "@" at a word start, up to the caret', () {
      expect(activeMentionQuery('שלום @יו', 8), (start: 5, query: 'יו'));
      expect(activeMentionQuery('@', 1), (start: 0, query: ''));
      expect(activeMentionQuery('mail@x', 6), isNull);
      expect(activeMentionQuery('שלום', 4), isNull);
      expect(activeMentionQuery('@יוסי\nאחר', 10), isNull);
      expect(activeMentionQuery('@יוסי ', 6), isNull);
      expect(activeMentionQuery('@יוסי כ', 7), (start: 0, query: 'יוסי כ'));
    });

    test('mentionCandidates: the name holds the query, its start first', () {
      final names = mentionCandidates([dana, yossi, manager], 'כה').map((m) => m.id);
      expect(names, ['m2']);
      expect(mentionCandidates([dana, yossi], '').length, 2);
    });

    test('mentionIdsInText keeps only the names still in the text', () {
      expect(mentionIdsInText('@יוסי כהן תבדוק', {'יוסי כהן': 'm2', 'דנה': 'm1'}), ['m2']);
    });

    test('mentionItemTitle: the tagging update without the own name', () {
      final task = buildTeamTask(id: 't', title: 'ציוד לתרגיל').copyWith(updates: [
        TaskUpdateEntry(
            id: 'u1', text: '@יוסי כהן  תזמין 20 מזרנים', at: DateTime(2026, 11, 20), byId: 'm1'),
        TaskUpdateEntry(id: 'u2', text: '@יוסי כהן', at: DateTime(2026, 11, 20), byId: 'm1'),
      ]);
      TeamTaskMention tag(String updateId) =>
          TeamTaskMention(memberId: 'm2', updateId: updateId, at: DateTime(2026, 11, 20));
      expect(mentionItemTitle(task, tag('u1'), memberName: 'יוסי כהן'), 'תזמין 20 מזרנים');
      // Nothing left, a deleted update, a tag from before: the task's title.
      expect(mentionItemTitle(task, tag('u2'), memberName: 'יוסי כהן'), 'ציוד לתרגיל');
      expect(mentionItemTitle(task, tag('gone'), memberName: 'יוסי כהן'), 'ציוד לתרגיל');
      expect(mentionItemTitle(task, tag(''), memberName: 'יוסי כהן'), 'ציוד לתרגיל');
    });

    test('teamTaskLogLinks: a done line to its tag, overlapping links in other lanes', () {
      TaskUpdateEntry entry(String id, [String? doneOf]) => TaskUpdateEntry(
          id: id, text: id, at: DateTime(2026, 11, 20), byId: 'x', mentionDoneOf: doneOf);
      // Newest first: d1 (0), d2 (1), plain (2), d3 (3), t1 (4), t2 (5), t3 (6).
      final links = teamTaskLogLinks([
        entry('d1', 't1'),
        entry('d2', 't2'),
        entry('plain'),
        entry('d3', 't3'),
        entry('t1'),
        entry('t2'),
        entry('t3'),
        entry('d4', 'gone'),
      ]);
      expect(links.map((l) => (l.doneIndex, l.tagIndex)), [(0, 4), (1, 5), (3, 6)]);
      // The shortest (3-6) is innermost; the three overlap, so three lanes.
      expect(links.map((l) => l.lane), [1, 2, 0]);
      // Apart: one lane is enough.
      final apart = teamTaskLogLinks([entry('a', 'b'), entry('b'), entry('c', 'd'), entry('d')]);
      expect(apart.map((l) => l.lane), [0, 0]);
      // A link inside another sits inside it.
      final nested = teamTaskLogLinks([entry('a', 'd'), entry('b', 'c'), entry('c'), entry('d')]);
      expect(nested.map((l) => (l.doneIndex, l.lane)), [(0, 1), (1, 0)]);
    });

    test('mentionSpans colours each tagged name', () {
      final span = mentionSpans('היי @יוסי כהן, תודה', ['יוסי כהן']);
      final parts = span.children!.cast<TextSpan>().map((s) => s.text).toList();
      expect(parts, ['היי ', '@יוסי כהן', ', תודה']);
    });

    test('a tagged member: in "המשימות שלי" until done; Blitz skips it', () {
      final open = buildTeamTask(id: 't', assigneeIds: ['m1']).copyWith(mentions: [
        TeamTaskMention(memberId: 'm2', updateId: 'u1', at: DateTime(2026, 11, 15)),
      ]);
      final done = open.copyWith(mentions: [
        TeamTaskMention(
            memberId: 'm2', updateId: 'u1', at: DateTime(2026, 11, 15), doneAt: DateTime(2026, 11, 16)),
      ]);
      final oneOfTwo = open.copyWith(mentions: [
        ...done.mentions,
        TeamTaskMention(memberId: 'm2', updateId: 'u2', at: DateTime(2026, 11, 16)),
      ]);
      expect(myTeamTaskRows([oneOfTwo], 'm2').map((t) => t.id), ['t']);
      expect(myTeamTaskRows([open], 'm2').map((t) => t.id), ['t']);
      expect(myTeamTaskRows([done], 'm2'), isEmpty);
      expect(isTeamTaskTaggedOnly(done, 'm2'), isTrue);
      expect(isTeamTaskTaggedOnly(open, 'm1'), isFalse);
      expect(spotlightQueue([open], ownerId: 'm2'), isEmpty);
      expect(spotlightQueue([open], ownerId: 'm1').length, 1);
    });
  });

  group('the screen', () {
    testWidgets('typing "@" lists the team; the pick is sent as a tag', (tester) async {
      final mine = buildTeamTask(id: 'a', title: 'להזמין אולם', assigneeIds: ['m1'])
          .copyWith(owners: [dana]);
      final harness = await pumpTeamTasks(tester, user: dana, board: board([mine]));
      await tester.tap(find.byKey(const Key('team-task-quick-update-a')));
      await tester.pumpAndSettle();
      final field = find.byKey(const Key('team-task-update-field'));
      await tester.enterText(field, 'תבדוק @יו');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-task-mention-suggestions')), findsOneWidget);
      // Above the field (msg 5298).
      expect(
        tester.getBottomLeft(find.byKey(const Key('team-task-mention-suggestions'))).dy,
        lessThanOrEqualTo(tester.getTopLeft(field).dy),
      );
      // The writer is not offered.
      expect(find.byKey(const Key('team-task-mention-option-m1')), findsNothing);
      await tester.tap(find.byKey(const Key('team-task-mention-option-m2')));
      await tester.pumpAndSettle();
      final controller = tester.widget<TextField>(field).controller!;
      expect(controller.text, 'תבדוק @יוסי כהן ');
      expect(find.byKey(const Key('team-task-mention-suggestions')), findsNothing);
      // The picked name is coloured in the field before sending (msg 5298).
      final shown = controller.buildTextSpan(
          context: tester.element(field), withComposing: false);
      final coloured = shown.children!.cast<TextSpan>().firstWhere((s) => s.text == '@יוסי כהן');
      expect(coloured.style?.color, mentionColor);
      await tester.tap(find.byKey(const Key('team-task-update-send')));
      await tester.pumpAndSettle();
      expect(harness.repository.calls, ['log:a:תבדוק @יוסי כהן:@m2']);
    });

    testWidgets('each tag is its own item, titled by its update; "סמן כבוצע" asks first',
        (tester) async {
      final tagged = buildTeamTask(id: 'a', title: 'להזמין אולם', assigneeIds: ['m1'])
          .copyWith(owners: [dana], updates: [
        TaskUpdateEntry(
            id: 'u2', text: '@יוסי כהן תאסוף קשר', at: DateTime(2026, 11, 16), byId: 'm1'),
        TaskUpdateEntry(
            id: 'u1', text: '@יוסי כהן תזמין מזרנים', at: DateTime(2026, 11, 15), byId: 'm1'),
      ], mentions: [
        TeamTaskMention(memberId: 'm2', updateId: 'u1', byId: 'm1', at: DateTime(2026, 11, 15)),
        TeamTaskMention(memberId: 'm2', updateId: 'u2', byId: 'm1', at: DateTime(2026, 11, 16)),
      ]);
      final harness = await pumpTeamTasks(tester, user: yossi, board: board([tagged]));
      expect(find.byKey(const Key('team-task-row-a-u1')), findsOneWidget);
      expect(find.byKey(const Key('team-task-row-a-u2')), findsOneWidget);
      expect(find.text('תזמין מזרנים'), findsOneWidget);
      expect(find.text('תאסוף קשר'), findsOneWidget);
      // The task's title, smaller, under each.
      expect(find.byKey(const Key('team-task-mention-parent-a-u1')), findsOneWidget);
      expect(find.byKey(const Key('team-task-mention-parent-a-u2')), findsOneWidget);
      // No status menu for them.
      expect(find.byKey(const Key('team-task-status-tap-a')), findsNothing);
      await tester.tap(find.byKey(const Key('team-task-mention-box-a-u1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-task-mention-done-dialog')), findsOneWidget);
      // "ביטול" leaves it as it was.
      await tester.tap(find.byKey(const Key('team-task-mention-done-cancel')));
      await tester.pumpAndSettle();
      expect(harness.repository.calls, isEmpty);
      await tester.tap(find.byKey(const Key('team-task-mention-box-a-u1')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('team-task-mention-done-dialog')),
          matching: find.text('תזמין מזרנים'),
        ),
        findsOneWidget,
      );
      await tester.enterText(find.byKey(const Key('team-task-mention-done-text')), 'שלחתי');
      await tester.tap(find.byKey(const Key('team-task-mention-done-confirm')));
      await tester.pumpAndSettle();
      expect(harness.repository.calls, ['mentionDone:a:u1:שלחתי']);
    });

    testWidgets('a done tag leaves its item; the other one stays', (tester) async {
      final tagged = buildTeamTask(id: 'a', title: 'להזמין אולם', assigneeIds: ['m1'])
          .copyWith(owners: [dana], updates: [
        TaskUpdateEntry(id: 'u2', text: '@יוסי כהן קשר', at: DateTime(2026, 11, 16), byId: 'm1'),
        TaskUpdateEntry(id: 'u1', text: '@יוסי כהן מזרנים', at: DateTime(2026, 11, 15), byId: 'm1'),
      ], mentions: [
        TeamTaskMention(
            memberId: 'm2',
            updateId: 'u1',
            byId: 'm1',
            at: DateTime(2026, 11, 15),
            doneAt: DateTime(2026, 11, 16)),
        TeamTaskMention(memberId: 'm2', updateId: 'u2', byId: 'm1', at: DateTime(2026, 11, 16)),
      ]);
      await pumpTeamTasks(tester, user: yossi, board: board([tagged]));
      expect(find.byKey(const Key('team-task-row-a-u1')), findsNothing);
      expect(find.byKey(const Key('team-task-row-a-u2')), findsOneWidget);
    });

    testWidgets('the log draws a bracket from a done line to its tag', (tester) async {
      final logged = buildTeamTask(id: 'a', title: 'להזמין אולם', assigneeIds: ['m1'])
          .copyWith(owners: [dana], updates: [
        TaskUpdateEntry(
            id: 'd1', text: 'done', at: DateTime(2026, 11, 4), byId: 'm2', mentionDoneOf: 'u1'),
        TaskUpdateEntry(id: 'p', text: 'אחר', at: DateTime(2026, 11, 3), byId: 'm1'),
        TaskUpdateEntry(id: 'u1', text: '@יוסי כהן', at: DateTime(2026, 11, 2), byId: 'm1'),
      ]);
      await pumpTeamTasks(tester, user: dana, board: board([logged]));
      await tester.tap(find.byKey(const Key('team-task-quick-update-a')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        expect(find.byKey(Key('team-task-log-links-$i')), findsOneWidget);
      }
      // Right of the lines (the log is right to left).
      expect(
        tester.getCenter(find.byKey(const Key('team-task-log-links-0'))).dx,
        greaterThan(tester.getCenter(find.byKey(const Key('team-task-log-d1'))).dx),
      );
    });

    testWidgets('a tagged name in the log is coloured', (tester) async {
      final logged = buildTeamTask(id: 'a', title: 'להזמין אולם', assigneeIds: ['m1'])
          .copyWith(owners: [dana], updates: [
        TaskUpdateEntry(
          id: 'u1',
          text: '@יוסי כהן תבדוק',
          at: DateTime(2026, 11, 3),
          byId: 'm1',
          byName: 'דנה',
          mentionIds: const ['m2'],
        ),
      ]);
      await pumpTeamTasks(tester, user: dana, board: board([logged]));
      await tester.tap(find.byKey(const Key('team-task-quick-update-a')));
      await tester.pumpAndSettle();
      final text = tester.widget<Text>(find.byKey(const Key('team-task-log-text-u1')));
      final spans = (text.textSpan! as TextSpan).children!.cast<TextSpan>();
      expect(spans.first.text, '@יוסי כהן');
      expect(spans.first.style?.color, mentionColor);
    });
  });
}
