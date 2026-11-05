import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../task_style.dart';

/// Builds the editor for one value. [onChanged] reports the draft as it is
/// typed; [onSubmit] asks to save it (Enter, or picking from a list).
typedef EditorBuilder<T> = Widget Function(
  BuildContext context,
  T draft,
  ValueChanged<T> onChanged,
  VoidCallback onSubmit,
);

/// One value of the editing screen: shown as [display], and edited on a
/// click.
///
/// On a wide window the editor takes the value's place: Enter or a click
/// anywhere else saves, Esc cancels. On a phone a tap opens the editor in a
/// sheet from the bottom with "שמירה" and "ביטול", since the keyboard hides
/// half the screen.
///
/// A draft equal to [value] saves nothing. [validate] keeps the editor open
/// with its message. A saved draft goes to [onCommit] at once; the screen
/// shows it and reports a refusal.
class EditableValue<T> extends StatefulWidget {
  const EditableValue({
    super.key,
    required this.value,
    required this.display,
    required this.sheetTitle,
    required this.wide,
    required this.editor,
    required this.onCommit,
    this.validate,
    this.expand = true,
  });

  final T value;
  final Widget display;

  /// The sheet's heading on a phone, such as "שם המשימה".
  final String sheetTitle;
  final bool wide;
  final EditorBuilder<T> editor;
  final ValueChanged<T> onCommit;
  final String? Function(T draft)? validate;

  /// Whether the value fills its cell's width; false for one sitting in a
  /// line with others, such as the stage's day.
  final bool expand;

  @override
  State<EditableValue<T>> createState() => _EditableValueState<T>();
}

bool _same(Object? a, Object? b) => const DeepCollectionEquality().equals(a, b);

class _EditableValueState<T> extends State<EditableValue<T>> {
  bool _editing = false;
  bool _hover = false;
  late T _draft;
  String? _error;

  void _start() {
    if (widget.wide) {
      setState(() {
        _editing = true;
        _draft = widget.value;
        _error = null;
      });
    } else {
      _openSheet();
    }
  }

  void _cancel() => setState(() {
        _editing = false;
        _error = null;
      });

  void _save() {
    if (!_editing) return;
    if (_same(_draft, widget.value)) {
      _cancel();
      return;
    }
    final error = widget.validate?.call(_draft);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final draft = _draft;
    setState(() {
      _editing = false;
      _error = null;
    });
    widget.onCommit(draft);
  }

  /// A click outside saves, except while a dialog or a drop-down this editor
  /// opened is on top: those clicks belong to it.
  void _onTapOutside(PointerDownEvent _) {
    if (ModalRoute.of(context)?.isCurrent == false) return;
    _save();
  }

  Future<void> _openSheet() async {
    final saved = await showModalBottomSheet<_Saved<T>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _EditSheet<T>(
        title: widget.sheetTitle,
        initial: widget.value,
        editor: widget.editor,
        validate: widget.validate,
      ),
    );
    if (saved == null || !mounted) return;
    if (_same(saved.value, widget.value)) return;
    widget.onCommit(saved.value);
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) return _buildEditor(context);
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _start,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: TaskStyle.editValuePadding(wide: widget.wide),
          decoration: BoxDecoration(
            color: _hover ? TaskStyle.editHover : Colors.transparent,
            borderRadius: BorderRadius.circular(TaskStyle.editRadius),
          ),
          child: Row(
            mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.expand)
                Expanded(child: widget.display)
              else
                Flexible(child: widget.display),
              // The pencil keeps its room, so hovering moves nothing.
              SizedBox(
                width: TaskStyle.editPencilSize + 4,
                child: Opacity(
                  opacity: _hover && widget.wide ? 1 : 0,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(start: 4),
                    child: Icon(
                      Icons.edit,
                      size: TaskStyle.editPencilSize,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditor(BuildContext context) {
    final theme = Theme.of(context);
    return TapRegion(
      onTapOutside: _onTapOutside,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _cancel,
        },
        child: Container(
          key: const Key('edit-value-editor'),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(TaskStyle.editRadius),
            boxShadow: TaskStyle.editRing,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              widget.editor(
                context,
                _draft,
                (next) => setState(() {
                  _draft = next;
                  _error = null;
                }),
                _save,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _error!,
                    key: const Key('edit-value-error'),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the phone sheet hands back on "שמירה"; null is "ביטול".
class _Saved<T> {
  const _Saved(this.value);
  final T value;
}

class _EditSheet<T> extends StatefulWidget {
  const _EditSheet({
    required this.title,
    required this.initial,
    required this.editor,
    required this.validate,
  });

  final String title;
  final T initial;
  final EditorBuilder<T> editor;
  final String? Function(T draft)? validate;

  @override
  State<_EditSheet<T>> createState() => _EditSheetState<T>();
}

class _EditSheetState<T> extends State<_EditSheet<T>> {
  late T _draft = widget.initial;
  String? _error;

  void _save() {
    final error = widget.validate?.call(_draft);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(_Saved<T>(_draft));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            key: const Key('edit-value-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              widget.editor(
                context,
                _draft,
                (next) => setState(() {
                  _draft = next;
                  _error = null;
                }),
                _save,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _error!,
                    key: const Key('edit-value-error'),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      key: const Key('edit-value-save'),
                      onPressed: _save,
                      child: const Text('שמירה'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('edit-value-cancel'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('ביטול'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
