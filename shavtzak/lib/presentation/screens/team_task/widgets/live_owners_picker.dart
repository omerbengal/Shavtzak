import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/debounced_saver.dart';
import '../../../../domain/entities/team_member.dart';
import '../../../bloc/team_task/team_task_bloc.dart';
import '../../task/edit/value_editors.dart';

/// A task's owners, picked with no save button (Omer, 16/11/2026: "שינוי
/// של צ'קבוקס - ישר שומר"): every tick goes to [saver], which shows it on the
/// task at once and sends the whole selection a moment after the last tick.
/// Closing sends a change still waiting. A refused save puts the saved owners
/// back in the list.
///
/// Wide: a small dialog; phone: a sheet from the bottom, as [EditableValue].
Future<void> showLiveOwnersPicker(
  BuildContext context, {
  required String taskId,
  required bool wide,
  required List<TeamMember> offered,
  required DebouncedSaver<List<String>> saver,
}) async {
  final bloc = context.read<TeamTaskBloc>();
  Widget content(BuildContext _) => BlocProvider.value(
        value: bloc,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: _LiveOwners(taskId: taskId, offered: offered, saver: saver),
        ),
      );
  if (wide) {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Padding(
            padding: const EdgeInsets.only(top: 20),
            child: content(dialogContext),
          ),
        ),
      ),
    );
  } else {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: content,
    );
  }
  saver.flush();
}

class _LiveOwners extends StatelessWidget {
  const _LiveOwners({required this.taskId, required this.offered, required this.saver});

  final String taskId;
  final List<TeamMember> offered;
  final DebouncedSaver<List<String>> saver;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          key: const Key('live-owners-picker'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('אחראים', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            ListenableBuilder(
              listenable: saver,
              builder: (context, _) {
                // The list keeps its own ticks; it re-reads the task only
                // after a refused save ([DebouncedSaver.revision]).
                final state = context.read<TeamTaskBloc>().state;
                final task = state is TeamTasksLoaded ? state.taskById(taskId) : null;
                return AssigneesEditor(
                  key: ValueKey('live-owners-${saver.revision}'),
                  initial: task?.assigneeIds ?? const [],
                  offered: offered,
                  current: task?.owners ?? const [],
                  onChanged: saver.change,
                  emptyLabel: 'אין חברי צוות',
                  notOfferedLabel: 'כבר לא פעיל/ה בצוות',
                  pickedFirst: true,
                  showPermanentMark: true,
                );
              },
            ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                key: const Key('live-owners-close'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('סגירה'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
