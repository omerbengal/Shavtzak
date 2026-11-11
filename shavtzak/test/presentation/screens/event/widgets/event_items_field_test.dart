import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/domain/entities/event_item.dart';
import 'package:shavtzak/presentation/screens/event/widgets/event_items_field.dart';

EventItem _item(String id, String name, String? emoji, int order,
        {bool archived = false}) =>
    EventItem(
      id: id,
      name: name,
      emoji: emoji,
      sortOrder: order,
      isArchived: archived,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

final _scan = _item('scan', 'סריקה', '🤳🏻', 0);
final _band = _item('band', 'להקה', null, 1);
final _old = _item('old', 'זיקוקים', '🎆', 2, archived: true);
final _gone = _item('gone', 'ישן', null, 3, archived: true);

void main() {
  late List<EventItemChoice> choices;

  Future<void> pump(WidgetTester tester, List<EventItemChoice> initial) async {
    choices = initial;
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: EventItemsField(
                choices: choices,
                catalogue: [_scan, _band, _old, _gone],
                onChanged: (next) => setState(() => choices = next),
              ),
            ),
          ),
        ),
      ),
    ));
  }

  testWidgets('the dropdown offers active items and ticks add them, both switches on',
      (tester) async {
    await pump(tester, const []);
    expect(find.text('בחירה'), findsOneWidget);

    await tester.tap(find.byKey(EventItemsField.dropdownKey));
    await tester.pumpAndSettle();
    expect(find.byKey(EventItemsField.optionKey('scan')), findsWidgets);
    expect(find.byKey(EventItemsField.optionKey('band')), findsWidgets);
    // Archived items are not offered to an event that does not have them.
    expect(find.byKey(EventItemsField.optionKey('old')), findsNothing);

    await tester.tap(find.byKey(EventItemsField.optionKey('band')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(EventItemsField.optionKey('scan')).first);
    await tester.pumpAndSettle();

    expect(choices, const [
      EventItemChoice(itemId: 'band'),
      EventItemChoice(itemId: 'scan'),
    ]);
    expect(find.text('נבחרו 2'), findsOneWidget);
  });

  testWidgets('unticking removes the item', (tester) async {
    await pump(tester, const [EventItemChoice(itemId: 'scan')]);
    await tester.tap(find.byKey(EventItemsField.dropdownKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(EventItemsField.optionKey('scan')).first);
    await tester.pumpAndSettle();
    expect(choices, isEmpty);
  });

  testWidgets('each picked row shows name and emoji and flips its switches',
      (tester) async {
    await pump(tester, const [EventItemChoice(itemId: 'scan')]);
    expect(find.text('סריקה'), findsOneWidget);
    expect(find.text('🤳🏻'), findsOneWidget);
    expect(find.text('להציג בייצוא אירוע'), findsOneWidget);
    expect(find.text('להציג בייצוא לוח שנה'), findsOneWidget);
    // On = a check beside the label.
    expect(find.byIcon(Icons.check), findsNWidgets(2));

    await tester.tap(find.byKey(EventItemsField.calendarExportKey('scan')));
    await tester.pump();
    expect(choices, const [
      EventItemChoice(itemId: 'scan', showInCalendarExport: false),
    ]);
    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.tap(find.byKey(EventItemsField.eventExportKey('scan')));
    await tester.pump();
    expect(choices, const [
      EventItemChoice(
          itemId: 'scan', showInEventExport: false, showInCalendarExport: false),
    ]);
  });

  testWidgets('an archived item the event has stays, marked, and can be removed',
      (tester) async {
    await pump(tester, const [EventItemChoice(itemId: 'old')]);
    expect(find.text('זיקוקים (בארכיון)'), findsOneWidget);
    await tester.tap(find.byTooltip('הסרה מהאירוע'));
    await tester.pump();
    expect(choices, isEmpty);
  });

  testWidgets('with an empty list it says where items are added', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EventItemsField(
          choices: const [],
          catalogue: const [],
          onChanged: (_) {},
        ),
      ),
    ));
    expect(find.textContaining('ניהול מה יש באירוע'), findsOneWidget);
  });
}
