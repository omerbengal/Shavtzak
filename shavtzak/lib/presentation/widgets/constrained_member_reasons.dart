import 'package:flutter/material.dart';

import '../../core/utils/constraint_labels.dart';
import '../../domain/entities/event.dart';
import '../../domain/entities/team_member.dart';

/// Why a member is in the "בעלי מגבלות / לא זמינים" list of [event], one line
/// per reason, under the member's name:
///
/// 1. the other events the member is assigned to on the same days
///    ([sameDayEvents], names), 'משובצ/ת ב: …';
/// 2. each approved unavailability that blocks the event, in red;
/// 3. each pending one, in orange;
/// 4. for a non-permanent member without availability, 'לא ציין/ה זמינות'.
///
/// Used as the `subtitle` of the row's ListTile in both lists (the assignments
/// screen and the summary screen). The leading icon comes from
/// [constrainedMemberIcon] and [constrainedMemberIconColor].
class ConstrainedMemberReasons extends StatelessWidget {
  const ConstrainedMemberReasons({
    super.key,
    required this.member,
    required this.event,
    this.sameDayEvents = const [],
  });

  final TeamMember member;
  final Event event;

  /// Names of the other events the member is assigned to on the same days.
  final List<String> sameDayEvents;

  static const double _fontSize = 12;

  @override
  Widget build(BuildContext context) {
    final lines = <Widget>[];

    void addLine(String text, Color color) {
      lines.add(Text(text, style: TextStyle(color: color, fontSize: _fontSize)));
    }

    if (sameDayEvents.isNotEmpty) {
      addLine('משובצ/ת ב: ${sameDayEvents.join(", ")}', Colors.red.shade600);
    }

    if (member.isPermanent) {
      final blockers = member.constraintsBlockingEvent(event);
      for (final constraint in blockers.where((c) => c.isApproved())) {
        addLine(constraintStatusLabel(constraint), Colors.red.shade600);
      }
      for (final constraint in blockers.where((c) => c.isPending())) {
        addLine(constraintStatusLabel(constraint), Colors.orange.shade800);
      }
    } else if (!member.isAvailableForEventWithTime(event)) {
      addLine('לא ציין/ה זמינות', Colors.red.shade600);
    }

    if (lines.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines,
    );
  }
}

/// True when every constraint that blocks [event] for [member] is still
/// pending, so the row says "waiting" rather than "blocked".
bool _onlyPendingBlocks(TeamMember member, Event event) {
  if (!member.isPermanent) return false;
  final blockers = member.constraintsBlockingEvent(event);
  return blockers.isNotEmpty && blockers.every((c) => c.isPending());
}

/// The leading icon of a row: another event the same days, the hourglass when
/// the member's only blockers are pending, the calendar when any constraint is
/// approved, the clock for a non-permanent member without availability.
IconData constrainedMemberIcon(
  TeamMember member,
  Event event, {
  required bool sameDayAssigned,
}) {
  if (sameDayAssigned) return Icons.event;
  if (_onlyPendingBlocks(member, event)) return Icons.hourglass_top;
  return member.isPermanent ? Icons.event_busy : Icons.schedule;
}

/// The colour of the icon from [constrainedMemberIcon]: orange for the
/// hourglass, today's red for the rest.
Color constrainedMemberIconColor(
  TeamMember member,
  Event event, {
  required bool sameDayAssigned,
}) {
  if (!sameDayAssigned && _onlyPendingBlocks(member, event)) {
    return Colors.orange.shade700;
  }
  return Colors.red.shade400;
}
