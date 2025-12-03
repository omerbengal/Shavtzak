import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Navigation menu widget for app bar
/// Shows a home icon that navigates to admin home screen
class NavigationMenu extends StatelessWidget {
  const NavigationMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.home),
      tooltip: 'בית',
      onPressed: () {
        context.go('/admin');
      },
    );
  }
}
