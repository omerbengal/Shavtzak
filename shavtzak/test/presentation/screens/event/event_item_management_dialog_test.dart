import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/data/repositories/event_item_repository.dart';
import 'package:shavtzak/domain/entities/event_item.dart';
import 'package:shavtzak/presentation/bloc/event/event_bloc.dart';
import 'package:shavtzak/presentation/bloc/event/event_event.dart';
import 'package:shavtzak/presentation/bloc/event/event_state.dart';
import 'package:shavtzak/presentation/bloc/event_item/event_item_bloc.dart';
import 'package:shavtzak/presentation/bloc/event_item/event_item_event.dart';
import 'package:shavtzak/presentation/screens/event/widgets/event_item_management_dialog.dart';

/// Records every write; the list it streams never changes.
class _FakeRepository implements EventItemRepository {
  final List<EventItem> items;
  final List<String> calls = [];

  _FakeRepository(this.items);

  @override
  Stream<List<EventItem>> watchEventItems() => Stream.value(items);

  @override
  Future<EventItem> createEventItem(String name, String? emoji,
      {required int nextSortOrder}) async {
    calls.add('create $name ${emoji ?? '-'} $nextSortOrder');
    return items.first;
  }

  @override
  Future<void> updateEventItem(EventItem item) async =>
      calls.add('update ${item.id} ${item.name} ${item.emoji ?? '-'}');

  @override
  Future<void> deleteEventItem(String id) async => calls.add('archive $id');

  @override
  Future<void> permanentlyDeleteEventItem(String id) async =>
      calls.add('delete $id');

  @override
  Future<void> restoreEventItem(String id) async => calls.add('restore $id');

  @override
  Future<void> reorderEventItems(List<EventItem> items) async =>
      calls.add('reorder');
}

class _MockEventBloc extends MockBloc<EventEvent, EventState>
    implements EventBloc {}

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
  late _FakeRepository repository;

  Future<void> pump(WidgetTester tester) async {
    repository = _FakeRepository([
      _item('scan', 'סריקה', '🤳🏻', 0),
      _item('old', 'זיקוקים', '🎆', 1, archived: true),
    ]);
    final bloc = EventItemBloc(repository)..add(const LoadEventItems());
    addTearDown(bloc.close);
    final events = _MockEventBloc();
    whenListen(events, const Stream<EventState>.empty(),
        initialState: const EventInitial());
    await tester.pumpWidget(MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider<EventItemBloc>.value(value: bloc),
          BlocProvider<EventBloc>.value(value: events),
        ],
        child: const Scaffold(body: EventItemManagementDialog()),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('lists the active items with their emoji', (tester) async {
    await pump(tester);
    expect(find.text('ניהול מה יש באירוע'), findsOneWidget);
    expect(find.text('סריקה'), findsOneWidget);
    expect(find.text('🤳🏻'), findsOneWidget);
    expect(find.text('זיקוקים'), findsNothing);
  });

  testWidgets('adds an item with a name and one emoji', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(EventItemManagementDialog.addButtonKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(EventItemEditDialog.nameKey), ' להקה ');
    await tester.enterText(find.byKey(EventItemEditDialog.emojiKey), '🎸🎺');
    await tester.tap(find.byKey(EventItemEditDialog.saveKey));
    await tester.pumpAndSettle();

    // Placed after every item, archived ones included.
    expect(repository.calls, ['create להקה 🎸 2']);
  });

  testWidgets('tapping an item edits it', (tester) async {
    await pump(tester);
    await tester.tap(find.text('סריקה'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(EventItemEditDialog.emojiKey), '');
    await tester.tap(find.byKey(EventItemEditDialog.saveKey));
    await tester.pumpAndSettle();

    expect(repository.calls, ['update scan סריקה -']);
  });

  testWidgets('the archive shows archived items and restores them',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('צפייה בארכיון'));
    await tester.pumpAndSettle();
    expect(find.text('זיקוקים'), findsOneWidget);
    await tester.tap(find.text('שחזור'));
    await tester.pumpAndSettle();
    expect(repository.calls, ['restore old']);
  });
}
