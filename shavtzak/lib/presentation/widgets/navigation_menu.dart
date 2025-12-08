import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../bloc/user_selection/user_selection_bloc.dart';
import '../bloc/user_selection/user_selection_event.dart';
import '../bloc/user_selection/user_selection_state.dart';
import '../../core/services/environment_service.dart';

/// Navigation menu widget for app bar
/// Shows home and logout buttons in a compact layout
class NavigationMenu extends StatelessWidget {
  const NavigationMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Home button
        IconButton(
          key: const ValueKey('nav_home_button'),
          icon: const Icon(Icons.home),
          tooltip: 'בית',
          onPressed: () {
            final envPrefix = EnvironmentService.instance.routePrefix;
            context.go('$envPrefix/admin');
          },
          iconSize: 24, // Slightly smaller icon size
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          constraints: const BoxConstraints(
            minWidth: 56, // Slightly smaller minimum touch target
            minHeight: 44,
          ),
        ),

        // Reduced spacing between icons
        const SizedBox(width: 4),

        // Logout button
        IconButton(
          key: const ValueKey('nav_logout_button'),
          icon: const Icon(Icons.logout),
          tooltip: 'התנתק',
          onPressed: () => _logout(context),
          iconSize: 24, // Slightly smaller icon size
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          constraints: const BoxConstraints(
            minWidth: 56, // Slightly smaller minimum touch target
            minHeight: 44,
          ),
        ),
      ],
    );
  }

  Future<void> _logout(BuildContext context) async {
    // Sign out first
    context.read<UserSelectionBloc>().add(const SignOut());

    // Listen for the state change and then navigate once
    bool handled = false;
    StreamSubscription? subscription;
    subscription = context.read<UserSelectionBloc>().stream.listen((state) {
      if (!handled && state is UserSignedOut && context.mounted) {
        handled = true;
        subscription?.cancel();
        final envPrefix = EnvironmentService.instance.routePrefix;
        context.go('$envPrefix/whoami');
      }
    });
  }
}
