import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Navigation menu widget for app bar
/// Shows a popup menu with navigation options to all main screens
class NavigationMenu extends StatelessWidget {
  const NavigationMenu({super.key});

  @override
  Widget build(BuildContext context) {
    // Get current route to highlight the active page
    final currentRoute = GoRouterState.of(context).uri.path;

    return PopupMenuButton<String>(
      icon: const Icon(Icons.menu),
      tooltip: 'ניווט',
      onSelected: (String route) {
        if (route != currentRoute) {
          context.go(route);
        }
      },
      itemBuilder: (BuildContext context) => [
        PopupMenuItem<String>(
          value: '/',
          child: Row(
            children: [
              const Icon(Icons.home, color: Colors.blue),
              const SizedBox(width: 12),
              Text(
                'בית',
                style: TextStyle(
                  fontWeight: currentRoute == '/' ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: '/team-members',
          child: Row(
            children: [
              const Icon(Icons.people, color: Colors.blue),
              const SizedBox(width: 12),
              Text(
                'צוות',
                style: TextStyle(
                  fontWeight: currentRoute == '/team-members' ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: '/events',
          child: Row(
            children: [
              const Icon(Icons.event, color: Colors.green),
              const SizedBox(width: 12),
              Text(
                'אירועים',
                style: TextStyle(
                  fontWeight: currentRoute == '/events' ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: '/assignments',
          child: Row(
            children: [
              const Icon(Icons.assignment, color: Colors.purple),
              const SizedBox(width: 12),
              Text(
                'שיבוצים',
                style: TextStyle(
                  fontWeight: currentRoute == '/assignments' ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
