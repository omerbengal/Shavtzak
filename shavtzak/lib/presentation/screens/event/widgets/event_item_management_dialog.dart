import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/debug/logger.dart';
import '../../../../core/utils/crud_action_result.dart';
import '../../../../core/utils/rtl_text_field_utils.dart';
import '../../../../domain/entities/event_item.dart';
import '../../../bloc/event/event_bloc.dart';
import '../../../bloc/event/event_state.dart';
import '../../../bloc/event_item/event_item_bloc.dart';
import '../../../bloc/event_item/event_item_event.dart';
import '../../../bloc/event_item/event_item_state.dart';
import '../../../widgets/loading_overlay.dart';

/// "ניהול מה יש באירוע": the list of things an event can have (name + emoji),
/// managed like the categories: add, edit (tap), reorder (drag), archive,
/// restore from the archive, delete for good.
class EventItemManagementDialog extends StatefulWidget {
  const EventItemManagementDialog({super.key});

  static const addButtonKey = ValueKey('event-item-add');

  @override
  State<EventItemManagementDialog> createState() =>
      _EventItemManagementDialogState();
}

class _EventItemManagementDialogState extends State<EventItemManagementDialog> {
  bool _showArchive = false;
  bool _isLoading = false;

  /// The order a drag left, shown until the stream brings it back.
  List<EventItem>? _pendingOrder;

  Future<void> _mutate(
    EventItemEvent Function(CrudActionCompleter completion) build,
  ) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    final completion = CrudActionCompleter();
    context.read<EventItemBloc>().add(build(completion));
    final result = await completion.future;
    if (!mounted) return;
    setState(() => _isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result.message ?? (result.isSuccess ? 'נשמר' : 'שגיאה')),
      backgroundColor: result.isSuccess ? null : Colors.red,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          Dialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              width: MediaQuery.of(context).size.width * 0.9,
              constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _showArchive
                              ? 'ארכיון מה יש באירוע'
                              : 'ניהול מה יש באירוע',
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: Icon(_showArchive ? Icons.list : Icons.history),
                        tooltip: _showArchive
                            ? 'חזרה לרשימה הראשית'
                            : 'צפייה בארכיון',
                        onPressed: () {
                          Logger.action('toggle:eventItemArchive',
                              {'on': !_showArchive});
                          setState(() => _showArchive = !_showArchive);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: BlocConsumer<EventItemBloc, EventItemState>(
                      listener: (context, state) {
                        if (state is EventItemsLoaded && _pendingOrder != null) {
                          setState(() => _pendingOrder = null);
                        }
                      },
                      builder: (context, state) {
                        if (state is EventItemsLoaded) {
                          return _showArchive
                              ? _archiveView(state.archivedItems)
                              : _mainView(_pendingOrder ?? state.activeItems);
                        }
                        if (state is EventItemError) {
                          return Center(
                            child: Text('שגיאה בטעינת הרשימה\n${state.message}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.red)),
                          );
                        }
                        return const Center(child: CircularProgressIndicator());
                      },
                    ),
                  ),
                  if (!_showArchive)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          key: EventItemManagementDialog.addButtonKey,
                          onPressed: _add,
                          icon: const Icon(Icons.add),
                          label: const Text('הוספת פריט'),
                          style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.all(16)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          LoadingOverlay(isLoading: _isLoading, message: 'מעבד...'),
        ],
      ),
    );
  }

  Widget _mainView(List<EventItem> items) {
    if (items.isEmpty) {
      return const Center(child: Text('אין פריטים עדיין'));
    }
    return ReorderableListView.builder(
      buildDefaultDragHandles: true,
      itemCount: items.length,
      onReorder: (oldIndex, newIndex) {
        Logger.action('reorder:eventItem', {'from': oldIndex, 'to': newIndex});
        final reordered = List<EventItem>.from(items);
        if (newIndex > oldIndex) newIndex -= 1;
        reordered.insert(newIndex, reordered.removeAt(oldIndex));
        setState(() => _pendingOrder = reordered);
        context.read<EventItemBloc>().add(ReorderEventItems(reordered));
      },
      itemBuilder: (context, index) => KeyedSubtree(
        key: ValueKey(items[index].id),
        child: _tile(items[index], isArchived: false),
      ),
    );
  }

  Widget _archiveView(List<EventItem> items) {
    if (items.isEmpty) {
      return const Center(child: Text('אין פריטים בארכיון'));
    }
    return ListView(
      children: [for (final item in items) _tile(item, isArchived: true)],
    );
  }

  Widget _tile(EventItem item, {required bool isArchived}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: ListTile(
        leading: SizedBox(
          width: 32,
          child: Center(
            child: item.emoji != null
                ? Text(item.emoji!, style: const TextStyle(fontSize: 22))
                : Icon(Icons.label_outline, color: Colors.grey.shade500),
          ),
        ),
        title: Text(
          item.name,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isArchived ? Colors.grey : null,
          ),
        ),
        onTap: isArchived ? null : () => _edit(item),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: isArchived
              ? [
                  TextButton.icon(
                    onPressed: () {
                      Logger.action('tap:restoreEventItem', {'id': item.id});
                      _mutate((c) => RestoreEventItem(item.id, completion: c));
                    },
                    icon: const Icon(Icons.restore, size: 18),
                    label: const Text('שחזור'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                    tooltip: 'מחיקה לצמיתות',
                    onPressed: () => _confirmDelete(item),
                  ),
                ]
              : [
                  IconButton(
                    icon: const Icon(Icons.archive,
                        color: Colors.orange, size: 20),
                    tooltip: 'העברה לארכיון',
                    onPressed: () => _confirmArchive(item),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                    tooltip: 'מחיקה לצמיתות',
                    onPressed: () => _confirmDelete(item),
                  ),
                  // Room for the list's own drag handle.
                  const SizedBox(width: 24),
                ],
        ),
      ),
    );
  }

  Future<void> _add() async {
    Logger.action('open:addEventItem');
    final result = await showDialog<({String name, String? emoji})>(
      context: context,
      builder: (_) => const EventItemEditDialog(),
    );
    if (result == null || !mounted) return;
    await _mutate((c) => CreateEventItem(result.name, result.emoji, completion: c));
  }

  Future<void> _edit(EventItem item) async {
    Logger.action('open:editEventItem', {'id': item.id});
    final result = await showDialog<({String name, String? emoji})>(
      context: context,
      builder: (_) => EventItemEditDialog(initial: item),
    );
    if (result == null || !mounted) return;
    if (result.name == item.name && result.emoji == item.emoji) return;
    await _mutate((c) => UpdateEventItem(
          item.copyWith(name: result.name, emoji: () => result.emoji),
          completion: c,
        ));
  }

  /// How many events have [item] (from the events already loaded).
  int _eventsWith(EventItem item) {
    final state = context.read<EventBloc>().state;
    if (state is! EventsLoaded) return 0;
    return state.events
        .where((event) => event.items.any((c) => c.itemId == item.id))
        .length;
  }

  Future<void> _confirmArchive(EventItem item) async {
    final ok = await _confirm(
      title: 'העברה לארכיון?',
      body: 'להעביר את "${item.name}" לארכיון?\n\n'
          'הוא לא יוצע יותר לאירועים, אבל יישאר באירועים שכבר יש בהם אותו. '
          'אפשר לשחזר מהארכיון.',
      action: 'העברה לארכיון',
    );
    if (ok) await _mutate((c) => DeleteEventItem(item.id, completion: c));
  }

  Future<void> _confirmDelete(EventItem item) async {
    final count = _eventsWith(item);
    final ok = await _confirm(
      title: 'מחיקה לצמיתות?',
      body: 'למחוק את "${item.name}" לצמיתות?'
          '${count > 0 ? '\n\nהוא יוסר מ-$count אירועים שיש בהם אותו.' : ''}'
          '\n\nאי אפשר לבטל.',
      action: 'מחיקה',
      destructive: true,
    );
    if (ok) {
      await _mutate((c) => PermanentlyDeleteEventItem(item.id, completion: c));
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
    bool destructive = false,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('ביטול'),
            ),
            ElevatedButton(
              style: destructive
                  ? ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white)
                  : null,
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(action),
            ),
          ],
        ),
      ),
    );
    return confirmed == true && mounted;
  }
}

/// Add or edit one item: its name (up to 40 characters) and one emoji.
/// Returns the trimmed values, or null when cancelled.
class EventItemEditDialog extends StatefulWidget {
  static const nameKey = ValueKey('event-item-name');
  static const emojiKey = ValueKey('event-item-emoji');
  static const saveKey = ValueKey('event-item-save');

  /// Longest name the backend keeps.
  static const maxNameLength = 40;

  final EventItem? initial;

  const EventItemEditDialog({super.key, this.initial});

  @override
  State<EventItemEditDialog> createState() => _EventItemEditDialogState();
}

class _EventItemEditDialogState extends State<EventItemEditDialog> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _emoji = TextEditingController(text: widget.initial?.emoji ?? '');
  late final FocusNode _nameFocus = createRtlCursorFixedFocusNode(_name);

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _emoji.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  String get _trimmedName => _name.text.trim();

  void _save() {
    if (_trimmedName.isEmpty) return;
    final emoji = _emoji.text.trim();
    Navigator.of(context).pop((
      name: _trimmedName.characters
          .take(EventItemEditDialog.maxNameLength)
          .toString(),
      emoji: emoji.isEmpty ? null : emoji.characters.first,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(widget.initial == null ? 'פריט חדש' : 'עריכת פריט'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: EventItemEditDialog.nameKey,
              controller: _name,
              focusNode: _nameFocus,
              autofocus: true,
              maxLength: EventItemEditDialog.maxNameLength,
              decoration: const InputDecoration(
                labelText: 'שם',
                hintText: 'למשל: סריקה, חנוכייה, להקה',
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 8),
            TextField(
              key: EventItemEditDialog.emojiKey,
              controller: _emoji,
              decoration: const InputDecoration(
                labelText: "אמוג'י",
                hintText: "אמוג'י אחד (לא חובה)",
              ),
              onSubmitted: (_) => _save(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            key: EventItemEditDialog.saveKey,
            onPressed: _trimmedName.isEmpty ? null : _save,
            child: const Text('שמירה'),
          ),
        ],
      ),
    );
  }
}
