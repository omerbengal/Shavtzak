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
import '../../../core/constants/constraint_status.dart';
import '../../../core/services/drive_service.dart';
import '../../../core/services/environment_service.dart';
import '../../../core/services/export_service.dart';
import '../../../core/services/user_cache_service.dart';
import '../../../core/services/google_oauth_service.dart';
import '../../widgets/passcode_requirement_dialog.dart';
import '../../widgets/shamap_export_dialog.dart';
import '../../widgets/settings_dialog.dart';

/// Choice screen - allows users to choose between available areas
/// For admins: Personal area, Management, Summary, and optional export screen
/// For non-admins with summary/export access: Personal area + allowed cards
class AdminChoiceScreen extends StatefulWidget {
  const AdminChoiceScreen({super.key});

  @override
  State<AdminChoiceScreen> createState() => _AdminChoiceScreenState();
}

class _AdminChoiceScreenState extends State<AdminChoiceScreen> {
  @override
  void initState() {
    super.initState();
    // Load team members to get pending constraint count for notification badge
    context.read<TeamBloc>().add(const team.LoadTeamMembers());
  }

  void _checkAndShowPasscodeDialog(BuildContext context) {
    final state = context.read<UserSelectionBloc>().state;
    if (state is UserAuthenticated) {
      final hasPasscode =
          state.user.passcode != null && state.user.passcode!.isNotEmpty;
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

  @override
  Widget build(BuildContext context) {
    // Check and show passcode dialog if user doesn't have one
    _checkAndShowPasscodeDialog(context);

    return Directionality(
      textDirection: TextDirection.rtl,
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
              final cardCount = 1 +
                  (showManagementCard ? 1 : 0) +
                  (showSummaryCard ? 1 : 0) +
                  (showShamapExportCard ? 1 : 0);

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
                              onTap: () =>
                                  context.go('$envPrefix/user/assignments'),
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
                                    onTap: () => context
                                        .go('$envPrefix/admin/team-members'),
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
                                onTap: () => context.go('$envPrefix/summary'),
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
                                  showDialog(
                                    context: context,
                                    builder: (context) => const Directionality(
                                      textDirection: TextDirection.rtl,
                                      child: ShamapExportDialog(),
                                    ),
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
    );
  }

  /// Count total pending constraints across all team members
  int _countPendingConstraints(TeamState teamState) {
    if (teamState is! TeamLoaded) return 0;
    int count = 0;
    for (final member in teamState.members) {
      for (final constraint in member.constraints) {
        if (constraint.status == ConstraintStatus.pending) {
          count++;
        }
      }
    }
    return count;
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
          final hasLeadingFullExport =
              state.isAdmin && DriveService.instance.isInitialized;
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
                          onPressed: () =>
                              _showGoogleCalendarSettingsDialog(context),
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
                          onPressed: () => _showFullExportDialog(context),
                          iconSize: 22,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 6),
                          constraints:
                              const BoxConstraints(minWidth: 40, minHeight: 44),
                        ),
                    ],
                  ),
            actions: [
              // Export buttons (admin only, when Drive is initialized)
              if (state.isAdmin && DriveService.instance.isInitialized) ...[
                // Assignments-only export button (cloud icon)
                IconButton(
                  icon: const Icon(Icons.cloud),
                  tooltip: 'ייצוא שיבוצים',
                  onPressed: () => _showAssignmentsExportDialog(context),
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
                onPressed: () => _showLogoutDialog(context),
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
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('ביטול'),
              ),
              TextButton(
                onPressed: () {
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
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('ייצוא שיבוצים'),
            content: const Text(
              'ייצוא רשימת שיבוצים בלבד לגיליון Google Sheets חדש.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('ביטול'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _performExport(context, isFullExport: false);
                },
                child: const Text('ייצוא'),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Perform the actual export
  Future<void> _performExport(BuildContext context,
      {required bool isFullExport}) async {
    // Show loading dialog and capture its context
    if (!context.mounted) return;
    BuildContext? dialogContext;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        dialogContext = ctx;
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

    // Close loading dialog using the dialog's context
    if (dialogContext != null) {
      Navigator.of(dialogContext!).pop();
    }

    // Show result dialog
    if (!context.mounted) return;
    if (result.success && result.spreadsheetUrl != null) {
      _showExportSuccessDialog(context, result.spreadsheetUrl!);
    } else {
      _showExportErrorDialog(context, result.error ?? 'שגיאה לא ידועה');
    }
  }

  /// Show success dialog with link to spreadsheet
  void _showExportSuccessDialog(BuildContext context, String url) {
    bool _copied = false;

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
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
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
                                _copied ? Icons.check_circle : Icons.copy,
                                color: _copied
                                    ? const Color(0xFF00E676)
                                    : Colors.white,
                                size: 16,
                              ),
                              label: const Text(
                                'העתק קישור',
                                style: TextStyle(fontSize: 12),
                              ),
                              onPressed: () async {
                                await Clipboard.setData(
                                    ClipboardData(text: url));
                                setState(() => _copied = true);
                                // Reset after 2 seconds
                                Future.delayed(const Duration(seconds: 2), () {
                                  if (context.mounted) {
                                    setState(() => _copied = false);
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
                onPressed: () => Navigator.of(dialogContext).pop(),
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
                  Navigator.of(context).pop();
                },
                child: const Text('ביטול'),
              ),
              TextButton(
                onPressed: () {
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
  void _showGoogleCalendarSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (context, setState) {
              final oauthService = GoogleOAuthService.instance;
              final isConnected = oauthService.isAuthenticated;
              final userEmail = oauthService.authenticatedUserEmail;

              // Auto-refresh dialog every 2 seconds while initializing
              if (!isConnected && oauthService.isInitialized) {
                Future.delayed(const Duration(seconds: 2), () {
                  if (context.mounted) {
                    setState(() {});
                  }
                });
              }

              return AlertDialog(
                title: const Row(
                  children: [
                    Icon(Icons.calendar_month, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('הגדרות יומן גוגל'),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Connection status
                    Row(
                      children: [
                        const Text(
                          'מצב חיבור:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          isConnected ? Icons.check_circle : Icons.cancel,
                          color: isConnected ? Colors.green : Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isConnected ? 'מחובר' : 'לא מחובר',
                          style: TextStyle(
                            color: isConnected ? Colors.green : Colors.red,
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
                        'התחבר/י ליומן גוגל כדי לאפשר הוספת משתתפים לאירועי יומן באופן אוטומטי.',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                  ],
                ),
                actions: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 52,
                            child: TextButton(
                              onPressed: () => setState(() {}),
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
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
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
                                    onPressed: () async {
                                      // Close main dialog first
                                      Navigator.of(dialogContext).pop();

                                      // Show loading indicator with context capture
                                      BuildContext? loadingContext;
                                      showDialog(
                                        context: context,
                                        barrierDismissible: false,
                                        builder: (ctx) {
                                          loadingContext = ctx;
                                          return Directionality(
                                            textDirection: TextDirection.rtl,
                                            child: const AlertDialog(
                                              content: Column(
                                                mainAxisSize: MainAxisSize.min,
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
                                        await oauthService.signOut().timeout(
                                              const Duration(seconds: 30),
                                            );
                                      } catch (e) {
                                        // Ignore sign-out errors
                                      }

                                      // Close loading dialog using captured context
                                      if (loadingContext != null &&
                                          loadingContext!.mounted) {
                                        Navigator.of(loadingContext!).pop();
                                      }

                                      // Show success dialog
                                      if (context.mounted) {
                                        _showDisconnectSuccessDialog(context);
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
                                    onPressed: () async {
                                      // Close main dialog first
                                      Navigator.of(dialogContext).pop();

                                      // Show loading indicator with context capture
                                      BuildContext? loadingContext;
                                      showDialog(
                                        context: context,
                                        barrierDismissible: false,
                                        builder: (ctx) {
                                          loadingContext = ctx;
                                          return Directionality(
                                            textDirection: TextDirection.rtl,
                                            child: const AlertDialog(
                                              content: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  CircularProgressIndicator(),
                                                  SizedBox(height: 16),
                                                  Text('מתחבר ליומן גוגל...'),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      );

                                      // Attempt sign in with error handling
                                      bool success = false;
                                      try {
                                        success =
                                            await oauthService.signIn().timeout(
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
                                        Navigator.of(loadingContext!).pop();
                                      }

                                      // Show result dialog
                                      if (context.mounted) {
                                        if (success) {
                                          _showConnectSuccessDialog(context);
                                        } else {
                                          _showConnectErrorDialog(context);
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
              'כעת ניתן להוסיף משתתפים לאירועי יומן באופן אוטומטי.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
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
                onPressed: () => Navigator.of(dialogContext).pop(),
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
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('סגירה'),
              ),
            ],
          ),
        );
      },
    );
  }
}
