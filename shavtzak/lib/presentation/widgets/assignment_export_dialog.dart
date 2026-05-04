import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/services/environment_service.dart';
import '../../core/services/export_service.dart';
import '../../core/utils/date_utils.dart' as app_date_utils;
import '../../data/repositories/event_repository.dart';
import '../../domain/entities/event.dart';

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

  @override
  void initState() {
    super.initState();
    EnvironmentService.instance.addListener(_handleEnvironmentChanged);
    _loadFutureEvents();
  }

  @override
  void dispose() {
    EnvironmentService.instance.removeListener(_handleEnvironmentChanged);
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
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ביטול'),
          ),
          FilledButton.icon(
            onPressed: canExport
                ? () async {
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

    return Column(
      key: const ValueKey('events-list'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
            'נבחרו ${_selectedEventIds.length} מתוך ${_futureEvents.length} אירועים'),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: Scrollbar(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _futureEvents.length,
              itemBuilder: (context, index) {
                final event = _futureEvents[index];
                final isSelected = _selectedEventIds.contains(event.id);
                return CheckboxListTile(
                  value: isSelected,
                  title: Text(event.name),
                  subtitle: Text(_formatEventSubtitle(event)),
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (value) {
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
