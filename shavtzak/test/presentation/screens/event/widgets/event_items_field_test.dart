import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/event_item.dart';
import 'package:shavtzak/presentation/screens/event/widgets/event_items_field.dart';

Event _past(List<EventItem> items) => Event(
      id: 'old',
      name: 'old',
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 1, 1),
      startTime: '',
      endTime: '',
      assemblyTime: '',
      requiresArmed: false,
      roleRequirements: const {},
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      items: items,
    );

void main() {
  late List<EventItem> current;

  Future<void> pump(WidgetTester tester, List<EventItem> items) async {
    current = items;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (context, setState) => EventItemsField(
              items: current,
              otherEvents: [
                _past(const [
                  EventItem(name: 'סריקה', emoji: '🤳🏻'),
                  EventItem(name: 'חנוכייה', emoji: '🕎'),
                ]),
              ],
              onChanged: (next) => setState(() => current = next),
            ),
          ),
        ),
      ),
    ));
  }

  testWidgets('typing offers an item from another event, with its emoji',
      (tester) async {
    await pump(tester, const []);

    await tester.enterText(find.byKey(EventItemsField.inputKey), 'סר');
    await tester.pump();
    await tester.tap(find.text('סריקה 🤳🏻'));
    await tester.pump();

    expect(current, const [EventItem(name: 'סריקה', emoji: '🤳🏻')]);
  });

  testWidgets('a new name is added without an emoji', (tester) async {
    await pump(tester, const []);

    await tester.enterText(find.byKey(EventItemsField.inputKey), 'להקה');
    await tester.pump();
    await tester.tap(find.text('הוספת "להקה" כחדש'));
    await tester.pump();

    expect(current, const [EventItem(name: 'להקה')]);
  });

  testWidgets('the emoji slot sets one emoji and can clear it',
      (tester) async {
    await pump(tester, const [EventItem(name: 'להקה')]);

    await tester.tap(find.byKey(const ValueKey('event-item-emoji-להקה')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(EventItemsField.emojiInputKey), '🎸🎺');
    await tester.tap(find.text('שמירה'));
    await tester.pumpAndSettle();
    expect(current, const [EventItem(name: 'להקה', emoji: '🎸')]);

    await tester.tap(find.byKey(const ValueKey('event-item-emoji-להקה')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('בלי אמוג\'י'));
    await tester.pumpAndSettle();
    expect(current, const [EventItem(name: 'להקה')]);
  });

  testWidgets('✕ removes an item', (tester) async {
    await pump(tester, const [
      EventItem(name: 'להקה'),
      EventItem(name: 'סריקה', emoji: '🤳🏻'),
    ]);

    await tester.tap(find.byKey(const ValueKey('event-item-remove-להקה')));
    await tester.pump();

    expect(current, const [EventItem(name: 'סריקה', emoji: '🤳🏻')]);
  });

  testWidgets('a name already on the event is not offered or added twice',
      (tester) async {
    await pump(tester, const [EventItem(name: 'סריקה', emoji: '🤳🏻')]);

    await tester.enterText(find.byKey(EventItemsField.inputKey), 'סריקה');
    await tester.pump();

    expect(find.text('הוספת "סריקה" כחדש'), findsNothing);
    // The chip shows the name and the emoji apart; no suggestion row.
    expect(find.text('סריקה 🤳🏻'), findsNothing);
  });
}
