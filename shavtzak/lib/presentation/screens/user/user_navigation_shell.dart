import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_state.dart';
import '../../widgets/member_bar_buttons.dart';
import '../../widgets/test_environment_indicator.dart';
import '../../widgets/settings_dialog.dart';
import '../../widgets/passcode_requirement_dialog.dart';
import '../../widgets/swipeable_page_view.dart' show BottomNavWithDebugTrigger;
import '../../../core/debug/debug_logger.dart';
import '../../../core/debug/logger.dart';
import '../../../core/services/environment_service.dart';
import '../../../core/services/user_cache_service.dart';

// Global callback to trigger constraints sync when constraints page becomes visible
void Function()? onConstraintsPageVisible;

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
  static const List<String> _kUserTabRoutes = [
    '/user/assignments',
    '/user/constraints',
    '/user/du-yomi',
  ];
  static const int _kDuYomiTab = 2;

  int? _previousIndex;

  @override
  void initState() {
    super.initState();
    _previousIndex = widget.navigationShell.currentIndex;
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

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        // The דו יומי screens bring their own bar with these buttons in it.
        appBar: currentIndex == _kDuYomiTab ? null : _buildAppBar(context),
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
          return previous.user.isPermanent != current.user.isPermanent;
        }
        return previous.runtimeType != current.runtimeType;
      },
      builder: (context, state) {
        if (state is! UserAuthenticated) {
          return const SizedBox.shrink();
        }

        final isPermanent = state.user.isPermanent;

        return BottomNavWithDebugTrigger(
          currentIndex: widget.navigationShell.currentIndex,
          onTap: (index) => _onItemTapped(index, context),
          type: BottomNavigationBarType.fixed,
          tabRoutes: _kUserTabRoutes,
          userDisplay: state.user.name,
          isAdmin: state.user.isAdmin,
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
          ],
        );
      },
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

  void _onItemTapped(int index, BuildContext context) {
    Logger.action('select:tab', {'tabIndex': index});
    if (index < _kUserTabRoutes.length) {
      DebugLogger.instance.reset(newRoute: _kUserTabRoutes[index]);
    }
    switch (index) {
      case 0:
        widget.navigationShell.goBranch(0);
        break;
      case 1:
        widget.navigationShell.goBranch(1);
        break;
      case 2:
        widget.navigationShell.goBranch(2);
        break;
    }
  }
}
