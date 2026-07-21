import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/debug/logger.dart';
import '../../core/services/environment_service.dart';
import '../../core/services/export_service.dart';
import '../../core/utils/date_utils.dart' as app_date_utils;
import '../../core/utils/event_filter_utils.dart';
import '../../data/repositories/event_repository.dart';
import '../../domain/entities/event.dart';
import 'date_picker_dialog.dart';
import 'event_search_filter_bar.dart';

class AssignmentExportDialog extends StatefulWidget {
  const AssignmentExportDialog({
    super.key,
    required this.onExport,
  });

  final Future<void> Function(
    AssignmentExportMode mode,
    List<String> eventIds,
  ) onExport;

  @override
  State<AssignmentExportDialog> createState() => _AssignmentExportDialogState();
}

class _AssignmentExportDialogState extends State<AssignmentExportDialog> {
  AssignmentExportMode _mode = AssignmentExportMode.perPerson;
  final Set<String> _selectedEventIds = {};
  List<Event> _futureEvents = [];
  bool _isLoadingEvents = true;
  String? _loadError;

  // Feature 3: search + category filter over the per-event list.
  String _searchQuery = '';
  Set<String> _selectedCategoryIds = <String>{};

  // Shared by the events Scrollbar + ListView so the Scrollbar always has a
  // ScrollPosition attached (a bare Scrollbar over a shrinkWrap ListView falls
  // back to the PrimaryScrollController, which the list never attaches to).
  final ScrollController _eventsScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    EnvironmentService.instance.addListener(_handleEnvironmentChanged);
    _loadFutureEvents();
  }

  @override
  void dispose() {
    EnvironmentService.instance.removeListener(_handleEnvironmentChanged);
    _eventsScrollController.dispose();
    super.dispose();
  }

  void _handleEnvironmentChanged() {
    if (!mounted) {
      if (EnvironmentService.instance.isTestMode &&
          _mode == AssignmentExportMode.perEvent) {
        _mode = AssignmentExportMode.perPerson;
        _selectedEventIds.clear();
      }
      return;
    }

    setState(() {
      if (EnvironmentService.instance.isTestMode &&
          _mode == AssignmentExportMode.perEvent) {
        _mode = AssignmentExportMode.perPerson;
        _selectedEventIds.clear();
      }
    });
  }

  Future<void> _loadFutureEvents() async {
    try {
      final events = await context.read<EventRepository>().getAllEvents();
      final today = _dateOnly(DateTime.now());
      final futureEvents = events.where((event) {
        // Deactivated ("on hold") events are excluded from exports on the
        // backend, so they must not be selectable here — otherwise selecting
        // one fails validation ("Selected future event IDs are invalid").
        if (event.isDeactivated) return false;
        final endDate = _dateOnly(event.endDate);
        return !endDate.isBefore(today);
      }).toList()
        ..sort((a, b) {
          final dateCompare =
              _dateOnly(a.startDate).compareTo(_dateOnly(b.startDate));
          if (dateCompare != 0) return dateCompare;
          final timeCompare = a.startTime.compareTo(b.startTime);
          if (timeCompare != 0) return timeCompare;
          return a.name.compareTo(b.name);
        });

      if (!mounted) return;
      setState(() {
        _futureEvents = futureEvents;
        _isLoadingEvents = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString();
        _isLoadingEvents = false;
      });
    }
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  @override
  Widget build(BuildContext context) {
    final isTestMode = EnvironmentService.instance.isTestMode;
    final canExport =
        _mode == AssignmentExportMode.perPerson || _selectedEventIds.isNotEmpty;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('ייצוא שיבוצים'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildModePicker(),
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: _mode == AssignmentExportMode.perPerson || isTestMode
                    ? _buildPerPersonContent()
                    : _buildPerEventContent(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Logger.action('tap:cancel:assignmentExportDialog');
              Navigator.of(context).pop();
            },
            child: const Text('ביטול'),
          ),
          FilledButton.icon(
            onPressed: canExport
                ? () async {
                    Logger.action('tap:exportAssignments', {
                      'mode': _mode.toString(),
                      'eventCount': _selectedEventIds.length,
                    });
                    final mode = _mode;
                    final eventIds = _selectedEventIds.toList();
                    Navigator.of(context).pop();
                    await widget.onExport(mode, eventIds);
                  }
                : null,
            icon: const Icon(Icons.cloud_upload),
            label: const Text('ייצוא'),
          ),
        ],
      ),
    );
  }

  Widget _buildModePicker() {
    final isTestMode = EnvironmentService.instance.isTestMode;

    return SegmentedButton<AssignmentExportMode>(
      segments: [
        const ButtonSegment(
          value: AssignmentExportMode.perPerson,
          icon: Icon(Icons.person),
          label: Text('לפי אדם'),
        ),
        ButtonSegment(
          value: AssignmentExportMode.perEvent,
          icon: const Icon(Icons.event),
          label: const Text('לפי אירוע'),
          enabled: !isTestMode,
        ),
      ],
      selected: {_mode},
      onSelectionChanged: (selection) {
        final nextMode = selection.first;
        Logger.action('select:exportMode', {'mode': nextMode.toString()});
        if (isTestMode && nextMode == AssignmentExportMode.perEvent) {
          return;
        }

        setState(() {
          _mode = nextMode;
        });
      },
    );
  }

  Widget _buildPerPersonContent() {
    final children = <Widget>[
      const Text(
        'ייצוא כל השיבוצים של אירועים עתידיים, ממוין לפי אדם ואז לפי תאריך אירוע.',
      ),
    ];

    if (EnvironmentService.instance.isTestMode) {
      children.addAll(const [
        SizedBox(height: 8),
        Text('ייצוא לפי אירוע זמין בפרודקשן בלבד.'),
      ]);
    }

    return Column(
      key: const ValueKey('per-person-content'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  /// Pick a date range and add every future event overlapping it to the export
  /// selection (union — existing picks are kept). Operates on all future events,
  /// independent of the active search/category filter.
  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final result = await showDialog<Map<String, DateTime?>>(
      context: context,
      builder: (_) => DualCalendarDatePicker(
        isSingleDate: false,
        title: 'בחירת אירועים לפי טווח תאריכים',
        minDate: today,
        highlightedDates: eventCoverageDays(_futureEvents),
      ),
    );
    if (result == null || result['startDate'] == null) return;
    final start = result['startDate']!;
    final end = result['endDate'] ?? start;
    final idsInRange = eventIdsInDateRange(_futureEvents, start, end);
    if (!mounted) return;
    if (idsInRange.isNotEmpty) {
      setState(() => _selectedEventIds.addAll(idsInRange));
    }
  }

  Widget _buildPerEventContent() {
    if (_isLoadingEvents) {
      return const SizedBox(
        key: ValueKey('events-loading'),
        height: 180,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null) {
      return Text(
        'שגיאה בטעינת אירועים עתידיים:\n$_loadError',
        key: const ValueKey('events-error'),
        style: const TextStyle(color: Colors.red),
      );
    }

    if (_futureEvents.isEmpty) {
      return const Text(
        'אין אירועים עתידיים לייצוא',
        key: ValueKey('events-empty'),
      );
    }

    final filteredEvents = filterEventsBySearchAndCategory(
      _futureEvents,
      query: _searchQuery,
      categoryIds: _selectedCategoryIds,
    );
    final filteredIds = filteredEvents.map((e) => e.id).toSet();
    final allFilteredSelected = filteredIds.isNotEmpty &&
        filteredIds.every((id) => _selectedEventIds.contains(id));

    return Column(
      key: const ValueKey('events-list'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Bulk-select events across a date range (adds to the selection).
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: () {
              Logger.action('open:exportDateRangePicker');
              _pickDateRange();
            },
            icon: const Icon(Icons.date_range, size: 20),
            label: const Text('בחירה לפי טווח תאריכים'),
          ),
        ),
        const SizedBox(height: 8),
        // Feature 3: search + category filter.
        EventSearchFilterBar(
          logField: 'exportEvents',
          padding: const EdgeInsets.only(bottom: 8),
          searchQuery: _searchQuery,
          onSearchChanged: (value) => setState(() => _searchQuery = value),
          selectedCategoryIds: _selectedCategoryIds,
          onCategoryFilterChanged: (ids) =>
              setState(() => _selectedCategoryIds = ids),
        ),
        // "Select all filtered" ⇄ "clear filtered" toggle + selection count.
        Row(
          children: [
            TextButton.icon(
              onPressed: filteredEvents.isEmpty
                  ? null
                  : () {
                      Logger.action('tap:selectAllExportEvents', {
                        'allSelected': allFilteredSelected,
                        'count': filteredIds.length,
                      });
                      setState(() {
                        if (allFilteredSelected) {
                          _selectedEventIds.removeAll(filteredIds);
                        } else {
                          _selectedEventIds.addAll(filteredIds);
                        }
                      });
                    },
              icon: Icon(
                allFilteredSelected ? Icons.remove_done : Icons.done_all,
                size: 20,
              ),
              label: Text(allFilteredSelected ? 'בטל בחירה' : 'בחר הכל'),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                'נבחרו ${_selectedEventIds.length} מתוך ${_futureEvents.length}',
                textAlign: TextAlign.end,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (filteredEvents.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'אין אירועים התואמים לסינון',
              textAlign: TextAlign.center,
            ),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: Scrollbar(
              controller: _eventsScrollController,
              child: ListView.builder(
                controller: _eventsScrollController,
                shrinkWrap: true,
                itemCount: filteredEvents.length,
                itemBuilder: (context, index) {
                  final event = filteredEvents[index];
                  final isSelected = _selectedEventIds.contains(event.id);
                  return CheckboxListTile(
                    value: isSelected,
                    title: Text(event.name),
                    subtitle: Text(_formatEventSubtitle(event)),
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (value) {
                      Logger.action('toggle:selectExportEvent', {
                        'eventId': event.id,
                        'on': value == true,
                      });
                      setState(() {
                        if (value == true) {
                          _selectedEventIds.add(event.id);
                        } else {
                          _selectedEventIds.remove(event.id);
                        }
                      });
                    },
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  String _formatEventSubtitle(Event event) {
    final details = <String>[_formatEventDate(event)];
    final startTime = event.startTime.trim();
    final location = event.location.trim();

    if (startTime.isNotEmpty) {
      details.add(startTime);
    }
    if (location.isNotEmpty) {
      details.add(location);
    }

    return details.join(' · ');
  }

  String _formatEventDate(Event event) {
    final start = app_date_utils.DateUtils.formatDate(event.startDate);
    if (_dateOnly(event.startDate) == _dateOnly(event.endDate)) {
      return start;
    }

    final end = app_date_utils.DateUtils.formatDate(event.endDate);
    return '$start - $end';
  }
}
