import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/crud_action_result.dart';
import '../../../../core/utils/debounced_saver.dart';
import '../../../../core/utils/search_utils.dart';
import '../../../../core/utils/team_task_rules.dart';
import '../../../../domain/entities/team_task.dart';
import '../../../../domain/entities/task_topic.dart';
import '../../../bloc/team_task/team_task_bloc.dart';
import '../../../widgets/rtl_arrow_keys.dart';
import '../../task/task_style.dart';

/// What the picker returns: a link, or "ללא שיוך" ([link] null). Null from
/// the dialog itself = cancelled. For events, [eventIds] holds every event
/// picked (16/11/2026: a task may belong to several), [link]'s first.
class TaskLinkChoice {
  const TaskLinkChoice(this.link, {this.eventIds = const []});
  final TaskLink? link;
  final List<String> eventIds;

  /// The events of the choice: [eventIds], or [link]'s event alone.
  List<String> get linkedEventIds {
    final link = this.link;
    if (link == null || link.type != TaskLinkType.event) return const [];
    return [link.id, ...eventIds.where((id) => id != link.id)];
  }
}

/// Shown in the picker while no event is marked: nothing is saved then.
const String noEventMarkedHint = 'צריך לסמן לפחות אירוע אחד (או "ללא שיוך"). השיוך הקודם נשמר.';

/// An existing task's events, saved as they are marked (Omer, 16/11/2026:
/// no save button). [onChanged] gets every marked set, in the list's order
/// (nearest first), even an empty one ([saver] refuses it and says so);
/// after a refused save the marks go back to [saved].
class LiveEventsLink {
  const LiveEventsLink({required this.onChanged, required this.saver, required this.saved});
  final ValueChanged<List<String>> onChanged;
  final DebouncedSaver<TaskLinkChoice> saver;
  final List<String> Function() saved;
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
/// בשבצק" of a placeholder), one event.
///
/// Otherwise several events can be picked (16/11/2026): a tap on an event,
/// on its box or on its name alike, marks it, and nothing is chosen until
/// "שיוך לאירוע" / "שיוך ל-N אירועים" (Omer, 16/11/2026: one way for both).
/// A category, a topic or a placeholder is still picked by a tap.
/// [initialEventIds] = the events marked when it opens.
///
/// [allowNewPending]: whether a new "אירוע שעוד לא נוצר" can be named here;
/// the filter's picker cannot (Omer, 16/11/2026: filtering creates nothing).
///
/// [liveEvents] (an existing task's link): no "שיוך ל-N אירועים" button;
/// each mark is saved through it, and "ביטול" becomes "סגירה". A new task's
/// form keeps the button: there nothing is saved until "שמירה".
Future<TaskLinkChoice?> showTaskLinkPicker(
  BuildContext context, {
  TaskLink? initial,
  List<String> initialEventIds = const [],
  bool allowNone = true,
  bool eventsOnly = false,
  bool multiEvents = true,
  bool allowNewPending = true,
  String? title,
  LiveEventsLink? liveEvents,
}) {
  return showDialog<TaskLinkChoice>(
    context: context,
    builder: (_) => BlocProvider.value(
      value: context.read<TeamTaskBloc>(),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: _TaskLinkPicker(
          initial: initial,
          initialEventIds: initialEventIds,
          allowNone: allowNone && !eventsOnly,
          eventsOnly: eventsOnly,
          multiEvents: multiEvents && !eventsOnly,
          allowNewPending: allowNewPending,
          title: title,
          live: multiEvents && !eventsOnly ? liveEvents : null,
        ),
      ),
    ),
  );
}

class _TaskLinkPicker extends StatefulWidget {
  const _TaskLinkPicker({
    this.initial,
    this.initialEventIds = const [],
    required this.allowNone,
    this.eventsOnly = false,
    this.multiEvents = true,
    this.allowNewPending = true,
    this.title,
    this.live,
  });

  final LiveEventsLink? live;

  final TaskLink? initial;
  final List<String> initialEventIds;
  final bool allowNone;
  final bool eventsOnly;

  /// Several events can be marked (a task's link; not the filter's).
  final bool multiEvents;

  /// "אירוע שעוד לא נוצר" can be named here (not in the filter).
  final bool allowNewPending;
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

  /// The events marked for a task of several events, in the order marked.
  late final List<String> _marked = [
    if (widget.multiEvents)
      if (widget.initialEventIds.isNotEmpty)
        ...widget.initialEventIds
      else if (widget.initial?.type == TaskLinkType.event)
        widget.initial!.id,
  ];

  void _toggleMarked(String id) {
    setState(() {
      if (!_marked.remove(id)) _marked.add(id);
    });
    final live = widget.live;
    if (live != null) live.onChanged(_sortedMarked(_options(_currentState()!)));
  }

  TeamTasksLoaded? _currentState() {
    final state = context.read<TeamTaskBloc>().state;
    return state is TeamTasksLoaded ? state : null;
  }

  int _seenRevision = 0;

  @override
  void initState() {
    super.initState();
    widget.live?.saver.addListener(_onSaver);
  }

  /// A refused save: the marks go back to what is saved.
  void _onSaver() {
    final live = widget.live;
    if (live == null || !mounted) return;
    if (live.saver.revision != _seenRevision) {
      _seenRevision = live.saver.revision;
      _marked
        ..clear()
        ..addAll(live.saved());
    }
    setState(() {});
  }

  /// The marked events in the list's order (nearest first).
  List<String> _sortedMarked(
      List<({TaskLinkType type, String id, String name, String? note})> options) {
    final order = [for (final option in options) option.id];
    return [..._marked]..sort((a, b) {
        final ia = order.indexOf(a);
        final ib = order.indexOf(b);
        return (ia < 0 ? order.length : ia).compareTo(ib < 0 ? order.length : ib);
      });
  }

  /// Confirms the marked events, in the list's order (nearest first).
  void _confirmMarked(List<({TaskLinkType type, String id, String name, String? note})> options) {
    final ids = _sortedMarked(options);
    Navigator.of(context)
        .pop(TaskLinkChoice(TaskLink(TaskLinkType.event, ids.first), eventIds: ids));
  }

  @override
  void dispose() {
    widget.live?.saver.removeListener(_onSaver);
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
        final linkable = linkableEvents(state.events, DateTime.now());
        // An ended event the task already has stays on the list, marked.
        final events = [
          for (final event in state.events)
            if (_marked.contains(event.id) && !linkable.contains(event)) event,
          ...linkable,
        ];
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
    final showPending = widget.allowNewPending &&
        !widget.eventsOnly &&
        _type == TaskLinkType.event &&
        state.canManage &&
        query.isEmpty;
    final multi = widget.multiEvents && _type == TaskLinkType.event;
    final live = multi && widget.live != null;
    final allOptions = _options(state);
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
                            current: _marked.isEmpty &&
                                widget.initial == TaskLink(option.type, option.id),
                            marked: multi && option.type == TaskLinkType.event
                                ? _marked.contains(option.id)
                                : null,
                            onMark: () => _toggleMarked(option.id),
                            // An event of a task's link is marked, never
                            // picked at once: the button saves (16/11/2026),
                            // or, for an existing task, the mark itself.
                            onTap: multi && option.type == TaskLinkType.event
                                ? () => _toggleMarked(option.id)
                                : (multi && _marked.isNotEmpty
                                    ? null
                                    : () => Navigator.of(context).pop(
                                        TaskLinkChoice(TaskLink(option.type, option.id)))),
                          ),
                      ],
                    ),
            ),
            if (live && widget.live!.saver.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  noEventMarkedHint,
                  key: const Key('task-link-no-event-hint'),
                  style: TextStyle(
                      fontSize: 13, color: Theme.of(context).colorScheme.error),
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
        if (multi && !live && _marked.isNotEmpty)
          FilledButton(
            key: const Key('task-link-confirm-events'),
            onPressed: () => _confirmMarked(allOptions),
            child: Text(_marked.length == 1 ? 'שיוך לאירוע' : 'שיוך ל-${_marked.length} אירועים'),
          ),
        if (widget.allowNone)
          TextButton(
            key: const Key('task-link-none'),
            onPressed: () => Navigator.of(context).pop(const TaskLinkChoice(null)),
            child: const Text('ללא שיוך'),
          ),
        TextButton(
          key: const Key('task-link-close'),
          onPressed: () => Navigator.of(context).pop(),
          // Marked events are already saved: closing cancels nothing.
          child: Text(widget.live != null ? 'סגירה' : 'ביטול'),
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
    this.marked,
    this.onMark,
  });

  final String name;
  final String? note;
  final bool current;
  final VoidCallback? onTap;

  /// An event of a task of several events: whether its box is marked; null
  /// = no box.
  final bool? marked;
  final VoidCallback? onMark;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsetsDirectional.fromSTEB(marked == null ? 12 : 0, 11, 12, 11),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: TaskStyle.editRowLine)),
        ),
        child: Row(
          children: [
            if (marked != null)
              Checkbox(
                key: key is ValueKey<String>
                    ? Key('${(key as ValueKey<String>).value}-mark')
                    : null,
                value: marked,
                visualDensity: VisualDensity.compact,
                onChanged: (_) => onMark?.call(),
              ),
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
