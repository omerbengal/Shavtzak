// Widget tests for CategoryManagementDialog's add/rename sub-dialogs.
//
// Bug: `_showAddCategoryDialog` and `_showRenameDialog` create a
// TextEditingController + RtlCursorFixedFocusNode as LOCAL variables and
// dispose them in `showDialog(...).then((_) { ... })`. That `.then` fires
// when the pop is INITIATED (Navigator.pop() completes the route's popped
// future on a microtask), but the dialog widget itself stays mounted through
// the ~150ms Material dialog exit transition. During that window the live
// TextField still holds the now-disposed controller/focus node, so any touch
// of them (web blur/focus events, or even framework/test code) throws
// "A RtlCursorFixedFocusNode was used after being disposed".
//
// This test proves the controller/focus node must stay alive for as long as
// the dialog widget is mounted (i.e. owned by State.dispose(), not by a
// showDialog().then() callback).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shavtzak/data/repositories/category_repository.dart';
import 'package:shavtzak/data/repositories/event_repository.dart';
import 'package:shavtzak/domain/entities/category.dart';
import 'package:shavtzak/presentation/bloc/category/category_bloc.dart';
import 'package:shavtzak/presentation/bloc/category/category_event.dart';
import 'package:shavtzak/presentation/screens/event/widgets/category_management_dialog.dart';

import 'category_management_dialog_test.mocks.dart';

@GenerateMocks([CategoryRepository, EventRepository])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 1, 1);
  final testCategory = Category(
    id: 'c1',
    name: 'קטגוריה לבדיקה',
    sortOrder: 0,
    createdAt: now,
    updatedAt: now,
  );

  late MockCategoryRepository categoryRepo;
  late MockEventRepository eventRepo;
  late StreamController<List<Category>> categoriesStream;
  late CategoryBloc categoryBloc;

  setUp(() {
    categoryRepo = MockCategoryRepository();
    eventRepo = MockEventRepository();

    // Single-subscription controller buffers events added before the bloc
    // subscribes, so the test has no add()-before-listen race.
    categoriesStream = StreamController<List<Category>>();
    when(categoryRepo.watchCategories())
        .thenAnswer((_) => categoriesStream.stream);

    categoryBloc = CategoryBloc(categoryRepo);
  });

  tearDown(() async {
    await categoriesStream.close();
    await categoryBloc.close();
  });

  Future<void> pumpTestApp(WidgetTester tester) async {
    await tester.pumpWidget(
      RepositoryProvider<EventRepository>.value(
        value: eventRepo,
        child: BlocProvider<CategoryBloc>.value(
          value: categoryBloc,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => const CategoryManagementDialog(),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // The bloc handler (emit.forEach over a real StreamController) settles via
  // real microtasks that tester.pump() alone won't flush — drive them under
  // runAsync, then pump to rebuild the tree with the settled bloc state.
  Future<void> emitCategories(
    WidgetTester tester,
    List<Category> data,
  ) async {
    await tester.runAsync(() async {
      categoriesStream.add(data);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'dialog resources stay alive during the exit transition',
    (tester) async {
      await pumpTestApp(tester);

      // The bloc dispatches nothing on its own until we ask it to — mirror
      // what main.dart does at startup by loading categories, then wait for
      // CategoriesLoaded before opening the dialog.
      categoryBloc.add(const LoadCategories());
      await emitCategories(tester, [testCategory]);

      // Open the CategoryManagementDialog.
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Open the add-category sub-dialog.
      await tester.tap(find.text('צור קטגוריה חדשה'));
      await tester.pumpAndSettle();

      final textFieldFinder = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'שם הקטגוריה',
      );
      expect(textFieldFinder, findsOneWidget);

      // Tap cancel to pop — the `.then()` disposal (if any) fires on the
      // microtask right after this, well before the exit transition ends.
      await tester.tap(find.text('ביטול'));

      // One frame to kick off the pop/exit transition...
      await tester.pump();
      // ...and 50ms into a ~150ms transition: the dialog widget (and its
      // TextField) must still be in the tree.
      await tester.pump(const Duration(milliseconds: 50));

      final midTransitionFinder = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'שם הקטגוריה',
      );
      expect(midTransitionFinder, findsOneWidget);

      final textField = tester.widget<TextField>(midTransitionFinder);
      final controller = textField.controller;
      final focusNode = textField.focusNode;

      // The controller/focus node backing the still-mounted TextField must
      // not have been disposed yet.
      expect(() => controller!.addListener(() {}), returnsNormally);
      expect(() => focusNode!.addListener(() {}), returnsNormally);

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
