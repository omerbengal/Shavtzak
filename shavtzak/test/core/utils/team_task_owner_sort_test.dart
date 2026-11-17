import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/team_task_rules.dart';
import 'package:shavtzak/domain/entities/team_task.dart';

import '../../support/task_fixtures.dart';
import '../../support/team_task_fixtures.dart';

/// Omer, msg 4581: "כל המשימות" sorts by urgency first; inside each urgency
/// the tasks with several owners (by title), then each owner's tasks in a row
/// (owners א-ב, then by title), then the tasks with no owner.
void main() {
  final avi = buildMember(id: 'avi', name: 'אבי כהן');
  final bat = buildMember(id: 'bat', name: 'בת-אל לוי');
  final gal = buildMember(id: 'gal', name: 'גל מזרחי');
  final byId = {for (final m in [avi, bat, gal]) m.id: m};

  TeamTask task(String id, String title, List<String> owners,
          {TeamTaskUrgency urgency = TeamTaskUrgency.normal,
          TeamTaskStatus status = TeamTaskStatus.open,
          String? deadline}) =>
      buildTeamTask(
        id: id,
        title: title,
        assigneeIds: owners,
        urgency: urgency,
        status: status,
        deadline: deadline,
      ).copyWith(owners: [for (final o in owners) byId[o]!]);

  List<String> order(List<TeamTask> tasks) =>
      [for (final t in [...tasks]..sort(compareTeamTasksByOwners)) t.id];

  test('the spec: urgent first, several owners, then by owner, then no owner', () {
    final tasks = [
      task('n-gal', 'אולם', ['gal']),
      task('h-bat-2', 'תקציב', ['bat'], urgency: TeamTaskUrgency.high),
      task('h-avi', 'זמרים', ['avi'], urgency: TeamTaskUrgency.high),
      task('h-multi-b', 'תאורה', ['avi', 'gal'], urgency: TeamTaskUrgency.high),
      task('h-bat-1', 'במה', ['bat'], urgency: TeamTaskUrgency.high),
      task('h-multi-a', 'הגברה', ['bat', 'gal'], urgency: TeamTaskUrgency.high),
      task('h-none', 'כיבוד', [], urgency: TeamTaskUrgency.high),
      task('n-multi', 'הסעות', ['avi', 'bat']),
      task('n-avi', 'שלטים', ['avi']),
      task('l-avi', 'ארכיון', ['avi'], urgency: TeamTaskUrgency.low),
    ];
    expect(order(tasks), [
      // גבוהה: several owners by title, then אבי, then בת-אל (by title), then none.
      'h-multi-a', 'h-multi-b', 'h-avi', 'h-bat-1', 'h-bat-2', 'h-none',
      // רגילה
      'n-multi', 'n-avi', 'n-gal',
      // נמוכה
      'l-avi',
    ]);
  });

  test('an owner\'s tasks stay together whatever their deadlines', () {
    final tasks = [
      task('avi-late', 'ב', ['avi'], deadline: '2026-12-30'),
      task('bat-soon', 'א', ['bat'], deadline: '2026-11-18'),
      task('avi-soon', 'א', ['avi'], deadline: '2026-11-18'),
    ];
    expect(order(tasks), ['avi-soon', 'avi-late', 'bat-soon']);
  });

  test('done, cancelled and duplicate still go last', () {
    final tasks = [
      task('done-urgent', 'א', ['avi'], urgency: TeamTaskUrgency.high, status: TeamTaskStatus.done),
      task('open-low', 'ב', ['gal'], urgency: TeamTaskUrgency.low),
    ];
    expect(order(tasks), ['open-low', 'done-urgent']);
  });

  test('Hebrew order: a final letter counts as its plain form', () {
    expect(compareHebrewText('סדרן', 'סדרנים'), lessThan(0));
    expect(compareHebrewText('מטבח', 'כיבוד'), greaterThan(0));
    expect(compareHebrewText('צה"ל', 'צהל'), isNot(0)); // raw tie-break
  });

  test('"כל המשימות" uses it in every list of a card; the default stays', () {
    const topic = TaskLink(TaskLinkType.topic, 'p1');
    final a = buildTeamTask(id: 'a', title: 'א', link: topic, assigneeIds: ['gal'], deadline: '2026-11-18')
        .copyWith(owners: [gal]);
    final b = buildTeamTask(id: 'b', title: 'ב', link: topic, assigneeIds: ['avi'], deadline: '2026-12-30')
        .copyWith(owners: [avi]);
    final now = DateTime.utc(2026, 11, 17, 10);
    final byOwners = groupTeamTasks([a, b], now, compare: compareTeamTasksByOwners);
    expect([for (final t in byOwners.single.tasks) t.id], ['b', 'a']);
    final byDeadline = groupTeamTasks([a, b], now);
    expect([for (final t in byDeadline.single.tasks) t.id], ['a', 'b']);
  });
}
