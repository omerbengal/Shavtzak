import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/event.dart';
import '../../domain/entities/team_member.dart';
import '../../domain/entities/assignment.dart';
import '../bloc/event/event_bloc.dart';
import '../bloc/event/event_event.dart';
import '../bloc/event/event_state.dart';
import '../bloc/team/team_bloc.dart';
import '../bloc/team/team_event.dart';
import '../bloc/team/team_state.dart';
import '../bloc/assignment/assignment_bloc.dart';
import '../bloc/assignment/assignment_event.dart';
import '../bloc/assignment/assignment_state.dart';

/// Dialog for copying vehicle information to clipboard
/// Allows admins to select team members and copy their vehicle details
class VehicleInfoCopyDialog extends StatefulWidget {
  const VehicleInfoCopyDialog({super.key});

  @override
  State<VehicleInfoCopyDialog> createState() => _VehicleInfoCopyDialogState();
}

class _VehicleInfoCopyDialogState extends State<VehicleInfoCopyDialog> {
  int _currentStep = 0;
  Event? _selectedEvent;
  List<Event> _futureEvents = [];
  List<TeamMember> _allTeamMembers = [];
  List<Assignment> _assignments = [];

  // Selected team member IDs (using Set for efficient add/remove)
  final Set<String> _selectedMemberIds = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    context.read<EventBloc>().add(const LoadUpcomingEvents());
    context.read<TeamBloc>().add(const LoadTeamMembers());
    // Load all assignments
    context.read<AssignmentBloc>().add(const LoadAssignments());
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<EventBloc, EventState>(
          listener: (context, state) {
            if (state is EventsLoaded) {
              setState(() {
                _futureEvents = state.events
                    .where((event) => !event.isPast)
                    .toList()
                  ..sort((a, b) => a.startDate.compareTo(b.startDate));
              });
            }
          },
        ),
        BlocListener<TeamBloc, TeamState>(
          listener: (context, state) {
            if (state is TeamLoaded) {
              setState(() {
                _allTeamMembers = state.members
                    .where((member) => member.isActive)
                    .toList()
                  ..sort((a, b) => a.name.compareTo(b.name));
              });
            }
          },
        ),
        BlocListener<AssignmentBloc, AssignmentState>(
          listener: (context, state) {
            if (state is AssignmentsLoaded) {
              setState(() {
                _assignments = state.assignments;
              });
            }
          },
        ),
      ],
      child: AlertDialog(
        title: Text(
          'העתקת פרטי רכב',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.green.shade700,
          ),
        ),
        content: SizedBox(
          width: 500,
          height: 550,
          child: Column(
            children: [
              // Progress indicator
              _buildProgressIndicator(),

              const SizedBox(height: 24),

              // Step content
              Expanded(
                child: _buildStepContent(),
              ),
            ],
          ),
        ),
        actions: [
          if (_currentStep == 1)
            TextButton(
              onPressed: () {
                setState(() {
                  _currentStep = 0;
                });
              },
              child: const Text('חזרה'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('סגור', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(2, (index) {
        return Container(
          width: 80,
          height: 4,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: index <= _currentStep ? Colors.green : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildEventSelectionStep();
      case 1:
        return _buildTeamMemberSelectionStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildEventSelectionStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'שלב 1 מתוך 2: בחירת אירוע',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.green.shade700,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'בחר אירוע עתידי להעתקת פרטי הרכבים:',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _futureEvents.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.event_busy, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'לא נמצאו אירועים עתידיים',
                        style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _futureEvents.length,
                  itemBuilder: (context, index) {
                    final event = _futureEvents[index];
                    final isSelected = _selectedEvent?.id == event.id;

                    return Card(
                      elevation: isSelected ? 4 : 1,
                      color: isSelected ? Colors.green.shade50 : Colors.white,
                      child: ListTile(
                        title: Text(
                          event.name,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Colors.green.shade700 : Colors.black,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(event.dateRangeString),
                            if (event.location.isNotEmpty) Text('מיקום: ${event.location}'),
                          ],
                        ),
                        onTap: () {
                          setState(() {
                            _selectedEvent = event;
                          });
                          // Auto-advance to next step
                          Future.delayed(const Duration(milliseconds: 300), () {
                            if (mounted) {
                              setState(() {
                                _currentStep = 1;
                              });
                            }
                          });
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTeamMemberSelectionStep() {
    if (_selectedEvent == null) return const SizedBox.shrink();

    // Get team member IDs assigned to the selected event
    final assignedMemberIds = _assignments
        .where((a) => a.eventId == _selectedEvent!.id)
        .map((a) => a.teamMemberId)
        .toSet();

    // Filter team members with complete vehicle info
    final membersWithVehicles = _allTeamMembers
        .where((member) => member.vehicleInfo != null && member.vehicleInfo!.isComplete)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    // Split into two lists
    final assignedWithVehicle = membersWithVehicles
        .where((member) => assignedMemberIds.contains(member.id))
        .toList();

    final unassignedWithVehicle = membersWithVehicles
        .where((member) => !assignedMemberIds.contains(member.id))
        .toList();

    final selectedCount = _selectedMemberIds.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'שלב 2 מתוך 2: בחירת אנשי צוות',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.green.shade700,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'בחר אנשי צוות להעתקת פרטי הרכב (${selectedCount.toString()} נבחרו):',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 16),

        // Copy button (appears at top for easy access)
        if (selectedCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _copyToClipboard,
                icon: const Icon(Icons.copy),
                label: Text('העתק $selectedCount פרטי רכב'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),

        // Primary list: Assigned to event
        if (assignedWithVehicle.isNotEmpty) ...[
          Text(
            'משובצים לאירוע "${_selectedEvent!.name}"',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            flex: unassignedWithVehicle.isEmpty ? 1 : 2,
            child: _buildMemberList(assignedWithVehicle),
          ),
          if (unassignedWithVehicle.isNotEmpty) const SizedBox(height: 16),
        ],

        // Secondary list: Not assigned to event
        if (unassignedWithVehicle.isNotEmpty) ...[
          Text(
            'עם פרטי רכב (לא משובצים לאירוע)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _buildMemberList(unassignedWithVehicle),
          ),
        ],

        // No members with vehicles message
        if (assignedWithVehicle.isEmpty && unassignedWithVehicle.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.directions_car, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'אין אנשי צוות עם פרטי רכב מלאים',
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMemberList(List<TeamMember> members) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: members.length,
        separatorBuilder: (context, index) => Divider(
          height: 1,
          color: Colors.grey.shade300,
        ),
        itemBuilder: (context, index) {
          final member = members[index];
          final isSelected = _selectedMemberIds.contains(member.id);

          return CheckboxListTile(
            value: isSelected,
            onChanged: (bool? value) {
              setState(() {
                if (value == true) {
                  _selectedMemberIds.add(member.id);
                } else {
                  _selectedMemberIds.remove(member.id);
                }
              });
            },
            title: Row(
              children: [
                Text(
                  member.name,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                if (member.isPermanent) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.verified_user,
                    size: 16,
                    color: Colors.blue.shade700,
                  ),
                ],
              ],
            ),
            subtitle: Text(
              member.vehicleInfo?.displayString ?? '',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
              ),
            ),
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
          );
        },
      ),
    );
  }

  void _copyToClipboard() {
    // Get selected team members
    final selectedMembers = _allTeamMembers
        .where((member) => _selectedMemberIds.contains(member.id))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    if (selectedMembers.isEmpty) return;

    // Format the output
    final buffer = StringBuffer();
    buffer.writeln('פרטי רכבים - ${_selectedEvent?.name ?? 'אירוע'}');
    buffer.writeln('תאריך: ${_selectedEvent?.dateRangeString ?? ''}');
    buffer.writeln('-' * 40);

    for (final member in selectedMembers) {
      final vehicle = member.vehicleInfo;
      if (vehicle != null) {
        buffer.writeln('${member.name}:');
        buffer.writeln('  מספר רכב: ${vehicle.formattedVehicleNumber}');
        buffer.writeln('  יצרן: ${vehicle.manufacturer}');
        buffer.writeln('  דגם: ${vehicle.model}');
        buffer.writeln('  צבע: ${vehicle.color}');
        if (member != selectedMembers.last) {
          buffer.writeln('');
        }
      }
    }

    // Copy to clipboard
    Clipboard.setData(ClipboardData(text: buffer.toString()));

    // Show confirmation
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Text('הועתקו פרטי ${selectedMembers.length} רכבים ללוח'),
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
