import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/theme/app_theme.dart';
import 'package:shavtzak/data/repositories/team_task_repository.dart';
import 'package:shavtzak/domain/entities/team_task.dart';
import 'package:shavtzak/presentation/screens/task/task_style.dart';
import 'package:shavtzak/presentation/screens/team_task/team_tasks_screen.dart';
import 'package:shavtzak/presentation/screens/team_task/widgets/team_task_spotlight.dart';

import '../../../support/task_fixtures.dart';
import '../../../support/team_task_fixtures.dart';
import '../../../support/team_tasks_harness.dart';

void main() {
  final dana = buildMember(id: 'm1', name: 'דנה');
  final yossi = buildMember(id: 'm2', name: 'יוסי');
  final manager = buildMember(id: 'mgr', name: 'מנהלת', isAdmin: true);

  TeamTaskBoard board(List<TeamTask> tasks) => TeamTaskBoard(
        tasks: tasks,
        members: [dana, yossi, manager],
        topics: [buildTopic()],
        categories: [buildCategory()],
      );

  final mine =
      buildTeamTask(id: 'a', title: 'להזמין אולם', assigneeIds: ['m1']).copyWith(owners: [dana]);

  testWidgets('owner sees no FAB and no all-tasks tab', (tester) async {
    await pumpTeamTasks(tester, user: dana, board: board([mine]));
    expect(find.byKey(const Key('team-task-new')), findsNothing);
    expect(find.text('כל המשימות'), findsNothing);
    expect(find.byKey(const Key('team-task-row-a')), findsOneWidget);
  });

  testWidgets('once settled, "בליץ" is drawn unseen under the list for a moment, once a session',
      (tester) async {
    resetTeamTasksBlitzWarmup();
    await pumpTeamTasks(tester, user: dana, board: board([mine]));
    expect(find.byType(TeamTaskSpotlight), findsNothing);
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump();
    final warm = find.byType(TeamTaskSpotlight);
    expect(warm, findsOneWidget);
    // Under the screen (painted first), untouchable and out of the semantics.
    expect(find.ancestor(of: warm, matching: find.byType(IgnorePointer)), findsWidgets);
    expect(find.ancestor(of: warm, matching: find.byType(ExcludeSemantics)), findsWidgets);
    expect(tester.getTopLeft(find.byKey(const Key('team-task-row-a'))), isNotNull);
    await tester.tap(find.byKey(const Key('team-task-row-a')), warnIfMissed: true);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.byType(TeamTaskSpotlight), findsNothing);

    // Once a session: the screen opened again does not warm it again.
    await pumpTeamTasks(tester, user: dana, board: board([mine]));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(TeamTaskSpotlight), findsNothing);
  });

  testWidgets('manager sees both', (tester) async {
    final theirs =
        buildTeamTask(id: 'b', title: 'של יוסי', assigneeIds: ['m2']).copyWith(owners: [yossi]);
    await pumpTeamTasks(tester, user: manager, board: board([mine, theirs]));
    expect(find.byKey(const Key('team-task-new')), findsOneWidget);
    expect(find.text('כל המשימות'), findsOneWidget);
    // A manager opens on every task.
    expect(find.byKey(const Key('team-task-row-a')), findsOneWidget);
    expect(find.byKey(const Key('team-task-row-b')), findsOneWidget);
    await tester.tap(find.text('המשימות שלי'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('team-task-row-a')), findsNothing);
  });

  testWidgets('switching to "המשימות שלי" shows its rows at once, with no animation',
      (tester) async {
    final theirs =
        buildTeamTask(id: 'b', title: 'של יוסי', assigneeIds: ['m2']).copyWith(owners: [yossi]);
    final own =
        buildTeamTask(id: 'c', title: 'שלי', assigneeIds: ['mgr']).copyWith(owners: [manager]);
    // One link card: three rows in "כל המשימות", one in "המשימות שלי".
    await pumpTeamTasks(tester, user: manager, board: board([mine, theirs, own]));
    await tester.tap(find.text('המשימות שלי'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byKey(const Key('team-task-row-c')), findsOneWidget);
    final cards = find.byType(AnimatedSize);
    final early = [for (final e in cards.evaluate()) e.size!.height];
    await tester.pumpAndSettle();
    final settled = [for (final e in cards.evaluate()) e.size!.height];
    expect(early, settled);
  });

  testWidgets('tabs as in דו יומי: "המשימות שלי" on the right, the chosen one readable',
      (tester) async {
    await pumpTeamTasks(tester, user: manager, board: board([mine]));
    final mineTab = tester.getCenter(find.byKey(const Key('team-tab-mine')));
    final allTab = tester.getCenter(find.byKey(const Key('team-tab-all')));
    expect(mineTab.dx, greaterThan(allTab.dx));
    // The same segmented switch as the דו יומי event screen, white on dark blue.
    final tabs = tester.widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>));
    final selected = {WidgetState.selected};
    expect(tabs.style?.foregroundColor?.resolve(selected), Colors.white);
    expect(tabs.style?.backgroundColor?.resolve(selected), AppTheme.primaryDark);
    expect(find.byType(TabBar), findsNothing);
  });

  testWidgets('late deadline is red', (tester) async {
    final late =
        buildTeamTask(id: 'l', title: 'באיחור', deadline: '2026-11-10').copyWith(owners: [dana]);
    final fine =
        buildTeamTask(id: 'f', title: 'בזמן', deadline: '2026-11-20').copyWith(owners: [dana]);
    await pumpTeamTasks(tester, user: dana, board: board([late, fine]));
    Text deadline(String id) => tester.widget<Text>(find.byKey(Key('team-task-deadline-$id')));
    expect(deadline('l').style?.color, TaskStyle.late);
    expect(deadline('f').style?.color, isNot(TaskStyle.late));
    expect(deadline('l').data, contains('10.11'));
  });

  testWidgets('new task saves with a topic link', (tester) async {
    final harness = await pumpTeamTasks(tester, user: manager, board: board(const []));
    await tester.tap(find.byKey(const Key('team-task-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new-team-task-title')), 'לסגור להקה');
    await tester.tap(find.byKey(const Key('new-team-task-link')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('נושא'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('task-link-option-p1')));
    await tester.pumpAndSettle();
    expect(find.text('נשות מגדים'), findsOneWidget);
    await tester.tap(find.byKey(const Key('new-team-task-save')));
    await tester.pumpAndSettle();
    final saved = harness.repository.inserted.single;
    expect(saved.title, 'לסגור להקה');
    expect(saved.link, const TaskLink(TaskLinkType.topic, 'p1'));
    expect(saved.status, TeamTaskStatus.open);
  });

  testWidgets('the link picker reads well: dark segments, roomy lines, the current one not blue',
      (tester) async {
    await pumpTeamTasks(tester, user: manager, board: board(const []));
    await tester.tap(find.byKey(const Key('team-task-new')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-team-task-link')));
    await tester.pumpAndSettle();
    final segments =
        tester.widget<SegmentedButton<TaskLinkType>>(find.byType(SegmentedButton<TaskLinkType>));
    expect(segments.style?.foregroundColor?.resolve({WidgetState.selected}), Colors.white);
    expect(segments.style?.backgroundColor?.resolve({WidgetState.selected}), AppTheme.primaryDark);
    await tester.tap(find.text('נושא'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('task-link-option-p1')));
    await tester.pumpAndSettle();
    // Open again: the chosen topic is marked in words, in the normal colour.
    await tester.tap(find.byKey(const Key('new-team-task-link')));
    await tester.pumpAndSettle();
    final option = find.byKey(const Key('task-link-option-p1'));
    expect(find.descendant(of: option, matching: find.text('השיוך הנוכחי')), findsOneWidget);
    final name =
        tester.widget<Text>(find.descendant(of: option, matching: find.text('נשות מגדים')));
    expect(name.style?.fontSize, 16);
    expect(name.style?.color, isNull);
    expect(find.descendant(of: option, matching: find.byType(ListTile)), findsNothing);
  });

  testWidgets('a new task needs a title', (tester) async {
    final harness = await pumpTeamTasks(tester, user: manager, board: board(const []));
    await tester.tap(find.byKey(const Key('team-task-new')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-team-task-save')));
    await tester.pumpAndSettle();
    expect(find.text('חובה להזין כותרת'), findsOneWidget);
    expect(harness.repository.inserted, isEmpty);
  });

  testWidgets('a new task is filled in full before it exists: contacts and urgency, no subtasks',
      (tester) async {
    final harness = await pumpTeamTasks(tester,
        user: manager, board: board(const []), size: const Size(1200, 1000));
    await tester.tap(find.byKey(const Key('team-task-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new-team-task-title')), 'להזמין אולם');
    expect(find.byKey(const Key('new-team-task-add-subtask')), findsNothing);

    await tester.tap(find.byKey(const Key('new-team-task-add-contact')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('edit-contact-name-0')), 'רונית');
    await tester.enterText(find.byKey(const Key('edit-contact-phone-0')), '0501234567');

    // Urgency: "רגילה" unless picked (16/11/2026).
    await tester.ensureVisible(find.byKey(const Key('team-task-urgency-high')));
    await tester.tap(find.byKey(const Key('team-task-urgency-high')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('new-team-task-save')));
    await tester.pumpAndSettle();
    final saved = harness.repository.inserted.single;
    expect(saved.title, 'להזמין אולם');
    expect(saved.contacts.single.name, 'רונית');
    expect(saved.urgency, TeamTaskUrgency.high);
  });

  testWidgets('a new task linked to several events keeps them all, the nearest first',
      (tester) async {
    final first = buildEvent(id: 'e1', name: 'ראשון', startDate: DateTime(2099, 1, 10));
    final second = buildEvent(id: 'e2', name: 'שני', startDate: DateTime(2099, 1, 20));
    final harness = await pumpTeamTasks(tester,
        user: manager,
        board: TeamTaskBoard(
          tasks: const [],
          events: [second, first],
          members: [dana, yossi, manager],
        ),
        size: const Size(1200, 1000));
    await tester.tap(find.byKey(const Key('team-task-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new-team-task-title')), 'שילוט');
    await tester.tap(find.byKey(const Key('new-team-task-link')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('task-link-option-e2-mark')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('task-link-option-e1-mark')));
    await tester.pumpAndSettle();
    expect(find.text('שיוך ל-2 אירועים'), findsOneWidget);
    await tester.tap(find.byKey(const Key('task-link-confirm-events')));
    await tester.pumpAndSettle();
    expect(find.text('ראשון, שני'), findsOneWidget);
    await tester.tap(find.byKey(const Key('new-team-task-save')));
    await tester.pumpAndSettle();
    final saved = harness.repository.inserted.single;
    expect(saved.link, const TaskLink(TaskLinkType.event, 'e1'));
    expect(saved.linkedEventIds, ['e1', 'e2']);
  });

  testWidgets('a tap on an event name marks it like its box; only the button saves',
      (tester) async {
    final first = buildEvent(id: 'e1', name: 'ראשון', startDate: DateTime(2099, 1, 10));
    await pumpTeamTasks(tester,
        user: manager,
        board: TeamTaskBoard(tasks: const [], events: [first], members: [dana, manager]),
        size: const Size(1200, 1000));
    await tester.tap(find.byKey(const Key('team-task-new')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-team-task-link')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ראשון'));
    await tester.pumpAndSettle();
    // Still open, the event marked, nothing chosen yet.
    expect(find.byKey(const Key('task-link-search')), findsOneWidget);
    expect(
        tester.widget<Checkbox>(find.byKey(const Key('task-link-option-e1-mark'))).value, isTrue);
    expect(find.text('שיוך לאירוע'), findsOneWidget);
    await tester.tap(find.text('ראשון'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-link-confirm-events')), findsNothing);
    await tester.tap(find.text('ראשון'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('task-link-confirm-events')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-link-search')), findsNothing);
    expect(find.text('ראשון'), findsOneWidget);
  });

  testWidgets('a new task without subtasks picks its owners in the form', (tester) async {
    final harness = await pumpTeamTasks(tester,
        user: manager, board: board(const []), size: const Size(1200, 1000));
    await tester.tap(find.byKey(const Key('team-task-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new-team-task-title')), 'לסגור להקה');
    await tester.tap(find.byKey(const Key('new-team-task-owners')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-assignee-m1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-team-task-save')));
    await tester.pumpAndSettle();
    expect(harness.repository.inserted.single.ownerIds, ['m1']);
  });

  testWidgets('an empty list says so', (tester) async {
    await pumpTeamTasks(tester, user: dana, board: board(const []));
    expect(find.text('אין משימות להצגה'), findsOneWidget);
  });

  group('round 3', () {
    final theirs =
        buildTeamTask(id: 'b', title: 'של יוסי', assigneeIds: ['m2']).copyWith(owners: [yossi]);
    final managersOwn = buildTeamTask(id: 'c', title: 'של המנהלת', assigneeIds: ['mgr'])
        .copyWith(owners: [manager]);

    Future<void> openMine(WidgetTester tester) async {
      await tester.tap(find.text('המשימות שלי'));
      await tester.pumpAndSettle();
    }

    testWidgets('"המשימות שלי" has no owner filter; "כל המשימות" has it', (tester) async {
      await pumpTeamTasks(tester, user: manager, board: board([mine, managersOwn]));
      expect(find.byKey(const Key('team-filter-owner')), findsOneWidget);
      await openMine(tester);
      expect(find.byKey(const Key('team-filter-owner')), findsNothing);
      expect(find.byKey(const Key('team-filter-status')), findsOneWidget);
    });

    testWidgets('an owner filter colours only the owner chip, not the status chip', (tester) async {
      // Wide enough for every chip with the test font (its letters are squares).
      await pumpTeamTasks(tester,
          user: manager, board: board([mine, theirs]), size: const Size(700, 1000));
      await tester.tap(find.byKey(const Key('team-filter-owner')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('יוסי').last);
      await tester.pumpAndSettle();
      Color? fill(String key) {
        final box = tester.widget<Container>(find
            .descendant(
              of: find.byKey(Key(key)),
              matching: find.byType(Container),
            )
            .first);
        return (box.decoration as BoxDecoration?)?.color;
      }

      expect(fill('team-filter-owner'), TaskStyle.currentLight);
      expect(fill('team-filter-status'), Colors.transparent);
    });

    testWidgets('a manager in "המשימות שלי" gets the view of a member', (tester) async {
      await pumpTeamTasks(tester, user: manager, board: board([managersOwn]));
      await openMine(tester);
      expect(find.byKey(const Key('team-task-new')), findsNothing);
      expect(find.byKey(const Key('team-tasks-menu')), findsNothing);
      await tester.tap(find.byKey(const Key('team-task-row-c')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-task-panel')), findsOneWidget);
      expect(find.byKey(const Key('team-task-edit-title')), findsNothing);
      expect(find.byKey(const Key('team-task-delete')), findsNothing);
    });

    testWidgets('a manager in "כל המשימות" gets the editing view', (tester) async {
      await pumpTeamTasks(tester, user: manager, board: board([managersOwn]));
      await tester.tap(find.byKey(const Key('team-task-row-c')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-task-edit-title')), findsOneWidget);
    });

    testWidgets('the search folds the chips into a funnel and filters', (tester) async {
      await pumpTeamTasks(tester, user: manager, board: board([mine, theirs]));
      expect(find.byKey(const Key('team-filter-funnel')), findsNothing);
      await tester.tap(find.byKey(const Key('team-filter-search')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-filter-funnel')), findsOneWidget);
      expect(find.byKey(const Key('team-filter-status')), findsNothing);
      await tester.enterText(find.byKey(const Key('team-filter-search')), 'יוסי');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-task-row-a')), findsNothing);
      expect(find.byKey(const Key('team-task-row-b')), findsOneWidget);

      // The funnel's menu holds the three filters as rows.
      await tester.tap(find.byKey(const Key('team-filter-funnel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-filter-menu-status')), findsOneWidget);
      expect(find.byKey(const Key('team-filter-menu-owner')), findsOneWidget);
      expect(find.byKey(const Key('team-filter-menu-link')), findsOneWidget);
      await tester.tap(find.byKey(const Key('team-filter-menu-status')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('team-filter-menu-status-open')).first);
      await tester.pumpAndSettle();
      // "פתוחה" unticked: both open tasks go.
      expect(find.byKey(const Key('team-task-row-b')), findsNothing);
      final funnel = tester.widget<Icon>(find.descendant(
        of: find.byKey(const Key('team-filter-funnel')),
        matching: find.byType(Icon),
      ));
      expect(funnel.icon, Icons.filter_alt);

      // Clearing the search brings the chips back.
      await tester.tapAt(const Offset(200, 900));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('team-filter-search-clear')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-filter-funnel')), findsNothing);
      expect(find.byKey(const Key('team-filter-status')), findsOneWidget);
    });

    testWidgets('tapping the search keeps the same field while it widens, so the keyboard opens',
        (tester) async {
      // On the web the field's text connection is the browser's hidden input,
      // and iPhone opens the keyboard only for the input focused in the tap.
      // Folding into the wide row must move the field, not rebuild it: a new
      // field would close that input and open another one after the tap.
      await pumpTeamTasks(tester, user: manager, board: board([mine, theirs]));
      final search = find.descendant(
        of: find.byKey(const Key('team-filter-search')),
        matching: find.byType(EditableText),
      );
      final before = tester.state<EditableTextState>(search);
      await tester.tap(find.byKey(const Key('team-filter-search')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-filter-funnel')), findsOneWidget);
      expect(tester.state<EditableTextState>(search), same(before));
      expect(before.mounted, isTrue);
      expect(tester.testTextInput.hasAnyClients, isTrue);
      expect(
        tester.testTextInput.log.where((call) => call.method == 'TextInput.clearClient'),
        isEmpty,
        reason: 'the text connection the tap opened stays open',
      );
    });

    testWidgets('a row shows the status circle and the initials of the owners', (tester) async {
      final omer = buildMember(id: 'o1', name: 'עומר בנגל');
      final task = buildTeamTask(
              id: 'x', title: 'משימה', assigneeIds: ['o1'], status: TeamTaskStatus.inProgress)
          .copyWith(owners: [omer]);
      await pumpTeamTasks(tester, user: omer, board: board([task]));
      expect(find.byKey(const Key('team-status-icon-inProgress')), findsOneWidget);
      expect(find.text('עב'), findsOneWidget);
      // As wide as the initials, not the whole row.
      final avatar = find.ancestor(of: find.text('עב'), matching: find.byType(Container)).first;
      expect(tester.getSize(avatar).width, lessThan(48));
    });
  });

  group('round 4', () {
    final theirs =
        buildTeamTask(id: 'b', title: 'של יוסי', assigneeIds: ['m2']).copyWith(owners: [yossi]);

    testWidgets('"המשימות שלי": the status from its circle, without opening the task',
        (tester) async {
      final harness = await pumpTeamTasks(tester, user: dana, board: board([mine]));
      await tester.tap(find.byKey(const Key('team-task-status-tap-a')));
      await tester.pumpAndSettle();
      // The words centred in the menu (item 9).
      expect(
        tester
            .widget<Row>(find.descendant(
              of: find.byKey(const Key('team-task-status-option-בטיפול')),
              matching: find.byType(Row),
            ))
            .mainAxisAlignment,
        MainAxisAlignment.center,
      );
      await tester.tap(find.byKey(const Key('team-task-status-option-בטיפול')));
      await tester.pumpAndSettle();
      expect(harness.repository.calls, ['status:a:inProgress']);
      expect(find.byKey(const Key('team-task-panel')), findsNothing);
    });

    testWidgets('"המשימות שלי": the quick update card shows every past update and adds one',
        (tester) async {
      final logged = mine.copyWith(updates: [
        TaskUpdateEntry(
            id: 'u2', text: 'חדש', at: DateTime(2026, 11, 3), byId: 'm1', byName: 'דנה'),
        TaskUpdateEntry(
            id: 'u1', text: 'ישן', at: DateTime(2026, 11, 2), byId: 'm1', byName: 'דנה'),
      ]);
      final harness = await pumpTeamTasks(tester, user: dana, board: board([logged]));
      await tester.tap(find.byKey(const Key('team-task-quick-update-a')));
      await tester.pumpAndSettle();
      final card = find.byKey(const Key('team-task-updates-dialog'));
      expect(card, findsOneWidget);
      // The whole log, newest first (round 5).
      expect(tester.getTopLeft(find.byKey(const Key('team-task-log-u2'))).dy,
          lessThan(tester.getTopLeft(find.byKey(const Key('team-task-log-u1'))).dy));
      await tester.enterText(find.byKey(const Key('team-task-update-field')), 'דיברתי עם האולם');
      final gate = harness.repository.gate = Completer<void>();
      await tester.tap(find.byKey(const Key('team-task-update-send')));
      await tester.pump();
      expect(harness.repository.calls, ['log:a:דיברתי עם האולם']);
      expect(find.byKey(const Key('team-task-update-sending')), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      // The card stays open, the new update shows once the stream has it.
      await harness.deliver(
        tester,
        board([
          logged.copyWith(updates: [
            TaskUpdateEntry(
                id: 'u3',
                text: 'דיברתי עם האולם',
                at: DateTime(2026, 11, 15),
                byId: 'm1',
                byName: 'דנה'),
            ...logged.updates,
          ]),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-task-log-u3')), findsOneWidget);
      await tester.tap(find.byKey(const Key('team-task-updates-close')));
      await tester.pumpAndSettle();
      expect(card, findsNothing);
      expect(find.byKey(const Key('team-task-panel')), findsNothing);
    });

    testWidgets('"כל המשימות" rows have no quick buttons', (tester) async {
      await pumpTeamTasks(tester, user: manager, board: board([mine, theirs]));
      expect(find.byKey(const Key('team-task-quick-update-a')), findsNothing);
      expect(find.byKey(const Key('team-task-status-tap-a')), findsNothing);
    });

    testWidgets('the closed search row is centred', (tester) async {
      // Wide enough for every chip with the test font (its letters are squares).
      await pumpTeamTasks(tester, user: dana, board: board([mine]), size: const Size(600, 1000));
      final width = tester.view.physicalSize.width;
      final field = tester.getRect(find.byKey(const Key('team-filter-search')));
      final last = tester.getRect(find.byKey(const Key('team-filter-late')));
      // RTL: the field on the right, "באיחור" last on the left (round 8).
      expect(((width - field.right) - last.left).abs(), lessThan(2));
    });

    testWidgets("the funnel's submenu arrows point right, where the submenus open", (tester) async {
      // A phone, a little wider than 400 for the test font's square letters.
      await pumpTeamTasks(tester,
          user: manager, board: board([mine, theirs]), size: const Size(480, 1000));
      await tester.tap(find.byKey(const Key('team-filter-search')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('team-filter-funnel')));
      await tester.pumpAndSettle();
      final status = tester.getRect(find.byKey(const Key('team-filter-menu-status')));
      await tester.tap(find.byKey(const Key('team-filter-menu-status')));
      await tester.pumpAndSettle();
      final submenu = tester.getRect(find.byKey(const Key('team-filter-menu-status-open')).first);
      expect(submenu.left, greaterThanOrEqualTo(status.right - 1));
      // Still pointing right, and now on the right of the word (round 5).
      final arrow = find.descendant(
        of: find.byKey(const Key('team-filter-menu-status')),
        matching: find.byKey(const Key('team-filter-submenu-arrow')),
      );
      final icon = tester.widget<Icon>(arrow);
      expect(icon.icon, Icons.arrow_right);
      final word = find.descendant(
        of: find.byKey(const Key('team-filter-menu-status')),
        matching: find.byType(Text),
      );
      expect(tester.getCenter(arrow).dx, greaterThan(tester.getRect(word.first).right));
    });

  });

  group('round 6', () {
    final theirs =
        buildTeamTask(id: 'b', title: 'של יוסי', assigneeIds: ['m2']).copyWith(owners: [yossi]);

    testWidgets('the status chip stays open while several statuses are ticked', (tester) async {
      await pumpTeamTasks(tester, user: manager, board: board([mine, theirs]));
      await tester.tap(find.byKey(const Key('team-filter-status')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('team-filter-status-open')).first);
      await tester.pumpAndSettle();
      // Still open: the next status is right there.
      expect(find.byKey(const Key('team-filter-status-done')), findsWidgets);
      expect(find.byKey(const Key('team-task-row-a')), findsNothing);
      await tester.tap(find.byKey(const Key('team-filter-status-open')).first);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-filter-status-done')), findsWidgets);
      expect(find.byKey(const Key('team-task-row-a')), findsOneWidget);
    });
  });

  group('round 7', () {
    final theirs =
        buildTeamTask(id: 'b', title: 'של יוסי', assigneeIds: ['m2']).copyWith(owners: [yossi]);
    final lateOne =
        buildTeamTask(id: 'l', title: 'מאחרת', deadline: '2026-11-10', assigneeIds: ['m1'])
            .copyWith(owners: [dana]);
    const wide = Size(1280, 900);

    testWidgets('"באיחור" shows only the late tasks', (tester) async {
      await pumpTeamTasks(tester, user: manager, board: board([mine, lateOne]), size: wide);
      await tester.tap(find.byKey(const Key('team-filter-late')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-task-row-l')), findsOneWidget);
      expect(find.byKey(const Key('team-task-row-a')), findsNothing);
      await tester.tap(find.byKey(const Key('team-filter-late')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-task-row-a')), findsOneWidget);
    });

    testWidgets('"אחראי/ת" takes several owners and stays open', (tester) async {
      await pumpTeamTasks(tester,
          user: manager, board: board([mine, theirs]), size: const Size(700, 1000));
      expect(find.text('אחראי/ת'), findsOneWidget);
      await tester.tap(find.byKey(const Key('team-filter-owner')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('team-filter-owner-m1')).first);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-task-row-b')), findsNothing);
      // Still open: the next name is right there.
      await tester.tap(find.byKey(const Key('team-filter-owner-m2')).first);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-task-row-a')), findsOneWidget);
      expect(find.byKey(const Key('team-task-row-b')), findsOneWidget);
      expect(find.text('אחראי/ת (2)'), findsOneWidget);
      // The names are centred in the menu.
      final menu = tester.getRect(find.byKey(const Key('team-filter-owner-m1')).first);
      final name = tester.getRect(find.descendant(
        of: find.byKey(const Key('team-filter-owner-m1')).first,
        matching: find.text('דנה'),
      ));
      final box = tester.getRect(find.byKey(const Key('team-filter-owner-m2')).first);
      final other = tester.getRect(find.descendant(
        of: find.byKey(const Key('team-filter-owner-m2')).first,
        matching: find.text('יוסי'),
      ));
      expect((name.center.dx - other.center.dx).abs(), lessThan(1));
      expect(menu.width, box.width);
    });

    testWidgets('a tap on a card header folds it; the app bar button folds and opens all',
        (tester) async {
      await pumpTeamTasks(tester, user: dana, board: board([mine]));
      expect(find.byKey(const Key('team-task-row-a')), findsOneWidget);
      await tester.tap(find.byKey(const Key('team-task-group-none')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-task-row-a')), findsNothing);
      expect(find.byKey(const Key('team-task-group-none')), findsOneWidget);
      // Everything folded: the button now opens all.
      expect(find.byTooltip('פתיחת כל השיוכים'), findsOneWidget);
      await tester.tap(find.byKey(const Key('team-tasks-fold-all')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-task-row-a')), findsOneWidget);
      await tester.tap(find.byKey(const Key('team-tasks-fold-all')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-task-row-a')), findsNothing);
    });

    testWidgets('a search opens a folded card', (tester) async {
      await pumpTeamTasks(tester, user: dana, board: board([mine]));
      await tester.tap(find.byKey(const Key('team-tasks-fold-all')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('team-filter-search')), 'אולם');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-task-row-a')), findsOneWidget);
    });

    for (final user in [manager, dana]) {
      testWidgets('wide: ${user.name} opens a task in a side panel, the list moves right',
          (tester) async {
        await pumpTeamTasks(tester, user: user, board: board([mine]), size: wide);
        final before = tester.getRect(find.byKey(const Key('team-task-row-a')));
        await tester.tap(find.byKey(const Key('team-task-row-a')));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        expect(find.byType(BottomSheet), findsNothing);
        final panel = tester.getRect(find.byKey(const Key('team-task-side-panel')));
        final row = tester.getRect(find.byKey(const Key('team-task-row-a')));
        expect(panel.left, lessThan(20));
        expect(row.left, greaterThanOrEqualTo(panel.right));
        expect(row.right, closeTo(wide.width, 20));
        expect(row.center.dx, greaterThan(before.center.dx));
        await tester.tap(find.byKey(const Key('team-task-close')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('team-task-side-panel')), findsNothing);
        expect(tester.getRect(find.byKey(const Key('team-task-row-a'))), before);
      });
    }

    testWidgets('wide: another task swaps the panel; the tab switch closes it', (tester) async {
      await pumpTeamTasks(tester, user: manager, board: board([mine, theirs]), size: wide);
      await tester.tap(find.byKey(const Key('team-task-row-a')));
      await tester.pumpAndSettle();
      expect(
          find.descendant(
            of: find.byKey(const Key('team-task-side-panel')),
            matching: find.text('להזמין אולם'),
          ),
          findsWidgets);
      await tester.tap(find.byKey(const Key('team-task-row-b')));
      await tester.pumpAndSettle();
      expect(
          find.descendant(
            of: find.byKey(const Key('team-task-side-panel')),
            matching: find.text('של יוסי'),
          ),
          findsWidgets);
      await tester.tap(find.text('המשימות שלי'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-task-side-panel')), findsNothing);
    });

    testWidgets('a phone still opens the task as a sheet', (tester) async {
      await pumpTeamTasks(tester, user: dana, board: board([mine]));
      await tester.tap(find.byKey(const Key('team-task-row-a')));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byKey(const Key('team-task-side-panel')), findsNothing);
    });
  });

  group('round 8', () {
    testWidgets('a done task is hidden until "בוצעה" is ticked', (tester) async {
      final done = buildTeamTask(id: 'd', title: 'גמורה', status: TeamTaskStatus.done)
          .copyWith(owners: [dana]);
      await pumpTeamTasks(tester, user: dana, board: board([mine, done]));
      expect(find.byKey(const Key('team-task-row-d')), findsNothing);
      expect(find.byKey(const Key('team-task-row-a')), findsOneWidget);
      await tester.tap(find.byKey(const Key('team-filter-status')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('team-filter-status-done')).first);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-task-row-d')), findsOneWidget);
    });

    testWidgets('"באיחור" is the leftmost chip and the last row of the funnel', (tester) async {
      await pumpTeamTasks(tester, user: manager, board: board([mine]), size: const Size(700, 1000));
      final late = tester.getRect(find.byKey(const Key('team-filter-late')));
      for (final key in ['team-filter-status', 'team-filter-owner', 'team-filter-link']) {
        expect(late.right, lessThanOrEqualTo(tester.getRect(find.byKey(Key(key))).left));
      }
      await tester.tap(find.byKey(const Key('team-filter-search')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('team-filter-funnel')));
      await tester.pumpAndSettle();
      final lateRow = tester.getRect(find.byKey(const Key('team-filter-menu-late')).first);
      for (final key in [
        'team-filter-menu-status',
        'team-filter-menu-owner',
        'team-filter-menu-link'
      ]) {
        expect(
            lateRow.top, greaterThanOrEqualTo(tester.getRect(find.byKey(Key(key)).first).bottom));
      }
    });
  });

  group('the time chips (19/11/2026)', () {
    const wide = Size(1280, 900);
    final fresh = buildTeamTask(
            id: 'f', title: 'חדשה', assigneeIds: ['m1'], createdAt: DateTime.utc(2026, 11, 15, 7))
        .copyWith(owners: [dana]);

    testWidgets('"יצירה ← היום" keeps the tasks of today; the same pick clears it', (tester) async {
      await pumpTeamTasks(tester, user: manager, board: board([mine, fresh]), size: wide);
      expect(find.text('יצירה'), findsOneWidget);
      expect(find.text('עדכון סטטוס'), findsOneWidget);
      await tester.tap(find.byKey(const Key('team-filter-created')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('team-filter-created-today')).first);
      await tester.pumpAndSettle();
      expect(find.text('יצירה: היום'), findsOneWidget);
      expect(find.byKey(const Key('team-task-row-f')), findsOneWidget);
      expect(find.byKey(const Key('team-task-row-a')), findsNothing);
      await tester.tap(find.byKey(const Key('team-filter-created')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('team-filter-created-today')).first);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-task-row-a')), findsOneWidget);
    });

    testWidgets('"המשימות שלי" has no time chips', (tester) async {
      await pumpTeamTasks(tester, user: dana, board: board([mine]), size: wide);
      expect(find.byKey(const Key('team-filter-created')), findsNothing);
      expect(find.byKey(const Key('team-filter-status-changed')), findsNothing);
    });

    testWidgets('"באיחור" stays the leftmost chip', (tester) async {
      await pumpTeamTasks(tester, user: manager, board: board([mine]), size: wide);
      final late = tester.getRect(find.byKey(const Key('team-filter-late')));
      for (final key in ['team-filter-created', 'team-filter-status-changed']) {
        expect(late.right, lessThanOrEqualTo(tester.getRect(find.byKey(Key(key))).left));
      }
    });
  });

  group('round 9', () {
    testWidgets('the "שיוך" row of the funnel has the arrow, its word lined up with the others',
        (tester) async {
      await pumpTeamTasks(tester, user: manager, board: board([mine]), size: const Size(700, 1000));
      await tester.tap(find.byKey(const Key('team-filter-search')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('team-filter-funnel')));
      await tester.pumpAndSettle();
      final link = find.byKey(const Key('team-filter-menu-link'));
      expect(
        find.descendant(of: link, matching: find.byKey(const Key('team-filter-submenu-arrow'))),
        findsOneWidget,
      );
      double wordRight(String key, String word) => tester
          .getRect(find.descendant(of: find.byKey(Key(key)).first, matching: find.text(word)))
          .right;
      final status = wordRight('team-filter-menu-status', 'סטטוס');
      expect(wordRight('team-filter-menu-link', 'שיוך'), closeTo(status, 1));
      expect(wordRight('team-filter-menu-owner', 'אחראי/ת'), closeTo(status, 1));
      expect(wordRight('team-filter-menu-late', 'באיחור'), closeTo(status, 1));
    });
  });

  group('16/11/2026: categories, several events, urgency', () {
    final hanukkah = buildCategory();
    final candles = buildEvent(
        id: 'e1', name: 'הדלקת נרות', categoryId: 'c1', startDate: DateTime(2099, 12, 1));
    final party = buildEvent(
        id: 'e2', name: 'מסיבה', categoryId: 'c1', startDate: DateTime(2099, 12, 20));
    TeamTaskBoard categoryBoard(List<TeamTask> tasks) => TeamTaskBoard(
          tasks: tasks,
          events: [candles, party],
          categories: [hanukkah],
          members: [dana, yossi, manager],
        );

    testWidgets('a category card: its tasks of several events on top with chips, then its events',
        (tester) async {
      final both = buildTeamTask(
        id: 'both',
        title: 'שילוט לשניהם',
        link: const TaskLink(TaskLinkType.event, 'e1'),
        eventIds: const ['e1', 'e2'],
        event: candles,
        events: [candles, party],
        assigneeIds: ['m1'],
      );
      final one = buildTeamTask(
        id: 'one',
        title: 'נרות',
        link: const TaskLink(TaskLinkType.event, 'e1'),
        event: candles,
        events: [candles],
        assigneeIds: ['m1'],
      );
      await pumpTeamTasks(tester, user: manager, board: categoryBoard([both, one]));
      expect(find.byKey(const Key('team-task-card-category:c1')), findsOneWidget);
      expect(find.byKey(const Key('team-task-events-both')), findsOneWidget);
      expect(find.byKey(const Key('team-task-events-one')), findsNothing);
      final section = find.byKey(const Key('team-task-section-category:c1/event:e1'));
      expect(section, findsOneWidget);
      final bothTop = tester.getTopLeft(find.byKey(const Key('team-task-row-both'))).dy;
      expect(tester.getTopLeft(section).dy, greaterThan(bothTop));
      expect(tester.getTopLeft(find.byKey(const Key('team-task-row-one'))).dy,
          greaterThan(tester.getTopLeft(section).dy));
      // A tap on the event's title folds its tasks.
      await tester.tap(find.byKey(const Key('team-task-section-fold-category:c1/event:e1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-task-row-one')), findsNothing);
    });

    testWidgets('the urgency shows on a row only when not "רגילה", and filters', (tester) async {
      final high = buildTeamTask(id: 'h', title: 'דחוף', urgency: TeamTaskUrgency.high)
          .copyWith(owners: [dana]);
      final normal = buildTeamTask(id: 'n', title: 'רגיל').copyWith(owners: [dana]);
      await pumpTeamTasks(tester, user: manager, board: board([high, normal]));
      expect(find.byKey(const Key('team-task-urgency-h')), findsOneWidget);
      expect(find.byKey(const Key('team-task-urgency-n')), findsNothing);
      expect(find.text('דחיפות גבוהה'), findsOneWidget);
      await tester.tap(find.byKey(const Key('team-filter-urgency')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('team-filter-urgency-high')).first);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-task-row-n')), findsNothing);
      expect(find.byKey(const Key('team-task-row-h')), findsOneWidget);
    });
  });
}
