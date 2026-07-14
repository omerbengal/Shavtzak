import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/participant_group.dart';

void main() {
  group('Event.participantsSummary', () {
    test('is null when there are no groups', () {
      expect(_eventWith(const []).participantsSummary, isNull);
    });

    test('a lone unlabeled group renders as a bare number', () {
      expect(
        _eventWith(const [ParticipantGroup(count: 500)]).participantsSummary,
        '500',
      );
    });

    test('a lone labeled group renders as "label: count"', () {
      expect(
        _eventWith(const [ParticipantGroup(label: 'בוקר', count: 500)])
            .participantsSummary,
        'בוקר: 500',
      );
    });

    test('two unlabeled groups fall back to נגלה numbering', () {
      expect(
        _eventWith(const [
          ParticipantGroup(count: 500),
          ParticipantGroup(count: 700),
        ]).participantsSummary,
        'נגלה 1: 500, נגלה 2: 700',
      );
    });

    test('numbering is positional, not a count of unlabeled groups', () {
      expect(
        _eventWith(const [
          ParticipantGroup(label: 'בוקר', count: 500),
          ParticipantGroup(count: 700),
        ]).participantsSummary,
        'בוקר: 500, נגלה 2: 700',
      );
    });

    test('all-labeled groups use their labels', () {
      expect(
        _eventWith(const [
          ParticipantGroup(label: 'בוקר', count: 500),
          ParticipantGroup(label: 'ערב', count: 700),
        ]).participantsSummary,
        'בוקר: 500, ערב: 700',
      );
    });

    test('a blank label counts as unset', () {
      expect(
        _eventWith(const [ParticipantGroup(label: '   ', count: 500)])
            .participantsSummary,
        '500',
      );
    });

    test('zero is a legal count', () {
      expect(
        _eventWith(const [ParticipantGroup(count: 0)]).participantsSummary,
        '0',
      );
    });
  });
}

Event _eventWith(List<ParticipantGroup> groups) {
  final now = DateTime(2026, 7, 14);
  return Event(
    id: 'event-1',
    name: 'טקס פתיחה',
    startDate: DateTime(2026, 7, 20),
    endDate: DateTime(2026, 7, 20),
    startTime: '18:00',
    endTime: '22:00',
    assemblyTime: '17:00',
    participantGroups: groups,
    requiresArmed: false,
    roleRequirements: const {},
    createdAt: now,
    updatedAt: now,
  );
}
