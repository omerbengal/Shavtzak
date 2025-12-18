import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/user_selection/user_selection_bloc.dart';
import '../bloc/user_selection/user_selection_state.dart';
import '../bloc/user_selection/user_selection_event.dart';
import '../../data/repositories/user_selection_repository.dart';
import '../../core/utils/validators.dart';
import 'passcode_setup_dialog.dart';
import 'passcode_change_dialog.dart';
import 'phone_edit_dialog.dart';

/// Settings dialog with passcode management
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  bool _isDeleting = false;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: BlocListener<UserSelectionBloc, UserSelectionState>(
        listener: (context, state) {
          if (state is UserSelectionError) {
            // Show error message and reset loading state
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: Colors.red,
                ),
              );
              setState(() {
                _isDeleting = false;
              });
            }
            // Reset to previous state
            context.read<UserSelectionBloc>().add(const RefreshUserData());
          }

          // Listen for successful phone updates
          if (_isDeleting && state is UserAuthenticated) {
            // Show success message when phone is updated
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('מספר טלפון נמחק בהצלחה'),
                  backgroundColor: Colors.green,
                ),
              );
              setState(() {
                _isDeleting = false;
              });
            }
          }
        },
        child: AlertDialog(
          title: const Text('הגדרות'),
          content: SizedBox(
            width: 350,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              // Phone number section
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.phone,
                            color: Theme.of(context).primaryColor,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'מספר טלפון',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      BlocBuilder<UserSelectionBloc, UserSelectionState>(
                        builder: (context, state) {
                          if (state is! UserAuthenticated) {
                            return const SizedBox.shrink();
                          }

                          final phone = state.user.phoneNumber;
                          final formattedPhone = Validators.formatPhoneNumber(phone);

                          if (phone != null && phone.isNotEmpty) {
                            return Column(
                              children: [
                                Text(
                                  formattedPhone,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Colors.blue,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Column(
                                  children: [
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: () => _showPhoneEditDialog(context),
                                        icon: const Icon(Icons.edit, size: 18),
                                        label: const Text(
                                          'ערוך מספר טלפון',
                                          style: TextStyle(fontSize: 14),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          minimumSize: const Size(0, 36),
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: _isDeleting ? null : () => _deletePhoneNumber(context),
                                        icon: _isDeleting
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.red)),
                                              )
                                            : const Icon(Icons.delete, size: 18, color: Colors.red),
                                        label: Text(
                                          _isDeleting ? 'מוחק...' : 'מחק טלפון',
                                          style: TextStyle(fontSize: 14, color: Colors.red),
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          minimumSize: const Size(0, 36),
                                          side: const BorderSide(color: Colors.red),
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        ),
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
                                  Icons.phone_disabled,
                                  size: 48,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'לא הוגדר מספר טלפון',
                                  style: TextStyle(fontSize: 16, color: Colors.grey),
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  onPressed: () => _showPhoneEditDialog(context),
                                  icon: const Icon(Icons.add),
                                  label: const Text('הוסף מספר טלפון'),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 24),
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
                            ElevatedButton(
                              onPressed: () => _showChangePasscodeDialog(context),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              ),
                              child: const Text('שנה קוד'),
                            ),
                            ElevatedButton(
                              onPressed: () => _showRemovePasscodeDialog(context),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              ),
                              child: const Text('הסר קוד'),
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
                        ElevatedButton(
                          onPressed: () => _showSetupPasscodeDialog(context),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            textStyle: const TextStyle(fontSize: 16),
                          ),
                          child: const Text('הגדר קוד גישה'),
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

  void _showPhoneEditDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const PhoneEditDialog(),
    );
  }

  void _deletePhoneNumber(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('מחיקת מספר טלפון'),
          content: const Text('האם את/ה בטוח/ה שברצונך למחוק את מספר הטלפון?'),
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
              child: const Text('מחק'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && context.mounted) {
      setState(() {
        _isDeleting = true;
      });

      final bloc = context.read<UserSelectionBloc>();
      final currentState = bloc.state;

      if (currentState is UserAuthenticated) {
        // Add the update event to delete the phone number
        bloc.add(const UpdatePhoneNumber(null));
      }
    }
  }
}