import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/data/repositories/team_task_repository.dart';
import 'package:shavtzak/domain/entities/team_task.dart';

import '../../../support/task_fixtures.dart';
import '../../../support/team_task_fixtures.dart';
import '../../../support/team_tasks_harness.dart';

/// Omer, msg 4480: "כל המשימות" shows when each task was created (in the
/// row's bottom-left corner and in its details card, under ✕ / 🗑), and the
/// new-task form has an icon on the right of every field.
void main() {
  final manager = buildMember(id: 'mgr', name: 'מנהלת', isAdmin: true);
  const topic = TaskLink(TaskLinkType.topic, 'p1');
  // 07:05 UTC on 7 November = 09:05 in Israel (winter, UTC+2).
  final mine = buildTeamTask(
    id: 'a',
    title: 'להזמין אולם',
    link: topic,
    assigneeIds: ['mgr'],
    createdAt: DateTime.utc(2026, 11, 7, 7, 5),
  ).copyWith(owners: [manager]);

  TeamTaskBoard board() => TeamTaskBoard(
        tasks: [mine],
        members: [manager],
        topics: [buildTopic()],
        categories: [buildCategory()],
      );

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  group('the creation date', () {
    testWidgets('"כל המשימות": on the row, at its bottom-left corner', (tester) async {
      await pumpTeamTasks(tester, user: manager, board: board());
      await tester.pumpAndSettle();
      final created = find.byKey(const Key('team-task-created-a'));
      expect(created, findsOneWidget);
      // "נוצרה DD/MM, HH:mm", Israel time (msg 4516).
      expect(tester.widget<Text>(created).data, 'נוצרה 07/11, 09:05');
      final row = tester.getRect(find.byKey(const Key('team-task-row-a')));
      final date = tester.getRect(created);
      expect(date.left - row.left, lessThan(40));
      expect(row.bottom - date.bottom, lessThan(20));
      // Small and muted.
      expect(tester.widget<Text>(created).style!.fontSize, lessThan(13));
    });

    testWidgets('"כל המשימות": in the details card, under ✕ and 🗑', (tester) async {
      await pumpTeamTasks(tester, user: manager, board: board(), size: teamWideSize);
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const Key('team-task-row-a')));
      final created = find.byKey(const Key('team-task-sheet-created'));
      expect(created, findsOneWidget);
      expect(tester.widget<Text>(created).data, 'נוצרה 07/11, 09:05');
      final close = tester.getRect(find.byKey(const Key('team-task-close')));
      final trash = tester.getRect(find.byKey(const Key('team-task-delete')));
      final date = tester.getRect(created);
      expect(date.top, greaterThanOrEqualTo(close.bottom));
      expect(date.top, greaterThanOrEqualTo(trash.bottom));
      // Left of the description.
      final description = tester.getRect(find.byKey(const Key('team-task-edit-description')));
      expect(date.right, lessThanOrEqualTo(description.left));
    });

    testWidgets('not in "המשימות שלי", neither on the row nor in the card', (tester) async {
      await pumpTeamTasks(tester, user: manager, board: board(), size: teamWideSize);
      await tester.pumpAndSettle();
      await tap(tester, find.text('המשימות שלי'));
      expect(find.byKey(const Key('team-task-created-a')), findsNothing);
      await tap(tester, find.byKey(const Key('team-task-row-a')));
      expect(find.byKey(const Key('team-task-sheet-created')), findsNothing);
    });

    testWidgets('not in Blitz', (tester) async {
      await pumpTeamTasks(tester, user: manager, board: board());
      await tester.pumpAndSettle();
      await tap(tester, find.text('המשימות שלי'));
      await tap(tester, find.byKey(const Key('spotlight-start')));
      expect(find.textContaining('נוצרה'), findsNothing);
    });
  });

  group('the new-task form', () {
    Future<void> openForm(WidgetTester tester) async {
      await pumpTeamTasks(tester, user: manager, board: board());
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const Key('team-task-new')));
    }

    const fields = {
      'new-team-task-link': Icons.label_outline,
      'new-team-task-title': Icons.title,
      'new-team-task-description': Icons.notes,
      'new-team-task-owners': Icons.group_outlined,
      'new-team-task-deadline': Icons.event,
      'new-team-task-urgency': Icons.flag_outlined,
      'new-team-task-contacts-title': Icons.contact_phone_outlined,
    };

    testWidgets('every field has its icon on the right', (tester) async {
      await openForm(tester);
      for (final entry in fields.entries) {
        final field = find.byKey(Key(entry.key));
        final icon = find.descendant(of: field, matching: find.byIcon(entry.value));
        expect(icon, findsOneWidget, reason: entry.key);
        // On the right half of its field (the start, in Hebrew).
        expect(tester.getCenter(icon).dx, greaterThan(tester.getCenter(field).dx),
            reason: entry.key);
      }
    });

    testWidgets('the deadline has no icon left on its left side', (tester) async {
      await openForm(tester);
      final field = find.byKey(const Key('new-team-task-deadline'));
      final icons =
          tester.widgetList<Icon>(find.descendant(of: field, matching: find.byType(Icon)));
      expect(icons.map((i) => i.icon), [Icons.event]);
    });

    testWidgets('a card\'s "+" opens the same form, with the icons', (tester) async {
      await pumpTeamTasks(tester, user: manager, board: board());
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const Key('team-task-group-add-topic:p1')));
      for (final entry in fields.entries) {
        expect(find.descendant(of: find.byKey(Key(entry.key)), matching: find.byIcon(entry.value)),
            findsOneWidget,
            reason: entry.key);
      }
    });
  });
}
