import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/presentation/screens/team_task/widgets/team_task_style.dart';

import '../../../support/team_task_fixtures.dart';

/// Omer, msg 4516: the creation date reads exactly "נוצרה DD/MM, HH:mm",
/// zero-padded, 24 hours, on Israel's clock.
void main() {
  String label(DateTime createdAt) => teamTaskCreatedLabel(buildTeamTask(createdAt: createdAt));

  test('winter (UTC+2), zero-padded', () {
    expect(label(DateTime.utc(2026, 11, 7, 7, 5)), 'נוצרה 07/11, 09:05');
  });

  test('summer (UTC+3), across midnight into the next day', () {
    expect(label(DateTime.utc(2026, 6, 30, 21, 30)), 'נוצרה 01/07, 00:30');
  });

  test('the afternoon in 24 hours', () {
    expect(label(DateTime.utc(2026, 12, 25, 15, 45)), 'נוצרה 25/12, 17:45');
  });
}
