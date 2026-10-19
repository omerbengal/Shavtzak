import 'package:flutter/material.dart';

import '../task_style.dart';

/// What the sheet holds: a title line and the body under it.
class SheetContent {
  const SheetContent({required this.header, required this.body});

  final Widget header;
  final Widget body;
}

/// The low sheet: where a stage, a list of results or a single task is read
/// and acted on.
///
/// It opens at about half the screen with no dark overlay, so what is above
/// it stays readable and tappable. Dragging up makes it taller; dragging it
/// down, or the X, closes it.
class TaskSheet extends StatefulWidget {
  const TaskSheet({
    super.key,
    required this.viewKey,
    required this.content,
    required this.onClose,
    this.onBack,
  });

  /// What is being shown; a new one starts the content at its top.
  final Object viewKey;

  final SheetContent content;
  final VoidCallback onClose;

  /// Back to the list a task was opened from; no arrow without it.
  final VoidCallback? onBack;

  @override
  State<TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends State<TaskSheet> {
  bool _closing = false;

  bool _onExtent(DraggableScrollableNotification notification) {
    if (!_closing && notification.extent < TaskStyle.sheetCloseBelow) {
      _closing = true;
      widget.onClose();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<DraggableScrollableNotification>(
      onNotification: _onExtent,
      child: DraggableScrollableSheet(
        initialChildSize: TaskStyle.sheetInitialSize,
        minChildSize: 0,
        maxChildSize: TaskStyle.sheetMaxSize,
        snap: true,
        snapSizes: const [TaskStyle.sheetInitialSize],
        builder: (context, scrollController) => Material(
          key: const Key('task-sheet'),
          color: Colors.white,
          elevation: 12,
          shadowColor: Colors.black54,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: CustomScrollView(
            key: ValueKey(widget.viewKey),
            controller: scrollController,
            slivers: [
              PinnedHeaderSliver(child: _buildHeader(context)),
              SliverToBoxAdapter(child: widget.content.body),
              SliverPadding(
                padding: EdgeInsets.only(
                  bottom: 24 + MediaQuery.paddingOf(context).bottom,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            key: const Key('task-sheet-handle'),
            height: 20,
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: TaskStyle.rest,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 4, 4),
            child: Row(
              children: [
                if (widget.onBack != null)
                  IconButton(
                    key: const Key('task-sheet-back'),
                    tooltip: 'חזרה',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: widget.onBack,
                  )
                else
                  const SizedBox(width: 12),
                Expanded(
                  child: DefaultTextStyle.merge(
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                    child: widget.content.header,
                  ),
                ),
                IconButton(
                  key: const Key('task-sheet-close'),
                  tooltip: 'סגירה',
                  icon: const Icon(Icons.close),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}
