import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Every size and colour of the tasks screens, kept together so that tuning
/// the look after trying it on a phone is a one-line change.
abstract final class TaskStyle {
  // Status colours, from the mockups.
  static const Color late = Color(0xFFE53935);
  static const Color lateLight = Color(0xFFFFEBEE);
  static const Color lateDark = Color(0xFFC62828);
  static const Color soon = Color(0xFFFB8C00);
  static const Color soonLight = Color(0xFFFFF3E0);
  static const Color soonDark = Color(0xFFBF360C);
  static const Color done = Color(0xFF43A047);
  static const Color doneLight = Color(0xFFE8F5E9);
  static const Color doneDark = Color(0xFF2E7D32);
  static const Color current = AppTheme.primary;
  static const Color currentLight = Color(0xFFE3F2FD);

  /// The viewer's own things: their assignee chip, their count on a stage.
  static const Color mine = Color(0xFF1565C0);

  /// The pencil and the bin, as they have always been.
  static const Color edit = Colors.blue;
  static const Color delete = Colors.red;

  static const Color rest = Color(0xFFE0E0E0);
  static const Color chip = Color(0xFFEEEEEE);
  static const Color neutralText = Color(0xFF616161);
  static const Color faintText = Color(0xFF9E9E9E);

  // The day calendar.
  static const double hourHeight = 56;
  static const double hourLabelWidth = 40;

  /// How far each hour's line reaches into the label column.
  static const double hourTickLength = 10;

  /// The box an hour's label is centred in, on its line.
  static const double hourLabelBoxHeight = 14;
  static const double minBlockHeight = 30;

  /// The height a squashed stretch of empty hours shrinks to.
  static const double squashedGapHeight = 24;

  /// How long an empty stretch must be before it squashes.
  static const int squashFromMinutes = 120;

  /// The line either side of a day's name on the phone's calendar.
  static const Color dayDividerLine = Color(0xFFBDBDBD);
  static const double outlineWidth = 2.5;
  static const double fadedOpacity = 0.35;
  static const double focusTopMargin = 8;

  // The low sheet, as shares of the screen's height.
  static const double sheetMaxSize = 0.92;

  /// The sheet opens all the way up.
  static const double sheetInitialSize = sheetMaxSize;

  /// Where it rests when dragged down part way, before it closes.
  static const double sheetHalfSize = 0.5;

  /// How long the sheet takes to slide up as it opens.
  static const Duration sheetSlideDuration = Duration(milliseconds: 350);
  static const double sheetCloseBelow = 0.12;

  // Layout.
  static const double wideBreakpoint = 1000;
  static const double readableWidth = 640;

  /// The sheet on a wide window: centred, no wider than this.
  static const double wideSheetWidth = 960;

  // Text and small parts.
  static const double filterFontSize = 13;
  static const double rowTitleSize = 15;
  static const double rowMetaSize = 12.5;

  /// A subtask's title in a row's list of subtasks.
  static const double subtaskSize = 14;

  /// The gap above an update line under a task.
  static const double updateLineGap = 4;
  static const double stripHeight = 6;
  static const double timeColumnWidth = 52;

  /// The grey box an assignee update sits in.
  static const Color updateBox = Color(0x0A000000);

  /// The arrow that opens and folds a task's subtasks.
  static const double foldArrowSize = 22;

  /// The shortest block, in minutes, that still draws [minBlockHeight] tall
  /// at [hourHeight].
  static int minBlockMinutes(double hourHeight) =>
      (minBlockHeight / hourHeight * 60).ceil();

  // The calendar's blocks (Task 9).
  static const double blockTitleSize = 13;
  static const double blockMetaSize = 11.5;
  static const double blockRadius = 6;
  static const double blockGap = 2;
  static const double allDayBlockWidth = 160;
  static const double lateEdgeWidth = 3;

  /// The green a block fills with, from the left, as its tasks get done.
  static const Color blockDoneFill = Color(0xFFC8E6C9);

  /// The row of the mine badge and the count, under a block's details.
  static const double blockBadgeRowHeight = 22;

  static const double hourLabelSize = 11;
  static const double nowLineWidth = 2;
  static const double nowPillHeight = 18;

  // The wide sheet's table (Task 11).
  static const double tableTickWidth = 40;
  static const double tableTimeWidth = 76;
  static const int tableTitleFlex = 5;
  static const int tableAssigneesFlex = 4;
  static const double tableSubtasksWidth = 72;

  /// Room for the pencil and the bin, at the end of a manager's rows.
  static const double tableActionsWidth = 96;
  static const double tableHeaderSize = 12.5;
  static const double tableCellGap = 8;
  static const double tableRowVerticalPadding = 8;
  static const double lateMarkSize = 12;

  // "המשימות שלי": a card per stage, its tinted header above white task rows.
  /// The header of a stage that is neither highlighted nor all done.
  static const Color stageHeader = Color(0xFFF0F3F7);
  static const Color stageCard = Colors.white;
  static const Color stageCardBorder = rest;
  static const double stageCardRadius = 12;
  static const double stageCardBorderWidth = 1;

  /// The highlighted stage's card border, drawn stronger.
  static const double stageCardCurrentBorderWidth = 1.5;
  static const double stageCardGap = 10;
  static const double stageCardInset = 12;

  /// The line between the header and the tasks, and between the tasks.
  static const Color stageCardDivider = Color(0xFFEEEEEE);
}
