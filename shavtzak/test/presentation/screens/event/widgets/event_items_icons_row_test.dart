import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/domain/entities/event_item.dart';
import 'package:shavtzak/presentation/bloc/event_item/event_item_bloc.dart';
import 'package:shavtzak/presentation/bloc/event_item/event_item_event.dart';
import 'package:shavtzak/presentation/bloc/event_item/event_item_state.dart';
import 'package:shavtzak/presentation/screens/event/widgets/event_items_icons_row.dart';

class _MockEventItemBloc extends MockBloc<EventItemEvent, EventItemState>
    implements EventItemBloc {}

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

void main() {
  Future<void> pump(
    WidgetTester tester,
    List<EventItemChoice> choices, {
    EventItemState state = const EventItemsLoaded(
      activeItems: [],
      archivedItems: [],
    ),
  }) async {
    final bloc = _MockEventItemBloc();
    whenListen(bloc, const Stream<EventItemState>.empty(), initialState: state);
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: BlocProvider<EventItemBloc>.value(
          value: bloc,
          child: Scaffold(body: EventItemsIconsRow(choices: choices)),
        ),
      ),
    ));
  }

  final loaded = EventItemsLoaded(
    activeItems: [
      _item('band', 'להקה', null, 2),
      _item('scan', 'סריקה', '🤳🏻', 0),
      _item('menorah', 'חנוכייה', '🕎', 1),
    ],
    archivedItems: [_item('old', 'זיקוקים', '🎆', 3, archived: true)],
  );

  Iterable<String> shown(WidgetTester tester) => tester
      .widgetList<Text>(find.descendant(
          of: find.byType(EventItemsIconsRow), matching: find.byType(Text)))
      .map((t) => t.data!);

  testWidgets('shows each item emoji, or its name, in the list order',
      (tester) async {
    await pump(
      tester,
      const [
        EventItemChoice(itemId: 'band'),
        EventItemChoice(itemId: 'scan'),
        EventItemChoice(itemId: 'old', showInEventExport: false),
      ],
      state: loaded,
    );
    expect(shown(tester), ['🤳🏻', 'להקה', '🎆']);
    // The name is there on hover / long press.
    expect(find.byTooltip('סריקה'), findsOneWidget);
  });

  testWidgets('an event with no items shows nothing', (tester) async {
    await pump(tester, const [], state: loaded);
    expect(shown(tester), isEmpty);
  });

  testWidgets('a deleted item, or a catalogue not loaded yet, shows nothing',
      (tester) async {
    await pump(tester, const [EventItemChoice(itemId: 'gone')], state: loaded);
    expect(shown(tester), isEmpty);

    await pump(tester, const [EventItemChoice(itemId: 'scan')],
        state: const EventItemInitial());
    expect(shown(tester), isEmpty);
  });
}
