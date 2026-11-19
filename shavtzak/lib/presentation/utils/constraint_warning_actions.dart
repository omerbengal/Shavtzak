import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/repositories/assignment_repository.dart';
import '../../data/repositories/event_repository.dart';
import '../../domain/entities/assignment.dart';
import '../../domain/entities/event.dart';
import '../../domain/entities/team_member.dart';
import '../../core/utils/constraint_event_overlap.dart';
import '../bloc/event/event_bloc.dart';
import '../bloc/event/event_state.dart';
import '../widgets/constraint_event_warning_dialog.dart';

Future<List<Event>> loadEventsForConstraintWarnings(
    BuildContext context) async {
  final eventState = context.read<EventBloc>().state;
  if (eventState is EventsLoaded) {
    return eventState.events;
  }

  try {
    return await context.read<EventRepository>().getAllEvents();
  } catch (_) {
    return [];
  }
}

/// The events [assignments] place a member in: every assignment counts.
Set<String> assignedEventIdsOf(List<Assignment> assignments) => {
      for (final assignment in assignments) assignment.eventId,
    };

/// Ids of the events [teamMemberId] is assigned to, for the
/// "משובץ/ת לאירוע!" mark in [ConstraintEventWarningDialog]. A failed read
/// shows no marks rather than blocking the approval.
Future<Set<String>> loadAssignedEventIdsForMember(
    BuildContext context, String teamMemberId) async {
  try {
    final assignments = await context
        .read<AssignmentRepository>()
        .getAssignmentsByPerson(teamMemberId);
    return assignedEventIdsOf(assignments);
  } catch (_) {
    return const {};
  }
}

Future<bool> confirmConstraintOverlapWarning({
  required BuildContext context,
  required DateConstraint constraint,
  required List<Event> events,
  required String title,
  required String message,
  required String confirmText,
  bool showMissingTimeNote = false,
  Set<String> assignedEventIds = const {},
}) async {
  if (!constraint.isUnavailability) {
    return true;
  }

  final overlaps = getConstraintEventOverlaps(
    constraint: constraint,
    events: events,
  );

  if (overlaps.isEmpty) {
    return true;
  }

  return ConstraintEventWarningDialog.show(
    context,
    title: title,
    message: message,
    confirmText: confirmText,
    overlaps: overlaps,
    showMissingTimeNote: showMissingTimeNote,
    assignedEventIds: assignedEventIds,
  );
}
