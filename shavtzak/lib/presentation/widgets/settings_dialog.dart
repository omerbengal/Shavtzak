import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/user_selection/user_selection_bloc.dart';
import '../bloc/user_selection/user_selection_state.dart';
import '../bloc/user_selection/user_selection_event.dart';
import '../../data/repositories/user_selection_repository.dart';
import 'passcode_setup_dialog.dart';
import 'passcode_change_dialog.dart';

/// Settings dialog with passcode management
class SettingsDialog extends StatelessWidget {
  const SettingsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('הגדרות'),
        content: SizedBox(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'ניהול קוד גישה',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              BlocBuilder<UserSelectionBloc, UserSelectionState>(
                builder: (context, state) {
                  if (state is! UserAuthenticated) {
                    return const SizedBox.shrink();
                  }

                  final hasPasscode = state.user.passcode != null;
                  final passcodeLength = state.user.passcodeLength ?? 0;

                  if (hasPasscode) {
                    return Column(
                      children: [
                        Icon(
                          Icons.lock,
                          size: 64,
                          color: Theme.of(context).primaryColor,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'קוד גישה מוגדר (${passcodeLength} ספרות)',
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () => _showChangePasscodeDialog(context),
                              icon: const Icon(Icons.edit),
                              label: const Text('שנה קוד'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: () => _showRemovePasscodeDialog(context),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('הסר קוד'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        Icon(
                          Icons.lock_open,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'לא הוגדר קוד גישה',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'הגדרת קוד גישה תאבטח את החשבון שלך',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () => _showSetupPasscodeDialog(context),
                          icon: const Icon(Icons.lock),
                          label: const Text('הגדר קוד גישה'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            textStyle: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ],
                    );
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('סגור'),
          ),
        ],
      ),
    );
  }

  void _showSetupPasscodeDialog(BuildContext context) async {
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => const PasscodeSetupDialog(),
    );

    if (result != null && context.mounted) {
      final passcode = result['passcode'] as String;
      final length = result['length'] as int;

      try {
        final userSelectionRepo = context.read<UserSelectionRepository>();
        final bloc = context.read<UserSelectionBloc>();
        final currentState = bloc.state;

        if (currentState is UserAuthenticated) {
          await userSelectionRepo.setTeamMemberPasscode(
            currentState.user.uniqueKey,
            passcode,
            length,
          );

          // Refresh user data
          bloc.add(const RefreshUserData());

          if (context.mounted) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('קוד גישה הוגדר בהצלחה'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('שגיאה בהגדרת קוד גישה: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showChangePasscodeDialog(BuildContext context) async {
    final bloc = context.read<UserSelectionBloc>();
    final currentState = bloc.state;

    if (currentState is! UserAuthenticated ||
        currentState.user.passcode == null ||
        currentState.user.passcodeLength == null) {
      return;
    }

    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => PasscodeChangeDialog(
        currentPasscode: currentState.user.passcode!,
        currentLength: currentState.user.passcodeLength!,
      ),
    );

    if (result != null && context.mounted) {
      final passcode = result['passcode'] as String;
      final length = result['length'] as int;

      try {
        final userSelectionRepo = context.read<UserSelectionRepository>();

        await userSelectionRepo.setTeamMemberPasscode(
          currentState.user.uniqueKey,
          passcode,
          length,
        );

        // Refresh user data
        bloc.add(const CheckCachedUser());

        if (context.mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('קוד גישה שונה בהצלחה'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('שגיאה בשינוי קוד גישה: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showRemovePasscodeDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('הסרת קוד גישה'),
          content: const Text(
            'האם את/ה בטוח/ה שברצונך להסיר את קוד הגישה?\nכל אחד יוכל לגשת לחשבון שלך ללא הגבלה.',
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: const Text('הסר קוד'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        final userSelectionRepo = context.read<UserSelectionRepository>();
        final bloc = context.read<UserSelectionBloc>();
        final currentState = bloc.state;

        if (currentState is UserAuthenticated) {
          await userSelectionRepo.clearTeamMemberPasscode(currentState.user.uniqueKey);

          // Refresh user data
          bloc.add(const RefreshUserData());

          if (context.mounted) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('קוד גישה הוסר בהצלחה'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('שגיאה בהסרת קוד גישה: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}