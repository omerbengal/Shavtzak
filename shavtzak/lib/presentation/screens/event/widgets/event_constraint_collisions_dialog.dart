import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/constraint_status.dart';
import '../../../../core/debug/logger.dart';
import '../../../../core/utils/event_constraint_collisions.dart';
import '../../../../domain/entities/event.dart';
import '../../../../domain/entities/team_member.dart';
import '../../../bloc/team/team_bloc.dart';
import '../../../bloc/team/team_event.dart' as team;
import '../../../bloc/team/team_state.dart';

/// Read-only list of the permanent members' constraints (approved, pending
/// and rejected) that collide with one event.
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
              if (members == null) {
                return const Center(child: CircularProgressIndicator());
              }

              final collisions = findEventConstraintCollisions(
                event: widget.event,
                members: members,
              );
              if (collisions.isEmpty) {
                return const Center(
                  child: Text('אין מגבלות של אנשי צוות קבועים שמתנגשות עם האירוע'),
                );
              }

              return ListView.builder(
                itemCount: collisions.length,
                itemBuilder: (context, index) =>
                    _buildCollisionCard(collisions[index]),
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
