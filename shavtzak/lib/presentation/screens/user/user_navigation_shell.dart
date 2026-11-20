import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/utils/team_task_rules.dart';
import '../../../domain/entities/team_member.dart';
import '../../bloc/team_task/team_task_bloc.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_state.dart';
import '../../widgets/member_bar_buttons.dart';
import '../../widgets/test_environment_indicator.dart';
import '../../widgets/settings_dialog.dart';
import '../../widgets/passcode_requirement_dialog.dart';
import '../../widgets/push_prompt_dialog.dart';
import '../team_task/team_tasks_place.dart';
import '../../widgets/swipeable_page_view.dart' show BottomNavWithDebugTrigger;
import '../../../core/debug/debug_logger.dart';
import '../../../core/debug/logger.dart';
import '../../../core/services/app_version_service.dart';
import '../../../core/services/environment_service.dart';
import '../../../core/services/user_cache_service.dart';

// Global callback to trigger constraints sync when constraints page becomes visible
void Function()? onConstraintsPageVisible;

/// The member bar's routes, in order; the team tasks tab is the 4th and
/// last, so the indexes of the first three never move.
List<String> memberTabRoutes({required bool withTeamTasks}) => [
      '/user/assignments',
      '/user/constraints',
      '/user/du-yomi',
      if (withTeamTasks) '/user/team-tasks',
    ];

/// The index of the team tasks branch ("משימות").
const int kTeamTasksTab = 3;

/// Whether the member bar shows "משימות" (back on 17/11/2026): to a manager
/// and a permanent member always (20/11/2026), to anyone else once they own a task that is not cancelled or a
/// duplicate. A member who is already on that tab (a link) keeps it.
bool memberShowsTeamTasksTab(
  TeamMember user,
  TeamTaskState state, {
  required int currentIndex,
}) {
  if (currentIndex == kTeamTasksTab) return true;
  final mine = state is TeamTasksLoaded && state.viewer.id == user.id
      ? state.mine
      : const <Never>[];
  return showTeamTasksTab(user, mine);
}

/// Navigation shell for user-facing screens with bottom navigation
class UserNavigationShell extends StatefulWidget {
  final StatefulNavigationShell navigationShell;

  const UserNavigationShell({
    super.key,
    required this.navigationShell,
  });

  @override
  State<UserNavigationShell> createState() => _UserNavigationShellState();
}

class _UserNavigationShellState extends State<UserNavigationShell> {
  static const int _kDuYomiTab = 2;

  int? _previousIndex;

  @override
  void initState() {
    super.initState();
    _previousIndex = widget.navigationShell.currentIndex;
    // The bar needs to know whether the member owns a team task.
    final auth = context.read<UserSelectionBloc>().state;
    if (auth is UserAuthenticated) {
      context.read<TeamTaskBloc>().add(TeamTasksSubscribe(auth.user));
    }
  }

  /// The notifications popup (push_prompt_dialog.dart), as on the admin
  /// home: every member may get them (17/11/2026), after the passcode popup,
  /// never both at once. Once per app session (maybeShowPushPrompt).
  void _schedulePushPrompt() {
    final state = context.read<UserSelectionBloc>().state;
    if (state is! UserAuthenticated || !state.user.hasPasscode) return;
    final user = state.user;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      maybeShowPushPrompt(
        context,
        canReceive: canGetTeamTaskNotifications(user),
        appVersion: AppVersionService.instance.cachedVersion,
      );
    });
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

  @override
  Widget build(BuildContext context) {
    final currentIndex = widget.navigationShell.currentIndex;

    // Check if we just navigated to the constraints page (index 1)
    if (_previousIndex != null &&
        _previousIndex != currentIndex &&
        currentIndex == 1) {
      // Just navigated to constraints page
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onConstraintsPageVisible?.call();
      });
    }

    _previousIndex = currentIndex;

    // Check and show passcode dialog if user doesn't have one
    _checkAndShowPasscodeDialog(context);
    _schedulePushPrompt();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        // The דו יומי and team tasks screens bring their own bar with these
        // buttons in it.
        appBar: currentIndex == _kDuYomiTab || currentIndex == kTeamTasksTab
            ? null
            : _buildAppBar(context),
        body: TestEnvironmentIndicator(
          child: SafeArea(
            child: widget.navigationShell,
          ),
        ),
        bottomNavigationBar: _buildBottomNavigationBar(context),
      ),
    );
  }

  /// Build the app bar with user info and logout button
  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: BlocBuilder<UserSelectionBloc, UserSelectionState>(
        buildWhen: (previous, current) {
          if (previous is UserAuthenticated && current is UserAuthenticated) {
            return previous.user.name != current.user.name ||
                previous.user.isAdmin != current.user.isAdmin ||
                previous.user.canAccessSummaryScreen !=
                    current.user.canAccessSummaryScreen ||
                previous.user.canAccessShamapExport !=
                    current.user.canAccessShamapExport ||
                previous.user.canAccessConstraintsExamining !=
                    current.user.canAccessConstraintsExamining;
          }
          return previous.runtimeType != current.runtimeType;
        },
        builder: (context, state) {
          if (state is! UserAuthenticated) {
            return AppBar(
              title: const Text('שבצק'),
              centerTitle: true,
            );
          }

          return AppBar(
            title: Text(
              'שלום, ${state.user.name}',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: MediaQuery.of(context).size.width < 370 ? 14 : 18,
              ),
            ),
            centerTitle: true,
            leading: const MemberSettingsButton(),
            actions: [
              MemberBarActions(user: state.user, balanceSettings: true),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBottomNavigationBar(BuildContext context) {
    return BlocBuilder<UserSelectionBloc, UserSelectionState>(
      buildWhen: (previous, current) {
        if (previous is UserAuthenticated && current is UserAuthenticated) {
          return previous.user.isPermanent != current.user.isPermanent ||
              previous.user.isAdmin != current.user.isAdmin ||
              previous.user.canManageTasks != current.user.canManageTasks;
        }
        return previous.runtimeType != current.runtimeType;
      },
      builder: (context, state) {
        if (state is! UserAuthenticated) {
          return const SizedBox.shrink();
        }
        final user = state.user;
        // The bloc decides "owns a visible task"; the current tab is read on
        // every build, outside the selector (a selector is re-run only when
        // the bloc emits, so a navigation to the tab would go unseen).
        return BlocSelector<TeamTaskBloc, TeamTaskState, bool>(
          selector: (taskState) =>
              memberShowsTeamTasksTab(user, taskState, currentIndex: -1),
          builder: (context, ownsVisibleTask) => _buildBar(
            context,
            user,
            ownsVisibleTask ||
                widget.navigationShell.currentIndex == kTeamTasksTab,
          ),
        );
      },
    );
  }

  Widget _buildBar(BuildContext context, TeamMember user, bool withTeamTasks) {
    final isPermanent = user.isPermanent;
    final tabRoutes = memberTabRoutes(withTeamTasks: withTeamTasks);

    return BottomNavWithDebugTrigger(
      currentIndex: widget.navigationShell.currentIndex,
      onTap: (index) => _onItemTapped(index, context, tabRoutes),
      type: BottomNavigationBarType.fixed,
      tabRoutes: tabRoutes,
      userDisplay: user.name,
      isAdmin: user.isAdmin,
      env: EnvironmentService.instance.isTestMode ? 'test' : 'prod',
      miniFabHeroTag: 'debug-share-mini-fab-user',
      items: [
        const BottomNavigationBarItem(
          icon: Icon(Icons.assignment),
          activeIcon: Icon(Icons.assignment_turned_in),
          label: 'האירועים שלי',
        ),
        BottomNavigationBarItem(
          icon: isPermanent
              ? const Icon(Icons.block)
              : const Icon(Icons.event_available),
          activeIcon: isPermanent
              ? const Icon(Icons.block)
              : const Icon(Icons.event_available),
          label: isPermanent ? 'המגבלות שלי' : 'הזמינות שלי',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.event_note_outlined),
          activeIcon: Icon(Icons.event_note),
          label: 'דו יומי',
        ),
        if (withTeamTasks)
          const BottomNavigationBarItem(
            icon: Icon(Icons.task_alt_outlined),
            activeIcon: Icon(Icons.task_alt),
            label: 'משימות',
          ),
      ],
    );
  }

  /// Show settings dialog
  void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return const SettingsDialog();
      },
    );
  }

  void _onItemTapped(int index, BuildContext context, List<String> tabRoutes) {
    Logger.action('select:tab', {'tabIndex': index});
    if (index < tabRoutes.length) {
      DebugLogger.instance.reset(newRoute: tabRoutes[index]);
      widget.navigationShell.goBranch(index);
    }
  }
}
