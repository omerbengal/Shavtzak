import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/task_schedule.dart';
import 'package:shavtzak/domain/entities/stage.dart';

import '../../support/sample_event.dart';
import '../../support/task_fixtures.dart';

void main() {
  List<String> ids(Iterable<Stage> stages) =>
      stages.map((stage) => stage.id).toList();

  test('ltr wraps text in a left-to-right isolate', () {
    expect(ltr('14:30–17:00'), '\u206614:30–17:00\u2069');
  });

  group('stageSpan', () {
    test('a stage with both times runs from its start to its end', () {
      expect(
        stageSpan(stWorkshops, sampleStages),
        StageSpan(DateTime(2026, 10, 20, 14, 30), DateTime(2026, 10, 20, 17)),
      );
    });

    test('a start-only stage runs until the next stage starts, the next day too',
        () {
      expect(
        stageSpan(stDinner, sampleStages)!.end,
        DateTime(2026, 10, 21, 7, 30),
      );
    });

    test('the last start-only stage runs to the end of its day', () {
      final close = buildStage(id: 'close', date: sampleWed, startTime: '16:00');
      expect(
        stageSpan(close, [...sampleStages, close])!.end,
        DateTime(2026, 10, 22),
      );
    });

    test('an end that is not after the start counts as no end', () {
      final odd = buildStage(
        id: 'odd',
        date: sampleTue,
        startTime: '15:00',
        endTime: '15:00',
      );
      expect(
        stageSpan(odd, [odd, stDinner])!.end,
        DateTime(2026, 10, 20, 19, 30),
      );
    });

    test('no time, or a malformed one, means no span', () {
      expect(stageSpan(stRooms, sampleStages), isNull);
      expect(
        stageSpan(
          buildStage(id: 'bad', date: sampleTue, startTime: '9:00'),
          sampleStages,
        ),
        isNull,
      );
    });

    test('contains its start and not its end', () {
      final span = StageSpan(DateTime(2026, 10, 20, 9), DateTime(2026, 10, 20, 10));
      expect(span.contains(DateTime(2026, 10, 20, 9)), isTrue);
      expect(span.contains(DateTime(2026, 10, 20, 10)), isFalse);
    });
  });

  group('currentStages', () {
    test('is the stage running now', () {
      expect(ids(currentStages(sampleStages, sampleNow)), ['ws']);
    });

    test('is empty between stages', () {
      expect(
        currentStages(sampleStages, DateTime(2026, 10, 20, 14, 10)),
        isEmpty,
      );
    });

    test('starts on the start minute and stops on the end minute', () {
      expect(
        ids(currentStages(sampleStages, DateTime(2026, 10, 20, 14, 30))),
        ['ws'],
      );
      expect(currentStages(sampleStages, DateTime(2026, 10, 20, 17)), isEmpty);
    });

    test('overlapping stages are both current, in screen order', () {
      final talk = buildStage(
        id: 'talk',
        date: sampleTue,
        startTime: '14:00',
        endTime: '16:00',
      );
      expect(
        ids(currentStages([...sampleStages, talk], DateTime(2026, 10, 20, 15))),
        ['talk', 'ws'],
      );
    });
  });

  group('isStageOver', () {
    test('a timed stage is over once its span ends', () {
      expect(isStageOver(stLunch, sampleStages, sampleNow), isTrue);
      expect(isStageOver(stWorkshops, sampleStages, sampleNow), isFalse);
    });

    test('a stage with no time is over once its day is', () {
      expect(
        isStageOver(stRooms, sampleStages, DateTime(2026, 10, 20, 23)),
        isFalse,
      );
      expect(
        isStageOver(stRooms, sampleStages, DateTime(2026, 10, 21, 8)),
        isTrue,
      );
    });
  });

  group('timelineAnchor', () {
    test('is the current stage', () {
      expect(timelineAnchor(sampleStages, sampleNow)!.id, 'ws');
    });

    test('between stages it is the next timed one', () {
      expect(
        timelineAnchor(sampleStages, DateTime(2026, 10, 20, 14, 10))!.id,
        'ws',
      );
    });

    test('before the event it is the first timed stage', () {
      expect(
        timelineAnchor(sampleStages, DateTime(2026, 10, 19, 10))!.id,
        'setup',
      );
    });

    test('after the event it is the last stage', () {
      expect(
        timelineAnchor(sampleStages, DateTime(2026, 10, 22, 10))!.id,
        'bf',
      );
    });

    test('with untimed stages only it is the first one not over', () {
      expect(
        timelineAnchor([stRooms, stCheckout], DateTime(2026, 10, 21, 12))!.id,
        'out',
      );
    });

    test('is null without stages', () {
      expect(timelineAnchor(const [], sampleNow), isNull);
    });
  });

  test(
      'foldedStageIds folds what comes before the anchor, '
      'except untimed stages of its day', () {
    expect(foldedStageIds(sampleStages, stWorkshops), {'setup', 'lunch'});
    expect(
      foldedStageIds(sampleStages, stBreakfast),
      {'rooms', 'setup', 'lunch', 'ws', 'dinner'},
    );
  });

  group('layoutDay', () {
    test('untimed stages go to the all-day row, the rest by minute', () {
      final layout = layoutDay(
        [stRooms, stSetup, stLunch, stWorkshops, stDinner],
        minBlockMinutes: 33,
      );
      expect(layout.allDay, [stRooms]);
      expect(
        [
          for (final b in layout.blocks)
            (b.stage.id, b.startMinute, b.endMinute, b.column, b.columnCount),
        ],
        [
          ('setup', 480, 540, 0, 1),
          ('lunch', 780, 840, 0, 1),
          ('ws', 870, 1020, 0, 1),
          ('dinner', 1170, 1203, 0, 1),
        ],
      );
    });

    test('overlapping stages take columns side by side', () {
      final a = buildStage(
          id: 'a', date: sampleTue, startTime: '10:00', endTime: '12:00');
      final b = buildStage(
          id: 'b', date: sampleTue, startTime: '11:00', endTime: '13:00');
      final c = buildStage(
          id: 'c', date: sampleTue, startTime: '12:30', endTime: '13:30');
      expect(
        [
          for (final x in layoutDay([a, b, c], minBlockMinutes: 33).blocks)
            (x.stage.id, x.column, x.columnCount),
        ],
        [('a', 0, 2), ('b', 1, 2), ('c', 0, 2)],
      );
    });

    test('a third stage overlapping two others becomes a full-width row', () {
      final a = buildStage(
          id: 'a', date: sampleTue, startTime: '10:00', endTime: '12:00');
      final b = buildStage(
          id: 'b', date: sampleTue, startTime: '11:00', endTime: '13:00');
      final c = buildStage(
          id: 'c', date: sampleTue, startTime: '11:30', endTime: '12:30');
      final layout = layoutDay([a, b, c], minBlockMinutes: 33);
      expect(
        [for (final x in layout.blocks) (x.stage.id, x.column, x.columnCount)],
        [('a', 0, 2), ('b', 1, 2)],
      );
      expect([for (final x in layout.bands) (x.stage.id, x.startMinute)],
          [('c', 690)]);
    });

    test('a stage that overlaps no other column takes the full width', () {
      final a = buildStage(
          id: 'a', date: sampleTue, startTime: '10:00', endTime: '14:00');
      final b = buildStage(
          id: 'b', date: sampleTue, startTime: '10:30', endTime: '11:00');
      final c = buildStage(
          id: 'c', date: sampleTue, startTime: '15:00', endTime: '16:00');
      expect(
        [
          for (final x in layoutDay([a, b, c], minBlockMinutes: 33).blocks)
            (x.stage.id, x.columnCount),
        ],
        [('a', 2), ('b', 2), ('c', 1)],
      );
    });

    test('a malformed start time goes to the all-day row', () {
      final bad = buildStage(id: 'bad', date: sampleTue, startTime: '9:00');
      expect(layoutDay([bad], minBlockMinutes: 33).allDay, [bad]);
    });

    test('an end that is not after the start draws as a start-only block', () {
      final odd = buildStage(
        id: 'odd',
        date: sampleTue,
        startTime: '15:00',
        endTime: '14:00',
      );
      final block = layoutDay([odd], minBlockMinutes: 33).blocks.single;
      expect((block.startMinute, block.endMinute), (900, 933));
    });
  });

  group('buildTimeAxis', () {
    Stage at(String id, String start, String end) => buildStage(
        id: id, date: sampleTue, startTime: start, endTime: end);
    DayLayout dayOf(List<Stage> stages) =>
        layoutDay(stages, minBlockMinutes: 30);

    test('with room to spare, a minute sits where the hour height puts it',
        () {
      final axis = buildTimeAxis(
        [dayOf([at('a', '08:00', '12:00')])],
        firstHour: 8,
        lastHour: 12,
        hourHeight: 60,
        needOf: (_) => 10,
      );
      expect(axis.before(9 * 60), 60);
      expect(axis.before(9 * 60 + 30), 90);
      expect(axis.height, 240);
    });

    test('a name that needs more room stretches the time from its start', () {
      final axis = buildTimeAxis(
        [dayOf([at('a', '09:00', '09:30'), at('b', '09:30', '11:00')])],
        firstHour: 9,
        lastHour: 11,
        hourHeight: 60,
        needOf: (block) => block.stage.id == 'a' ? 100 : 10,
      );
      expect(axis.after(9 * 60 + 30) - axis.after(9 * 60), 100);
      expect(axis.before(10 * 60), 130);
      expect(axis.height, 190);
    });

    test('a full-width row takes its own room at its start minute', () {
      final layout = dayOf([
        at('a', '10:00', '12:00'),
        at('b', '10:00', '11:00'),
        at('c', '10:00', '10:30'),
      ]);
      final band = layout.bands.single;
      final axis = buildTimeAxis(
        [layout],
        firstHour: 10,
        lastHour: 12,
        hourHeight: 60,
        needOf: (block) => block.stage.id == 'c' ? 40 : 10,
      );
      expect(axis.bandTop(layout, band), 0);
      expect(axis.after(10 * 60), 40);
      expect(axis.height, 160);
    });

    test('two or more empty hours squash into a thin gap', () {
      final axis = buildTimeAxis(
        [dayOf([at('a', '08:00', '09:00'), at('b', '13:00', '14:00')])],
        firstHour: 8,
        lastHour: 14,
        hourHeight: 60,
        needOf: (_) => 10,
        squashedHeight: 24,
      );
      expect(axis.before(13 * 60) - axis.before(9 * 60), 24);
      expect(axis.isSquashed(11 * 60), isTrue);
      expect(axis.isSquashed(9 * 60), isFalse);
    });

    test('one empty hour keeps its height', () {
      final axis = buildTimeAxis(
        [dayOf([at('a', '08:00', '09:00'), at('b', '10:00', '11:00')])],
        firstHour: 8,
        lastHour: 11,
        hourHeight: 60,
        needOf: (_) => 10,
      );
      expect(axis.before(10 * 60) - axis.before(9 * 60), 60);
    });
  });

  test('calendarHours runs from the earliest start to the latest drawn end', () {
    expect(
      calendarHours([stSetup, stWorkshops, stDinner], minBlockMinutes: 33),
      (first: 8, last: 21),
    );
    expect(calendarHours([stRooms], minBlockMinutes: 33), isNull);
  });

  test('calendarHours never runs past midnight', () {
    final late = buildStage(
      id: 'late',
      date: sampleTue,
      startTime: '23:45',
    );
    expect(calendarHours([late], minBlockMinutes: 33), (first: 23, last: 24));
  });

  test('calendarDays adds the day of a stage that fell outside the event', () {
    final stray = buildStage(id: 'stray', date: DateTime(2026, 10, 23));
    expect(
      calendarDays(sampleEvent, [...sampleStages, stray]),
      [sampleTue, sampleWed, DateTime(2026, 10, 23)],
    );
  });

  test('initialCalendarDay is today during the event, else the first day', () {
    expect(
      initialCalendarDay([sampleTue, sampleWed], DateTime(2026, 10, 21, 9)),
      sampleWed,
    );
    expect(
      initialCalendarDay([sampleTue, sampleWed], DateTime(2026, 10, 11)),
      sampleTue,
    );
  });

  test('labels', () {
    expect(hebrewWeekday(DateTime(2026, 10, 18)), 'ראשון');
    expect(hebrewWeekday(sampleTue), 'שלישי');
    expect(hebrewWeekday(DateTime(2026, 10, 24)), 'שבת');
    expect(dayLabel(sampleTue, sampleNow), 'שלישי 20/10 · היום');
    expect(dayLabel(sampleWed, sampleNow), 'רביעי 21/10');
    expect(eventDaysLabel(sampleEvent), 'שלישי–רביעי, ${ltr('20–21/10')}');
    expect(eventDaysLabel(buildEvent(startDate: sampleTue)), 'שלישי, 20/10');
    expect(
      eventDaysLabel(buildEvent(
        startDate: DateTime(2026, 10, 30),
        endDate: DateTime(2026, 11, 1),
      )),
      'שישי–ראשון, ${ltr('30/10–01/11')}',
    );
    expect(stageTimeLabel(stWorkshops), ltr('14:30–17:00'));
    expect(stageTimeLabel(stDinner), ltr('19:30'));
    expect(stageTimeLabel(stRooms), '');
  });

  test('isEventUnderWay counts the event days only', () {
    expect(isEventUnderWay(sampleEvent, sampleNow), isTrue);
    expect(
      isEventUnderWay(sampleEvent, DateTime(2026, 10, 19, 23, 59)),
      isFalse,
    );
    expect(isEventUnderWay(sampleEvent, DateTime(2026, 10, 22)), isFalse);
  });
}
