import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shavtzak/core/services/drive_service.dart';
import 'package:shavtzak/data/data_sources/database_interface.dart';
import 'package:shavtzak/data/repositories/event_repository.dart';
import 'package:shavtzak/domain/entities/event.dart';

import 'event_repository_reconcile_test.mocks.dart';

@GenerateMocks([DatabaseInterface, DriveService])
void main() {
  late MockDatabaseInterface db;
  late MockDriveService drive;
  late EventRepository repo;

  Event buildEvent({String? driveFolderId}) => Event(
        id: 'e1',
        name: 'אירוע',
        startDate: DateTime(2026, 5, 1),
        endDate: DateTime(2026, 5, 1),
        startTime: '10:00',
        endTime: '12:00',
        assemblyTime: '09:00',
        requiresArmed: false,
        roleRequirements: const {},
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        driveFolderId: driveFolderId,
      );

  void stubCreateFolder(Future<CreateFolderResult> Function() answer) {
    when(drive.createFolder(
      eventName: anyNamed('eventName'),
      date: anyNamed('date'),
      endDate: anyNamed('endDate'),
    )).thenAnswer((_) => answer());
  }

  setUp(() {
    db = MockDatabaseInterface();
    drive = MockDriveService();
    repo = EventRepository(db, driveService: drive);
    when(db.updateEvent(any)).thenAnswer((_) async {});
  });

  test('creates a folder and persists the id when one is missing', () async {
    when(drive.isInitialized).thenReturn(true);
    stubCreateFolder(() async => const CreateFolderResult(
          success: true,
          folderId: 'folder-1',
          folderLink: 'link-1',
        ));

    final result = await repo.ensureDriveFolder(buildEvent());

    expect(result?.success, isTrue);
    verify(db.updateEvent(argThat(predicate<Event>(
      (e) => e.driveFolderId == 'folder-1' && e.driveFolderLink == 'link-1',
    )))).called(1);
  });

  test('returns null (skipped) when the event already has a folder', () async {
    when(drive.isInitialized).thenReturn(true);

    final result =
        await repo.ensureDriveFolder(buildEvent(driveFolderId: 'existing'));

    expect(result, isNull);
    verifyNever(drive.createFolder(
      eventName: anyNamed('eventName'),
      date: anyNamed('date'),
      endDate: anyNamed('endDate'),
    ));
    verifyNever(db.updateEvent(any));
  });

  test('returns null (skipped) when Drive is not initialized', () async {
    when(drive.isInitialized).thenReturn(false);

    final result = await repo.ensureDriveFolder(buildEvent());

    expect(result, isNull);
    verifyNever(drive.createFolder(
      eventName: anyNamed('eventName'),
      date: anyNamed('date'),
      endDate: anyNamed('endDate'),
    ));
    verifyNever(db.updateEvent(any));
  });

  test('returns the failed result (and persists nothing) when creation fails',
      () async {
    when(drive.isInitialized).thenReturn(true);
    stubCreateFolder(() async => const CreateFolderResult(
          success: false,
          error: 'boom',
          isNetworkError: true,
        ));

    final result = await repo.ensureDriveFolder(buildEvent());

    expect(result?.success, isFalse);
    expect(result?.error, 'boom');
    expect(result?.isNetworkError, isTrue);
    verifyNever(db.updateEvent(any));
  });

  test('does not start a second creation while one is already in flight',
      () async {
    when(drive.isInitialized).thenReturn(true);
    final gate = Completer<CreateFolderResult>();
    stubCreateFolder(() => gate.future);

    final event = buildEvent();
    final first = repo.ensureDriveFolder(event);
    final second = repo.ensureDriveFolder(event); // while first is pending

    gate.complete(const CreateFolderResult(
      success: true,
      folderId: 'folder-1',
      folderLink: 'link-1',
    ));
    await Future.wait([first, second]);

    verify(drive.createFolder(
      eventName: anyNamed('eventName'),
      date: anyNamed('date'),
      endDate: anyNamed('endDate'),
    )).called(1);
  });

  group('updateEvent', () {
    setUp(() {
      when(db.isDuplicateEvent(any, any,
              excludeEventId: anyNamed('excludeEventId')))
          .thenAnswer((_) async => false);
    });

    // Regression: the save used to await a one-shot getEventById() purely to
    // decide whether to background-rename the Drive folder. On a flaky
    // Firestore Web connection that .get() can park for ~30s (live snapshot
    // streams stay fast, but a fresh .get() stalls), freezing the whole save.
    // When the caller supplies the original event, no read must happen.
    test('does not re-fetch the original when the caller supplies it', () async {
      when(drive.isInitialized).thenReturn(false);
      // If updateEvent ever awaited getEventById, this would hang the save.
      final neverCompletes = Completer<Event?>();
      when(db.getEventById(any)).thenAnswer((_) => neverCompletes.future);

      final original = buildEvent(driveFolderId: 'folder-1');
      final renamed = original.copyWith(name: 'שם חדש');

      // Completes promptly despite getEventById never completing.
      await repo
          .updateEvent(renamed, knownOriginal: original)
          .timeout(const Duration(seconds: 2));

      verify(db.updateEvent(any)).called(1);
      verifyNever(db.getEventById(any));
    });

    test('renames the Drive folder when the supplied original changed name',
        () async {
      when(drive.isInitialized).thenReturn(true);
      when(drive.renameFolder(
        folderId: anyNamed('folderId'),
        newName: anyNamed('newName'),
        newDate: anyNamed('newDate'),
        newEndDate: anyNamed('newEndDate'),
      )).thenAnswer((_) async => true);

      final original = buildEvent(driveFolderId: 'folder-1');
      final renamed = original.copyWith(name: 'שם חדש');

      await repo.updateEvent(renamed, knownOriginal: original);

      verify(drive.renameFolder(
        folderId: 'folder-1',
        newName: 'שם חדש',
        newDate: anyNamed('newDate'),
        newEndDate: anyNamed('newEndDate'),
      )).called(1);
      verifyNever(db.getEventById(any));
    });

    test('does not rename the Drive folder when name and dates are unchanged',
        () async {
      when(drive.isInitialized).thenReturn(true);

      final original = buildEvent(driveFolderId: 'folder-1');
      final sameNameAndDate = original.copyWith(location: 'מיקום חדש');

      await repo.updateEvent(sameNameAndDate, knownOriginal: original);

      verifyNever(drive.renameFolder(
        folderId: anyNamed('folderId'),
        newName: anyNamed('newName'),
        newDate: anyNamed('newDate'),
        newEndDate: anyNamed('newEndDate'),
      ));
    });
  });
}
