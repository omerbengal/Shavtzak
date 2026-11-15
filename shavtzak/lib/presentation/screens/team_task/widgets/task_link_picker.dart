import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/crud_action_result.dart';
import '../../../../core/utils/search_utils.dart';
import '../../../../core/utils/team_task_rules.dart';
import '../../../../domain/entities/team_task.dart';
import '../../../../domain/entities/task_topic.dart';
import '../../../bloc/team_task/team_task_bloc.dart';
import '../../../widgets/rtl_arrow_keys.dart';
import '../../task/task_style.dart';

/// What the picker returns: a link, or "ללא שיוך" ([link] null). Null from
/// the dialog itself = cancelled.
class TaskLinkChoice {
  const TaskLinkChoice(this.link);
  final TaskLink? link;
}

/// The name of [link]'s target in [state], or null when it is gone.
String? taskLinkName(TeamTasksLoaded state, TaskLink? link) {
  if (link == null) return null;
  switch (link.type) {
    case TaskLinkType.event:
      return state.events.where((e) => e.id == link.id).firstOrNull?.name;
    case TaskLinkType.category:
      return state.categories.where((c) => c.id == link.id).firstOrNull?.name;
    case TaskLinkType.topic:
      return state.topics.where((t) => t.id == link.id).firstOrNull?.name;
    case TaskLinkType.pendingEvent:
      return state.pendingEvents.where((p) => p.id == link.id).firstOrNull?.name;
  }
}

/// The label of a "אירוע שעוד לא נוצר" (round 10), in the picker and on a card.
const String pendingEventLabel = 'אירוע שעוד לא נוצר';

/// Picks what a task belongs to: an event, a category or a topic, in three
/// segments, with a search and, for topics, "נושא חדש". The events segment
/// opens with "אירוע שעוד לא נוצר" (round 10): a manager names a new one
/// there, and the existing ones are listed first.
///
/// [eventsOnly]: only the app's real events, no segments ("קישור לאירוע
/// בשבצק" of a placeholder).
Future<TaskLinkChoice?> showTaskLinkPicker(
  BuildContext context, {
  TaskLink? initial,
  bool allowNone = true,
  bool eventsOnly = false,
  String? title,
}) {
  return showDialog<TaskLinkChoice>(
    context: context,
    builder: (_) => BlocProvider.value(
      value: context.read<TeamTaskBloc>(),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: _TaskLinkPicker(
          initial: initial,
          allowNone: allowNone && !eventsOnly,
          eventsOnly: eventsOnly,
          title: title,
        ),
      ),
    ),
  );
}

class _TaskLinkPicker extends StatefulWidget {
  const _TaskLinkPicker({
    this.initial,
    required this.allowNone,
    this.eventsOnly = false,
    this.title,
  });

  final TaskLink? initial;
  final bool allowNone;
  final bool eventsOnly;
  final String? title;

  @override
  State<_TaskLinkPicker> createState() => _TaskLinkPickerState();
}

class _TaskLinkPickerState extends State<_TaskLinkPicker> {
  /// The segment: a placeholder lives in the events segment.
  late TaskLinkType _type = widget.initial?.type == TaskLinkType.pendingEvent
      ? TaskLinkType.event
      : (widget.initial?.type ?? TaskLinkType.event);
  String _query = '';
  final TextEditingController _newTopic = TextEditingController();
  final TextEditingController _newPending = TextEditingController();
  bool _addingTopic = false;
  bool _pendingOpen = false;
  bool _addingPending = false;
  String? _error;
  String? _pendingError;

  @override
  void dispose() {
    _newTopic.dispose();
    _newPending.dispose();
    super.dispose();
  }

  Future<void> _addPending(TeamTasksLoaded state) async {
    final name = _newPending.text.trim();
    if (name.isEmpty) {
      setState(() => _pendingError = 'חובה להזין שם לאירוע');
      return;
    }
    final pending = TaskTopic(
      id: const Uuid().v4(),
      name: name,
      sortOrder: state.pendingEvents.length,
    );
    final completion = CrudActionCompleter();
    setState(() => _addingPending = true);
    context.read<TeamTaskBloc>().add(CreatePendingEvent(pending, completion: completion));
    final result = await completion.future;
    if (!mounted) return;
    if (result.isFailure) {
      setState(() {
        _addingPending = false;
        _pendingError = result.message;
      });
      return;
    }
    Navigator.of(context)
        .pop(TaskLinkChoice(TaskLink(TaskLinkType.pendingEvent, pending.id)));
  }

  /// "אירוע שעוד לא נוצר" at the top of the events: a tap opens a field for
  /// its name (a manager only).
  Widget _pendingEntry(TeamTasksLoaded state) {
    if (!_pendingOpen) {
      return InkWell(
        key: const Key('task-link-pending-new'),
        onTap: () => setState(() => _pendingOpen = true),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: TaskStyle.editRowLine)),
          ),
          child: const Row(
            children: [
              Icon(Icons.add, size: 18, color: TaskStyle.edit),
              SizedBox(width: 6),
              Flexible(
                child: Text(
                  pendingEventLabel,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: TaskStyle.edit,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: RtlArrowKeys(
              child: TextField(
                key: const Key('task-link-pending-name'),
                controller: _newPending,
                autofocus: true,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'שם האירוע שעוד לא נוצר',
                  errorText: _pendingError,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() => _pendingError = null),
                onSubmitted: (_) => _addPending(state),
              ),
            ),
          ),
          IconButton(
            key: const Key('task-link-pending-add'),
            tooltip: 'הוספה',
            onPressed: _addingPending ? null : () => _addPending(state),
            icon: const Icon(Icons.check),
          ),
        ],
      ),
    );
  }

  Future<void> _addTopic(TeamTasksLoaded state) async {
    final name = _newTopic.text.trim();
    if (name.isEmpty) return;
    final topic = TaskTopic(
      id: const Uuid().v4(),
      name: name,
      sortOrder: state.topics.length,
    );
    final completion = CrudActionCompleter();
    setState(() => _addingTopic = true);
    context.read<TeamTaskBloc>().add(CreateTaskTopic(topic, completion: completion));
    final result = await completion.future;
    if (!mounted) return;
    if (result.isFailure) {
      setState(() {
        _addingTopic = false;
        _error = result.message;
      });
      return;
    }
    Navigator.of(context).pop(TaskLinkChoice(TaskLink(TaskLinkType.topic, topic.id)));
  }

  List<({TaskLinkType type, String id, String name, String? note})> _options(
      TeamTasksLoaded state) {
    switch (_type) {
      case TaskLinkType.event:
      case TaskLinkType.pendingEvent:
        final events = linkableEvents(state.events, DateTime.now());
        return [
          // The placeholders first (round 10).
          if (!widget.eventsOnly)
            for (final pending in state.pendingEvents)
              if (!pending.isArchived)
                (
                  type: TaskLinkType.pendingEvent,
                  id: pending.id,
                  name: pending.name,
                  note: pendingEventLabel,
                ),
          for (final event in events)
            (
              type: TaskLinkType.event,
              id: event.id,
              name: event.name,
              note: '${event.startDate.day}.${event.startDate.month}.${event.startDate.year}',
            ),
        ];
      case TaskLinkType.category:
        return [
          for (final category in state.categories)
            if (!category.isArchived)
              (type: TaskLinkType.category, id: category.id, name: category.name, note: null),
        ];
      case TaskLinkType.topic:
        return [
          for (final topic in state.topics)
            if (!topic.isArchived)
              (type: TaskLinkType.topic, id: topic.id, name: topic.name, note: null),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TeamTaskBloc>().state;
    if (state is! TeamTasksLoaded) return const SizedBox.shrink();
    final query = normalizeForSearch(_query.trim()).toLowerCase();
    final options = _options(state)
        .where((o) => query.isEmpty || normalizeForSearch(o.name).toLowerCase().contains(query))
        .toList();
    final showPending =
        !widget.eventsOnly && _type == TaskLinkType.event && state.canManage && query.isEmpty;
    return AlertDialog(
      title: Text(widget.title ?? 'שיוך המשימה'),
      content: SizedBox(
        width: 360,
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.eventsOnly) ...[
            SegmentedButton<TaskLinkType>(
              // The דו יומי switch's colours: the theme's own are white text
              // on light orange, which is unreadable.
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: AppTheme.primaryDark,
                selectedForegroundColor: Colors.white,
              ),
              segments: const [
                ButtonSegment(value: TaskLinkType.event, label: Text('אירוע')),
                ButtonSegment(value: TaskLinkType.category, label: Text('קטגוריה')),
                ButtonSegment(value: TaskLinkType.topic, label: Text('נושא')),
              ],
              selected: {_type},
              showSelectedIcon: false,
              onSelectionChanged: (value) => setState(() => _type = value.first),
            ),
            const SizedBox(height: 8),
            ],
            RtlArrowKeys(
              child: TextField(
                key: const Key('task-link-search'),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'חיפוש...',
                  prefixIcon: Icon(Icons.search, size: 18),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: options.isEmpty && !showPending
                  ? const Center(child: Text('אין מה להציג'))
                  : ListView(
                      children: [
                        if (showPending) _pendingEntry(state),
                        for (final option in options)
                          _LinkOption(
                            key: Key('task-link-option-${option.id}'),
                            name: option.name,
                            note: option.note,
                            current: widget.initial == TaskLink(option.type, option.id),
                            onTap: () => Navigator.of(context)
                                .pop(TaskLinkChoice(TaskLink(option.type, option.id))),
                          ),
                      ],
                    ),
            ),
            if (_type == TaskLinkType.topic && state.canManage)
              Row(
                children: [
                  Expanded(
                    child: RtlArrowKeys(
                      child: TextField(
                        key: const Key('task-link-new-topic'),
                        controller: _newTopic,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'נושא חדש',
                          errorText: _error,
                          border: const OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _addTopic(state),
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('task-link-new-topic-add'),
                    tooltip: 'הוספת נושא',
                    onPressed: _addingTopic ? null : () => _addTopic(state),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        if (widget.allowNone)
          TextButton(
            key: const Key('task-link-none'),
            onPressed: () => Navigator.of(context).pop(const TaskLinkChoice(null)),
            child: const Text('ללא שיוך'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ביטול'),
        ),
      ],
    );
  }
}

/// One choice in the picker, in the look of the דו יומי "העברה לשלב אחר"
/// list: a roomy line in the normal text colour, the current one marked in
/// words rather than in colour.
class _LinkOption extends StatelessWidget {
  const _LinkOption({
    super.key,
    required this.name,
    required this.note,
    required this.current,
    required this.onTap,
  });

  final String name;
  final String? note;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: TaskStyle.editRowLine)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  if (note != null)
                    Text(
                      note!,
                      style: const TextStyle(fontSize: 13, color: TaskStyle.editMuted),
                    ),
                ],
              ),
            ),
            if (current)
              const Padding(
                padding: EdgeInsetsDirectional.only(start: 8),
                child: Text(
                  'השיוך הנוכחי',
                  style: TextStyle(fontSize: 12, color: TaskStyle.editMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
