import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/constraint_status.dart';
import '../../../../core/debug/logger.dart';
import '../../../../core/utils/event_constraint_collisions.dart';
import '../../../../core/utils/search_utils.dart';
import '../../../../data/repositories/assignment_repository.dart';
import '../../../../domain/entities/assignment.dart';
import '../../../../domain/entities/event.dart';
import '../../../../domain/entities/team_member.dart';
import '../../../bloc/team/team_bloc.dart';
import '../../../bloc/team/team_event.dart' as team;
import '../../../bloc/team/team_state.dart';
import '../../../widgets/name_search_field.dart';

/// How long [readEventAssignmentsOnce] waits for the stream's first emit.
const Duration eventAssignmentsReadTimeout = Duration(seconds: 10);

/// The event's assignments, read once from the live stream: its first emit,
/// which Firestore serves from cache at once and heals from the server. Never
/// an awaited one-shot `getX()`, which can park for ~30 s on a transport
/// hiccup while listeners on the same connection stay fast.
///
/// Returns an empty list when the read fails, ends without an emit or takes
/// longer than [timeout], so the caller falls back to judging every member by
/// the whole event instead of waiting on, or failing with, the read.
Future<List<Assignment>> readEventAssignmentsOnce(
  AssignmentRepository repository,
  String eventId, {
  Duration timeout = eventAssignmentsReadTimeout,
}) async {
  try {
    return await repository
        .watchAssignmentsByEvent(eventId)
        .first
        .timeout(timeout);
  } catch (e) {
    Logger.warning('eventConstraintCollisions:assignmentsUnread', {
      'eventId': eventId,
      'error': e.runtimeType.toString(),
    });
    return const [];
  }
}

/// Read-only list of the permanent members' constraints (approved, pending
/// and rejected) that collide with one event. A member assigned with custom
/// hours is judged against those hours, so a constraint on a day they are not
/// there for is not listed.
class EventConstraintCollisionsDialog extends StatefulWidget {
  final Event event;

  const EventConstraintCollisionsDialog({super.key, required this.event});

  @override
  State<EventConstraintCollisionsDialog> createState() =>
      _EventConstraintCollisionsDialogState();
}

class _EventConstraintCollisionsDialogState
    extends State<EventConstraintCollisionsDialog> {
  List<TeamMember>? _lastLoadedMembers;

  /// The event's assignments, or null until the one read has settled (it
  /// settles as an empty list when it fails or times out).
  List<Assignment>? _eventAssignments;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    final state = context.read<TeamBloc>().state;
    if (state is TeamLoaded) {
      _lastLoadedMembers = state.members;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<TeamBloc>().add(const team.LoadTeamMembers());
      });
    }
    _readEventAssignments(context.read<AssignmentRepository>());
  }

  Future<void> _readEventAssignments(AssignmentRepository repository) async {
    final assignments =
        await readEventAssignmentsOnce(repository, widget.event.id);
    if (!mounted) return;
    setState(() => _eventAssignments = assignments);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        title: Text(
          'מגבלות שמתנגשות - ${widget.event.name}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        content: SizedBox(
          width: 560,
          height: 520,
          child: BlocBuilder<TeamBloc, TeamState>(
            buildWhen: (previous, current) => current is TeamLoaded,
            builder: (context, state) {
              if (state is TeamLoaded) _lastLoadedMembers = state.members;
              final members = _lastLoadedMembers;
              final assignments = _eventAssignments;
              if (members == null || assignments == null) {
                return const Center(child: CircularProgressIndicator());
              }

              final collisions = findEventConstraintCollisions(
                event: widget.event,
                members: members,
                assignments: assignments,
              );
              if (collisions.isEmpty) {
                return const Center(
                  child: Text('אין מגבלות של אנשי צוות קבועים שמתנגשות עם האירוע'),
                );
              }

              final shownCollisions = collisions
                  .where((c) => nameMatchesSearch(c.member.name, _searchQuery))
                  .toList();
              return Column(
                children: [
                  NameSearchField(
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                  Expanded(
                    child: shownCollisions.isEmpty
                        ? const NameSearchNoResults()
                        : ListView.builder(
                            itemCount: shownCollisions.length,
                            itemBuilder: (context, index) =>
                                _buildCollisionCard(shownCollisions[index]),
                          ),
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Logger.action('tap:close:eventConstraintCollisions',
                  {'eventId': widget.event.id});
              Navigator.of(context).pop();
            },
            child: const Text('סגור'),
          ),
        ],
      ),
    );
  }

  Widget _buildCollisionCard(EventConstraintCollision collision) {
    final constraint = collision.constraint;
    final note = (constraint.note ?? '').trim();
    final detailStyle = TextStyle(fontSize: 12, color: Colors.grey[700]);

    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: ListTile(
        leading: Icon(
          _statusIcon(constraint.status),
          color: _statusColor(constraint.status),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                collision.member.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _buildStatusBadge(constraint.status),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(_dateLine(constraint), style: detailStyle),
            if (constraint.startTime != null && constraint.endTime != null)
              Text(
                'שעות: ${constraint.startTime} עד ${constraint.endTime}',
                style: detailStyle,
              ),
            if (note.isNotEmpty) Text('הערה: $note', style: detailStyle),
          ],
        ),
      ),
    );
  }

  IconData _statusIcon(ConstraintStatus status) => switch (status) {
        ConstraintStatus.pending => Icons.hourglass_empty,
        ConstraintStatus.approved => Icons.check_circle,
        ConstraintStatus.rejected => Icons.cancel,
      };

  Color _statusColor(ConstraintStatus status) => switch (status) {
        ConstraintStatus.pending => Colors.orange,
        ConstraintStatus.approved => Colors.green,
        ConstraintStatus.rejected => Colors.red,
      };

  Widget _buildStatusBadge(ConstraintStatus status) {
    final text = switch (status) {
      ConstraintStatus.pending => 'ממתין',
      ConstraintStatus.approved => 'אושר',
      ConstraintStatus.rejected => 'נדחה',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _statusColor(status),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _dateLine(DateConstraint constraint) {
    if (constraint.repeatType != null) {
      final repeat = switch (constraint.repeatType!) {
        RepeatType.daily => 'קבועה יומית',
        RepeatType.weekly => 'קבועה שבועית',
        RepeatType.monthly => 'קבועה חודשית',
      };
      final end = constraint.repeatEndDate;
      return 'מגבלה $repeat: ${_formatDate(constraint.startDate)}'
          ' עד ${end == null ? '?' : _formatDate(end)}';
    }

    final end = constraint.endDate;
    if (end == null || _formatDate(end) == _formatDate(constraint.startDate)) {
      return 'תאריך: ${_formatDate(constraint.startDate)}';
    }
    return 'תאריכים: ${_formatDate(constraint.startDate)} עד ${_formatDate(end)}';
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
