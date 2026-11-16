import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/team_task_spotlight.dart';
import 'package:shavtzak/domain/entities/team_task.dart';

import '../../support/team_task_fixtures.dart';

TaskUpdateEntry entry(String id, DateTime at) =>
    TaskUpdateEntry(id: id, text: 'עדכון $id', at: at, byId: 'm1', byName: 'דנה');

void main() {
  final now = DateTime.utc(2026, 11, 16, 8);

  group('spotlightQueue', () {
    test('only tasks still to be done, the quietest first, no update = quietest', () {
      final fresh =
          buildTeamTask(id: 'fresh', title: 'א', updates: [entry('1', DateTime.utc(2026, 11, 15))]);
      final old = buildTeamTask(id: 'old', title: 'ב', updates: [
        entry('3', DateTime.utc(2026, 11, 2)),
        entry('2', DateTime.utc(2026, 11, 1)),
      ]);
      final never = buildTeamTask(id: 'never', title: 'ג');
      final done = buildTeamTask(id: 'done', status: TeamTaskStatus.done);
      final cancelled = buildTeamTask(id: 'cx', status: TeamTaskStatus.cancelled);
      final busy = buildTeamTask(
          id: 'busy',
          status: TeamTaskStatus.inProgress,
          updates: [entry('4', DateTime.utc(2026, 11, 10))]);
      final queue = spotlightQueue([fresh, done, old, never, cancelled, busy]);
      expect(queue.map((t) => t.id), ['never', 'old', 'busy', 'fresh']);
    });

    test('ignores the deadline: most tasks have none', () {
      final dated = buildTeamTask(
          id: 'dated',
          title: 'א',
          deadline: '2026-11-17',
          updates: [entry('1', DateTime.utc(2026, 11, 15))]);
      final quiet =
          buildTeamTask(id: 'quiet', title: 'ב', updates: [entry('2', DateTime.utc(2026, 11, 3))]);
      expect(spotlightQueue([dated, quiet]).map((t) => t.id), ['quiet', 'dated']);
    });
  });

  test('quiet days and label by Israel day', () {
    expect(teamTaskQuietLabel(buildTeamTask(), now), 'אין עדכון עדיין');
    TeamTask at(DateTime when) => buildTeamTask(updates: [entry('x', when)]);
    // 23:30 UTC on the 15th is already the 16th in Israel.
    expect(teamTaskQuietLabel(at(DateTime.utc(2026, 11, 15, 23, 30)), now), 'עודכנה היום');
    expect(teamTaskQuietLabel(at(DateTime.utc(2026, 11, 15, 9)), now), 'עודכנה אתמול');
    expect(teamTaskQuietDays(at(DateTime.utc(2026, 11, 5, 9)), now), 11);
    expect(teamTaskQuietLabel(at(DateTime.utc(2026, 11, 5, 9)), now), 'שקט 11 ימים');
  });

  test('the tally counts an updated-then-closed task once, as closed', () {
    var tally = const SpotlightTally();
    tally = tally.update('a').close('a').update('b').skip('c').close('d');
    expect(tally.summary, '2 נסגרו · אחת עודכנה · אחת נדחתה');
    expect(tally.touched, {'a', 'b', 'd'});
    expect(tally.reopen('d').summary, 'אחת נסגרה · אחת עודכנה · אחת נדחתה');
    expect(const SpotlightTally().summary, 'לא שינית כלום');
  });
}
