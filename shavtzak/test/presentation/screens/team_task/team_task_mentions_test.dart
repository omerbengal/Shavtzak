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

    test('mentionSpans colours each tagged name', () {
      final span = mentionSpans('היי @יוסי כהן, תודה', ['יוסי כהן']);
      final parts = span.children!.cast<TextSpan>().map((s) => s.text).toList();
      expect(parts, ['היי ', '@יוסי כהן', ', תודה']);
    });

    test('a tagged member: in "המשימות שלי" until done; Blitz skips it', () {
      final open = buildTeamTask(id: 't', assigneeIds: ['m1']).copyWith(mentions: [
        TeamTaskMention(memberId: 'm2', at: DateTime(2026, 11, 15)),
      ]);
      final done = open.copyWith(mentions: [
        TeamTaskMention(memberId: 'm2', at: DateTime(2026, 11, 15), doneAt: DateTime(2026, 11, 16)),
      ]);
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
      // The writer is not offered.
      expect(find.byKey(const Key('team-task-mention-option-m1')), findsNothing);
      await tester.tap(find.byKey(const Key('team-task-mention-option-m2')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, 'תבדוק @יוסי כהן ');
      expect(find.byKey(const Key('team-task-mention-suggestions')), findsNothing);
      await tester.tap(find.byKey(const Key('team-task-update-send')));
      await tester.pumpAndSettle();
      expect(harness.repository.calls, ['log:a:תבדוק @יוסי כהן:@m2']);
    });

    testWidgets('the tagged member sees the @ mark and a box; "סמן כבוצע" asks first',
        (tester) async {
      final tagged = buildTeamTask(id: 'a', title: 'להזמין אולם', assigneeIds: ['m1'])
          .copyWith(owners: [dana], mentions: [
        TeamTaskMention(memberId: 'm2', byId: 'm1', at: DateTime(2026, 11, 15)),
      ]);
      final harness = await pumpTeamTasks(tester, user: yossi, board: board([tagged]));
      expect(find.byKey(const Key('team-task-row-a')), findsOneWidget);
      expect(find.byKey(const Key('team-task-mention-mark-a')), findsOneWidget);
      // No status menu for them.
      expect(find.byKey(const Key('team-task-status-tap-a')), findsNothing);
      await tester.tap(find.byKey(const Key('team-task-mention-box-a')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-task-mention-done-dialog')), findsOneWidget);
      // "ביטול" leaves it as it was.
      await tester.tap(find.byKey(const Key('team-task-mention-done-cancel')));
      await tester.pumpAndSettle();
      expect(harness.repository.calls, isEmpty);
      await tester.tap(find.byKey(const Key('team-task-mention-box-a')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('team-task-mention-done-text')), 'שלחתי');
      await tester.tap(find.byKey(const Key('team-task-mention-done-confirm')));
      await tester.pumpAndSettle();
      expect(harness.repository.calls, ['mentionDone:a:שלחתי']);
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
