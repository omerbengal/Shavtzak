// Widget tests for CalendarFeedDialog covering two specific hazards flagged
// in review:
//
// - completing an in-flight ensureCalendarFeedToken request AFTER the
//   dialog has already been disposed must not throw. The mounted guards
//   are easy to get right today and easy to silently break later, and this
//   is the one path unit/manual testing can't catch reliably.
// - isAdminView: false must not expose the admin-only "שלח בוואטסאפ" /
//   "אפס קישור" actions.
//
// Both tests go through the public showCalendarFeedDialog entry point
// (CalendarFeedDialog's implementation is private to its own file), wiring
// a real TeamRepository around a mocked DatabaseInterface — TeamRepository
// is a thin concrete wrapper, so no TeamRepository mock is needed.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shavtzak/data/data_sources/database_interface.dart';
import 'package:shavtzak/data/repositories/team_repository.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/widgets/calendar_feed_dialog.dart';

import 'calendar_feed_dialog_test.mocks.dart';

@GenerateMocks([DatabaseInterface])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testMember = TeamMember(
    id: 'member-1',
    name: 'בודק/ת',
    isActive: true,
    constraints: const [],
    roleCapabilities: const {},
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
    uniqueKey: 'uk-1',
  );

  late MockDatabaseInterface mockDb;
  late TeamRepository teamRepository;

  setUp(() {
    mockDb = MockDatabaseInterface();
    teamRepository = TeamRepository(mockDb);
  });

  Future<void> pumpTestApp(
    WidgetTester tester, {
    required bool isAdminView,
  }) async {
    await tester.pumpWidget(
      RepositoryProvider<TeamRepository>.value(
        value: teamRepository,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showCalendarFeedDialog(
                    context,
                    member: testMember,
                    isAdminView: isAdminView,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'completing ensureCalendarFeedToken after the dialog is disposed does not throw',
    (tester) async {
      final completer = Completer<String>();
      when(mockDb.ensureCalendarFeedToken(any))
          .thenAnswer((_) => completer.future);

      await pumpTestApp(tester, isAdminView: false);
      await tester.tap(find.text('open'));
      // Deliberately NOT pumpAndSettle(): the loading state renders an
      // indeterminate CircularProgressIndicator, whose ticker animates
      // forever and would make pumpAndSettle() time out. Fast-forward past
      // the dialog's entrance transition with a bounded pump instead.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Dismiss the dialog by tapping the modal barrier (showDialog
      // defaults to barrierDismissible: true), then fast-forward past the
      // exit transition so the dialog's State is actually disposed while
      // ensureCalendarFeedToken is still unresolved.
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(CircularProgressIndicator), findsNothing);

      completer.complete('tok-123');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'isAdminView: false hides the WhatsApp and reset-link actions',
    (tester) async {
      when(mockDb.ensureCalendarFeedToken(any))
          .thenAnswer((_) async => 'tok-123');

      await pumpTestApp(tester, isAdminView: false);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Sanity: the dialog actually reached its ready state, so the
      // absence of the admin actions below isn't just a stuck spinner.
      expect(find.text('הוסף ליומן'), findsOneWidget);

      expect(find.text('שלח בוואטסאפ'), findsNothing);
      expect(find.text('אפס קישור'), findsNothing);
    },
  );
}
