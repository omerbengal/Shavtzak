import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_event.dart';
import '../../bloc/user_selection/user_selection_state.dart';
import '../../bloc/team/team_bloc.dart';
import '../../bloc/team/team_event.dart' as team;
import '../../bloc/team/team_state.dart';
import '../../bloc/calendar_sync/calendar_sync_bloc.dart';
import '../../bloc/calendar_sync/calendar_sync_event.dart';
import '../../bloc/calendar_sync/calendar_sync_state.dart';
import '../../../core/debug/logger.dart';
import '../../../core/services/environment_service.dart';
import '../../../core/services/export_service.dart';
import '../../../core/services/user_cache_service.dart';
import '../../../core/services/google_oauth_service.dart';
import '../../../core/services/google_calendar_service.dart';
import '../../../domain/entities/team_member.dart';
import '../../widgets/passcode_requirement_dialog.dart';
import '../../widgets/assignment_export_dialog.dart';
import '../../widgets/shamap_export_dialog.dart';
import '../../widgets/settings_dialog.dart';
import '../../widgets/constraints_examining_dialog.dart';

/// Choice screen - allows users to choose between available areas
/// For admins: Personal area, Management, Summary, and optional export screen
/// For non-admins with optional access flags: Personal area + allowed cards
class AdminChoiceScreen extends StatefulWidget {
  const AdminChoiceScreen({super.key});

  @override
  State<AdminChoiceScreen> createState() => _AdminChoiceScreenState();
}

class _AdminChoiceScreenState extends State<AdminChoiceScreen> {
  bool _hasRequestedAdminCalendarStartupCheck = false;
  bool _hasAutoOpenedCalendarReconnectDialog = false;

  @override
  void initState() {
    super.initState();
    // Load team members to get pending constraint count for notification badge
    context.read<TeamBloc>().add(const team.LoadTeamMembers());
  }

  void _scheduleAdminCalendarStartupCheckIfNeeded() {
    final authState = context.read<UserSelectionBloc>().state;

    if (authState is UserAuthenticated && authState.isAdmin) {
      if (_hasRequestedAdminCalendarStartupCheck) return;
      _hasRequestedAdminCalendarStartupCheck = true;

      final calendarState = context.read<CalendarSyncBloc>().state;
      final shouldAutoOpenFromExistingState =
          calendarState is CalendarSyncFailure &&
              calendarState.constraintId == 'calendar_startup_auth_check' &&
              !calendarState.isRetryable &&
              !_hasAutoOpenedCalendarReconnectDialog;
      if (shouldAutoOpenFromExistingState) {
        _hasAutoOpenedCalendarReconnectDialog = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showGoogleCalendarSettingsDialog(context);
        });
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context
            .read<CalendarSyncBloc>()
            .add(const CheckCalendarAuthOnAdminAppLoad());
      });
      return;
    }

    _hasRequestedAdminCalendarStartupCheck = false;
    _hasAutoOpenedCalendarReconnectDialog = false;
  }

  void _checkAndShowPasscodeDialog(BuildContext context) {
    final state = context.read<UserSelectionBloc>().state;
    if (state is UserAuthenticated) {
      final hasPasscode = state.user.hasPasscode;
      if (!hasPasscode) {
        final cacheService = UserCacheService();
        if (!cacheService.hasPasscodeDialogBeenShownThisSession()) {
          cacheService.markPasscodeDialogShownThisSession();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              PasscodeRequirementDialog.show(
                context,
                onGoToSettings: () => _showSettingsDialog(context),
              );
            }
          });
        }
      }
    }
  }

  void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return const SettingsDialog();
      },
    );
  }

  Future<void> _showCalendarSyncResponseDialog(
    BuildContext context, {
    required String title,
    required String message,
    required IconData icon,
    required Color iconColor,
    String? retryLabel,
    VoidCallback? onRetry,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Row(
              children: [
                Icon(icon, color: iconColor),
                const SizedBox(width: 8),
                Expanded(child: Text(title)),
              ],
            ),
            content: Text(message),
            actions: [
              if (retryLabel != null && onRetry != null)
                TextButton(
                  onPressed: () {
                    Logger.action('tap:retry:calendarSync');
                    Navigator.of(dialogContext).pop();
                    onRetry();
                  },
                  child: Text(retryLabel),
                ),
              TextButton(
                onPressed: () {
                  Logger.action('tap:close:calendarSyncResponseDialog');
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('סגירה'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmAndStartGuestCleanup(
    BuildContext context,
    AppEventGuestCleanupMode mode,
  ) async {
    final isOmerOnly = mode == AppEventGuestCleanupMode.omer;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(
            isOmerOnly
                ? 'הסרת עומר מאירועים עתידיים'
                : 'הסרת כל המשתתפים מאירועים עתידיים',
          ),
          content: Text(
            isOmerOnly
                ? 'הפעולה תסיר את omerbengal7@gmail.com מכל אירועי שבצק העתידיים ביומן. שאר המשתתפים וסטטוסי המענה שלהם יישמרו.'
                : 'הפעולה תסיר את כל המשתתפים מכל אירועי שבצק העתידיים ביומן. לא ניתן לבטל את הפעולה דרך האפליקציה.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('ביטול'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.person_remove),
              label: const Text('התחלת ניקוי'),
              style: isOmerOnly
                  ? null
                  : FilledButton.styleFrom(backgroundColor: Colors.red),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !context.mounted) return;
    Logger.action('tap:startAppEventGuestCleanup', {'mode': mode.wireValue});
    context.read<CalendarSyncBloc>().add(StartAppEventGuestCleanup(mode));
  }

  String _guestCleanupResultMessage(AppEventGuestCleanupStatus result) {
    return 'עובדו ${result.processedPartCount} מתוך ${result.totalPartCount} חלקי אירועים. '
        'שונו ${result.changedPartCount}, דולגו ${result.skippedPartCount}, '
        'נכשלו ${result.failedPartCount}.';
  }

  @override
  Widget build(BuildContext context) {
    // Check and show passcode dialog if user doesn't have one
    _checkAndShowPasscodeDialog(context);
    _scheduleAdminCalendarStartupCheckIfNeeded();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: MultiBlocListener(
        listeners: [
          BlocListener<CalendarSyncBloc, CalendarSyncState>(
            listenWhen: (previous, current) =>
                current is CalendarSyncFailure &&
                current.constraintId == 'calendar_startup_auth_check',
            listener: (context, state) {
              if (state is! CalendarSyncFailure) return;
              if (state.isRetryable) return;
              if (_hasAutoOpenedCalendarReconnectDialog) return;

              final authState = context.read<UserSelectionBloc>().state;
              if (authState is! UserAuthenticated || !authState.isAdmin) return;

              _hasAutoOpenedCalendarReconnectDialog = true;
              _showGoogleCalendarSettingsDialog(context);
            },
          ),
        ],
        child: Scaffold(
          appBar: _buildAppBar(context),
          body: SafeArea(
            child: BlocBuilder<UserSelectionBloc, UserSelectionState>(
              builder: (context, state) {
                if (state is! UserAuthenticated) {
                  return const Center(child: CircularProgressIndicator());
                }

                final isAdmin = state.isAdmin;
                final showManagementCard = isAdmin;
                final showSummaryCard =
                    isAdmin || state.user.canAccessSummaryScreen;
                final showShamapExportCard = state.user.canAccessShamapExport;
                final showConstraintsExaminingCard =
                    state.user.canAccessConstraintsExamining;
                final cardCount = 1 +
                    (showManagementCard ? 1 : 0) +
                    (showSummaryCard ? 1 : 0) +
                    (showShamapExportCard ? 1 : 0) +
                    (showConstraintsExaminingCard ? 1 : 0);

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final envPrefix = EnvironmentService.instance.routePrefix;
                    final screenWidth = constraints.maxWidth;
                    final screenHeight = constraints.maxHeight;

                    // Responsive card width
                    final cardWidth =
                        screenWidth > 400 ? 350.0 : screenWidth * 0.85;

                    // Determine if we need compact mode based on available height
                    final isCompact = cardCount > 2 && screenHeight < 600;
                    final cardSpacing =
                        isCompact ? 8.0 : (cardCount > 2 ? 12.0 : 16.0);

                    return Center(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: isCompact ? 16 : 24,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'ברוכים הבאים לשבצק',
                                style: TextStyle(
                                  fontSize: isCompact ? 26 : 32,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: isCompact ? 8 : 16),
                              Text(
                                'באיזה כובע תרצה/י להיכנס?',
                                style: TextStyle(
                                  fontSize: isCompact ? 16 : 18,
                                  color: Colors.grey,
                                ),
                              ),
                              SizedBox(height: isCompact ? 16 : 32),

                              // Personal Area Card (always shown)
                              _buildChoiceCard(
                                width: cardWidth,
                                icon: Icons.person,
                                iconColor: Colors.blue,
                                title: 'איזור אישי',
                                subtitle: 'צפה בשיבוצים ובקשות מגבלות',
                                isCompact: isCompact,
                                onTap: () {
                                  Logger.action('tap:personalArea');
                                  context.go('$envPrefix/user/assignments');
                                },
                              ),

                              SizedBox(height: cardSpacing),

                              // Management Card (admin only)
                              if (showManagementCard) ...[
                                BlocBuilder<TeamBloc, TeamState>(
                                  builder: (context, teamState) {
                                    final pendingCount =
                                        _countPendingConstraints(teamState);
                                    return _buildChoiceCard(
                                      width: cardWidth,
                                      icon: Icons.admin_panel_settings,
                                      iconColor: Colors.green,
                                      title: 'ניהול שבצק',
                                      subtitle: 'ניהול צוות, אירועים ושיבוצים',
                                      isCompact: isCompact,
                                      onTap: () {
                                        Logger.action('tap:management');
                                        context.go(
                                            '$envPrefix/admin/team-members');
                                      },
                                      badgeCount: pendingCount,
                                    );
                                  },
                                ),
                                SizedBox(height: cardSpacing),
                              ],

                              // Summary/Manager Screen Card
                              if (showSummaryCard)
                                _buildChoiceCard(
                                  width: cardWidth,
                                  icon: Icons.dashboard,
                                  iconColor: Colors.purple,
                                  title: 'מסך מנהלים',
                                  subtitle: 'צפה בסיכום כללי',
                                  isCompact: isCompact,
                                  onTap: () {
                                    Logger.action('tap:summary');
                                    context.go('$envPrefix/summary');
                                  },
                                ),

                              // Shamap export card
                              if (showShamapExportCard) ...[
                                if (showSummaryCard)
                                  SizedBox(height: cardSpacing),
                                _buildChoiceCard(
                                  width: cardWidth,
                                  icon: Icons.content_paste,
                                  iconColor: Colors.teal,
                                  title: 'ייצוא שמפים',
                                  subtitle: 'העתקת פרטי שמ"פ ללוח',
                                  isCompact: isCompact,
                                  onTap: () {
                                    Logger.action('open:shamapExportDialog');
                                    showDialog(
                                      context: context,
                                      builder: (context) =>
                                          const Directionality(
                                        textDirection: TextDirection.rtl,
                                        child: ShamapExportDialog(),
                                      ),
                                    );
                                  },
                                ),
                              ],

                              // Constraints examining card
                              if (showConstraintsExaminingCard) ...[
                                if (showShamapExportCard || showSummaryCard)
                                  SizedBox(height: cardSpacing),
                                BlocBuilder<TeamBloc, TeamState>(
                                  builder: (context, teamState) {
                                    final pendingCount =
                                        _countPendingConstraints(teamState);
                                    return _buildChoiceCard(
                                      width: cardWidth,
                                      icon: Icons.fact_check,
                                      iconColor: Colors.deepOrange,
                                      title: 'בחינת מגבלות',
                                      subtitle:
                                          'צפייה ועדכון סטטוס מגבלות צוות',
                                      isCompact: isCompact,
                                      onTap: () {
                                        Logger.action(
                                            'open:constraintsExaminingDialog');
                                        showDialog(
                                          context: context,
                                          builder: (context) =>
                                              const Directionality(
                                            textDirection: TextDirection.rtl,
                                            child: ConstraintsExaminingDialog(),
                                          ),
                                        );
                                      },
                                      badgeCount: pendingCount,
                                    );
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Count total pending constraints across all team members
  int _countPendingConstraints(TeamState teamState) {
    if (teamState is! TeamLoaded) return 0;
    int count = 0;
    for (final member in teamState.members) {
      if (member.isArchived) continue;
      for (final constraint in member.constraints) {
        if (!constraint.isPending()) continue;
        if (!_isConstraintRelevantForMember(member, constraint)) continue;
        if (!_isFutureOrTodayConstraint(constraint)) continue;
        count++;
      }
    }
    return count;
  }

  bool _isConstraintRelevantForMember(
    TeamMember member,
    DateConstraint constraint,
  ) {
    if (member.isPermanent && constraint.isAvailability) return false;
    if (!member.isPermanent && constraint.isUnavailability) return false;
    return true;
  }

  bool _isFutureOrTodayConstraint(DateConstraint constraint) {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    if (constraint.repeatType != null && constraint.repeatEndDate != null) {
      final repeatEndDate = DateTime(
        constraint.repeatEndDate!.year,
        constraint.repeatEndDate!.month,
        constraint.repeatEndDate!.day,
      );
      return !repeatEndDate.isBefore(todayDate);
    }

    if (constraint.endDate != null) {
      final endDate = DateTime(
        constraint.endDate!.year,
        constraint.endDate!.month,
        constraint.endDate!.day,
      );
      return !endDate.isBefore(todayDate);
    }

    final startDate = DateTime(
      constraint.startDate.year,
      constraint.startDate.month,
      constraint.startDate.day,
    );
    return !startDate.isBefore(todayDate);
  }

  /// Build a choice card - no fixed height, content-sized
  Widget _buildChoiceCard({
    required double width,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool isCompact,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    final card = SizedBox(
      width: width,
      child: Card(
        elevation: 4,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: isCompact ? 12 : 20,
              horizontal: 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: isCompact ? 32 : 48, color: iconColor),
                SizedBox(height: isCompact ? 4 : 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: isCompact ? 18 : 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: isCompact ? 2 : 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: isCompact ? 12 : 13,
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (badgeCount <= 0) return card;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        card,
        // Red notification badge at top-right corner (offset accounts for Card's default 4px margin)
        PositionedDirectional(
          top: -2,
          end: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withValues(alpha: 0.4),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            constraints: const BoxConstraints(
              minWidth: 24,
              minHeight: 24,
            ),
            child: Text(
              '$badgeCount',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  /// Build the app bar with user info and logout button
  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: BlocBuilder<UserSelectionBloc, UserSelectionState>(
        builder: (context, state) {
          if (state is! UserAuthenticated) {
            return AppBar(
              title: const Text('שבצק'),
              centerTitle: true,
            );
          }

          final hasLeadingCalendar = state.isAdmin;
          final hasLeadingFullExport = state.isAdmin;
          final leadingIconCount =
              (hasLeadingCalendar ? 1 : 0) + (hasLeadingFullExport ? 1 : 0);

          return AppBar(
            leadingWidth:
                leadingIconCount == 0 ? 0 : (leadingIconCount * 40.0) + 8.0,
            title: Text(
              'שלום, ${state.user.name}',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            centerTitle: true,
            leading: leadingIconCount == 0
                ? const SizedBox.shrink()
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasLeadingCalendar)
                        IconButton(
                          icon: const Icon(Icons.calendar_month),
                          tooltip: 'הגדרות יומן גוגל',
                          onPressed: () {
                            Logger.action('open:googleCalendarSettingsDialog');
                            _showGoogleCalendarSettingsDialog(context);
                          },
                          iconSize: 22,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 6),
                          constraints:
                              const BoxConstraints(minWidth: 40, minHeight: 44),
                        ),
                      if (hasLeadingFullExport)
                        IconButton(
                          icon: const Icon(Icons.storage),
                          tooltip: 'ייצוא בסיס נתונים',
                          onPressed: () {
                            Logger.action('open:fullExportDialog');
                            _showFullExportDialog(context);
                          },
                          iconSize: 22,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 6),
                          constraints:
                              const BoxConstraints(minWidth: 40, minHeight: 44),
                        ),
                    ],
                  ),
            actions: [
              // Export buttons (admin only)
              if (state.isAdmin) ...[
                // Assignments-only export button (cloud icon)
                IconButton(
                  icon: const Icon(Icons.cloud),
                  tooltip: 'ייצוא שיבוצים',
                  onPressed: () {
                    Logger.action('open:assignmentsExportDialog');
                    _showAssignmentsExportDialog(context);
                  },
                  iconSize: 22,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 44),
                ),
              ],
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'התנתקות',
                onPressed: () {
                  Logger.action('open:logoutDialog');
                  _showLogoutDialog(context);
                },
                iconSize: 22,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Show full DB export confirmation dialog
  void _showFullExportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('ייצוא בסיס נתונים'),
            content: const Text(
              'פעולה זו תייצא את כל בסיס הנתונים של הפרודקשן לגיליון Google Sheets חדש.\n\n'
              'שימו לב: הגיליון יכיל מידע רגיש (קודים, מפתחות, פרטים אישיים).',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Logger.action('tap:cancel:fullExport');
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('ביטול'),
              ),
              TextButton(
                onPressed: () {
                  Logger.action('tap:confirmFullExport');
                  Navigator.of(dialogContext).pop();
                  _performExport(context, isFullExport: true);
                },
                child: const Text('ייצוא'),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Show assignments-only export confirmation dialog
  void _showAssignmentsExportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AssignmentExportDialog(
          onExport: (mode, eventIds) async {
            await _performAssignmentsExport(
              context,
              mode: mode,
              eventIds: eventIds,
            );
          },
        );
      },
    );
  }

  /// Perform the actual export
  Future<void> _performExport(BuildContext context,
      {required bool isFullExport}) async {
    // Show loading dialog
    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                    isFullExport ? 'מייצא בסיס נתונים...' : 'מייצא שיבוצים...'),
              ],
            ),
          ),
        );
      },
    );

    // Perform export in background
    final result = isFullExport
        ? await ExportService().exportToSheets()
        : await ExportService().exportAssignmentsOnly();

    // Show result dialog
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    if (result.success && result.spreadsheetUrl != null) {
      _showExportSuccessDialog(context, result.spreadsheetUrl!);
    } else {
      _showExportErrorDialog(context, result.error ?? 'שגיאה לא ידועה');
    }
  }

  Future<void> _performAssignmentsExport(
    BuildContext context, {
    required AssignmentExportMode mode,
    required List<String> eventIds,
  }) async {
    if (!context.mounted) return;

    final navigator = Navigator.of(context, rootNavigator: true);
    var isLoadingDialogOpen = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return const Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('מייצא שיבוצים...'),
              ],
            ),
          ),
        );
      },
    ).then((_) => isLoadingDialogOpen = false);

    final result = await ExportService().exportAssignmentsOnly(
      mode: mode,
      eventIds: eventIds,
    );

    if (isLoadingDialogOpen && navigator.mounted) {
      navigator.pop();
    }

    if (!context.mounted) return;
    if (result.success && result.spreadsheetUrl != null) {
      _showExportSuccessDialog(context, result.spreadsheetUrl!);
    } else {
      _showExportErrorDialog(context, result.error ?? 'שגיאה לא ידועה');
    }
  }

  /// Show success dialog with link to spreadsheet
  void _showExportSuccessDialog(BuildContext context, String url) {
    bool copied = false;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                actionsPadding: EdgeInsets.zero,
                title: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('הייצוא הושלם בהצלחה',
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                content:
                    const Text('הגיליון נוצר בתיקיית שבצק ב-Google Drive.'),
                actions: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8.0, vertical: 8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: TextButton(
                              onPressed: () {
                                Logger.action('tap:close:exportSuccessDialog');
                                Navigator.of(dialogContext).pop();
                              },
                              style: TextButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                              ),
                              child: const Text(
                                'סגירה',
                                style: TextStyle(fontSize: 14),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: ElevatedButton.icon(
                              icon: Icon(
                                copied ? Icons.check_circle : Icons.copy,
                                color: copied
                                    ? const Color(0xFF00E676)
                                    : Colors.white,
                                size: 16,
                              ),
                              label: const Text(
                                'העתק קישור',
                                style: TextStyle(fontSize: 12),
                              ),
                              onPressed: () async {
                                Logger.action('tap:copyToClipboard:exportUrl');
                                await Clipboard.setData(
                                    ClipboardData(text: url));
                                setState(() => copied = true);
                                // Reset after 2 seconds
                                Future.delayed(const Duration(seconds: 2), () {
                                  if (context.mounted) {
                                    setState(() => copied = false);
                                  }
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: () {
                                Logger.action('tap:openExportSheet');
                                Navigator.of(dialogContext).pop();
                                launchUrl(Uri.parse(url),
                                    mode: LaunchMode.externalApplication);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                              ),
                              child: const Text(
                                'פתח גיליון',
                                style: TextStyle(fontSize: 14),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  /// Show export error dialog
  void _showExportErrorDialog(BuildContext context, String error) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error, color: Colors.red),
                SizedBox(width: 8),
                Text('שגיאה בייצוא'),
              ],
            ),
            content: Text('הייצוא נכשל:\n$error'),
            actions: [
              TextButton(
                onPressed: () {
                  Logger.action('tap:close:exportErrorDialog');
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('סגירה'),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Show logout confirmation dialog
  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('אישור התנתקות'),
            content: const Text('האם את/ה בטוח/ה שברצונך להתנתק?'),
            actions: [
              TextButton(
                onPressed: () {
                  Logger.action('tap:cancel:logout');
                  Navigator.of(context).pop();
                },
                child: const Text('ביטול'),
              ),
              TextButton(
                onPressed: () {
                  Logger.action('tap:confirmLogout');
                  Navigator.of(context).pop();
                  context.read<UserSelectionBloc>().add(const SignOut());
                },
                child: const Text(
                  'התנתקות',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Show Google Calendar OAuth settings dialog
  Future<void> _showGoogleCalendarSettingsDialog(
      BuildContext screenContext) async {
    final oauthService = GoogleOAuthService.instance;
    bool hasInitializedDialog = false;
    bool isStatusLoading = true;

    Future<void> refreshStatus(
      StateSetter setState,
      BuildContext dialogContext,
    ) async {
      if (!dialogContext.mounted) return;
      setState(() {
        isStatusLoading = true;
      });

      await oauthService.refreshStatus();

      if (!dialogContext.mounted) return;
      setState(() {
        isStatusLoading = false;
      });
    }

    await showDialog(
      context: screenContext,
      builder: (BuildContext dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: BlocListener<CalendarSyncBloc, CalendarSyncState>(
            listenWhen: (previous, current) =>
                current is CalendarEventsAndConstraintsSyncComplete ||
                current is CalendarGuestCleanupComplete ||
                current is CalendarGuestCleanupFailure ||
                (current is CalendarSyncFailure &&
                    current.constraintId == 'events_and_constraints'),
            listener: (context, state) {
              if (state is CalendarGuestCleanupComplete) {
                final hasFailures = state.result.failedPartCount > 0;
                _showCalendarSyncResponseDialog(
                  dialogContext,
                  title: hasFailures
                      ? 'ניקוי המשתתפים הושלם חלקית'
                      : 'ניקוי המשתתפים הושלם',
                  message: _guestCleanupResultMessage(state.result),
                  icon: hasFailures
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle,
                  iconColor: hasFailures ? Colors.orange : Colors.green,
                  retryLabel: hasFailures ? 'נסה שוב' : null,
                  onRetry: hasFailures
                      ? () => screenContext.read<CalendarSyncBloc>().add(
                            StartAppEventGuestCleanup(state.result.mode),
                          )
                      : null,
                );
                return;
              }

              if (state is CalendarGuestCleanupFailure) {
                final isAuthBlocked = state.result?.status == 'auth-blocked';
                final progressMessage = state.result == null
                    ? state.errorMessage
                    : '${_guestCleanupResultMessage(state.result!)}\n${state.errorMessage}';
                _showCalendarSyncResponseDialog(
                  dialogContext,
                  title: isAuthBlocked
                      ? 'נדרש חיבור מחדש ליומן גוגל'
                      : 'ניקוי המשתתפים נכשל',
                  message: progressMessage,
                  icon: isAuthBlocked ? Icons.link_off : Icons.error,
                  iconColor: isAuthBlocked ? Colors.orange : Colors.red,
                  retryLabel: isAuthBlocked ? null : 'נסה שוב',
                  onRetry: isAuthBlocked
                      ? null
                      : () => screenContext.read<CalendarSyncBloc>().add(
                            StartAppEventGuestCleanup(state.mode),
                          ),
                );
                return;
              }

              if (state is CalendarEventsAndConstraintsSyncComplete) {
                final hasPartialFailures = state.failedEventCount > 0 ||
                    state.successfulConstraintRetryCount <
                        state.retriedConstraintCount;
                _showCalendarSyncResponseDialog(
                  dialogContext,
                  title: hasPartialFailures
                      ? 'אירועים בתור, סנכרון המגבלות הושלם חלקית'
                      : 'אירועים בתור, המגבלות סונכרנו',
                  message: state.message,
                  icon: hasPartialFailures
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle,
                  iconColor: hasPartialFailures ? Colors.orange : Colors.green,
                );
                return;
              }

              if (state is CalendarSyncFailure &&
                  state.constraintId == 'events_and_constraints') {
                _showCalendarSyncResponseDialog(
                  dialogContext,
                  title: 'שגיאה בסנכרון',
                  message: state.errorMessage,
                  icon: Icons.error,
                  iconColor: Colors.red,
                  retryLabel: state.isRetryable ? 'נסה שוב' : null,
                  onRetry: state.isRetryable
                      ? () {
                          screenContext
                              .read<CalendarSyncBloc>()
                              .add(const SyncEventsAndConstraints());
                        }
                      : null,
                );
              }
            },
            child: StatefulBuilder(
              builder: (context, setState) {
                if (!hasInitializedDialog) {
                  hasInitializedDialog = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!dialogContext.mounted) return;
                    refreshStatus(setState, dialogContext);
                  });
                }

                final isConnected = oauthService.isAuthenticated;
                final userEmail = oauthService.authenticatedUserEmail;
                final calendarBloc = context.watch<CalendarSyncBloc>();
                final calendarState = calendarBloc.state;
                final isCombinedSyncInProgress =
                    calendarState is CalendarSyncInProgress &&
                        calendarState.constraintId == 'events_and_constraints';
                final guestCleanupResult = calendarBloc.activeGuestCleanup;
                final isGuestCleanupInProgress =
                    calendarBloc.isGuestCleanupRunning;

                return AlertDialog(
                  title: const Row(
                    children: [
                      Icon(Icons.calendar_month, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('הגדרות יומן גוגל'),
                    ],
                  ),
                  content: isStatusLoading
                      ? const SizedBox(
                          width: 280,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text(
                                'טוען את מצב החיבור...',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Connection status
                              Row(
                                children: [
                                  const Text(
                                    'מצב חיבור:',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    isConnected
                                        ? Icons.check_circle
                                        : Icons.cancel,
                                    color:
                                        isConnected ? Colors.green : Colors.red,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isConnected ? 'מחובר' : 'לא מחובר',
                                    style: TextStyle(
                                      color: isConnected
                                          ? Colors.green
                                          : Colors.red,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // Authenticated user email
                              if (isConnected && userEmail != null) ...[
                                const Text(
                                  'משתמש:',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  userEmail,
                                  style: const TextStyle(fontSize: 13),
                                ),
                                const SizedBox(height: 16),
                              ],
                              // Explanation
                              if (!isConnected)
                                const Text(
                                  'התחבר/י ליומן גוגל כדי לסנכרן אירועים ומגבלות באופן אוטומטי.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey,
                                  ),
                                ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: !isConnected ||
                                          isCombinedSyncInProgress ||
                                          isGuestCleanupInProgress ||
                                          isStatusLoading
                                      ? null
                                      : () {
                                          Logger.action(
                                              'tap:syncEventsAndConstraints');
                                          screenContext
                                              .read<CalendarSyncBloc>()
                                              .add(
                                                const SyncEventsAndConstraints(),
                                              );
                                        },
                                  icon: isCombinedSyncInProgress
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.sync,
                                          color: Colors.white,
                                        ),
                                  label: const Text('סנכרון אירועים ומגבלות'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal,
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor:
                                        Colors.grey.shade400,
                                    disabledForegroundColor: Colors.white70,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                  ),
                                ),
                              ),
                              if (isConnected) ...[
                                const SizedBox(height: 20),
                                const Divider(),
                                const SizedBox(height: 8),
                                const Text(
                                  'ניקוי משתתפים מאירועים עתידיים',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                if (guestCleanupResult != null) ...[
                                  const SizedBox(height: 10),
                                  LinearProgressIndicator(
                                    value: guestCleanupResult.totalPartCount > 0
                                        ? guestCleanupResult
                                                .processedPartCount /
                                            guestCleanupResult.totalPartCount
                                        : null,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    guestCleanupResult.totalPartCount > 0
                                        ? 'עובדו ${guestCleanupResult.processedPartCount} מתוך ${guestCleanupResult.totalPartCount} חלקי אירועים'
                                        : 'מכין את ניקוי המשתתפים...',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: isGuestCleanupInProgress ||
                                            isCombinedSyncInProgress
                                        ? null
                                        : () => _confirmAndStartGuestCleanup(
                                              screenContext,
                                              AppEventGuestCleanupMode.omer,
                                            ),
                                    icon: isGuestCleanupInProgress &&
                                            guestCleanupResult?.mode ==
                                                AppEventGuestCleanupMode.omer
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.person_remove),
                                    label: const Text(
                                      'הסר את omerbengal7@gmail.com',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: isGuestCleanupInProgress ||
                                            isCombinedSyncInProgress
                                        ? null
                                        : () => _confirmAndStartGuestCleanup(
                                              screenContext,
                                              AppEventGuestCleanupMode.all,
                                            ),
                                    icon: isGuestCleanupInProgress &&
                                            guestCleanupResult?.mode ==
                                                AppEventGuestCleanupMode.all
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.group_remove),
                                    label: const Text('הסר את כל המשתתפים'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 52,
                              child: TextButton(
                                onPressed: isStatusLoading
                                    ? null
                                    : () {
                                        Logger.action('tap:refreshStatus');
                                        refreshStatus(
                                          setState,
                                          dialogContext,
                                        );
                                      },
                                child: const Text(
                                  'רענן סטטוס',
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: SizedBox(
                              height: 52,
                              child: TextButton(
                                onPressed: () {
                                  Logger.action(
                                      'tap:close:googleCalendarSettingsDialog');
                                  Navigator.of(dialogContext).pop();
                                },
                                child: const Text(
                                  'סגירה',
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: SizedBox(
                              height: 52,
                              child: isConnected
                                  ? TextButton(
                                      onPressed: isStatusLoading
                                          ? null
                                          : () async {
                                              Logger.action(
                                                  'tap:disconnectGoogleCalendar');
                                              // Close main dialog first
                                              Navigator.of(dialogContext).pop();

                                              // Show loading indicator with context capture
                                              BuildContext? loadingContext;
                                              showDialog(
                                                context: screenContext,
                                                barrierDismissible: false,
                                                builder: (ctx) {
                                                  loadingContext = ctx;
                                                  return Directionality(
                                                    textDirection:
                                                        TextDirection.rtl,
                                                    child: const AlertDialog(
                                                      content: Column(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          CircularProgressIndicator(),
                                                          SizedBox(height: 16),
                                                          Text('מתנתק...'),
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                },
                                              );

                                              // Sign out with error handling
                                              try {
                                                await oauthService
                                                    .signOut()
                                                    .timeout(
                                                      const Duration(
                                                          seconds: 30),
                                                    );
                                              } catch (e) {
                                                // Ignore sign-out errors
                                              }

                                              // Close loading dialog using captured context
                                              if (loadingContext != null &&
                                                  loadingContext!.mounted) {
                                                Navigator.of(loadingContext!)
                                                    .pop();
                                              }

                                              // Show success dialog
                                              if (screenContext.mounted) {
                                                _showDisconnectSuccessDialog(
                                                  screenContext,
                                                );
                                              }
                                            },
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.red,
                                      ),
                                      child: const Text(
                                        'התנתק',
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    )
                                  : ElevatedButton(
                                      onPressed: isStatusLoading
                                          ? null
                                          : () async {
                                              Logger.action(
                                                  'tap:connectGoogleCalendar');
                                              // Close main dialog first
                                              Navigator.of(dialogContext).pop();

                                              // Show loading indicator with context capture
                                              BuildContext? loadingContext;
                                              showDialog(
                                                context: screenContext,
                                                barrierDismissible: false,
                                                builder: (ctx) {
                                                  loadingContext = ctx;
                                                  return Directionality(
                                                    textDirection:
                                                        TextDirection.rtl,
                                                    child: const AlertDialog(
                                                      content: Column(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          CircularProgressIndicator(),
                                                          SizedBox(height: 16),
                                                          Text(
                                                              'מתחבר ליומן גוגל...'),
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                },
                                              );

                                              // Attempt sign in with error handling
                                              bool success = false;
                                              try {
                                                success = await oauthService
                                                    .signIn()
                                                    .timeout(
                                                  const Duration(seconds: 60),
                                                  onTimeout: () {
                                                    return false;
                                                  },
                                                );
                                              } catch (e) {
                                                success = false;
                                              }

                                              // Close loading dialog using captured context
                                              if (loadingContext != null &&
                                                  loadingContext!.mounted) {
                                                Navigator.of(loadingContext!)
                                                    .pop();
                                              }

                                              // Show result dialog
                                              if (screenContext.mounted) {
                                                if (success) {
                                                  _showConnectSuccessDialog(
                                                    screenContext,
                                                  );
                                                } else {
                                                  _showConnectErrorDialog(
                                                    screenContext,
                                                  );
                                                }
                                              }
                                            },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue,
                                        foregroundColor: Colors.white,
                                      ),
                                      child: const Text(
                                        'התחבר ליומן גוגל',
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// Show success dialog after connecting to Google Calendar
  void _showConnectSuccessDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('חיבור הצליח'),
              ],
            ),
            content: const Text(
              'החיבור ליומן גוגל הצליח!\n'
              'כעת ניתן לסנכרן אירועים ומגבלות באופן אוטומטי.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Logger.action('tap:close:connectSuccessDialog');
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('סגירה'),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Show error dialog after failed connection attempt
  void _showConnectErrorDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error, color: Colors.red),
                SizedBox(width: 8),
                Text('שגיאה בחיבור'),
              ],
            ),
            content: const Text(
              'החיבור ליומן גוגל נכשל.\n'
              'ייתכן שביטלת את התהליך או שאין הרשאות מתאימות.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Logger.action('tap:close:connectErrorDialog');
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('סגירה'),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Show success dialog after disconnecting from Google Calendar
  void _showDisconnectSuccessDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('התנתקות הצליחה'),
              ],
            ),
            content: const Text(
              'ההתנתקות מיומן גוגל הצליחה.\n'
              'הוסרו כל האסימונים השמורים.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Logger.action('tap:close:disconnectSuccessDialog');
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('סגירה'),
              ),
            ],
          ),
        );
      },
    );
  }
}
