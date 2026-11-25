// Captures the REAL admin "ניהול אירועים" screen for the event-items story
// (V5.6.7: each event card shows what the event has, as emojis under the
// Drive / constraints icons, the name on long press). Made-up events.
// Not part of the test suite: run it on purpose, from shavtzak/:
//
//   flutter test tool/story_capture/event_items_capture_test.dart --update-goldens
//
// The PNGs land in tool/story_capture/out/event_items/ (git-ignored); copy
// them to feature_stories/public/event_items/. Emojis: Windows' Segoe UI
// Emoji as the theme's fallback font (the test renderer has none).
import 'dart:async';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shavtzak/core/theme/app_theme.dart';
import 'package:shavtzak/domain/entities/category.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/event_item.dart';
import 'package:shavtzak/presentation/bloc/category/category_bloc.dart';
import 'package:shavtzak/presentation/bloc/category/category_event.dart';
import 'package:shavtzak/presentation/bloc/category/category_state.dart';
import 'package:shavtzak/presentation/bloc/event/event_bloc.dart';
import 'package:shavtzak/presentation/bloc/event/event_event.dart';
import 'package:shavtzak/presentation/bloc/event/event_state.dart';
import 'package:shavtzak/presentation/bloc/event_item/event_item_bloc.dart';
import 'package:shavtzak/presentation/bloc/event_item/event_item_event.dart';
import 'package:shavtzak/presentation/bloc/event_item/event_item_state.dart';
import 'package:shavtzak/presentation/screens/event/event_list_screen.dart';
import 'package:shavtzak/presentation/screens/event/widgets/event_items_icons_row.dart';

import '../../test/support/task_fixtures.dart';
import 'capture_support.dart';

class _EventBloc extends MockBloc<EventEvent, EventState> implements EventBloc {}

class _CategoryBloc extends MockBloc<CategoryEvent, CategoryState>
    implements CategoryBloc {}

class _EventItemBloc extends MockBloc<EventItemEvent, EventItemState>
    implements EventItemBloc {}

final _at = DateTime(2026, 1, 1);

EventItem _item(String id, String name, String? emoji, int order) => EventItem(
    id: id, name: name, emoji: emoji, sortOrder: order, createdAt: _at, updatedAt: _at);

void main() {
  setUpAll(() async {
    await loadStoryFonts();
    // The browser falls back to the system emoji font; give the test
    // renderer one too (Windows' Segoe UI Emoji) so the emojis are real.
    final emoji = File('C:/Windows/Fonts/seguiemj.ttf').readAsBytesSync();
    await (FontLoader('StoryEmoji')
          ..addFont(Future.value(ByteData.view(emoji.buffer))))
        .load();
  });

  final catalogue = EventItemsLoaded(activeItems: [
    _item('menorah', 'חנוכייה', '🕎', 0),
    _item('donuts', 'סופגניות', '🍩', 1),
    _item('band', 'להקה', '🎸', 2),
    _item('mic', 'הגברה', '🎤', 3),
    _item('stage', 'במה', null, 4),
    _item('cake', 'עוגה', '🎂', 5),
  ], archivedItems: const []);

  final categories = CategoriesLoaded(activeCategories: [
    Category(id: 'c1', name: 'אירועי חנוכה', sortOrder: 0, createdAt: _at, updatedAt: _at),
    Category(id: 'c2', name: 'טקסים', sortOrder: 1, createdAt: _at, updatedAt: _at),
  ], archivedCategories: const []);

  List<EventItemChoice> pick(List<String> ids) =>
      [for (final id in ids) EventItemChoice(itemId: id)];

  List<Event> events({required bool withItems}) => [
        buildEvent(id: 'e1', name: 'הדלקת נרות בבסיס', startDate: DateTime(2026, 12, 6),
                location: 'בסיס צפון', categoryId: 'c1')
            .copyWith(items: withItems ? pick(['menorah', 'donuts', 'band', 'stage']) : []),
        buildEvent(id: 'e2', name: 'טקס סיום קורס', startDate: DateTime(2026, 12, 9),
                location: 'מחנה מרכז', categoryId: 'c2')
            .copyWith(items: withItems ? pick(['mic', 'stage']) : []),
        buildEvent(id: 'e3', name: 'מסיבת חנוכה למשפחות', startDate: DateTime(2026, 12, 13),
                location: 'אולם העיר', categoryId: 'c1')
            .copyWith(items: withItems ? pick(['menorah', 'donuts', 'cake']) : []),
        buildEvent(id: 'e4', name: 'ערב הוקרה', startDate: DateTime(2026, 12, 20),
                location: 'חיפה', categoryId: 'c2')
            .copyWith(items: withItems ? pick(['band', 'mic']) : []),
      ];

  Future<void> pumpScreen(WidgetTester tester, {required bool withItems}) async {
    // Real card shadows, not the test default's black outline.
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = true);
    await phone(tester);
    addTearDown(tester.view.reset);
    final eventBloc = _EventBloc();
    final categoryBloc = _CategoryBloc();
    final itemBloc = _EventItemBloc();
    when(eventBloc.watchCalendarSyncStates).thenAnswer((_) => const Stream.empty());
    whenListen(eventBloc, const Stream<EventState>.empty(),
        initialState: EventsLoaded(events(withItems: withItems)));
    whenListen(categoryBloc, const Stream<CategoryState>.empty(), initialState: categories);
    whenListen(itemBloc, const Stream<EventItemState>.empty(), initialState: catalogue);
    await tester.pumpWidget(MultiBlocProvider(
      providers: [
        BlocProvider<EventBloc>.value(value: eventBloc),
        BlocProvider<CategoryBloc>.value(value: categoryBloc),
        BlocProvider<EventItemBloc>.value(value: itemBloc),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme.copyWith(
          textTheme: AppTheme.lightTheme.textTheme
              .apply(fontFamilyFallback: const ['StoryEmoji']),
        ),
        debugShowCheckedModeBanner: false,
        home: const EventListScreen(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('event items: before / after / long press', (tester) async {
    await pumpScreen(tester, withItems: false);
    await capture(tester, 'event_items/01_before');

    await pumpScreen(tester, withItems: true);
    await capture(tester, 'event_items/02_after');
    final rows = find.byType(EventItemsIconsRow);
    for (var r = 0; r < tester.widgetList(rows).length; r++) {
      final texts = find.descendant(of: rows.at(r), matching: find.byType(Text));
      for (var i = 0; i < tester.widgetList(texts).length; i++) {
        final text = tester.widget<Text>(texts.at(i));
        mark(tester, 'row${r}_item${i}_${text.data}', texts.at(i));
      }
    }
    final cards = find.byType(Card);
    for (var c = 0; c < tester.widgetList(cards).length; c++) {
      mark(tester, 'card$c', cards.at(c));
    }

    // Long press on the first card's donuts: the name shows.
    await tester.longPress(find.descendant(of: rows.at(0), matching: find.text('🍩')));
    await tester.pump(const Duration(milliseconds: 400));
    await capture(tester, 'event_items/03_long_press');
    mark(tester, 'tooltip', find.text('סופגניות'));
    writePoints('event_items');
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
