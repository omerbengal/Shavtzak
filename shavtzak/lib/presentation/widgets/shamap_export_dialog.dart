import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/debug/logger.dart';
import '../../core/utils/date_utils.dart' as app_date_utils;
import '../../domain/entities/assignment.dart';
import '../../domain/entities/event.dart';
import '../../domain/entities/team_member.dart';
import '../bloc/assignment/assignment_bloc.dart';
import '../bloc/assignment/assignment_event.dart';
import '../bloc/assignment/assignment_state.dart';
import '../bloc/event/event_bloc.dart';
import '../bloc/event/event_event.dart';
import '../bloc/event/event_state.dart';
import '../bloc/team/team_bloc.dart';
import '../bloc/team/team_event.dart';
import '../bloc/team/team_state.dart';
import 'map_location_picker.dart';

/// Dialog for exporting shamap details into clipboard in Google Sheets format
class ShamapExportDialog extends StatefulWidget {
  const ShamapExportDialog({super.key});

  @override
  State<ShamapExportDialog> createState() => _ShamapExportDialogState();
}

class _ShamapExportDialogState extends State<ShamapExportDialog> {
  int _currentStep = 0;
  Event? _selectedEvent;

  List<Event> _futureEvents = [];
  List<Event> _pastEvents = [];
  List<TeamMember> _allTeamMembers = [];
  List<Assignment> _assignments = [];

  final Set<String> _selectedMemberIds = {};

  bool _eventsLoaded = false;
  bool _teamLoaded = false;
  bool _assignmentsLoaded = false;
  bool _copied = false;

  int _visiblePastCount = 10;
  bool _isFutureExpanded = true;
  bool _isPastExpanded = false;

  final TextEditingController _shamapLocationController =
      TextEditingController();
  final ScrollController _eventStepScrollController = ScrollController();
  final ScrollController _memberStepScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _shamapLocationController.dispose();
    _eventStepScrollController.dispose();
    _memberStepScrollController.dispose();
    super.dispose();
  }

  void _loadData() {
    context.read<EventBloc>().add(const LoadEvents());
    context.read<TeamBloc>().add(const LoadTeamMembers());
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
                _eventsLoaded = true;
                _rebuildEventLists(state.events);
              });
            } else if (state is EventsEmpty || state is EventError) {
              setState(() {
                _eventsLoaded = true;
                _rebuildEventLists(const []);
              });
            }
          },
        ),
        BlocListener<TeamBloc, TeamState>(
          listener: (context, state) {
            if (state is TeamLoaded) {
              final sortedMembers = List<TeamMember>.from(state.members)
                ..sort((a, b) => a.name.compareTo(b.name));
              setState(() {
                _teamLoaded = true;
                _allTeamMembers = sortedMembers;
              });
            } else if (state is TeamEmpty || state is TeamError) {
              setState(() {
                _teamLoaded = true;
                _allTeamMembers = [];
              });
            }
          },
        ),
        BlocListener<AssignmentBloc, AssignmentState>(
          listener: (context, state) {
            if (state is AssignmentsLoaded) {
              setState(() {
                _assignmentsLoaded = true;
                _assignments = state.assignments;
              });
            } else if (state is AssignmentsEmpty || state is AssignmentError) {
              setState(() {
                _assignmentsLoaded = true;
                _assignments = [];
              });
            }
          },
        ),
      ],
      child: AlertDialog(
        actionsAlignment: _currentStep == 2
            ? MainAxisAlignment.spaceBetween
            : MainAxisAlignment.end,
        title: Text(
          'ייצוא שמפים',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.teal.shade700,
          ),
        ),
        content: SizedBox(
          width: 560,
          height: 620,
          child: Column(
            children: [
              _buildProgressIndicator(),
              const SizedBox(height: 20),
              Expanded(child: _buildStepContent()),
            ],
          ),
        ),
        actions: _buildActions(),
      ),
    );
  }

  List<Widget> _buildActions() {
    if (_currentStep == 0) {
      return [
        TextButton(
          onPressed: () {
            Logger.action('tap:cancel:shamapExport');
            Navigator.of(context).pop();
          },
          child: const Text('ביטול', style: TextStyle(color: Colors.red)),
        ),
        ElevatedButton(
          onPressed: _selectedEvent == null
              ? null
              : () {
                  Logger.action('tap:continueToLocation',
                      {'eventId': _selectedEvent!.id});
                  _goToLocationStep();
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
          ),
          child: const Text('המשך'),
        ),
      ];
    }

    if (_currentStep == 1) {
      final hasShamapLocation =
          _shamapLocationController.text.trim().isNotEmpty;
      return [
        TextButton(
          onPressed: () {
            Logger.action('tap:back:locationStep');
            _goToStep(0);
          },
          child: const Text('אחורה'),
        ),
        ElevatedButton(
          onPressed: hasShamapLocation
              ? () {
                  Logger.action('tap:continueToMembers',
                      {'eventId': _selectedEvent?.id});
                  _goToMembersStep();
                }
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
          ),
          child: const Text('המשך'),
        ),
      ];
    }

    final selectedCount = _selectedMemberIds.length;
    return [
      TextButton(
        onPressed: () {
          Logger.action('tap:back:membersStep');
          _goToStep(1);
        },
        child: const Text('אחורה'),
      ),
      TextButton(
        onPressed: () {
          Logger.action('tap:close:shamapExport');
          Navigator.of(context).pop();
        },
        child: const Text('סגירה'),
      ),
      ElevatedButton.icon(
        onPressed: selectedCount > 0
            ? () {
                Logger.action('tap:copyToClipboard', {
                  'eventId': _selectedEvent?.id,
                  'count': selectedCount,
                });
                _copyToClipboard();
              }
            : null,
        icon: Icon(
          _copied ? Icons.check_circle : Icons.copy,
          color: _copied ? const Color(0xFF00E676) : Colors.white,
          size: 18,
        ),
        label: const Text('העתק פרטי שמ"פ'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.teal,
          foregroundColor: Colors.white,
        ),
      ),
    ];
  }

  Widget _buildProgressIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        return Container(
          width: 60,
          height: 4,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: index <= _currentStep ? Colors.teal : Colors.grey.shade300,
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
        return _buildShamapLocationStep();
      case 2:
        return _buildTeamMemberSelectionStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildEventSelectionStep() {
    if (!_eventsLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final hasAnyEvents = _futureEvents.isNotEmpty || _pastEvents.isNotEmpty;
    if (!hasAnyEvents) {
      return _buildEmptyState(
        icon: Icons.event_busy,
        message: 'לא נמצאו אירועים להצגה',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'שלב 1 מתוך 3: בחירת אירוע',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.teal.shade700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'בחר אירוע לייצוא פרטי שמ"פ:',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 10),
        if (_selectedEvent != null) ...[
          _buildSelectedEventSummary(_selectedEvent!),
          const SizedBox(height: 10),
        ],
        Expanded(
          child: SingleChildScrollView(
            controller: _eventStepScrollController,
            child: Column(
              children: [
                _buildEventSection(
                  title: 'אירועים עתידיים',
                  events: _futureEvents,
                  isExpanded: _isFutureExpanded,
                  onToggle: () {
                    Logger.action('toggle:futureEventsSection',
                        {'on': !_isFutureExpanded});
                    setState(() {
                      _isFutureExpanded = !_isFutureExpanded;
                    });
                  },
                ),
                const SizedBox(height: 10),
                _buildEventSection(
                  title: 'אירועי עבר',
                  events: _pastEvents,
                  isExpanded: _isPastExpanded,
                  onToggle: () {
                    Logger.action('toggle:pastEventsSection',
                        {'on': !_isPastExpanded});
                    setState(() {
                      _isPastExpanded = !_isPastExpanded;
                    });
                  },
                  visibleCount: _visiblePastCount,
                  onLoadMore: _pastEvents.length > _visiblePastCount
                      ? () {
                          Logger.action('tap:loadMorePastEvents',
                              {'visibleCount': _visiblePastCount});
                          setState(() {
                            _visiblePastCount += 10;
                          });
                        }
                      : null,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildShamapLocationStep() {
    if (_selectedEvent == null) {
      return _buildEmptyState(
        icon: Icons.event_note,
        message: 'יש לבחור אירוע לפני הזנת מיקום שמ"פ',
      );
    }

    final eventLocation = _formatLocationForDisplay(_selectedEvent!.location);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'שלב 2 מתוך 3: מיקום שמ"פ',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.teal.shade700,
          ),
        ),
        const SizedBox(height: 10),
        _buildSelectedEventSummary(_selectedEvent!),
        const SizedBox(height: 14),
        Text(
          'מיקום האירוע הינו: $eventLocation\nמה מיקום השמ"פ?',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade800,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _shamapLocationController,
          autofocus: false,
          maxLines: 1,
          decoration: InputDecoration(
            hintText: 'הקלד/י מיקום שמ"פ',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          onChanged: (_) {
            setState(() {
              _copied = false;
            });
          },
        ),
      ],
    );
  }

  Widget _buildSelectedEventSummary(Event event) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.teal.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'אירוע נבחר:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.teal.shade700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            event.name,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            _formatEventDatesHebrew(event),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  Widget _buildEventSection({
    required String title,
    required List<Event> events,
    required bool isExpanded,
    required VoidCallback onToggle,
    int? visibleCount,
    VoidCallback? onLoadMore,
  }) {
    final displayedEvents =
        visibleCount == null ? events : events.take(visibleCount).toList();

    return Card(
      elevation: 1,
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$title (${events.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            if (events.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'אין אירועים בקטגוריה זו',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
              )
            else
              ListView.builder(
                itemCount: displayedEvents.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemBuilder: (context, index) {
                  return _buildEventTile(displayedEvents[index]);
                },
              ),
            if (onLoadMore != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextButton(
                  onPressed: onLoadMore,
                  child: const Text('טען עוד 10'),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildEventTile(Event event) {
    final isSelected = _selectedEvent?.id == event.id;

    return Card(
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      elevation: isSelected ? 3 : 1,
      color: isSelected ? Colors.teal.shade50 : Colors.white,
      child: ListTile(
        title: Text(
          event.name,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.teal.shade700 : Colors.black,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_formatEventDatesHebrew(event)),
            if (event.assemblyTime.isNotEmpty)
              Text('התייצבות: ${event.assemblyTime}'),
            if (event.startTime.isNotEmpty) Text('התכנסות: ${event.startTime}'),
            if (event.actualShowStartTime.isNotEmpty)
              Text('תחילת מופע: ${event.actualShowStartTime}'),
            if (event.endTime.isNotEmpty)
              Text('סיום המופע: ${event.endTime}'),
            if (event.teamEndTime.isNotEmpty)
              Text('סיום הצוות: ${event.teamEndTime}'),
            if (event.location.isNotEmpty)
              Text('מיקום: ${_formatLocationForDisplay(event.location)}'),
          ],
        ),
        onTap: () {
          Logger.action('select:event', {'eventId': event.id});
          final isDifferentEvent = _selectedEvent?.id != event.id;
          setState(() {
            _selectedEvent = event;
            if (isDifferentEvent) {
              _shamapLocationController.clear();
              _selectedMemberIds.clear();
            }
            _copied = false;
          });
        },
      ),
    );
  }

  Widget _buildTeamMemberSelectionStep() {
    if (_selectedEvent == null) {
      return _buildEmptyState(
        icon: Icons.event_note,
        message: 'יש לבחור אירוע לפני בחירת אנשי צוות',
      );
    }

    if (!_teamLoaded || !_assignmentsLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final assignedMembers = _getAssignedMembersForSelectedEvent();
    final selectedCount = _selectedMemberIds.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'שלב 3 מתוך 3: בחירת אנשי צוות',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.teal.shade700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'אירוע: ${_selectedEvent!.name}',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 6),
        Text(
          'נבחרו $selectedCount מתוך ${assignedMembers.length}',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: assignedMembers.isEmpty
              ? _buildEmptyState(
                  icon: Icons.people_outline,
                  message: 'לא נמצאו אנשי צוות משובצים לאירוע זה',
                )
              : Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.separated(
                    controller: _memberStepScrollController,
                    itemCount: assignedMembers.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      color: Colors.grey.shade300,
                    ),
                    itemBuilder: (context, index) {
                      final member = assignedMembers[index];
                      final isSelected = _selectedMemberIds.contains(member.id);
                      return CheckboxListTile(
                        value: isSelected,
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                        onChanged: (value) {
                          Logger.action('toggle:shamapMember',
                              {'memberId': member.id, 'on': value ?? false});
                          setState(() {
                            if (value == true) {
                              _selectedMemberIds.add(member.id);
                            } else {
                              _selectedMemberIds.remove(member.id);
                            }
                            _copied = false;
                          });
                        },
                        title: Row(
                          children: [
                            Text(
                              member.name,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
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
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState({required IconData icon, required String message}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 46, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _goToLocationStep() {
    if (_selectedEvent == null) return;
    _goToStep(1);
  }

  void _goToMembersStep() {
    if (_selectedEvent == null) return;
    if (_shamapLocationController.text.trim().isEmpty) return;

    final selectedIds = _getAssignedMemberIdsForEvent(_selectedEvent!.id);
    setState(() {
      _selectedMemberIds
        ..clear()
        ..addAll(selectedIds);
      _copied = false;
    });

    _goToStep(2);
  }

  void _goToStep(int step) {
    setState(() {
      _currentStep = step;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (step == 0 && _eventStepScrollController.hasClients) {
        _eventStepScrollController.jumpTo(0);
      } else if (step == 2 && _memberStepScrollController.hasClients) {
        _memberStepScrollController.jumpTo(0);
      }
    });
  }

  Set<String> _getAssignedMemberIdsForEvent(String eventId) {
    return _assignments
        .where((assignment) => assignment.eventId == eventId)
        .map((assignment) => assignment.teamMemberId)
        .toSet();
  }

  List<TeamMember> _getAssignedMembersForSelectedEvent() {
    if (_selectedEvent == null) return [];

    final assignedIds = _getAssignedMemberIdsForEvent(_selectedEvent!.id);
    final byId = <String, TeamMember>{
      for (final member in _allTeamMembers) member.id: member,
    };

    final members = <TeamMember>[];
    for (final memberId in assignedIds) {
      final member = byId[memberId];
      if (member != null) {
        members.add(member);
        continue;
      }

      // Fallback to populated relation in assignment objects
      for (final assignment in _assignments) {
        if (assignment.eventId == _selectedEvent!.id &&
            assignment.teamMemberId == memberId &&
            assignment.teamMember != null) {
          members.add(assignment.teamMember!);
          break;
        }
      }
    }

    members.sort((a, b) => a.name.compareTo(b.name));
    return members;
  }

  Future<void> _copyToClipboard() async {
    if (_selectedEvent == null) return;

    final selectedMembers = _getAssignedMembersForSelectedEvent()
        .where((member) => _selectedMemberIds.contains(member.id))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    if (selectedMembers.isEmpty) return;

    final location = _sanitizeCell(_shamapLocationController.text);
    final startDate =
        app_date_utils.DateUtils.formatDate(_selectedEvent!.startDate);
    final endDate =
        app_date_utils.DateUtils.formatDate(_selectedEvent!.endDate);

    final lines = selectedMembers.map((member) {
      final (firstNameRaw, lastNameRaw) = _splitName(member.name);
      final firstName = _sanitizeCell(firstNameRaw);
      final lastName = _sanitizeCell(lastNameRaw);
      // A=empty, B=firstName, C=lastName, D=location, E=empty, F=empty, G=start, H=end
      return '\t$firstName\t$lastName\t$location\t\t\t$startDate\t$endDate';
    }).join('\n');

    await Clipboard.setData(ClipboardData(text: lines));

    if (!mounted) return;
    setState(() {
      _copied = true;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _copied = false;
      });
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Text('הועתקו ${selectedMembers.length} שורות ללוח'),
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _rebuildEventLists(List<Event> events) {
    final previousSelectedId = _selectedEvent?.id;

    final today = _dateOnly(DateTime.now());
    final future = <Event>[];
    final past = <Event>[];

    for (final event in events) {
      final endDateOnly = _dateOnly(event.endDate);
      if (!endDateOnly.isBefore(today)) {
        future.add(event);
      } else {
        past.add(event);
      }
    }

    future.sort((a, b) {
      final dateCompare =
          _dateOnly(a.startDate).compareTo(_dateOnly(b.startDate));
      if (dateCompare != 0) return dateCompare;
      return _timeToMinutes(a.assemblyTime).compareTo(
        _timeToMinutes(b.assemblyTime),
      );
    });

    past.sort((a, b) {
      return _dateOnly(b.startDate).compareTo(_dateOnly(a.startDate));
    });

    _futureEvents = future;
    _pastEvents = past;

    if (previousSelectedId == null) return;

    for (final event in events) {
      if (event.id == previousSelectedId) {
        _selectedEvent = event;
        return;
      }
    }

    _selectedEvent = null;
    _shamapLocationController.clear();
    _selectedMemberIds.clear();
    _copied = false;
    if (_currentStep > 0) {
      _currentStep = 0;
    }
  }

  int _timeToMinutes(String timeValue) {
    if (timeValue.trim().isEmpty) return 24 * 60 + 1;

    final parts = timeValue.split(':');
    if (parts.length != 2) return 24 * 60 + 1;

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return 24 * 60 + 1;

    return (hour * 60) + minute;
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  /// Format event dates in Hebrew (same pattern used in assignments screen)
  String _formatEventDatesHebrew(Event event) {
    final isSameDay = event.startDate.year == event.endDate.year &&
        event.startDate.month == event.endDate.month &&
        event.startDate.day == event.endDate.day;

    if (isSameDay) {
      return 'יום ${_getFullHebrewDayName(event.startDate.weekday)} ${event.startDate.day} ב${_getHebrewMonthName(event.startDate.month)}';
    } else {
      return 'יום ${_getFullHebrewDayName(event.startDate.weekday)} ${event.startDate.day} ב${_getHebrewMonthName(event.startDate.month)} - יום ${_getFullHebrewDayName(event.endDate.weekday)} ${event.endDate.day} ב${_getHebrewMonthName(event.endDate.month)}';
    }
  }

  String _getFullHebrewDayName(int weekday) {
    const days = ['', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת', 'ראשון'];
    return days[weekday];
  }

  String _getHebrewMonthName(int month) {
    const months = [
      '',
      'ינואר',
      'פברואר',
      'מרץ',
      'אפריל',
      'מאי',
      'יוני',
      'יולי',
      'אוגוסט',
      'ספטמבר',
      'אוקטובר',
      'נובמבר',
      'דצמבר',
    ];
    return months[month];
  }

  String _formatLocationForDisplay(String location) {
    final stripped = _formatLocationForClipboard(location);
    return stripped.isEmpty ? '-' : stripped;
  }

  String _formatLocationForClipboard(String location) {
    var result = location.trim();
    if (result.isEmpty) return '';

    if (result.contains('||')) {
      result = MapLocationResult.stripCoordinates(result).trim();
    }

    // Remove explicit lat,lng fragments if they exist in free text.
    result = result.replaceAll(
      RegExp(r'\(?\s*-?\d{1,3}(?:\.\d+)?\s*,\s*-?\d{1,3}(?:\.\d+)?\s*\)?'),
      '',
    );

    result = result.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    return result;
  }

  String _sanitizeCell(String value) {
    return value.replaceAll('\t', ' ').replaceAll('\n', ' ').trim();
  }

  (String, String) _splitName(String fullName) {
    final parts = fullName
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return ('', '');
    if (parts.length == 1) return (parts.first, '');
    return (parts.first, parts.sublist(1).join(' '));
  }
}
