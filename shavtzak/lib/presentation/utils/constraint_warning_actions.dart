import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/repositories/event_repository.dart';
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

Future<bool> confirmConstraintOverlapWarning({
  required BuildContext context,
  required DateConstraint constraint,
  required List<Event> events,
  required String title,
  required String message,
  required String confirmText,
  bool showMissingTimeNote = false,
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
  );
}
