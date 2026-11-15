import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/debug/logger.dart';
import '../../../../core/utils/crud_action_result.dart';
import '../../../../domain/entities/task_topic.dart';
import '../../../bloc/team_task/team_task_bloc.dart';
import '../../../widgets/rtl_arrow_keys.dart';
import '../../task/task_style.dart';

/// "ניהול נושאים": add, rename, archive and restore the topics a team task
/// can belong to, like "ניהול קטגוריות". An archived topic stays on its tasks
/// and is no longer offered for new ones.
Future<void> showTopicManagementDialog(BuildContext context) {
  Logger.action('open:topicManagement');
  return showDialog<void>(
    context: context,
    builder: (_) => BlocProvider.value(
      value: context.read<TeamTaskBloc>(),
      child: const Directionality(
        textDirection: TextDirection.rtl,
        child: TopicManagementDialog(),
      ),
    ),
  );
}

class TopicManagementDialog extends StatefulWidget {
  const TopicManagementDialog({super.key});

  @override
  State<TopicManagementDialog> createState() => _TopicManagementDialogState();
}

class _TopicManagementDialogState extends State<TopicManagementDialog> {
  final TextEditingController _newName = TextEditingController();
  bool _showArchived = false;
  String? _error;

  @override
  void dispose() {
    _newName.dispose();
    super.dispose();
  }

  Future<void> _run(TeamTaskEvent Function(CrudActionCompleter) event) async {
    final completion = CrudActionCompleter();
    context.read<TeamTaskBloc>().add(event(completion));
    final result = await completion.future;
    if (!mounted) return;
    setState(() => _error = result.isFailure ? result.message : null);
  }

  Future<void> _add(List<TaskTopic> topics) async {
    final name = _newName.text.trim();
    if (name.isEmpty) return;
    if (topics.any((t) => t.name == name)) {
      setState(() => _error = 'כבר יש נושא בשם הזה');
      return;
    }
    _newName.clear();
    await _run((c) => CreateTaskTopic(
          TaskTopic(id: const Uuid().v4(), name: name, sortOrder: topics.length),
          completion: c,
        ));
  }

  Future<void> _rename(TaskTopic topic) async {
    final controller = TextEditingController(text: topic.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('שינוי שם הנושא'),
          content: RtlArrowKeys(
            child: TextField(
              key: const Key('topic-rename-field'),
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              onSubmitted: (value) => Navigator.of(context).pop(value),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('ביטול')),
            FilledButton(
              key: const Key('topic-rename-save'),
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('שמירה'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == topic.name) return;
    await _run((c) => UpdateTaskTopic(topic.copyWith(name: trimmed), completion: c));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TeamTaskBloc>().state;
    final topics = state is TeamTasksLoaded ? state.topics : const <TaskTopic>[];
    final shown = topics.where((t) => _showArchived || !t.isArchived).toList();
    return AlertDialog(
      title: const Text('ניהול נושאים'),
      content: SizedBox(
        width: 380,
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: RtlArrowKeys(
                    child: TextField(
                      key: const Key('topic-new-name'),
                      controller: _newName,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'נושא חדש',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _add(topics),
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('topic-add'),
                  tooltip: 'הוספה',
                  onPressed: () => _add(topics),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_error!, style: const TextStyle(color: TaskStyle.late)),
              ),
            SwitchListTile(
              key: const Key('topic-show-archived'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('להציג נושאים בארכיון'),
              value: _showArchived,
              onChanged: (value) => setState(() => _showArchived = value),
            ),
            Expanded(
              child: shown.isEmpty
                  ? const Center(child: Text('אין נושאים עדיין'))
                  : ListView(
                      children: [
                        for (final topic in shown)
                          ListTile(
                            key: Key('topic-row-${topic.id}'),
                            dense: true,
                            title: Text(
                              topic.name,
                              style: TextStyle(
                                color: topic.isArchived ? TaskStyle.faintText : null,
                              ),
                            ),
                            subtitle: topic.isArchived ? const Text('בארכיון') : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  key: Key('topic-rename-${topic.id}'),
                                  tooltip: 'שינוי שם',
                                  icon: const Icon(Icons.edit, size: 18),
                                  onPressed: () => _rename(topic),
                                ),
                                IconButton(
                                  key: Key(topic.isArchived
                                      ? 'topic-restore-${topic.id}'
                                      : 'topic-archive-${topic.id}'),
                                  tooltip: topic.isArchived ? 'שחזור' : 'העברה לארכיון',
                                  icon: Icon(
                                    topic.isArchived ? Icons.unarchive : Icons.archive_outlined,
                                    size: 18,
                                  ),
                                  onPressed: () => _run((c) => ArchiveTaskTopic(
                                        topic.id,
                                        archive: !topic.isArchived,
                                        completion: c,
                                      )),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('topic-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('סגירה'),
        ),
      ],
    );
  }
}
