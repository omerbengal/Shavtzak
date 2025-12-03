import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_state.dart';

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
        body: SafeArea(
          child: navigationShell,
        ),
        bottomNavigationBar: _buildBottomNavigationBar(context),
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
              label: 'הגבלות שלי',
            ),
          ],
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