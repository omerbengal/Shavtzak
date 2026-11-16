/// The admin home ("/admin") cards: their ids, each member's own order of
/// them (`TeamMember.homeCardOrder`, saved on the server) and the wide
/// layout of two rows.
abstract final class HomeCardIds {
  static const personal = 'personal';
  static const management = 'management';
  static const duYomi = 'duYomi';
  static const teamTasks = 'teamTasks';
  static const summary = 'summary';
  static const shamapExport = 'shamapExport';
  static const constraintsExamining = 'constraintsExamining';
}

/// A window at least this wide lays the cards in two rows.
const double homeCardsWideWidth = 900;

/// The widest a card gets, and the narrowest it may get in the two rows.
const double homeCardMaxWidth = 350;
const double homeCardMinWideWidth = 240;

/// The room between cards and around them.
const double homeCardGap = 16;
const double homeCardsSidePadding = 24;

/// The cards [shown] (in their default order) in the member's [saved] order:
/// the saved ids that are shown first, then every shown card the saved order
/// does not have, in the default order. Saved ids that are not shown (no
/// permission, an old card) are ignored.
List<String> orderHomeCards(List<String> shown, List<String> saved) {
  final shownSet = shown.toSet();
  final ordered = <String>[];
  for (final id in saved) {
    if (shownSet.contains(id) && !ordered.contains(id)) ordered.add(id);
  }
  for (final id in shown) {
    if (!ordered.contains(id)) ordered.add(id);
  }
  return ordered;
}

/// [order] with [dragged] taking [target]'s place: the cards between them
/// move one step towards where [dragged] was. Onto itself or an id that is
/// not there = [order] unchanged.
List<String> moveHomeCard(List<String> order, String dragged, String target) {
  final from = order.indexOf(dragged);
  final to = order.indexOf(target);
  if (from < 0 || to < 0 || from == to) return order;
  final next = [...order]..removeAt(from);
  next.insert(to, dragged);
  return next;
}

/// How many cards go in a row: one on a phone; on a wide window two rows,
/// so half the cards (rounded up) per row, as long as each card still gets
/// [homeCardMinWideWidth]. One or two cards stay one under the other.
int homeCardColumns({required double width, required int count}) {
  if (width < homeCardsWideWidth || count <= 2) return 1;
  final columns = (count + 1) ~/ 2;
  return homeCardWidthFor(width: width, columns: columns) >=
          homeCardMinWideWidth
      ? columns
      : 1;
}

/// A card's width when [columns] cards share a row of [width].
double homeCardWidthFor({required double width, required int columns}) {
  final room = width - 2 * homeCardsSidePadding - (columns - 1) * homeCardGap;
  final each = room / columns;
  return each > homeCardMaxWidth ? homeCardMaxWidth : each;
}
