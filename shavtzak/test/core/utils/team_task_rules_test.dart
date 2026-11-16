import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/team_task_rules.dart';
import 'package:shavtzak/domain/entities/team_task.dart';

import '../../support/task_fixtures.dart';
import '../../support/team_task_fixtures.dart';

void main() {
  // Sunday 15 November 2026, 10:00 in Israel (08:00 UTC).
  final now = DateTime.utc(2026, 11, 15, 8);

  group('isTeamTaskLate', () {
    test('a deadline before today is late while open or in progress', () {
      expect(isTeamTaskLate(buildTeamTask(deadline: '2026-11-14'), now), isTrue);
      expect(
        isTeamTaskLate(
            buildTeamTask(deadline: '2026-11-14', status: TeamTaskStatus.inProgress), now),
        isTrue,
      );
    });

    test('late is false on the deadline day itself', () {
      expect(isTeamTaskLate(buildTeamTask(deadline: '2026-11-15'), now), isFalse);
    });

    test('late uses the Israel date, not UTC', () {
      // 23:30 UTC on the 14th is already the 15th in Israel.
      final lateNight = DateTime.utc(2026, 11, 14, 23, 30);
      expect(isTeamTaskLate(buildTeamTask(deadline: '2026-11-14'), lateNight), isTrue);
    });

    test('late is false for done/cancelled', () {
      for (final status in [
        TeamTaskStatus.done,
        TeamTaskStatus.cancelled,
        TeamTaskStatus.duplicate,
      ]) {
        expect(isTeamTaskLate(buildTeamTask(deadline: '2026-11-01', status: status), now), isFalse);
      }
      expect(isTeamTaskLate(buildTeamTask(), now), isFalse);
    });
  });

  test('canManageTeamTasks: admins and "ניהול משימות"', () {
    expect(canManageTeamTasks(buildMember(isAdmin: true)), isTrue);
    expect(canManageTeamTasks(buildMember(canManageTasks: true)), isTrue);
    expect(canManageTeamTasks(buildMember()), isFalse);
  });

  test('isTeamTaskOwner reads ownerIds', () {
    final task = buildTeamTask(subtasks: const [
      TeamSubtask(id: 's1', title: 'x', assigneeIds: ['m2']),
    ]);
    expect(isTeamTaskOwner(task, 'm2'), isTrue);
    expect(isTeamTaskOwner(task, 'm1'), isFalse);
  });

  group('teamTaskParentStatus (Omer, round 4)', () {
    TeamSubtask sub(TeamTaskStatus status) =>
        TeamSubtask(id: status.name, title: status.name, status: status);
    const open = TeamTaskStatus.open;
    const inProgress = TeamTaskStatus.inProgress;
    const done = TeamTaskStatus.done;
    const cancelled = TeamTaskStatus.cancelled;
    const duplicate = TeamTaskStatus.duplicate;

    test('his three rules, cancelled and duplicate not counted', () {
      expect(teamTaskParentStatus([sub(open), sub(open), sub(cancelled)]), open);
      expect(teamTaskParentStatus([sub(done), sub(duplicate)]), done);
      expect(teamTaskParentStatus([sub(open), sub(inProgress), sub(done)]), inProgress);
    });

    test('open and done mixed = in progress; nothing left = cancelled', () {
      expect(teamTaskParentStatus([sub(open), sub(done)]), inProgress);
      expect(teamTaskParentStatus([sub(cancelled), sub(duplicate)]), cancelled);
    });

    test('withParentStatus overrides a stored parent status; a plain task keeps its own', () {
      final parent = buildTeamTask(
        status: done,
        subtasks: [TeamSubtask(id: 's1', title: 'x', status: open)],
      );
      expect(withParentStatus(parent).status, open);
      final plain = buildTeamTask(status: done);
      expect(withParentStatus(plain).status, done);
    });

    test('withSubtaskStatus moves the parent with the subtask', () {
      final parent = buildTeamTask(subtasks: const [
        TeamSubtask(id: 's1', title: 'a'),
        TeamSubtask(id: 's2', title: 'b'),
      ]);
      final moved = withSubtaskStatus(parent, 's1', inProgress);
      expect(moved.status, inProgress);
      final allDone = withSubtaskStatus(withSubtaskStatus(parent, 's1', done), 's2', done);
      expect(allDone.status, done);
    });
  });

  group('groupTeamTasks', () {
    final hanukkah = buildCategory();
    final wives = buildTopic();
    final event = buildEvent(id: 'e1', name: 'הדלקת נרות');

    test('groups by link, ordered by their nearest open deadline, none last', () {
      final tasks = [
        buildTeamTask(id: 'a', title: 'א', deadline: '2026-12-10')
            .copyWith(link: () => TaskLink(TaskLinkType.category, 'c1'), category: () => hanukkah),
        buildTeamTask(id: 'b', title: 'ב', deadline: '2026-11-20')
            .copyWith(link: () => TaskLink(TaskLinkType.topic, 'p1'), topic: () => wives),
        buildTeamTask(id: 'c', title: 'ג'),
        buildTeamTask(id: 'd', title: 'ד', deadline: '2026-11-30')
            .copyWith(link: () => TaskLink(TaskLinkType.event, 'e1'), event: () => event),
        buildTeamTask(id: 'e', title: 'ה')
            .copyWith(link: () => TaskLink(TaskLinkType.topic, 'p1'), topic: () => wives),
      ];
      final groups = groupTeamTasks(tasks, now);
      expect(groups.map((g) => g.label), ['נשות מגדים', 'הדלקת נרות', 'אירועי חנוכה', 'ללא שיוך']);
      expect(groups.first.tasks.map((t) => t.id), ['b', 'e']);
      expect(groups.first.type, TaskLinkType.topic);
      expect(groups.last.type, isNull);
    });

    test('inside a group: deadline ascending, none last, done at the bottom, then title', () {
      TeamTask t(String id, String title, {String? deadline, TeamTaskStatus? status}) =>
          buildTeamTask(
              id: id, title: title, deadline: deadline, status: status ?? TeamTaskStatus.open);
      final groups = groupTeamTasks([
        t('1', 'ב'),
        t('2', 'א'),
        t('3', 'ג', deadline: '2026-11-20'),
        t('4', 'ד', deadline: '2026-11-01', status: TeamTaskStatus.done),
        t('5', 'ה', deadline: '2026-11-18'),
      ], now);
      expect(groups.single.tasks.map((x) => x.id), ['5', '3', '2', '1', '4']);
    });

    test('a task of a deleted event lands in the "אירוע שנמחק" group', () {
      final groups = groupTeamTasks([
        buildTeamTask().copyWith(link: () => TaskLink(TaskLinkType.event, 'gone')),
        buildTeamTask(id: 't2').copyWith(link: () => TaskLink(TaskLinkType.topic, 'gone')),
      ], now);
      expect(groups.map((g) => g.label).toSet(), {'אירוע שנמחק', 'נושא שנמחק'});
    });

    test('an archived category keeps its name as the group', () {
      final groups = groupTeamTasks([
        buildTeamTask().copyWith(
          link: () => TaskLink(TaskLinkType.category, 'c1'),
          category: () => buildCategory(isArchived: true),
        ),
      ], now);
      expect(groups.single.label, 'אירועי חנוכה');
    });
  });

  group('TeamTaskFilter', () {
    test('initial shows only open and in progress (round 8)', () {
      final tasks = [
        for (final status in TeamTaskStatus.values) buildTeamTask(id: status.key, status: status),
      ];
      final shown = applyTeamTaskFilter(tasks, TeamTaskFilter.initial, const {});
      expect(shown.map((t) => t.status), [TeamTaskStatus.open, TeamTaskStatus.inProgress]);
    });

    test('owner filter', () {
      final tasks = [
        buildTeamTask(id: 'a', assigneeIds: ['m1']),
        buildTeamTask(id: 'b', assigneeIds: ['m2']),
      ];
      final shown =
          applyTeamTaskFilter(tasks, TeamTaskFilter.initial.copyWith(ownerIds: {'m2'}), const {});
      expect(shown.map((t) => t.id), ['b']);
    });

    test('a category link also matches tasks linked to events of that category', () {
      final tasks = [
        buildTeamTask(id: 'cat').copyWith(link: () => TaskLink(TaskLinkType.category, 'c1')),
        buildTeamTask(id: 'ev').copyWith(link: () => TaskLink(TaskLinkType.event, 'e1')),
        buildTeamTask(id: 'other').copyWith(link: () => TaskLink(TaskLinkType.event, 'e2')),
        buildTeamTask(id: 'none'),
      ];
      final filter =
          TeamTaskFilter.initial.copyWith(link: () => TaskLink(TaskLinkType.category, 'c1'));
      final shown = applyTeamTaskFilter(tasks, filter, const {'e1': 'c1', 'e2': 'c2'});
      expect(shown.map((t) => t.id), ['cat', 'ev']);
    });

    test('an event or topic link matches only itself', () {
      final tasks = [
        buildTeamTask(id: 'ev').copyWith(link: () => TaskLink(TaskLinkType.event, 'e1')),
        buildTeamTask(id: 'top').copyWith(link: () => TaskLink(TaskLinkType.topic, 'p1')),
      ];
      final shown = applyTeamTaskFilter(
        tasks,
        TeamTaskFilter.initial.copyWith(link: () => TaskLink(TaskLinkType.topic, 'p1')),
        const {},
      );
      expect(shown.map((t) => t.id), ['top']);
    });
  });

  group('linkableEvents', () {
    test('drops events that ended before today and puts the nearest first', () {
      final ended =
          buildEvent(id: 'old', startDate: DateTime(2026, 11, 10), endDate: DateTime(2026, 11, 14));
      final endsToday = buildEvent(
          id: 'today', startDate: DateTime(2026, 11, 13), endDate: DateTime(2026, 11, 15));
      final later = buildEvent(id: 'later', startDate: DateTime(2026, 12, 20));
      final soon = buildEvent(id: 'soon', startDate: DateTime(2026, 11, 20));
      expect(
        linkableEvents([later, ended, soon, endsToday], now).map((e) => e.id),
        ['today', 'soon', 'later'],
      );
    });
  });

  test('teamTaskOwnerChips marks a permanent owner', () {
    final tal = buildMember(id: 'm4', name: 'טל').copyWith(isPermanent: true);
    final dana = buildMember(id: 'm1', name: 'דנה');
    final task = buildTeamTask(assigneeIds: ['m4', 'm1', 'gone']).copyWith(owners: [tal, dana]);
    expect(teamTaskOwnerChips(task).map((o) => (o.name, o.permanent)), [
      ('טל', true),
      ('דנה', false),
      ('חבר צוות לא ידוע', false),
    ]);
  });

  group('round 3: search and the status chip', () {
    const sub1 = TeamSubtask(id: 's1', title: 'גנרטור ותאורה', assigneeIds: ['m1']);
    const sub2 = TeamSubtask(id: 's2', title: 'שילוט', assigneeIds: ['m2']);
    final parent = buildTeamTask(id: 'p', title: 'הכנת שטח', subtasks: const [sub1, sub2]);
    final other = buildTeamTask(id: 'o', title: 'הזמנת אוטובוסים');

    test('the search matches a title, or a subtask title', () {
      final byTitle = applyTeamTaskFilter(
          [parent, other], TeamTaskFilter.initial.copyWith(query: ' אוטובוס '), const {});
      expect(byTitle.map((t) => t.id), ['o']);
      final bySubtask = applyTeamTaskFilter(
          [parent, other], TeamTaskFilter.initial.copyWith(query: 'שילוט'), const {});
      expect(bySubtask.map((t) => t.id), ['p']);
    });

    test('nested subtasks: only the matching ones, unless the parent matches', () {
      final filter = TeamTaskFilter.initial.copyWith(query: 'שילוט');
      expect(visibleSubtasks(parent, filter).map((s) => s.id), ['s2']);
      final byParent = TeamTaskFilter.initial.copyWith(query: 'הכנת');
      expect(visibleSubtasks(parent, byParent).map((s) => s.id), ['s1', 's2']);
      expect(visibleSubtasks(parent, TeamTaskFilter.initial).length, 2);
    });

    test('an owner filter does not mark the statuses as changed', () {
      final filter = TeamTaskFilter.initial.copyWith(ownerIds: {'m1'});
      expect(filter.isInitial, isFalse);
      expect(filter.statusesChanged, isFalse);
      expect(
        TeamTaskFilter.initial.copyWith(statuses: {TeamTaskStatus.open}).statusesChanged,
        isTrue,
      );
    });
  });

  group('round 7 filters', () {
    test('"באיחור" keeps the late tasks, a parent through a late subtask', () {
      final tasks = [
        buildTeamTask(id: 'late', deadline: '2026-11-14'),
        buildTeamTask(id: 'today', deadline: '2026-11-15'),
        buildTeamTask(id: 'doneLate', deadline: '2026-11-01', status: TeamTaskStatus.done),
        buildTeamTask(id: 'none'),
        buildTeamTask(id: 'parent', subtasks: const [
          TeamSubtask(id: 's1', title: 'בזמן', deadline: '2026-11-20', assigneeIds: ['m1']),
          TeamSubtask(id: 's2', title: 'מאחר', deadline: '2026-11-10', assigneeIds: ['m1']),
        ]),
      ];
      final filter = TeamTaskFilter.initial.copyWith(lateOnly: true);
      expect(filter.anyFilterSet, isTrue);
      expect(filter.statusesChanged, isFalse);
      final shown = applyTeamTaskFilter(tasks, filter, const {}, now: now);
      expect(shown.map((t) => t.id), ['late', 'parent']);
      // Under the parent, only the late subtask.
      expect(visibleSubtasks(tasks.last, filter, now: now).map((s) => s.id), ['s2']);
      expect(visibleSubtasks(tasks.last, TeamTaskFilter.initial, now: now).length, 2);
    });

    test('a done subtask past its deadline does not make its parent late', () {
      final parent = buildTeamTask(id: 'p', subtasks: const [
        TeamSubtask(
          id: 's1',
          title: 'בוצעה',
          deadline: '2026-11-10',
          status: TeamTaskStatus.done,
          assigneeIds: ['m1'],
        ),
        TeamSubtask(id: 's2', title: 'פתוחה', assigneeIds: ['m1']),
      ]);
      expect(isTeamTaskOrSubtaskLate(parent, now), isFalse);
    });

    test('several owners: a task of any of them', () {
      final tasks = [
        buildTeamTask(id: 'a', assigneeIds: ['m1']),
        buildTeamTask(id: 'b', assigneeIds: ['m2']),
        buildTeamTask(id: 'c', assigneeIds: ['m3']),
      ];
      final shown = applyTeamTaskFilter(
          tasks, TeamTaskFilter.initial.copyWith(ownerIds: {'m1', 'm3'}), const {});
      expect(shown.map((t) => t.id), ['a', 'c']);
      expect(TeamTaskFilter.initial.copyWith(ownerIds: {'m1', 'm3'}),
          TeamTaskFilter.initial.copyWith(ownerIds: {'m3', 'm1'}));
    });
  });
}
