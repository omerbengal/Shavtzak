import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/debug/logger.dart';
import '../../domain/entities/team_member.dart';
import '../bloc/user_selection/user_selection_bloc.dart';
import '../bloc/user_selection/user_selection_event.dart';
import 'navigation_menu.dart';
import 'settings_dialog.dart';

/// The buttons of the member area's top bar, shared by the member shell and
/// the screens that bring their own bar in its place (the דו יומי tab).

/// The settings button, the bar's leading.
class MemberSettingsButton extends StatelessWidget {
  const MemberSettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.settings),
      tooltip: 'הגדרות',
      onPressed: () {
        Logger.action('open:settingsDialog');
        showDialog(
          context: context,
          builder: (BuildContext context) => const SettingsDialog(),
        );
      },
      iconSize: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      constraints: const BoxConstraints(minWidth: 56, minHeight: 44),
    );
  }
}

/// Whether [user] reaches a home screen beyond the member area.
bool hasChoiceScreen(TeamMember user) =>
    user.isAdmin ||
    user.canAccessSummaryScreen ||
    user.canAccessShamapExport ||
    user.canAccessConstraintsExamining;

/// Home and logout for those with a choice screen, logout alone otherwise.
class MemberBarActions extends StatelessWidget {
  const MemberBarActions({
    super.key,
    required this.user,
    this.balanceSettings = false,
  });

  final TeamMember user;

  /// Pads the lone logout to the width of the settings button, so a centred
  /// title stays centred.
  final bool balanceSettings;

  @override
  Widget build(BuildContext context) {
    if (hasChoiceScreen(user)) return const NavigationMenu();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (balanceSettings) const SizedBox(width: 60),
        IconButton(
          icon: const Icon(Icons.logout),
          tooltip: 'התנתקות',
          onPressed: () {
            Logger.action('open:logoutDialog');
            _showLogoutDialog(context);
          },
        ),
      ],
    );
  }

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
                  Logger.action('tap:cancel:logoutDialog');
                  Navigator.of(context).pop(); // Close dialog
                },
                child: const Text('ביטול'),
              ),
              TextButton(
                onPressed: () {
                  Logger.action('tap:logout');
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
}
