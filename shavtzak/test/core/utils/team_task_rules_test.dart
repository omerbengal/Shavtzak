import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/team_task_rules.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/stage.dart';
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
    final task = buildTeamTask(assigneeIds: ['m2']);
    expect(isTeamTaskOwner(task, 'm2'), isTrue);
    expect(isTeamTaskOwner(task, 'm1'), isFalse);
  });

  test('myTeamTaskRows: the tasks the viewer owns', () {
    final tasks = [
      buildTeamTask(id: 'a', assigneeIds: ['m1']),
      buildTeamTask(id: 'b', assigneeIds: ['m2']),
    ];
    expect(myTeamTaskRows(tasks, 'm1').map((t) => t.id), ['a']);
  });

  group('groupTeamTasks (16/11/2026)', () {
    final hanukkah = buildCategory();
    final shows = buildCategory(id: 'c2', name: 'אירועי בית');
    final wives = buildTopic();
    // now = 15.11: e1 is ongoing, e2 upcoming, e3 and e4 over.
    final candles = buildEvent(
        id: 'e1', name: 'הדלקת נרות', categoryId: 'c1',
        startDate: DateTime(2026, 11, 14), endDate: DateTime(2026, 11, 16));
    final party = buildEvent(
        id: 'e2', name: 'מסיבה', categoryId: 'c1', startDate: DateTime(2026, 12, 20));
    final older = buildEvent(
        id: 'e3', name: 'ישן', categoryId: 'c1', startDate: DateTime(2026, 10, 1));
    final recent = buildEvent(
        id: 'e4', name: 'אחרון שעבר', categoryId: 'c1', startDate: DateTime(2026, 11, 10));
    final concert = buildEvent(
        id: 'e5', name: 'הופעה', categoryId: 'c2', startDate: DateTime(2026, 11, 25));
    final loose = buildEvent(
        id: 'e6', name: 'בלי קטגוריה', categoryId: null, startDate: DateTime(2026, 11, 22));
    TeamTask onEvent(String id, Event event, {String? deadline}) => buildTeamTask(
        id: id, title: id, deadline: deadline,
        link: TaskLink(TaskLinkType.event, event.id), event: event, events: [event]);

    test('a card per category by name; on top its own tasks; then its events, nearest first',
        () {
      final tasks = [
        onEvent('party', party),
        onEvent('older', older),
        onEvent('candles', candles),
        onEvent('recent', recent),
        buildTeamTask(id: 'cat', title: 'cat',
            link: const TaskLink(TaskLinkType.category, 'c1'), category: hanukkah),
        onEvent('concert', concert),
        buildTeamTask(id: 'topic', title: 'topic')
            .copyWith(link: () => const TaskLink(TaskLinkType.topic, 'p1'), topic: () => wives),
        buildTeamTask(id: 'none', title: 'none'),
        onEvent('loose', loose),
      ];
      final groups = groupTeamTasks(tasks, now, categories: [hanukkah, shows]);
      expect(groups.map((g) => g.label),
          ['אירועי בית', 'אירועי חנוכה', 'בלי קטגוריה', 'נשות מגדים', 'ללא שיוך']);
      final card = groups[1];
      expect(card.type, TaskLinkType.category);
      expect(card.link, const TaskLink(TaskLinkType.category, 'c1'));
      expect(card.tasks.map((t) => t.id), ['cat']);
      // Ongoing first, then upcoming; then the past, the latest first.
      expect(card.sections.map((s) => s.eventId), ['e1', 'e2', 'e4', 'e3']);
      expect(card.sections.first.tasks.map((t) => t.id), ['candles']);
      expect(card.allTasks.length, 5);
      expect(groups[2].type, TaskLinkType.event);
      expect(groups[2].event, loose);
      expect(groups.last.type, isNull);
    });

    test('a task of several events sits on top of each of their categories', () {
      final both = buildTeamTask(
        id: 'both',
        link: const TaskLink(TaskLinkType.event, 'e1'),
        eventIds: const ['e1', 'e2', 'e5'],
        event: candles,
        events: [candles, party, concert],
      );
      final groups = groupTeamTasks([both], now, categories: [hanukkah, shows]);
      expect(groups.map((g) => g.label), ['אירועי בית', 'אירועי חנוכה']);
      for (final group in groups) {
        expect(group.tasks, isEmpty);
        expect(group.severalEventTasks.map((t) => t.id), ['both']);
        expect(group.sections, isEmpty);
        expect(group.allTasks.map((t) => t.id), ['both']);
      }
    });

    test('a category card: its own tasks and its tasks of several events are two lists', () {
      final several = buildTeamTask(
        id: 'several',
        title: 'א',
        link: const TaskLink(TaskLinkType.event, 'e1'),
        eventIds: const ['e1', 'e2'],
        event: candles,
        events: [candles, party],
      );
      final own = buildTeamTask(id: 'own', title: 'ב',
          link: const TaskLink(TaskLinkType.category, 'c1'), category: hanukkah);
      final card = groupTeamTasks([several, own, onEvent('candles', candles)], now,
              categories: [hanukkah])
          .single;
      expect(card.tasks.map((t) => t.id), ['own']);
      expect(card.severalEventTasks.map((t) => t.id), ['several']);
      expect(card.sections.single.tasks.map((t) => t.id), ['candles']);
      expect(card.allTasks.map((t) => t.id), ['own', 'several', 'candles']);
    });

    test('inside every list: urgency first (גבוהה, רגילה, נמוכה), then the old order', () {
      TeamTask t(String id, TeamTaskUrgency urgency,
              {String? deadline, TeamTaskStatus status = TeamTaskStatus.open, TaskLink? link,
              List<String> eventIds = const [], List<Event> events = const []}) =>
          buildTeamTask(
              id: id, title: id, urgency: urgency, deadline: deadline, status: status,
              link: link, eventIds: eventIds, event: events.firstOrNull, events: events,
              category: link?.type == TaskLinkType.category ? hanukkah : null);
      const low = TeamTaskUrgency.low;
      const normal = TeamTaskUrgency.normal;
      const high = TeamTaskUrgency.high;
      // A list with no link: the deadline still orders a level, done stays last.
      final plain = groupTeamTasks([
        t('low-soon', low, deadline: '2026-11-16'),
        t('normal-late', normal, deadline: '2026-11-30'),
        t('high-none', high),
        t('normal-soon', normal, deadline: '2026-11-17'),
        t('high-soon', high, deadline: '2026-11-18'),
        t('high-done', high, status: TeamTaskStatus.done),
      ], now).single;
      expect(plain.tasks.map((x) => x.id),
          ['high-soon', 'high-none', 'normal-soon', 'normal-late', 'low-soon', 'high-done']);

      // A category's two lists and an event's section, each on its own.
      const catLink = TaskLink(TaskLinkType.category, 'c1');
      const e1 = TaskLink(TaskLinkType.event, 'e1');
      final card = groupTeamTasks([
        t('cat-low', low, link: catLink),
        t('cat-high', high, link: catLink),
        t('sev-normal', normal, link: e1, eventIds: ['e1', 'e2'], events: [candles, party]),
        t('sev-high', high, link: e1, eventIds: ['e1', 'e2'], events: [candles, party]),
        t('ev-low', low, link: e1, events: [candles]),
        t('ev-normal', normal, link: e1, events: [candles]),
        t('ev-high', high, link: e1, events: [candles]),
      ], now, categories: [hanukkah]).single;
      expect(card.tasks.map((x) => x.id), ['cat-high', 'cat-low']);
      expect(card.severalEventTasks.map((x) => x.id), ['sev-high', 'sev-normal']);
      expect(card.sections.single.tasks.map((x) => x.id), ['ev-high', 'ev-normal', 'ev-low']);
    });

    test('a task of several events with no category shows on each event card', () {
      final other = buildEvent(id: 'e7', name: 'עוד אחד', categoryId: null,
          startDate: DateTime(2026, 11, 28));
      final both = buildTeamTask(
        id: 'both',
        link: const TaskLink(TaskLinkType.event, 'e6'),
        eventIds: const ['e6', 'e7'],
        event: loose,
        events: [loose, other],
      );
      final groups = groupTeamTasks([both], now, categories: [hanukkah]);
      expect(groups.map((g) => g.label), ['בלי קטגוריה', 'עוד אחד']);
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
        buildTeamTask().copyWith(link: () => const TaskLink(TaskLinkType.event, 'gone')),
        buildTeamTask(id: 't2').copyWith(link: () => const TaskLink(TaskLinkType.topic, 'gone')),
      ], now);
      expect(groups.map((g) => g.label).toList(), ['אירוע שנמחק', 'נושא שנמחק']);
    });

    test('an archived category keeps its name as the group', () {
      final groups = groupTeamTasks([
        buildTeamTask().copyWith(
          link: () => const TaskLink(TaskLinkType.category, 'c1'),
          category: () => buildCategory(isArchived: true),
        ),
      ], now);
      expect(groups.single.label, 'אירועי חנוכה');
    });
  });

  test('compareEventsByNearest: ongoing and upcoming by start, then the past by end', () {
    final past = buildEvent(id: 'p', startDate: DateTime(2026, 11, 1));
    final ongoing = buildEvent(
        id: 'o', startDate: DateTime(2026, 11, 14), endDate: DateTime(2026, 11, 15));
    final next = buildEvent(id: 'n', startDate: DateTime(2026, 11, 16));
    final events = [past, next, ongoing]..sort((a, b) => compareEventsByNearest(a, b, now));
    expect(events.map((e) => e.id), ['o', 'n', 'p']);
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

    test('urgency filter; none ticked = every urgency', () {
      final tasks = [
        buildTeamTask(id: 'low', urgency: TeamTaskUrgency.low),
        buildTeamTask(id: 'normal'),
        buildTeamTask(id: 'high', urgency: TeamTaskUrgency.high),
      ];
      final high = TeamTaskFilter.initial.copyWith(urgencies: {TeamTaskUrgency.high});
      expect(applyTeamTaskFilter(tasks, high, const {}).map((t) => t.id), ['high']);
      expect(high.anyFilterSet, isTrue);
      expect(applyTeamTaskFilter(tasks, TeamTaskFilter.initial, const {}).length, 3);
    });

    test('a task of several events matches each of its events and their categories', () {
      final task = buildTeamTask(
        id: 'both',
        link: const TaskLink(TaskLinkType.event, 'e1'),
        eventIds: const ['e1', 'e2'],
      );
      TeamTaskFilter by(TaskLink link) => TeamTaskFilter.initial.copyWith(link: () => link);
      const categories = {'e1': 'c1', 'e2': 'c2'};
      expect(applyTeamTaskFilter([task], by(const TaskLink(TaskLinkType.event, 'e2')), categories),
          hasLength(1));
      expect(
          applyTeamTaskFilter([task], by(const TaskLink(TaskLinkType.category, 'c2')), categories),
          hasLength(1));
      expect(applyTeamTaskFilter([task], by(const TaskLink(TaskLinkType.event, 'e3')), categories),
          isEmpty);
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

  group('showTeamTasksTab', () {
    test('tab hidden for a member with no tasks', () {
      expect(showTeamTasksTab(buildMember(), const []), isFalse);
    });

    test('tab shown for an owner and for canManageTasks', () {
      expect(showTeamTasksTab(buildMember(), [buildTeamTask()]), isTrue);
      expect(showTeamTasksTab(buildMember(canManageTasks: true), const []), isTrue);
      expect(showTeamTasksTab(buildMember(isAdmin: true), const []), isTrue);
    });

    test('only cancelled or duplicate tasks do not show the tab', () {
      expect(
        showTeamTasksTab(buildMember(), [
          buildTeamTask(status: TeamTaskStatus.cancelled),
          buildTeamTask(id: 't2', status: TeamTaskStatus.duplicate),
        ]),
        isFalse,
      );
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
    test('the search matches a title or a description', () {
      final tasks = [
        buildTeamTask(id: 'p', title: 'הכנת שטח'),
        buildTeamTask(id: 'o', title: 'הזמנת אוטובוסים'),
      ];
      final byTitle =
          applyTeamTaskFilter(tasks, TeamTaskFilter.initial.copyWith(query: ' אוטובוס '), const {});
      expect(byTitle.map((t) => t.id), ['o']);
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
    test('"באיחור" keeps the late tasks', () {
      final tasks = [
        buildTeamTask(id: 'late', deadline: '2026-11-14'),
        buildTeamTask(id: 'today', deadline: '2026-11-15'),
        buildTeamTask(id: 'doneLate', deadline: '2026-11-01', status: TeamTaskStatus.done),
        buildTeamTask(id: 'none'),
      ];
      final filter = TeamTaskFilter.initial.copyWith(lateOnly: true);
      expect(filter.anyFilterSet, isTrue);
      expect(filter.statusesChanged, isFalse);
      final shown = applyTeamTaskFilter(tasks, filter, const {}, now: now);
      expect(shown.map((t) => t.id), ['late']);
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

  group('the search (Omer, msg 4500)', () {
    final omer = buildMember(id: 'o1', name: 'עומר בנגל');
    final hanukkah = buildEvent(id: 'e9', name: 'הדלקת נרות', categoryId: 'c7');
    final base = buildTeamTask(id: 'x', title: 'הזמנת אולם', assigneeIds: ['o1']);
    List<String> search(List<TeamTask> tasks, String query) => applyTeamTaskFilter(
          tasks,
          TeamTaskFilter.initial.copyWith(query: query),
          const {'e9': 'c7'},
          categoryNameById: const {'c7': 'אירועי חנוכה'},
        ).map((t) => t.id).toList();

    test('the last name of an owner finds their tasks ("בנגל" for "עומר בנגל")', () {
      final mine = base.copyWith(owners: [omer]);
      final other = buildTeamTask(id: 'y', title: 'משהו אחר');
      expect(search([mine, other], 'בנגל'), ['x']);
      expect(search([mine, other], 'עומר בנגל'), ['x']);
    });

    test('what the task belongs to: its event, the category of the event, a topic', () {
      final byEvent = base.copyWith(
        link: () => const TaskLink(TaskLinkType.event, 'e9'),
        event: () => hanukkah,
        events: [hanukkah],
      );
      expect(search([byEvent], 'נרות'), ['x']);
      expect(search([byEvent], 'חנוכה'), ['x']);
      final byTopic = base.copyWith(
          link: () => const TaskLink(TaskLinkType.topic, 'p1'), topic: () => buildTopic());
      expect(search([byTopic], 'מגדים'), ['x']);
    });

    test('the update log (text and writer) and the contacts', () {
      final logged = base.copyWith(updates: [
        TaskUpdateEntry(
            id: 'u', text: 'דיברתי עם הספק', at: DateTime.utc(2026, 11, 1), byId: 'm2', byName: 'יוסי כהן'),
      ]);
      expect(search([logged], 'הספק'), ['x']);
      expect(search([logged], 'כהן'), ['x']);
      final contact = base.copyWith(contacts: const [
        StageContact(id: 'k', name: 'רינה לוי', phone: '050-1234567', role: 'מנהלת אולם'),
      ]);
      expect(search([contact], 'רינה'), ['x']);
      expect(search([contact], '1234567'), ['x']);
      expect(search([contact], 'מנהלת'), ['x']);
    });

    test('ignores case, Hebrew points and quotes', () {
      final task = base.copyWith(description: 'Bus לצה"ל');
      expect(search([task], 'bus'), ['x']);
      expect(search([task], 'צהל'), ['x']);
      expect(search([base], 'אוּלָם'), ['x']);
      expect(search([base], 'לא קיים'), isEmpty);
    });

    test('stays quick on many tasks', () {
      final many = [
        for (var i = 0; i < 2000; i++)
          base.copyWith(owners: [omer], description: 'תיאור ארוך ' * 20),
      ];
      final watch = Stopwatch()..start();
      search(many, 'בנגל');
      expect(watch.elapsedMilliseconds, lessThan(500));
    });
  });
}
