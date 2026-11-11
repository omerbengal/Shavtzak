import 'package:flutter/material.dart';

import '../../../../core/utils/event_items.dart';
import '../../../../domain/entities/event_item.dart';

/// The event form's "מה יש באירוע" section.
///
/// A dropdown of checkboxes picks the event's items from [catalogue] (the
/// list kept in "ניהול מה יש באירוע"). Each picked item gets a row with its
/// name and emoji and two on/off buttons: "להציג בייצוא אירוע" (the event's
/// picture) and "להציג בייצוא לוח שנה" (the calendar picture). A new pick
/// starts with both on.
class EventItemsField extends StatelessWidget {
  static const dropdownKey = ValueKey('event-items-dropdown');

  final List<EventItemChoice> choices;

  /// Every item, archived ones included (an archived item an event already
  /// has stays on it; it is just not offered to new ones).
  final List<EventItem> catalogue;
  final ValueChanged<List<EventItemChoice>> onChanged;

  const EventItemsField({
    super.key,
    required this.choices,
    required this.catalogue,
    required this.onChanged,
  });

  static ValueKey<String> optionKey(String itemId) =>
      ValueKey('event-item-option-$itemId');
  static ValueKey<String> eventExportKey(String itemId) =>
      ValueKey('event-item-event-export-$itemId');
  static ValueKey<String> calendarExportKey(String itemId) =>
      ValueKey('event-item-calendar-export-$itemId');

  EventItemChoice? _choiceFor(String itemId) {
    for (final choice in choices) {
      if (choice.itemId == itemId) return choice;
    }
    return null;
  }

  void _toggle(EventItem item) {
    if (_choiceFor(item.id) != null) {
      onChanged(choices.where((c) => c.itemId != item.id).toList());
    } else {
      onChanged([...choices, EventItemChoice(itemId: item.id)]);
    }
  }

  void _update(EventItemChoice updated) {
    onChanged([
      for (final choice in choices)
        choice.itemId == updated.itemId ? updated : choice,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final picked = eventItemsOf(choices, catalogue);
    // Offered: every active item, plus archived ones this event already has.
    final offered = catalogue
        .where((item) => !item.isArchived || _choiceFor(item.id) != null)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MenuAnchor(
          style: const MenuStyle(
            maximumSize: WidgetStatePropertyAll(Size(double.infinity, 360)),
          ),
          menuChildren: [
            for (final item in offered)
              CheckboxMenuButton(
                key: optionKey(item.id),
                value: _choiceFor(item.id) != null,
                closeOnActivate: false,
                onChanged: (_) => _toggle(item),
                child: Text(
                  item.isArchived ? '${item.label} (בארכיון)' : item.label,
                ),
              ),
          ],
          builder: (context, controller, _) => InkWell(
            key: dropdownKey,
            borderRadius: BorderRadius.circular(4),
            onTap: offered.isEmpty
                ? null
                : () => controller.isOpen ? controller.close() : controller.open(),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'מה יש באירוע',
                border: const OutlineInputBorder(),
                suffixIcon: const Icon(Icons.arrow_drop_down),
                helperText: offered.isEmpty
                    ? 'אין פריטים עדיין. מוסיפים אותם ב"ניהול מה יש באירוע" במסך האירועים'
                    : null,
                helperMaxLines: 2,
              ),
              child: Text(
                picked.isEmpty ? 'בחירה' : 'נבחרו ${picked.length}',
                style: TextStyle(
                  color: picked.isEmpty ? Colors.grey.shade600 : null,
                ),
              ),
            ),
          ),
        ),
        for (final item in picked)
          _PickedItemRow(
            item: item,
            choice: _choiceFor(item.id)!,
            onChanged: _update,
            onRemove: () => _toggle(item),
          ),
      ],
    );
  }
}

class _PickedItemRow extends StatelessWidget {
  final EventItem item;
  final EventItemChoice choice;
  final ValueChanged<EventItemChoice> onChanged;
  final VoidCallback onRemove;

  const _PickedItemRow({
    required this.item,
    required this.choice,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(4, 6, 12, 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (item.emoji != null) ...[
                Text(item.emoji!, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  item.isArchived ? '${item.name} (בארכיון)' : item.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'הסרה מהאירוע',
                visualDensity: VisualDensity.compact,
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ExportToggle(
                key: EventItemsField.eventExportKey(item.id),
                label: 'להציג בייצוא אירוע',
                isOn: choice.showInEventExport,
                onTap: () => onChanged(choice.copyWith(
                    showInEventExport: !choice.showInEventExport)),
              ),
              _ExportToggle(
                key: EventItemsField.calendarExportKey(item.id),
                label: 'להציג בייצוא לוח שנה',
                isOn: choice.showInCalendarExport,
                onTap: () => onChanged(choice.copyWith(
                    showInCalendarExport: !choice.showInCalendarExport)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// On: light green with a dark green check. Off: a plain outlined button.
class _ExportToggle extends StatelessWidget {
  final String label;
  final bool isOn;
  final VoidCallback onTap;

  const _ExportToggle({
    super.key,
    required this.label,
    required this.isOn,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: isOn,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isOn ? Colors.green.shade50 : null,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isOn ? Colors.green.shade400 : Colors.grey.shade400,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isOn) ...[
                Icon(Icons.check, size: 16, color: Colors.green.shade800),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: isOn ? Colors.green.shade900 : Colors.grey.shade800,
                  fontWeight: isOn ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
