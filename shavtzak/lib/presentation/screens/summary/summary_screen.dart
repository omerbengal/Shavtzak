import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_event.dart';
import '../../bloc/user_selection/user_selection_state.dart';
import '../../../core/services/environment_service.dart';

/// Summary screen - isolated admin screen
/// Accessible directly via /summary route (not part of main navigation)
class SummaryScreen extends StatelessWidget {
  const SummaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('מסך מנהלים'),
          centerTitle: true,
          automaticallyImplyLeading: false,
          actions: [
            // Home button (appears closest to title in RTL)
            BlocBuilder<UserSelectionBloc, UserSelectionState>(
              builder: (context, state) {
                return IconButton(
                  icon: const Icon(Icons.home),
                  tooltip: 'בית',
                  onPressed: () {
                    final envPrefix = EnvironmentService.instance.routePrefix;
                    if (state is UserAuthenticated && state.isAdmin) {
                      // Admin goes back to /admin
                      context.go('$envPrefix/admin');
                    } else {
                      // Non-admin with summary access goes back to /choice
                      context.go('$envPrefix/choice');
                    }
                  },
                  iconSize: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  constraints: const BoxConstraints(minWidth: 56, minHeight: 44),
                );
              },
            ),
            // Logout button (appears farthest left in RTL)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'התנתק',
              onPressed: () => _showLogoutDialog(context),
              iconSize: 24,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              constraints: const BoxConstraints(minWidth: 56, minHeight: 44),
            ),
          ],
        ),
        body: const SafeArea(
          child: Center(
            child: Text('תוכן מסך מנהלים'),
          ),
        ),
      ),
    );
  }

  /// Show logout confirmation dialog
  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('אישור התנתקות'),
            content: const Text('האם את/ה בטוח/ה שברצונך להתנתק?'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('ביטול'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
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
}
