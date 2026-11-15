import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/utils/crud_action_result.dart';
import '../../../../core/utils/search_utils.dart';
import '../../../../domain/entities/team_task.dart';
import '../../../../domain/entities/task_topic.dart';
import '../../../bloc/team_task/team_task_bloc.dart';
import '../../../widgets/rtl_arrow_keys.dart';

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
  }
}

/// Picks what a task belongs to: an event, a category or a topic, in three
/// segments, with a search and, for topics, "נושא חדש".
Future<TaskLinkChoice?> showTaskLinkPicker(
  BuildContext context, {
  TaskLink? initial,
  bool allowNone = true,
}) {
  return showDialog<TaskLinkChoice>(
    context: context,
    builder: (_) => BlocProvider.value(
      value: context.read<TeamTaskBloc>(),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: _TaskLinkPicker(initial: initial, allowNone: allowNone),
      ),
    ),
  );
}

class _TaskLinkPicker extends StatefulWidget {
  const _TaskLinkPicker({this.initial, required this.allowNone});

  final TaskLink? initial;
  final bool allowNone;

  @override
  State<_TaskLinkPicker> createState() => _TaskLinkPickerState();
}

class _TaskLinkPickerState extends State<_TaskLinkPicker> {
  late TaskLinkType _type = widget.initial?.type ?? TaskLinkType.event;
  String _query = '';
  final TextEditingController _newTopic = TextEditingController();
  bool _addingTopic = false;
  String? _error;

  @override
  void dispose() {
    _newTopic.dispose();
    super.dispose();
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

  List<({String id, String name, String? note})> _options(TeamTasksLoaded state) {
    switch (_type) {
      case TaskLinkType.event:
        final events = [...state.events]..sort((a, b) => b.startDate.compareTo(a.startDate));
        return [
          for (final event in events)
            (
              id: event.id,
              name: event.name,
              note: '${event.startDate.day}.${event.startDate.month}.${event.startDate.year}',
            ),
        ];
      case TaskLinkType.category:
        return [
          for (final category in state.categories)
            if (!category.isArchived) (id: category.id, name: category.name, note: null),
        ];
      case TaskLinkType.topic:
        return [
          for (final topic in state.topics)
            if (!topic.isArchived) (id: topic.id, name: topic.name, note: null),
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
    return AlertDialog(
      title: const Text('שיוך המשימה'),
      content: SizedBox(
        width: 360,
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<TaskLinkType>(
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
              child: options.isEmpty
                  ? const Center(child: Text('אין מה להציג'))
                  : ListView(
                      children: [
                        for (final option in options)
                          ListTile(
                            key: Key('task-link-option-${option.id}'),
                            dense: true,
                            title: Text(option.name),
                            subtitle: option.note == null ? null : Text(option.note!),
                            selected: widget.initial == TaskLink(_type, option.id),
                            onTap: () => Navigator.of(context)
                                .pop(TaskLinkChoice(TaskLink(_type, option.id))),
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
