import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_event.dart';
import '../../bloc/user_selection/user_selection_state.dart';
import '../../widgets/navigation_menu.dart';
import '../../widgets/test_environment_indicator.dart';
import '../../widgets/environment_switcher_button.dart';

/// Navigation shell for user-facing screens with bottom navigation
class UserNavigationShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const UserNavigationShell({
    super.key,
    required this.navigationShell,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: _buildAppBar(context),
        body: TestEnvironmentIndicator(
          child: SafeArea(
            child: navigationShell,
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
              actions: const [
                EnvironmentSwitcherButton(),
              ],
            );
          }

          return AppBar(
            title: Text(
              'שלום, ${state.user.name}',
              textAlign: TextAlign.center,
            ),
            centerTitle: true,
            actions: [
              const EnvironmentSwitcherButton(),
              // Show navigation menu (home + logout) only for admin users
              if (state.user.isAdmin)
                const NavigationMenu()
              else
                // Regular users get only logout button
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

        return BottomNavigationBar(
          currentIndex: navigationShell.currentIndex,
          onTap: (index) => _onItemTapped(index, context),
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.assignment),
              activeIcon: Icon(Icons.assignment_turned_in),
              label: 'המשימות שלי',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.block),
              activeIcon: Icon(Icons.block),
              label: 'המגבלות שלי',
            ),
          ],
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
        navigationShell.goBranch(0);
        break;
      case 1:
        navigationShell.goBranch(1);
        break;
    }
  }
}