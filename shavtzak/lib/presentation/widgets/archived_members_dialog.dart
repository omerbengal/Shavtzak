import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/team_member.dart';
import '../bloc/team/team_bloc.dart';
import '../bloc/team/team_event.dart';
import '../bloc/team/team_state.dart';

/// Dialog showing list of archived team members with restore option
class ArchivedMembersDialog extends StatelessWidget {
  const ArchivedMembersDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: BlocBuilder<TeamBloc, TeamState>(
        builder: (context, state) {
          final archivedMembers = state is TeamLoaded ? state.archivedMembers : <TeamMember>[];

          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  Icons.inventory_2,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 8),
                const Text('חברי צוות מאורכבים'),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: archivedMembers.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: archivedMembers.length,
                      itemBuilder: (context, index) {
                        final member = archivedMembers[index];
                        return _buildArchivedMemberTile(context, member);
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('סגור'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'אין חברי צוות מאורכבים',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'חברי צוות שיועברו לארכיון יופיעו כאן',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildArchivedMemberTile(BuildContext context, TeamMember member) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.grey[300],
          child: Text(
            member.name.isNotEmpty ? member.name[0] : '?',
            style: TextStyle(color: Colors.grey[700]),
          ),
        ),
        title: Text(member.name),
        subtitle: Text(
          member.isPermanent ? 'חבר/ת צוות קבוע/ה' : 'חבר/ת צוות לא קבוע/ה',
          style: TextStyle(color: Colors.grey[600]),
        ),
        trailing: ElevatedButton.icon(
          onPressed: () => _restoreMember(context, member),
          icon: const Icon(Icons.restore, size: 18),
          label: const Text('שחזור'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      ),
    );
  }

  void _restoreMember(BuildContext context, TeamMember member) {
    // Show confirmation dialog
    showDialog(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('שחזור חבר צוות'),
          content: Text('האם לשחזר את ${member.name} מהארכיון?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('ביטול'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                // Update member to not be archived
                final updatedMember = member.copyWith(
                  isArchived: false,
                  isActive: true, // Also set active when restoring
                  updatedAt: DateTime.now(),
                );
                context.read<TeamBloc>().add(UpdateTeamMember(updatedMember));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Directionality(
                      textDirection: TextDirection.rtl,
                      child: Text('${member.name} שוחזר/ה בהצלחה'),
                    ),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('שחזור'),
            ),
          ],
        ),
      ),
    );
  }

  /// Show the archived members dialog
  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const ArchivedMembersDialog(),
    );
  }
}
