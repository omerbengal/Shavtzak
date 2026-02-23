import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/constants/calendar_constants.dart';
import '../../core/constants/constraint_status.dart';
import '../../domain/entities/team_member.dart';
import '../bloc/team/team_bloc.dart';
import '../bloc/team/team_event.dart' as team;
import '../bloc/team/team_state.dart';
import '../utils/constraint_warning_actions.dart';

class ConstraintsExaminingDialog extends StatefulWidget {
  const ConstraintsExaminingDialog({super.key});

  @override
  State<ConstraintsExaminingDialog> createState() =>
      _ConstraintsExaminingDialogState();
}

class _ConstraintsExaminingDialogState
    extends State<ConstraintsExaminingDialog> {
  final Set<String> _pendingConstraintKeys = {};
  final TextEditingController _searchController = TextEditingController();
  List<TeamMember>? _lastLoadedMembers;
  String _searchQuery = '';
  int _expansionResetToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<TeamBloc>().add(const team.LoadTeamMembers());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    if (_searchQuery == value) return;
    setState(() {
      _searchQuery = value;
      _expansionResetToken++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<TeamBloc, TeamState>(
      listenWhen: (previous, current) =>
          current is TeamMemberOperationSuccess || current is TeamError,
      listener: (context, state) {
        if (_pendingConstraintKeys.isNotEmpty) {
          setState(() => _pendingConstraintKeys.clear());
        }

        if (state is TeamMemberOperationSuccess) {
          _showMessage(state.message, Colors.green[700]!);
        } else if (state is TeamError) {
          _showMessage(state.message, Colors.red[700]!);
        }
      },
      child: AlertDialog(
        title: const Text('בחינת מגבלות צוות'),
        content: SizedBox(
          width: 900,
          height: 620,
          child: BlocBuilder<TeamBloc, TeamState>(
            builder: (context, state) {
              if (state is TeamLoading && _lastLoadedMembers == null) {
                return const Center(child: CircularProgressIndicator());
              }

              if (state is TeamLoaded) {
                _lastLoadedMembers = state.members;
              }

              final baseMembers = state is TeamLoaded
                  ? state.members
                  : (_lastLoadedMembers ?? const <TeamMember>[]);

              if (baseMembers.isEmpty) {
                return const Center(
                  child: Text('לא הצלחנו לטעון את חברי הצוות'),
                );
              }

              final allMembers = baseMembers
                  .where((member) => !member.isArchived)
                  .where(_hasDisplayableConstraints)
                  .toList()
                ..sort((a, b) => a.name.compareTo(b.name));

              final filteredMembers = _filterMembersBySearch(allMembers);

              final pendingCount = filteredMembers
                  .expand((member) => _getRelevantConstraints(member))
                  .where((constraint) =>
                      constraint.status == ConstraintStatus.pending)
                  .length;

              final membersWithPending = filteredMembers
                  .where((member) => _getPendingConstraints(member).isNotEmpty)
                  .toList()
                ..sort((a, b) => a.name.compareTo(b.name));

              final membersWithoutPending = filteredMembers
                  .where((member) => _getPendingConstraints(member).isEmpty)
                  .toList()
                ..sort((a, b) => a.name.compareTo(b.name));

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'חיפוש לפי שם חבר צוות או הערת מגבלה...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  _onSearchChanged('');
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onChanged: _onSearchChanged,
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.fact_check, color: Colors.deepOrange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'סה״כ מגבלות ממתינות: $pendingCount',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filteredMembers.isEmpty
                        ? const Center(
                            child: Text('לא נמצאו תוצאות לחיפוש'),
                          )
                        : ListView.builder(
                            itemCount: membersWithPending.length +
                                (membersWithPending.isNotEmpty &&
                                        membersWithoutPending.isNotEmpty
                                    ? 1
                                    : 0) +
                                membersWithoutPending.length,
                            itemBuilder: (context, index) {
                              if (index < membersWithPending.length) {
                                return _buildMemberSection(
                                  membersWithPending[index],
                                  _expansionResetToken,
                                );
                              }

                              if (membersWithPending.isNotEmpty &&
                                  membersWithoutPending.isNotEmpty &&
                                  index == membersWithPending.length) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  child: Divider(
                                    thickness: 2,
                                    color: Colors.grey[700],
                                  ),
                                );
                              }

                              final remainingIndex = index -
                                  membersWithPending.length -
                                  (membersWithPending.isNotEmpty &&
                                          membersWithoutPending.isNotEmpty
                                      ? 1
                                      : 0);
                              return _buildMemberSection(
                                membersWithoutPending[remainingIndex],
                                _expansionResetToken,
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('סגור'),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberSection(TeamMember member, int resetToken) {
    final approvedConstraints = _getApprovedConstraints(member);
    final pendingConstraints = _getPendingConstraints(member);
    final rejectedConstraints = _getRejectedConstraints(member);

    final pendingCount = pendingConstraints.length;

    return Card(
      elevation: 1,
      child: ExpansionTile(
        key: PageStorageKey('member_${member.id}_$resetToken'),
        initiallyExpanded: false,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        title: Row(
          children: [
            const Icon(Icons.person, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                member.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (pendingCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$pendingCount ממתינות',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            member.isPermanent ? 'חבר צוות קבוע' : 'חבר צוות לא-קבוע',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
            ),
          ),
        ),
        children: [
          _buildStatusSectionCard(
            member: member,
            title: 'אושרו',
            constraints: approvedConstraints,
            cardColor: Colors.green[100]!,
            emptyText: 'אין מגבלות מאושרות',
            resetToken: resetToken,
          ),
          _buildStatusSectionCard(
            member: member,
            title: 'מחכות לאישור',
            constraints: pendingConstraints,
            cardColor: Colors.orange[100]!,
            emptyText: 'אין מגבלות שמחכות לאישור',
            resetToken: resetToken,
          ),
          _buildStatusSectionCard(
            member: member,
            title: 'נדחו',
            constraints: rejectedConstraints,
            cardColor: Colors.red[100]!,
            emptyText: 'אין מגבלות שנדחו',
            resetToken: resetToken,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusSectionCard({
    required TeamMember member,
    required String title,
    required List<DateConstraint> constraints,
    required Color cardColor,
    required String emptyText,
    required int resetToken,
  }) {
    return Card(
      color: cardColor,
      margin: const EdgeInsets.only(top: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ExpansionTile(
          key: PageStorageKey(
            'status_${member.id}_${title}_$resetToken',
          ),
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          childrenPadding: EdgeInsets.zero,
          title: Text(
            '$title (${constraints.length})',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),
          children: [
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.surface,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: constraints.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        emptyText,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    )
                  : Column(
                      children: constraints.map((constraint) {
                        return _buildConstraintCard(
                          member: member,
                          constraint: constraint,
                        );
                      }).toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConstraintCard({
    required TeamMember member,
    required DateConstraint constraint,
  }) {
    final constraintKey = _constraintKey(member.id, constraint.id);
    final isUpdating = _pendingConstraintKeys.contains(constraintKey);
    final effectiveStatus = constraint.status;
    final noteTitle = _extractConstraintDisplayNote(constraint);

    return Card(
      color: constraint.isAvailability ? Colors.green[50] : null,
      margin: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              effectiveStatus == ConstraintStatus.pending
                  ? Icons.hourglass_empty
                  : effectiveStatus == ConstraintStatus.approved
                      ? Icons.check_circle
                      : Icons.cancel,
              color: effectiveStatus == ConstraintStatus.pending
                  ? Colors.amber
                  : effectiveStatus == ConstraintStatus.approved
                      ? Colors.green
                      : Colors.red,
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    noteTitle.isEmpty ? 'ללא הערה' : noteTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _buildStatusBadge(effectiveStatus),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (constraint.repeatType != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _buildRecurringTypeText(constraint),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _buildAdminConstraintDateLine(constraint),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (constraint.startTime != null && constraint.endTime != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'שעות: ${constraint.startTime} עד ${constraint.endTime}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (constraint.wasAutoRejectedFromCalendar) ...[
                  const SizedBox(height: 4),
                  const Text(
                    CalendarAutoRejection.message,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.red,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: effectiveStatus == ConstraintStatus.pending
                  ? Colors.amber[50]
                  : effectiveStatus == ConstraintStatus.approved
                      ? Colors.green[50]
                      : Colors.grey[50],
              border: Border(
                top: BorderSide(
                  color: effectiveStatus == ConstraintStatus.pending
                      ? Colors.amber[200]!
                      : effectiveStatus == ConstraintStatus.approved
                          ? Colors.green[200]!
                          : Colors.grey[200]!,
                ),
              ),
            ),
            child: isUpdating
                ? const Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (effectiveStatus == ConstraintStatus.pending)
                        _buildActionButton(
                          icon: Icons.check_circle,
                          label: 'אשר',
                          color: Colors.green,
                          onPressed: () => _onConstraintAction(
                            member: member,
                            constraint: constraint,
                            newStatus: ConstraintStatus.approved,
                          ),
                        )
                      else if (effectiveStatus == ConstraintStatus.approved)
                        _buildActionButton(
                          icon: Icons.hourglass_empty,
                          label: 'החזר לממתין',
                          color: Colors.amber,
                          onPressed: () => _onConstraintAction(
                            member: member,
                            constraint: constraint,
                            newStatus: ConstraintStatus.pending,
                          ),
                        )
                      else
                        _buildActionButton(
                          icon: Icons.hourglass_empty,
                          label: 'החזר לממתין',
                          color: Colors.amber,
                          onPressed: () => _onConstraintAction(
                            member: member,
                            constraint: constraint,
                            newStatus: ConstraintStatus.pending,
                          ),
                        ),
                      const SizedBox(width: 8),
                      if (effectiveStatus == ConstraintStatus.rejected)
                        _buildActionButton(
                          icon: Icons.check_circle,
                          label: 'אשר',
                          color: Colors.green,
                          onPressed: () => _onConstraintAction(
                            member: member,
                            constraint: constraint,
                            newStatus: ConstraintStatus.approved,
                          ),
                        )
                      else
                        _buildActionButton(
                          icon: Icons.cancel,
                          label: 'דחה',
                          color: Colors.red,
                          onPressed: () => _onConstraintAction(
                            member: member,
                            constraint: constraint,
                            newStatus: ConstraintStatus.rejected,
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: color, size: 20),
      label: Text(
        label,
        style: TextStyle(color: color),
      ),
      style: TextButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.08),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
    );
  }

  Future<void> _onConstraintAction({
    required TeamMember member,
    required DateConstraint constraint,
    required ConstraintStatus newStatus,
  }) async {
    if (newStatus == constraint.status) return;

    final constraintKey = _constraintKey(member.id, constraint.id);
    if (_pendingConstraintKeys.contains(constraintKey)) return;

    if (newStatus == ConstraintStatus.approved) {
      final events = await loadEventsForConstraintWarnings(context);
      if (!mounted) return;

      final shouldProceed = await confirmConstraintOverlapWarning(
        context: context,
        constraint: constraint.copyWith(status: ConstraintStatus.approved),
        events: events,
        title: 'אזהרה לפני אישור מגבלה',
        message: 'שים לב: במועדים הללו קיימים אירועים:',
        confirmText: 'אשר בכל זאת',
        showMissingTimeNote: true,
      );

      if (!shouldProceed || !mounted) {
        return;
      }
    }

    setState(() => _pendingConstraintKeys.add(constraintKey));

    final shouldResetAutoRejected = newStatus == ConstraintStatus.approved ||
        newStatus == ConstraintStatus.pending;

    context.read<TeamBloc>().add(
          team.EditConstraintRequest(
            teamMemberId: member.id,
            constraintId: constraint.id,
            startDate: constraint.startDate,
            endDate: constraint.endDate,
            note: constraint.note,
            status: newStatus,
            constraintType: constraint.constraintType,
            startTime: constraint.startTime,
            endTime: constraint.endTime,
            wasAutoRejectedFromCalendar: shouldResetAutoRejected
                ? false
                : constraint.wasAutoRejectedFromCalendar,
            repeatType: constraint.repeatType,
            repeatDay: constraint.repeatDay,
            repeatEndDate: constraint.repeatEndDate,
          ),
        );
  }

  List<DateConstraint> _getRelevantConstraints(TeamMember member) {
    return member.constraints.where((constraint) {
      if (member.isPermanent && constraint.isAvailability) return false;
      if (!member.isPermanent && constraint.isUnavailability) return false;
      return true;
    }).toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
  }

  List<DateConstraint> _getApprovedConstraints(TeamMember member) {
    return _getRelevantConstraints(member).where((constraint) {
      if (constraint.status != ConstraintStatus.approved) return false;
      if (_isPastConstraint(constraint)) return false;
      return true;
    }).toList();
  }

  List<DateConstraint> _getPendingConstraints(TeamMember member) {
    return _getRelevantConstraints(member).where((constraint) {
      if (constraint.status != ConstraintStatus.pending) return false;
      if (_isPastConstraint(constraint)) return false;
      return true;
    }).toList();
  }

  List<DateConstraint> _getRejectedConstraints(TeamMember member) {
    return _getRelevantConstraints(member).where((constraint) {
      return constraint.status == ConstraintStatus.rejected;
    }).toList();
  }

  bool _hasDisplayableConstraints(TeamMember member) {
    return _getApprovedConstraints(member).isNotEmpty ||
        _getPendingConstraints(member).isNotEmpty ||
        _getRejectedConstraints(member).isNotEmpty;
  }

  List<TeamMember> _filterMembersBySearch(List<TeamMember> members) {
    final query = _normalizeSearch(_searchQuery);
    if (query.isEmpty) return members;

    return members.where((member) {
      if (_normalizeSearch(member.name).contains(query)) {
        return true;
      }

      final searchableConstraints = [
        ..._getApprovedConstraints(member),
        ..._getPendingConstraints(member),
        ..._getRejectedConstraints(member),
      ];

      for (final constraint in searchableConstraints) {
        if (_normalizeSearch(constraint.note ?? '').contains(query)) {
          return true;
        }
      }
      return false;
    }).toList();
  }

  String _normalizeSearch(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  bool _isPastConstraint(DateConstraint constraint) {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    if (constraint.endDate != null) {
      final constraintEndDate = DateTime(
        constraint.endDate!.year,
        constraint.endDate!.month,
        constraint.endDate!.day,
      );
      return constraintEndDate.isBefore(todayDate);
    }

    final constraintStartDate = DateTime(
      constraint.startDate.year,
      constraint.startDate.month,
      constraint.startDate.day,
    );
    return constraintStartDate.isBefore(todayDate);
  }

  String _extractConstraintDisplayNote(DateConstraint constraint) {
    final raw = (constraint.note ?? '').trim();
    if (raw.isEmpty) return raw;
    const marker = '\nהערה:';
    final markerIndex = raw.indexOf(marker);
    if (markerIndex != -1) {
      return raw.substring(markerIndex + marker.length).trim();
    }
    return raw;
  }

  String _buildRecurringTypeText(DateConstraint constraint) {
    switch (constraint.repeatType) {
      case RepeatType.daily:
        return 'מגבלה קבועה יומית';
      case RepeatType.weekly:
        return 'מגבלה קבועה שבועית, כל יום ${_weekdayName(constraint.repeatDay)}';
      case RepeatType.monthly:
        return 'מגבלה קבועה חודשית, כל ${constraint.repeatDay ?? '?'} לחודש';
      case null:
        return '';
    }
  }

  String _weekdayName(int? weekday) {
    switch (weekday) {
      case 1:
        return 'שני';
      case 2:
        return 'שלישי';
      case 3:
        return 'רביעי';
      case 4:
        return 'חמישי';
      case 5:
        return 'שישי';
      case 6:
        return 'שבת';
      case 7:
        return 'ראשון';
      default:
        return '?';
    }
  }

  String _buildAdminConstraintDateLine(DateConstraint constraint) {
    if (constraint.repeatType != null) {
      if (constraint.repeatEndDate == null) {
        return 'עד תאריך: ?';
      }
      return 'תאריכים: ${_formatDate(constraint.startDate)} עד ${_formatDate(constraint.repeatEndDate!)}';
    }

    if (constraint.endDate == null ||
        _isSameDay(constraint.startDate, constraint.endDate!)) {
      return 'תאריך: ${_formatDate(constraint.startDate)}';
    }
    return 'תאריכים: ${_formatDate(constraint.startDate)} עד ${_formatDate(constraint.endDate!)}';
  }

  Widget _buildStatusBadge(ConstraintStatus status) {
    Color backgroundColor;
    Color textColor;
    String text;

    switch (status) {
      case ConstraintStatus.pending:
        backgroundColor = Colors.orange;
        textColor = Colors.white;
        text = 'ממתין';
        break;
      case ConstraintStatus.approved:
        backgroundColor = Colors.green;
        textColor = Colors.white;
        text = 'אושר';
        break;
      case ConstraintStatus.rejected:
        backgroundColor = Colors.red;
        textColor = Colors.white;
        text = 'נדחה';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  String _constraintKey(String teamMemberId, String constraintId) {
    return '$teamMemberId::$constraintId';
  }

  void _showMessage(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
