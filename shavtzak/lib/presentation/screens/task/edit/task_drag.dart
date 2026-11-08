import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../domain/entities/task_item.dart';
import '../task_style.dart';
import 'edit_context.dart';
import 'edit_rules.dart';

/// The editing screen's drags besides moving a task to another stage:
///
/// * a task dropped on another task of its stage due at the same moment takes
///   its place among them ([TaskReorderTarget]);
/// * a task's value (time, description, assignees, subtasks) dragged onto the
///   same value of another task of its stage is copied there
///   ([TaskFieldDragSource] and [TaskFieldDropTarget]).

/// What a dragged value carries: whose it is and which one.
class TaskFieldDrag {
  const TaskFieldDrag(this.task, this.field);

  final TaskItem task;
  final TaskField field;
}

/// A value that can be dragged onto another task. A finger starts the drag
/// with a long press, so a tap still edits and a swipe still scrolls; on a
/// wide window the mouse also starts it by moving a few pixels with the
/// button held, so a plain click still edits. An empty value has nothing to
/// give and does not drag.
class TaskFieldDragSource extends StatelessWidget {
  const TaskFieldDragSource({
    super.key,
    required this.task,
    required this.field,
    required this.ctx,
    required this.child,
  });

  final TaskItem task;
  final TaskField field;
  final EditContext ctx;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (isTaskFieldEmpty(task, field)) return child;
    final data = TaskFieldDrag(task, field);
    final feedback = _ValueFeedback(field: field);
    final dragging = Opacity(opacity: 0.4, child: child);
    final key = Key('edit-field-drag-${field.name}-${task.id}');
    final mouse = !ctx.wide
        ? child
        : _SlopDraggable<TaskFieldDrag>(
            data: data,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: feedback,
            childWhenDragging: dragging,
            onDragUpdate: (details) => ctx.onDragMoved(details.globalPosition),
            onDragEnd: (_) => ctx.onDragDone(),
            child: child,
          );
    return LongPressDraggable<TaskFieldDrag>(
      key: key,
      data: data,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: feedback,
      childWhenDragging: dragging,
      onDragUpdate: (details) => ctx.onDragMoved(details.globalPosition),
      onDragEnd: (_) => ctx.onDragDone(),
      child: mouse,
    );
  }
}

/// The same value of another task, lit while a matching value is held over
/// it; a drop copies the value in (the screen asks first when this one is
/// not empty).
class TaskFieldDropTarget extends StatelessWidget {
  const TaskFieldDropTarget({
    super.key,
    required this.task,
    required this.field,
    required this.ctx,
    required this.child,
  });

  final TaskItem task;
  final TaskField field;
  final EditContext ctx;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DragTarget<TaskFieldDrag>(
      onWillAcceptWithDetails: (details) =>
          details.data.field == field &&
          canCopyField(details.data.task, task, field),
      onAcceptWithDetails: (details) =>
          ctx.onCopyField(details.data.task, task, field),
      builder: (context, candidates, _) {
        final lit = candidates.isNotEmpty;
        return AnimatedContainer(
          key: lit ? Key('edit-field-drop-${field.name}-${task.id}') : null,
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: lit ? TaskStyle.editDropTarget : Colors.transparent,
            borderRadius: BorderRadius.circular(TaskStyle.editRadius),
          ),
          // Drawn over the value, so lighting it moves nothing.
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TaskStyle.editRadius),
            border: Border.all(
              color: lit ? TaskStyle.editDropLine : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: child,
        );
      },
    );
  }
}

/// A task that another task of its stage, due at the same moment, can be
/// dropped on to take its place: above it when dropped on its top half,
/// below it on its bottom half. A line shows where it will land.
class TaskReorderTarget extends StatefulWidget {
  const TaskReorderTarget({
    super.key,
    required this.task,
    required this.ctx,
    required this.child,
  });

  final TaskItem task;
  final EditContext ctx;
  final Widget child;

  @override
  State<TaskReorderTarget> createState() => _TaskReorderTargetState();
}

class _TaskReorderTargetState extends State<TaskReorderTarget> {
  bool _after = false;

  bool _isAfter(Offset global) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    return box.globalToLocal(global).dy > box.size.height / 2;
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<TaskItem>(
      onWillAcceptWithDetails: (details) =>
          canReorderOnto(details.data, widget.task),
      onMove: (details) {
        final after = _isAfter(details.offset);
        if (after != _after) setState(() => _after = after);
      },
      onAcceptWithDetails: (details) => widget.ctx.onReorder(
        details.data,
        widget.task,
        _isAfter(details.offset),
      ),
      builder: (context, candidates, _) {
        if (candidates.isEmpty) return widget.child;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            widget.child,
            Positioned(
              key: Key(
                'edit-reorder-line-${_after ? 'after' : 'before'}-'
                '${widget.task.id}',
              ),
              left: TaskStyle.editTaskCardMargin,
              right: TaskStyle.editTaskCardMargin,
              top: _after ? null : 0,
              bottom: _after ? 0 : null,
              height: 3,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: TaskStyle.editDropLine,
                  borderRadius: BorderRadius.all(Radius.circular(2)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// What follows the pointer while a value is dragged.
class _ValueFeedback extends StatelessWidget {
  const _ValueFeedback({required this.field});

  final TaskField field;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        color: TaskStyle.editDropTarget,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.content_copy, size: 16),
              const SizedBox(width: 6),
              Text(field.label),
            ],
          ),
        ),
      ),
    );
  }
}

/// A [Draggable] for the mouse that starts only once the pointer has moved a
/// few pixels, in any direction, so a click on the same spot is still a
/// click. Fingers are left to the long press round it: on a touch screen a
/// swipe must scroll.
class _SlopDraggable<T extends Object> extends Draggable<T> {
  const _SlopDraggable({
    super.key,
    required super.child,
    required super.feedback,
    super.data,
    super.childWhenDragging,
    super.dragAnchorStrategy,
    super.onDragUpdate,
    super.onDragEnd,
  });

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) =>
      _SlopMultiDragGestureRecognizer(
        allowedButtonsFilter: allowedButtonsFilter,
      )..onStart = onStart;
}

class _SlopMultiDragGestureRecognizer extends MultiDragGestureRecognizer {
  _SlopMultiDragGestureRecognizer({super.allowedButtonsFilter})
      : super(debugOwner: null, supportedDevices: _mouseLike);

  static const Set<PointerDeviceKind> _mouseLike = {
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
  };

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) =>
      _SlopPointerState(event.position, event.kind, gestureSettings);

  @override
  String get debugDescription => 'slop multidrag';
}

class _SlopPointerState extends MultiDragPointerState {
  _SlopPointerState(super.initialPosition, super.kind, super.gestureSettings);

  /// A mouse counts 1 px as a move; a hand on a mouse shakes more than that
  /// while clicking.
  static const double _minSlop = 8;

  @override
  void checkForResolutionAfterMove() {
    final slop = math.max(computeHitSlop(kind, gestureSettings), _minSlop);
    if (pendingDelta!.distance > slop) {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    starter(initialPosition);
  }
}
