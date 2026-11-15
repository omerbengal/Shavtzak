import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/presentation/screens/team_task/widgets/team_task_style.dart';

void main() {
  test('initials: first letter of the first name and of the last name', () {
    expect(memberInitials('עומר בנגל'), 'עב');
    expect(memberInitials('עומר אליהו'), 'עא');
    expect(memberInitials('  דנה  '), 'ד');
    expect(memberInitials('אבי בן דוד'), 'אד');
    expect(memberInitials(''), '?');
  });
}
