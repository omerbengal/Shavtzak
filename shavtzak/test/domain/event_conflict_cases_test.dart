// The shared conflict-check case table, run unchanged by this test and by
// functions/src/event_conflict_cases.test.ts. Both sides must reach the same
// answers, so the app and the backend can't drift apart again. The table is
// the contract: never edit it to make one side pass.
//
// `flutter test` runs from shavtzak/, so the repo root is one level up.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/constraint_status.dart';
import 'package:shavtzak/core/utils/event_stretch.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/team_member.dart';

const _casesPath = '../shared/test-fixtures/event_conflict_cases.json';

final _metadataDate = DateTime(2026, 1, 1);

/// A `yyyy-MM-dd` Israel calendar day as the app holds it: local midnight.
DateTime _day(String key) {
  final parts = key.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

DateTime? _optionalDay(Object? key) => key == null ? null : _day(key as String);

Event _event(Map<String, dynamic> row) {
  return Event(
    id: 'evt',
    name: 'evt',
    startDate: _day(row['startDate'] as String),
    endDate: _day(row['endDate'] as String),
    assemblyTime: row['assemblyTime'] as String,
    startTime: row['startTime'] as String,
    endTime: row['endTime'] as String,
    teamEndTime: row['teamEndTime'] as String,
    requiresArmed: false,
    roleRequirements: const {},
    createdAt: _metadataDate,
    updatedAt: _metadataDate,
  );
}

DateConstraint _constraint(int index, Map<String, dynamic> row) {
  final repeatType = row['repeatType'] as String?;
  return DateConstraint(
    id: 'c$index',
    startDate: _day(row['startDate'] as String),
    endDate: _optionalDay(row['endDate']),
    status: ConstraintStatus.values.byName(row['status'] as String),
    constraintType:
        ConstraintType.values.byName(row['constraintType'] as String),
    startTime: row['startTime'] as String?,
    endTime: row['endTime'] as String?,
    repeatType:
        repeatType == null ? null : RepeatType.values.byName(repeatType),
    repeatDay: row['repeatDay'] as int?,
    repeatEndDate: _optionalDay(row['repeatEndDate']),
  );
}

TeamMember _member(Map<String, dynamic> row) {
  final constraints = (row['constraints'] as List).cast<Map<String, dynamic>>();
  return TeamMember(
    id: 'member',
    name: 'member',
    isActive: row['isActive'] as bool,
    isPermanent: row['isPermanent'] as bool,
    isArchived: row['isArchived'] as bool,
    constraints: [
      for (var i = 0; i < constraints.length; i++)
        _constraint(i, constraints[i]),
    ],
    roleCapabilities: const {},
    createdAt: _metadataDate,
    updatedAt: _metadataDate,
    uniqueKey: 'member',
    availableEventIds:
        (row['availableEventIds'] as List).cast<String>().toList(),
  );
}

void main() {
  final table =
      jsonDecode(File(_casesPath).readAsStringSync()) as Map<String, dynamic>;
  final cases = (table['cases'] as List).cast<Map<String, dynamic>>();

  test('case table holds at least 60 cases', () {
    expect(cases.length, greaterThanOrEqualTo(60));
    expect(cases.map((row) => row['id']).toSet().length, cases.length,
        reason: 'case ids must be unique');
  });

  for (final row in cases) {
    final id = row['id'] as String;
    test('case $id: ${row['label']}', () {
      final event = _event(row['event'] as Map<String, dynamic>);
      final member = _member(row['member'] as Map<String, dynamic>);

      final expectedStretch = row['expectedStretch'] as Map<String, dynamic>?;
      if (expectedStretch != null) {
        final stretch = eventStretch(event);
        expect(
          {
            'start': formatWallMoment(stretch.start),
            'end': formatWallMoment(stretch.end),
          },
          expectedStretch,
          reason: '$id: stretch',
        );
      }

      // Bad or missing data must fall back, never throw.
      expect(member.isAvailableForEventWithTime(event),
          row['expectedAvailable'] as bool,
          reason: id);
    });
  }
}
