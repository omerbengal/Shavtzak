import 'package:flutter/material.dart';

import 'team_task_style.dart';

/// Lets the team tasks list open a task in its side panel instead of a sheet
/// (wide window, Omer round 7). [showTeamTaskSheet] looks for it above the
/// tapped row: found = the task opens (or replaces the one) in the panel.
class TeamTaskPanelScope extends InheritedWidget {
  const TeamTaskPanelScope({
    super.key,
    required this.open,
    required this.close,
    required super.child,
  });

  /// Shows the task with this id in the panel.
  final ValueChanged<String> open;

  /// Closes the panel; the list slides back.
  final VoidCallback close;

  /// The scope above [context], or null (a phone, or outside the list).
  static TeamTaskPanelScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<TeamTaskPanelScope>();

  @override
  bool updateShouldNotify(TeamTaskPanelScope oldWidget) => false;
}

/// The list and, while a task is open, its panel (round 7): the list slides
/// to the right edge, narrowed, and the panel slides in from the left, both
/// animated. Closed, the list takes the whole width again.
class TeamTaskSplitView extends StatefulWidget {
  const TeamTaskSplitView({
    super.key,
    required this.list,
    required this.openTaskId,
    required this.panelBuilder,
  });

  final Widget list;

  /// The task in the panel; null = closed.
  final String? openTaskId;

  /// The panel's content for a task id (the task sheet).
  final Widget Function(BuildContext context, String taskId) panelBuilder;

  /// The list's width beside the panel, out of [width].
  static double listWidthFor(double width) {
    final share = width * TeamTaskStyle.splitListShare;
    return share.clamp(TeamTaskStyle.splitListMinWidth, TeamTaskStyle.maxListWidth).toDouble();
  }

  @override
  State<TeamTaskSplitView> createState() => _TeamTaskSplitViewState();
}

class _TeamTaskSplitViewState extends State<TeamTaskSplitView> {
  /// What the panel shows: kept while it slides out after closing.
  String? _shown;

  @override
  void initState() {
    super.initState();
    _shown = widget.openTaskId;
  }

  @override
  void didUpdateWidget(TeamTaskSplitView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.openTaskId != null) _shown = widget.openTaskId;
  }

  @override
  Widget build(BuildContext context) {
    final open = widget.openTaskId != null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final listWidth = TeamTaskSplitView.listWidthFor(width);
        final panelWidth = width - listWidth;
        final shown = _shown;
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // Positions are physical: the list on the right, the panel on the
            // left (an RTL screen).
            AnimatedPositioned(
              key: const Key('team-task-split-list'),
              duration: TeamTaskStyle.splitDuration,
              curve: TeamTaskStyle.splitCurve,
              top: 0,
              bottom: 0,
              right: 0,
              width: open ? listWidth : width,
              child: widget.list,
            ),
            AnimatedPositioned(
              duration: TeamTaskStyle.splitDuration,
              curve: TeamTaskStyle.splitCurve,
              top: 0,
              bottom: 0,
              left: open ? 0 : -panelWidth,
              width: panelWidth,
              onEnd: () {
                if (widget.openTaskId == null && _shown != null) {
                  setState(() => _shown = null);
                }
              },
              child: shown == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
                      child: Material(
                        key: const Key('team-task-side-panel'),
                        elevation: 3,
                        clipBehavior: Clip.antiAlias,
                        borderRadius: BorderRadius.circular(12),
                        child: KeyedSubtree(
                          key: ValueKey(shown),
                          child: widget.panelBuilder(context, shown),
                        ),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}
