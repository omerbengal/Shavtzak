import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/team_task_spotlight.dart';
import 'package:shavtzak/domain/entities/team_task.dart';

import '../../support/team_task_fixtures.dart';

TaskUpdateEntry entry(String id, DateTime at) =>
    TaskUpdateEntry(id: id, text: 'עדכון $id', at: at, byId: 'm1', byName: 'דנה');

void main() {
  final now = DateTime.utc(2026, 11, 16, 8);

  group('spotlightQueue', () {
    test('the open tasks in the order given (the list order), not by quietness (Omer, msg 4500)',
        () {
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
      expect(queue.map((t) => t.id), ['fresh', 'old', 'never', 'busy']);
    });

    test('a task shown twice (on two cards) comes once, at its first place', () {
      final a = buildTeamTask(id: 'a');
      final b = buildTeamTask(id: 'b');
      expect(spotlightQueue([a, b, a]).map((t) => t.id), ['a', 'b']);
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
    expect(tally.summary, '2 נסגרו · אחת עודכנה · אחת לפעם אחרת');
    expect(tally.touched, {'a', 'b', 'd'});
    expect(tally.reopen('d').summary, 'אחת נסגרה · אחת עודכנה · אחת לפעם אחרת');
    expect(const SpotlightTally().summary, 'לא שינית כלום');
  });

  group('spotlightWarmupGlyphs', () {
    TaskUpdateEntry said(String id, String text) =>
        TaskUpdateEntry(id: id, text: text, at: DateTime.utc(2026, 11, 1), byId: 'm1');

    test('the given glyphs, then each emoji or symbol of the updates once', () {
      final a = buildTeamTask(id: 'a', updates: [said('1', 'התקדמתי 👍'), said('2', 'נשלח ✅ ו-✅')]);
      final b = buildTeamTask(id: 'b', updates: [said('3', 'רגיל, בלי סימנים (1/2)')]);
      final c = buildTeamTask(id: 'c', updates: [said('4', 'סגור 🔒 ←')]);
      expect(spotlightWarmupGlyphs([a, b, c], base: '👍⏳'), '👍⏳✅🔒←');
    });

    test('keeps an emoji of two code points whole', () {
      final a = buildTeamTask(id: 'a', updates: [said('1', 'אש 🔥 דגל 🇮🇱')]);
      expect(spotlightWarmupGlyphs([a], base: ''), '🔥🇮🇱');
    });

    test('stops at maxGlyphs', () {
      final many = buildTeamTask(id: 'm', updates: [
        for (var i = 0; i < 80; i++) said('$i', String.fromCharCode(0x1F600 + i)),
      ]);
      expect(spotlightWarmupGlyphs([many], base: '', maxGlyphs: 10).runes.length, 10);
    });
  });
}
