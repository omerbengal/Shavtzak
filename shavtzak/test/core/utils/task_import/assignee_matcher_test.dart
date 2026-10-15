import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/task_import/assignee_matcher.dart';
import 'package:shavtzak/domain/entities/team_member.dart';

import '../../../support/task_fixtures.dart';

void main() {
  final omer = buildMember(id: 'm1', name: 'עומר אליהו');
  final matan = buildMember(id: 'm2', name: 'מתן סלפטי');
  final boazCohen = buildMember(id: 'm3', name: 'בועז כהן');
  final boazLevi = buildMember(id: 'm4', name: 'בועז לוי');
  final boazi = buildMember(id: 'm5', name: 'בועזי דוד');
  final charlie = buildMember(id: 'm6', name: "צ'רלי ברק");
  final all = [omer, matan, boazCohen, boazLevi, boazi, charlie];

  TeamMember? found(AssigneeMatch match) =>
      match is AssigneeFound ? match.member : null;

  test('a full name matches, ignoring spaces and invisible marks', () {
    expect(found(matchAssignee('עומר אליהו', all)), omer);
    expect(found(matchAssignee('  עומר   אליהו\u2069 ', all)), omer);
  });

  test('a unique part of a name matches on whole words', () {
    expect(found(matchAssignee('סלפטי', all)), matan);
    expect(found(matchAssignee('בועז לוי', all)), boazLevi);
  });

  test('a part shared by several members is ambiguous, and names them', () {
    final match = matchAssignee('בועז', [boazCohen, boazLevi, boazi]);
    expect(match, isA<AssigneeAmbiguous>());
    expect((match as AssigneeAmbiguous).members, [boazCohen, boazLevi]);
  });

  test('a word is not matched inside a longer word', () {
    expect(found(matchAssignee('בועז', [boazi])), isNull);
  });

  test('a geresh or quote does not stop a match', () {
    expect(found(matchAssignee('צרלי', all)), charlie);
    expect(found(matchAssignee("צ'רלי ברק", all)), charlie);
  });

  test('a name of nobody assigned is not found', () {
    expect(matchAssignee('יצחק דני', all), isA<AssigneeNotFound>());
    expect(matchAssignee('', all), isA<AssigneeNotFound>());
  });

  test('an exact full name wins over partial matches', () {
    final dan = buildMember(id: 'd1', name: 'דן');
    final danCohen = buildMember(id: 'd2', name: 'דן כהן');
    expect(found(matchAssignee('דן', [dan, danCohen])), dan);
  });
}
