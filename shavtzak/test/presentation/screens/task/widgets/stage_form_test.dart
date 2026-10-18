import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/crud_action_result.dart';
import 'package:shavtzak/core/utils/rtl_text_field_utils.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/stage.dart';
import 'package:shavtzak/presentation/screens/task/widgets/stage_form_modal.dart';

import '../../../../support/task_fixtures.dart';

/// What the stage form was given and did: the stages it asked to save, and
/// whether it closed.
class _Form {
  final saved = <Stage>[];
  CrudActionResult? saveResult = const CrudActionResult.success();
  Completer<CrudActionResult>? pendingSave;
  bool closed = false;

  Future<CrudActionResult> save(Stage stage) {
    saved.add(stage);
    final result = saveResult;
    if (result != null) return Future.value(result);
    return (pendingSave = Completer<CrudActionResult>()).future;
  }
}

void main() {
  final now = DateTime(2026, 10, 11, 14, 0);
  final twoDays = buildEvent(
    id: 'e1',
    startDate: DateTime(2026, 10, 20),
    endDate: DateTime(2026, 10, 21),
  );
  final oneDay = buildEvent(id: 'e2', startDate: DateTime(2026, 10, 25));

  Future<_Form> openForm(
    WidgetTester tester, {
    Stage? existing,
    Event? event,
  }) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final form = _Form();
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                await showStageFormModal(
                  context,
                  existing: existing,
                  event: event ?? twoDays,
                  onSave: form.save,
                  currentUserId: 'm-admin',
                  now: now,
                );
                form.closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return form;
  }

  final title = find.byKey(const Key('stage-form-title'));
  final saveButton = find.byKey(const Key('stage-form-save'));
  Finder timeField(String key) => find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(TextFormField),
      );

  bool saveEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(saveButton).enabled;

  Future<void> pickDay(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(const Key('stage-form-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
  }

  testWidgets('needs a title and a day before it can be saved', (tester) async {
    await openForm(tester);
    expect(saveEnabled(tester), isFalse);

    await tester.enterText(title, 'קליטה');
    await tester.pump();
    expect(saveEnabled(tester), isFalse);

    await pickDay(tester, '20/10/2026');
    expect(saveEnabled(tester), isTrue);
  });

  testWidgets('offers exactly the event\'s days, right to left',
      (tester) async {
    await openForm(tester);
    await tester.tap(find.byKey(const Key('stage-form-date')));
    await tester.pumpAndSettle();

    expect(find.text('20/10/2026'), findsWidgets);
    expect(find.text('21/10/2026'), findsWidgets);
    expect(find.text('22/10/2026'), findsNothing);
    expect(find.text('19/10/2026'), findsNothing);
    final label = tester.renderObject<RenderParagraph>(
      find.text('21/10/2026').last,
    );
    expect(label.textDirection, TextDirection.rtl);
  });

  testWidgets('a one-day event has its day picked already', (tester) async {
    await openForm(tester, event: oneDay);
    await tester.enterText(title, 'קליטה');
    await tester.pump();

    expect(saveEnabled(tester), isTrue);
  });

  testWidgets('saves every field, trimmed, with blank contact rows dropped',
      (tester) async {
    final form = await openForm(tester);
    await tester.enterText(title, '  קליטה ורישום  ');
    await pickDay(tester, '21/10/2026');
    await tester.enterText(timeField('stage-form-start'), '0800');
    await tester.enterText(timeField('stage-form-end'), '1045');
    await tester.enterText(
      find.byKey(const Key('stage-form-requirements')),
      'שני שולחנות בלובי',
    );
    await tester.enterText(
        find.byKey(const Key('stage-form-location')), 'לובי');
    await tester.enterText(find.byKey(const Key('stage-form-notes')), 'מוקדם');
    await tester.tap(find.byKey(const Key('stage-form-add-contact')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('stage-form-add-contact')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('stage-form-contact-name-0')),
      ' אבי ',
    );
    await tester.enterText(
      find.byKey(const Key('stage-form-contact-phone-0')),
      '050-1234567',
    );
    await tester.enterText(
      find.byKey(const Key('stage-form-contact-role-0')),
      'מנהל אירועים',
    );
    await tester.pump();
    await save(tester);

    final stage = form.saved.single;
    expect(stage.eventId, 'e1');
    expect(stage.id, isNotEmpty);
    expect(stage.title, 'קליטה ורישום');
    expect(stage.date, DateTime(2026, 10, 21));
    expect(stage.startTime, '08:00');
    expect(stage.endTime, '10:45');
    expect(stage.requirements, 'שני שולחנות בלובי');
    expect(stage.hotelLocation, 'לובי');
    expect(stage.notes, 'מוקדם');
    expect(stage.contacts, hasLength(1));
    expect(stage.contacts.single.name, 'אבי');
    expect(stage.contacts.single.phone, '050-1234567');
    expect(stage.contacts.single.role, 'מנהל אירועים');
    expect(form.closed, isTrue);
  });

  group('time rules', () {
    Future<_Form> fillBasics(WidgetTester tester) async {
      final form = await openForm(tester);
      await tester.enterText(title, 'קליטה');
      await pickDay(tester, '20/10/2026');
      return form;
    }

    final error = find.byKey(const Key('stage-form-time-error'));

    testWidgets('a single start time is fine', (tester) async {
      final form = await fillBasics(tester);
      await tester.enterText(timeField('stage-form-start'), '0800');
      await tester.pump();
      await save(tester);

      expect(form.saved.single.startTime, '08:00');
      expect(form.saved.single.endTime, isNull);
    });

    testWidgets('an end time without a start time is refused', (tester) async {
      final form = await fillBasics(tester);
      await tester.enterText(timeField('stage-form-end'), '1000');
      await tester.pump();
      await save(tester);

      expect(form.saved, isEmpty);
      expect(find.text('שעת סיום דורשת שעת התחלה.'), findsOneWidget);
    });

    testWidgets('an end time not after the start is refused', (tester) async {
      final form = await fillBasics(tester);
      await tester.enterText(timeField('stage-form-start'), '1000');
      await tester.enterText(timeField('stage-form-end'), '1000');
      await tester.pump();
      await save(tester);

      expect(form.saved, isEmpty);
      expect(
        find.text('שעת הסיום חייבת להיות אחרי שעת ההתחלה.'),
        findsOneWidget,
      );
    });

    testWidgets('an impossible time is refused, and editing clears the error',
        (tester) async {
      final form = await fillBasics(tester);
      await tester.enterText(timeField('stage-form-start'), '9300');
      await tester.pump();
      await save(tester);

      expect(form.saved, isEmpty);
      expect(error, findsOneWidget);

      await tester.enterText(timeField('stage-form-start'), '0930');
      await tester.pump();
      expect(error, findsNothing);
    });
  });

  group('contacts', () {
    testWidgets('a contact with a phone but no name is refused',
        (tester) async {
      final form = await openForm(tester, event: oneDay);
      await tester.enterText(title, 'קליטה');
      await tester.tap(find.byKey(const Key('stage-form-add-contact')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('stage-form-contact-phone-0')),
        '050',
      );
      await tester.pump();
      await save(tester);

      expect(form.saved, isEmpty);
      expect(find.text('לכל איש קשר נדרש שם.'), findsOneWidget);
    });

    testWidgets('a phone not in the team-member format is refused',
        (tester) async {
      final form = await openForm(tester, event: oneDay);
      await tester.enterText(title, 'קליטה');
      await tester.tap(find.byKey(const Key('stage-form-add-contact')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('stage-form-contact-name-0')),
        'אבי',
      );
      await tester.enterText(
        find.byKey(const Key('stage-form-contact-phone-0')),
        '0721234',
      );
      await tester.pump();
      await save(tester);

      expect(form.saved, isEmpty);
      expect(
          find.byKey(const Key('stage-form-contacts-error')), findsOneWidget);
    });

    testWidgets('a phone is formatted as typed, like a team member\'s',
        (tester) async {
      await openForm(tester, event: oneDay);
      await tester.tap(find.byKey(const Key('stage-form-add-contact')));
      await tester.pump();
      final phone = find.byKey(const Key('stage-form-contact-phone-0'));

      await tester.enterText(phone, '0501234567');
      await tester.pump();
      expect(tester.widget<TextField>(phone).controller!.text, '050-1234567');

      await tester.enterText(phone, 'abc');
      await tester.pump();
      expect(tester.widget<TextField>(phone).controller!.text, '');
    });

    testWidgets('name and phone sit side by side, the role below them',
        (tester) async {
      await openForm(tester, event: oneDay);
      await tester.tap(find.byKey(const Key('stage-form-add-contact')));
      await tester.pump();
      final name =
          tester.getRect(find.byKey(const Key('stage-form-contact-name-0')));
      final role =
          tester.getRect(find.byKey(const Key('stage-form-contact-role-0')));
      final phone =
          tester.getRect(find.byKey(const Key('stage-form-contact-phone-0')));

      expect(name.top, phone.top);
      expect(name.center.dx, greaterThan(phone.center.dx),
          reason: 'right to left: the name comes first, on the right');
      expect(role.top, greaterThan(name.bottom));
    });

    testWidgets('the start time field is on the right, the end on the left',
        (tester) async {
      await openForm(tester, event: oneDay);
      final start = tester.getRect(find.byKey(const Key('stage-form-start')));
      final end = tester.getRect(find.byKey(const Key('stage-form-end')));

      expect(start.top, end.top);
      expect(start.center.dx, greaterThan(end.center.dx),
          reason: 'right to left: the start time comes first, on the right');
    });

    testWidgets('a removed contact is not saved', (tester) async {
      final existing = buildStage(
        id: 's1',
        eventId: 'e1',
        date: DateTime(2026, 10, 20),
        contacts: const [
          StageContact(id: 'c1', name: 'אבי'),
          StageContact(id: 'c2', name: 'דנה'),
        ],
      );
      final form = await openForm(tester, existing: existing);

      await tester.tap(find.byKey(const Key('stage-form-contact-remove-0')));
      await tester.pump();
      await save(tester);

      expect(form.saved.single.contacts.map((contact) => contact.id), ['c2']);
    });
  });

  group('editing', () {
    final existing = buildStage(
      id: 's1',
      eventId: 'e1',
      title: 'קליטה',
      date: DateTime(2026, 10, 20),
      startTime: '08:00',
      endTime: '10:45',
      notes: 'מוקדם',
    );

    testWidgets('starts from the stage and saves only once something changed',
        (tester) async {
      final form = await openForm(tester, existing: existing);
      expect(tester.widget<TextField>(title).controller!.text, 'קליטה');
      expect(saveEnabled(tester), isFalse);

      await tester.enterText(title, 'קליטה ורישום');
      await tester.pump();
      expect(saveEnabled(tester), isTrue);
      await tester.enterText(title, 'קליטה');
      await tester.pump();
      expect(saveEnabled(tester), isFalse);

      await tester.enterText(timeField('stage-form-end'), '');
      await tester.pump();
      await save(tester);

      final saved = form.saved.single;
      expect(saved.id, 's1');
      expect(saved.startTime, '08:00');
      expect(saved.endTime, isNull);
      expect(saved.notes, 'מוקדם');
    });

    testWidgets('a stage left outside the moved event must get a new day',
        (tester) async {
      final stranded = existing.copyWith(date: DateTime(2026, 10, 15));
      final form = await openForm(tester, existing: stranded);

      expect(
        find.textContaining('התאריך הקודם (15/10/2026) אינו מתאריכי האירוע'),
        findsOneWidget,
      );
      await tester.enterText(title, 'קליטה ורישום');
      await tester.pump();
      expect(saveEnabled(tester), isFalse);

      await pickDay(tester, '21/10/2026');
      await save(tester);
      expect(form.saved.single.date, DateTime(2026, 10, 21));
    });
  });

  group('saving and leaving', () {
    testWidgets('shows a spinner until the backend answers, then closes',
        (tester) async {
      final form = await openForm(tester, event: oneDay);
      form.saveResult = null;
      await tester.enterText(title, 'קליטה');
      await tester.pump();

      await tester.tap(saveButton);
      await tester.pump();
      expect(
        find.descendant(
            of: saveButton, matching: find.byType(CircularProgressIndicator)),
        findsOneWidget,
      );
      expect(form.closed, isFalse);

      form.pendingSave!.complete(const CrudActionResult.success());
      await tester.pumpAndSettle();
      expect(form.closed, isTrue);
    });

    testWidgets('a refused save stays open with the reason', (tester) async {
      final form = await openForm(tester, event: oneDay);
      form.saveResult =
          const CrudActionResult.failure('התאריך אינו מתאריכי האירוע');
      await tester.enterText(title, 'קליטה');
      await tester.pump();
      await save(tester);

      expect(form.closed, isFalse);
      expect(find.text('התאריך אינו מתאריכי האירוע'), findsOneWidget);
      expect(saveEnabled(tester), isTrue);
    });

    testWidgets('cancel on an untouched form closes at once', (tester) async {
      final form = await openForm(tester);
      await tester.tap(find.byKey(const Key('stage-form-cancel')));
      await tester.pumpAndSettle();
      expect(form.closed, isTrue);
    });

    testWidgets('cancel with something typed asks first', (tester) async {
      final form = await openForm(tester);
      await tester.enterText(title, 'קליטה');
      await tester.pump();

      await tester.tap(find.byKey(const Key('stage-form-cancel')));
      await tester.pumpAndSettle();
      expect(form.closed, isFalse);

      await tester.tap(find.byKey(const Key('stage-form-discard-leave')));
      await tester.pumpAndSettle();
      expect(form.closed, isTrue);
      expect(form.saved, isEmpty);
    });
  });

  testWidgets('the Hebrew text fields carry the RTL caret fix', (tester) async {
    await openForm(tester);
    await tester.tap(find.byKey(const Key('stage-form-add-contact')));
    await tester.pump();

    for (final key in const [
      'stage-form-title',
      'stage-form-requirements',
      'stage-form-location',
      'stage-form-notes',
      'stage-form-contact-name-0',
      'stage-form-contact-role-0',
    ]) {
      expect(
        tester.widget<TextField>(find.byKey(Key(key))).focusNode,
        isA<RtlCursorFixedFocusNode>(),
        reason: key,
      );
    }
  });
}
