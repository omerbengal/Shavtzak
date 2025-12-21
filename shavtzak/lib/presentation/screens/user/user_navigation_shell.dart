import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_event.dart';
import '../../bloc/user_selection/user_selection_state.dart';
import '../../widgets/navigation_menu.dart';
import '../../widgets/test_environment_indicator.dart';
import '../../widgets/settings_dialog.dart';

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
  int? _previousIndex;

  @override
  void initState() {
    super.initState();
    _previousIndex = widget.navigationShell.currentIndex;
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = widget.navigationShell.currentIndex;

    // Check if we just navigated to the constraints page (index 1)
    if (_previousIndex != null && _previousIndex != currentIndex && currentIndex == 1) {
      // Just navigated to constraints page
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onConstraintsPageVisible?.call();
      });
    }

    _previousIndex = currentIndex;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: _buildAppBar(context),
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
            ),
            centerTitle: true,
            leading: state.user.isAdmin ? null : IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'הגדרות',
            onPressed: () => _showSettingsDialog(context),
            iconSize: 24,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            constraints: const BoxConstraints(minWidth: 56, minHeight: 44),
          ),
          actions: [
              // Show navigation menu (home + logout) only for admin users
              if (state.user.isAdmin)
                const NavigationMenu()
              else
                // Regular users get logout button
                IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'התנתקות',
                  onPressed: () => _showLogoutDialog(context),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBottomNavigationBar(BuildContext context) {
    return BlocBuilder<UserSelectionBloc, UserSelectionState>(
      builder: (context, state) {
        if (state is! UserAuthenticated) {
          return const SizedBox.shrink();
        }

        final isPermanent = state.user.isPermanent;

        return BottomNavigationBar(
          currentIndex: widget.navigationShell.currentIndex,
          onTap: (index) => _onItemTapped(index, context),
          type: BottomNavigationBarType.fixed,
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.assignment),
              activeIcon: Icon(Icons.assignment_turned_in),
              label: 'המשימות שלי',
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
              icon: Icon(Icons.checklist),
              activeIcon: Icon(Icons.checklist),
              label: 'צ\'קליסט',
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
                  Navigator.of(context).pop(); // Close dialog
                },
                child: const Text('ביטול'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close dialog
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

  void _onItemTapped(int index, BuildContext context) {
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