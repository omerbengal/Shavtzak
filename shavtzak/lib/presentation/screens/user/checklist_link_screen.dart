import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_state.dart';
import '../../widgets/test_environment_indicator.dart';
import '../admin/checklist_screen.dart';
import 'user_checklist_screen.dart';

/// The checklist, at `/tasks`: the admins' version for admins, the member's
/// own items for everyone else.
///
/// Reachable only by link: no tab or menu leads here.
class ChecklistLinkScreen extends StatelessWidget {
  const ChecklistLinkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.select<UserSelectionBloc, bool>((bloc) {
      final state = bloc.state;
      return state is UserAuthenticated && state.isAdmin;
    });
    return TestEnvironmentIndicator(
      child: isAdmin
          ? const AdminChecklistScreen()
          : const UserChecklistScreen(),
    );
  }
}
