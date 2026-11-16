import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/home_card_order.dart';

void main() {
  const shown = ['personal', 'management', 'duYomi', 'teamTasks', 'summary'];

  group('orderHomeCards', () {
    test('no saved order = the default order', () {
      expect(orderHomeCards(shown, const []), shown);
    });

    test('follows the saved order', () {
      expect(
        orderHomeCards(shown, const [
          'summary',
          'teamTasks',
          'duYomi',
          'management',
          'personal',
        ]),
        ['summary', 'teamTasks', 'duYomi', 'management', 'personal'],
      );
    });

    test('a card missing from the saved order follows in the default order',
        () {
      expect(
        orderHomeCards(shown, const ['teamTasks', 'personal']),
        ['teamTasks', 'personal', 'management', 'duYomi', 'summary'],
      );
    });

    test('a saved id that is not shown (or unknown) is ignored', () {
      expect(
        orderHomeCards(
            shown, const ['shamapExport', 'summary', 'gone', 'summary']),
        ['summary', 'personal', 'management', 'duYomi', 'teamTasks'],
      );
    });
  });

  group('moveHomeCard', () {
    test('forward: the dragged card takes the target place', () {
      expect(
        moveHomeCard(shown, 'personal', 'duYomi'),
        ['management', 'duYomi', 'personal', 'teamTasks', 'summary'],
      );
    });

    test('backward: the dragged card takes the target place', () {
      expect(
        moveHomeCard(shown, 'summary', 'management'),
        ['personal', 'summary', 'management', 'duYomi', 'teamTasks'],
      );
    });

    test('onto itself or an unknown card = no change', () {
      expect(moveHomeCard(shown, 'duYomi', 'duYomi'), shown);
      expect(moveHomeCard(shown, 'duYomi', 'nope'), shown);
      expect(moveHomeCard(shown, 'nope', 'duYomi'), shown);
    });
  });

  group('homeCardColumns', () {
    test('a phone keeps one column', () {
      expect(homeCardColumns(width: 390, count: 5), 1);
      expect(homeCardColumns(width: 800, count: 5), 1);
    });

    test('a wide window lays the cards in two rows', () {
      expect(homeCardColumns(width: 1280, count: 5), 3);
      expect(homeCardColumns(width: 1280, count: 4), 2);
      expect(homeCardColumns(width: 1280, count: 7), 4);
    });

    test('one or two cards stay in one column', () {
      expect(homeCardColumns(width: 1280, count: 1), 1);
      expect(homeCardColumns(width: 1280, count: 2), 1);
    });

    test('too narrow for the columns = one column', () {
      expect(homeCardColumns(width: 920, count: 7), 1);
    });
  });
}
