import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/presentation/screens/task/row_hold.dart';
import 'package:shavtzak/presentation/screens/task/sheet_view.dart';

import '../../../support/sample_event.dart';
import '../../../support/task_fixtures.dart';

void main() {
  final a = buildTask(id: 'a', stage: stWorkshops, assemblyTime: '15:00');
  final b = buildTask(id: 'b', stage: stWorkshops, assemblyTime: '14:45');
  final bDone = b.copyWith(isComplete: true);
  const missing = StageView('ws', missingOnly: true);

  test('a row that stops matching stays while the view stays the same', () {
    final hold = RowHold();
    hold.rows(missing, matching: [a, b], all: [a, b]);

    expect(hold.rows(missing, matching: [a], all: [a, bDone]), [bDone, a]);
  });

  test('another view starts from scratch', () {
    final hold = RowHold();
    hold.rows(missing, matching: [a, b], all: [a, b]);

    expect(
      hold.rows(const StageView('ws'), matching: [a], all: [a, bDone]),
      [a],
    );
  });

  test('clear forgets the rows', () {
    final hold = RowHold();
    hold.rows(missing, matching: [a, b], all: [a, b]);
    hold.clear();

    expect(hold.rows(missing, matching: [a], all: [a, bDone]), [a]);
  });

  test('a deleted task leaves the list', () {
    final hold = RowHold();
    hold.rows(missing, matching: [a, b], all: [a, b]);

    expect(hold.rows(missing, matching: [a], all: [a]), [a]);
  });

  test('an opened row stays open while the view stays the same', () {
    final hold = RowHold();
    hold.rows(missing, matching: [a, b], all: [a, b]);
    hold.expand('a');

    hold.rows(missing, matching: [a], all: [a, bDone]);
    expect(hold.isExpanded('a'), isTrue);
    expect(hold.isExpanded('b'), isFalse);
  });

  test('an opened row folds again', () {
    final hold = RowHold();
    hold.rows(missing, matching: [a, b], all: [a, b]);
    hold.expand('a');
    hold.collapse('a');
    expect(hold.isExpanded('a'), isFalse);
  });

  test('another view, or clear, closes the opened rows', () {
    final hold = RowHold();
    hold.rows(missing, matching: [a, b], all: [a, b]);
    hold.expand('a');
    hold.rows(const StageView('ws'), matching: [a], all: [a, b]);
    expect(hold.isExpanded('a'), isFalse);

    hold.expand('a');
    hold.clear();
    expect(hold.isExpanded('a'), isFalse);
  });

  test('sheet views compare by what they show', () {
    expect(const StageView('ws'), const StageView('ws'));
    expect(const StageView('ws'), isNot(missing));
    expect(
      const ResultsView(ResultsKind.search, query: 'א'),
      isNot(const ResultsView(ResultsKind.search, query: 'אב')),
    );
    expect(
      const TaskView('t', back: missing),
      const TaskView('t', back: StageView('ws', missingOnly: true)),
    );
  });
}
