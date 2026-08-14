// Widget tests for AssignmentExportDialog.
//
// Regression guard for a crash found by manual smoke testing: switching to the
// "לפי אירוע" tab threw
//   RenderShrinkWrappingViewport does not support returning intrinsic dimensions
// AlertDialog always wraps its column in an IntrinsicWidth (see Flutter's
// material/dialog.dart), so any intrinsic query that reaches a
// ListView(shrinkWrap: true) inside the dialog's content explodes.
//
// These tests pump the dialog for real and assert no exception escapes.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shavtzak/core/services/export_service.dart';
import 'package:shavtzak/data/repositories/event_repository.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/presentation/bloc/category/category_bloc.dart';
import 'package:shavtzak/presentation/bloc/category/category_event.dart';
import 'package:shavtzak/presentation/bloc/category/category_state.dart';
import 'package:shavtzak/presentation/widgets/assignment_export_dialog.dart';

import 'assignment_export_dialog_test.mocks.dart';

class MockCategoryBloc extends MockBloc<CategoryEvent, CategoryState>
    implements CategoryBloc {}

@GenerateMocks([EventRepository])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockEventRepository eventRepo;
  late MockCategoryBloc categoryBloc;

  Event event({
    required String id,
    required DateTime start,
    String name = 'אירוע',
  }) {
    final now = DateTime(2026, 1, 1);
    return Event(
      id: id,
      name: name,
      startDate: start,
      endDate: start,
      startTime: '18:00',
      endTime: '22:00',
      assemblyTime: '17:00',
      location: 'מיקום',
      requiresArmed: false,
      roleRequirements: const {'medic': 1},
      createdAt: now,
      updatedAt: now,
    );
  }

  setUp(() {
    eventRepo = MockEventRepository();
    categoryBloc = MockCategoryBloc();
    const categoryState = CategoriesLoaded(
      activeCategories: [],
      archivedCategories: [],
    );
    whenListen(
      categoryBloc,
      const Stream<CategoryState>.empty(),
      initialState: categoryState,
    );
  });

  Future<void> pumpDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      RepositoryProvider<EventRepository>.value(
        value: eventRepo,
        child: BlocProvider<CategoryBloc>.value(
          value: categoryBloc,
          child: MaterialApp(
            home: Scaffold(
              body: AssignmentExportDialog(
                onExport: (AssignmentExportMode mode, List<String> ids) async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('per-event tab renders without throwing, with past and future events',
      (tester) async {
    final today = DateTime.now();
    when(eventRepo.getAllEvents()).thenAnswer((_) async => [
          event(id: 'future', start: today.add(const Duration(days: 7))),
          event(id: 'past', start: today.subtract(const Duration(days: 7))),
        ]);

    await pumpDialog(tester);

    // Switch to the לפי אירוע segment.
    await tester.tap(find.text('לפי אירוע'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('expanding the past-events section does not throw', (tester) async {
    final today = DateTime.now();
    when(eventRepo.getAllEvents()).thenAnswer((_) async => [
          event(id: 'future', start: today.add(const Duration(days: 7))),
          event(id: 'past', start: today.subtract(const Duration(days: 7))),
        ]);

    await pumpDialog(tester);
    await tester.tap(find.text('לפי אירוע'));
    await tester.pumpAndSettle();

    final pastHeader = find.textContaining('אירועים שעברו');
    await tester.ensureVisible(pastHeader);
    await tester.pumpAndSettle();
    await tester.tap(pastHeader);
    await tester.pumpAndSettle();

    // Guard against a vacuous pass: the section must really have expanded.
    expect(find.byIcon(Icons.expand_less), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded past section does not overflow on a phone viewport',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final today = DateTime.now();
    when(eventRepo.getAllEvents()).thenAnswer((_) async => [
          for (var i = 1; i <= 15; i++)
            event(
              id: 'future-$i',
              start: today.add(Duration(days: i)),
              name: 'עתידי $i',
            ),
          for (var i = 1; i <= 15; i++)
            event(
              id: 'past-$i',
              start: today.subtract(Duration(days: i)),
              name: 'עבר $i',
            ),
        ]);

    await pumpDialog(tester);
    await tester.tap(find.text('לפי אירוע'));
    await tester.pumpAndSettle();

    // The future list must be capped by the viewport budget (screen height
    // 640 - 360 chrome = 280), not grow to fit all 15 events.
    expect(
      tester.getSize(find.byType(ListView).first).height,
      lessThanOrEqualTo(280.0),
    );

    final pastHeader = find.textContaining('אירועים שעברו');
    await tester.ensureVisible(pastHeader);
    await tester.pumpAndSettle();
    await tester.tap(pastHeader);
    await tester.pumpAndSettle();

    // Guard against a vacuous pass: the section must really have expanded.
    expect(find.byIcon(Icons.expand_less), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
