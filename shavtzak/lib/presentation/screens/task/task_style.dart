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
  static const double wideHourHeight = 48;
  static const double hourLabelWidth = 40;
  static const double minBlockHeight = 30;
  static const double blockDetailsMinHeight = 52;
  static const double blockProgressMinHeight = 68;
  static const double outlineWidth = 2.5;
  static const double fadedOpacity = 0.35;
  static const double focusTopMargin = 8;

  // The low sheet, as shares of the screen's height.
  static const double sheetInitialSize = 0.5;
  static const double sheetMaxSize = 0.92;
  static const double sheetCloseBelow = 0.12;

  // Layout.
  static const double wideBreakpoint = 1000;
  static const double readableWidth = 640;
  static const int maxSideBySideDays = 3;
  static const int calendarFlex = 5;
  static const int panelFlex = 6;

  // Text and small parts.
  static const double filterFontSize = 13;
  static const double rowTitleSize = 15;
  static const double rowMetaSize = 12.5;
  static const double stripHeight = 6;
  static const double timeColumnWidth = 52;

  /// The shortest block, in minutes, that still draws [minBlockHeight] tall
  /// at [hourHeight].
  static int minBlockMinutes(double hourHeight) =>
      (minBlockHeight / hourHeight * 60).ceil();
}
