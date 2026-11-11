import 'package:flutter/material.dart';

import '../../../../core/utils/event_items.dart';
import '../../../../core/utils/rtl_text_field_utils.dart';
import '../../../../domain/entities/event.dart';
import '../../../../domain/entities/event_item.dart';

/// The event form's "מה יש באירוע" section.
///
/// The items are chips: the name, a round emoji slot (tap to set, change or
/// clear it) and ✕. Below them a field: typing offers names already used on
/// [otherEvents] (with the emoji they last had, see [suggestEventItems]) and,
/// for a name not on this event yet, adding it as new.
class EventItemsField extends StatefulWidget {
  static const inputKey = ValueKey('event-items-input');
  static const emojiInputKey = ValueKey('event-item-emoji-input');

  /// Longest name the backend keeps.
  static const maxNameLength = 40;

  final List<EventItem> items;
  final List<Event> otherEvents;
  final ValueChanged<List<EventItem>> onChanged;

  const EventItemsField({
    super.key,
    required this.items,
    required this.otherEvents,
    required this.onChanged,
  });

  @override
  State<EventItemsField> createState() => _EventItemsFieldState();
}

class _EventItemsFieldState extends State<EventItemsField> {
  final _controller = TextEditingController();
  late final FocusNode _focusNode = createRtlCursorFixedFocusNode(_controller);

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String get _typed => _controller.text.trim();

  bool _isOnEvent(String name) =>
      widget.items.any((item) => item.name == name);

  void _add(EventItem item) {
    if (_isOnEvent(item.name)) return;
    widget.onChanged([...widget.items, item]);
    _controller.clear();
    setState(() {});
  }

  /// Enter adds the typed name: the suggestion with exactly that name when
  /// there is one (keeping its emoji), else as new.
  void _submit(List<EventItem> suggestions) {
    final name = _typed;
    if (name.isEmpty || _isOnEvent(name)) return;
    final exact = suggestions.where((item) => item.name == name);
    _add(exact.isNotEmpty ? exact.first : EventItem(name: name));
    _focusNode.requestFocus();
  }

  void _remove(EventItem item) {
    widget.onChanged(widget.items.where((i) => i.name != item.name).toList());
  }

  Future<void> _editEmoji(EventItem item) async {
    final result = await showDialog<_EmojiChoice>(
      context: context,
      builder: (context) => _EmojiDialog(item: item),
    );
    if (result == null || !mounted) return;
    widget.onChanged([
      for (final i in widget.items)
        if (i.name == item.name) i.copyWith(emoji: () => result.emoji) else i,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typed = _typed;
    final showSuggestions = typed.isNotEmpty || _focusNode.hasFocus;
    final suggestions = showSuggestions
        ? suggestEventItems(typed, widget.otherEvents, widget.items)
            .take(6)
            .toList()
        : const <EventItem>[];
    final canAddNew = typed.isNotEmpty &&
        !_isOnEvent(typed) &&
        !suggestions.any((item) => item.name == typed);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('מה יש באירוע', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (widget.items.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in widget.items) _chip(item, theme),
            ],
          ),
          const SizedBox(height: 10),
        ],
        TextField(
          key: EventItemsField.inputKey,
          controller: _controller,
          focusNode: _focusNode,
          maxLength: EventItemsField.maxNameLength,
          decoration: const InputDecoration(
            hintText: 'לדוגמה: סריקה, חנוכייה, להקה',
            prefixIcon: Icon(Icons.add_circle_outline),
            border: OutlineInputBorder(),
            counterText: '',
            isDense: true,
          ),
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(suggestions),
        ),
        if (suggestions.isNotEmpty || canAddNew)
          Card(
            margin: const EdgeInsets.only(top: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final item in suggestions)
                  ListTile(
                    dense: true,
                    title: Text(item.label),
                    subtitle: const Text('מאירועים קודמים'),
                    onTap: () => _add(item),
                  ),
                if (canAddNew)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.add),
                    title: Text('הוספת "$typed" כחדש'),
                    onTap: () => _add(EventItem(name: typed)),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _chip(EventItem item, ThemeData theme) {
    return Container(
      padding: const EdgeInsetsDirectional.only(start: 12, end: 4),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(item.name),
          const SizedBox(width: 6),
          Tooltip(
            message: item.emoji == null ? 'הוספת אמוג\'י' : 'שינוי אמוג\'י',
            child: InkWell(
              key: ValueKey('event-item-emoji-${item.name}'),
              customBorder: const CircleBorder(),
              onTap: () => _editEmoji(item),
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.dividerColor),
                ),
                child: item.emoji == null
                    ? Icon(Icons.add_reaction_outlined,
                        size: 18, color: theme.hintColor)
                    : Text(item.emoji!, style: const TextStyle(fontSize: 17)),
              ),
            ),
          ),
          IconButton(
            key: ValueKey('event-item-remove-${item.name}'),
            tooltip: 'הסרה',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => _remove(item),
          ),
        ],
      ),
    );
  }
}

/// What the emoji dialog decided: [emoji] null means "no emoji".
class _EmojiChoice {
  final String? emoji;
  const _EmojiChoice(this.emoji);
}

class _EmojiDialog extends StatefulWidget {
  final EventItem item;
  const _EmojiDialog({required this.item});

  @override
  State<_EmojiDialog> createState() => _EmojiDialogState();
}

class _EmojiDialogState extends State<_EmojiDialog> {
  late final _controller = TextEditingController(text: widget.item.emoji);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// One emoji: the first grapheme, so a skin-toned 🤳🏻 counts as one.
  String? get _emoji {
    final first = _controller.text.trim().characters.take(1).toString();
    return first.isEmpty ? null : first;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text('אמוג\'י ל${widget.item.name}'),
        content: TextField(
          key: EventItemsField.emojiInputKey,
          controller: _controller,
          autofocus: true,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 28),
          decoration: const InputDecoration(
            hintText: '🙂',
            helperText: 'אמוג\'י אחד מהמקלדת',
          ),
          onSubmitted: (_) =>
              Navigator.of(context).pop(_EmojiChoice(_emoji)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ביטול'),
          ),
          if (widget.item.emoji != null)
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(const _EmojiChoice(null)),
              child: const Text('בלי אמוג\'י'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_EmojiChoice(_emoji)),
            child: const Text('שמירה'),
          ),
        ],
      ),
    );
  }
}
