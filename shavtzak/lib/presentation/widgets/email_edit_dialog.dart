import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/user_selection/user_selection_bloc.dart';
import '../bloc/user_selection/user_selection_state.dart';
import '../bloc/user_selection/user_selection_event.dart';
import '../../core/utils/validators.dart';

/// Dialog for editing user's email address
class EmailEditDialog extends StatefulWidget {
  const EmailEditDialog({super.key});

  @override
  State<EmailEditDialog> createState() => _EmailEditDialogState();
}

class _EmailEditDialogState extends State<EmailEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _emailController;
  bool _isDirty = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<UserSelectionBloc>().state;
    if (state is UserAuthenticated) {
      _emailController = TextEditingController(
        text: state.user.email ?? '',
      );
    } else {
      _emailController = TextEditingController();
    }

    _emailController.addListener(() {
      if (mounted) {
        setState(() => _isDirty = true);
      }
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.email, color: Colors.blue),
            SizedBox(width: 8),
            Text('עריכת כתובת אימייל'),
          ],
        ),
        content: SizedBox(
          width: 300,
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'הזן את כתובת האימייל שלך על מנת שתוכל להיות מזומן לאירועים ביומן',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'כתובת אימייל',
                      hintText: 'example@mail.com',
                      prefixIcon: Icon(Icons.email),
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    validator: Validators.validateEmail,
                    keyboardType: TextInputType.emailAddress,
                    textDirection: TextDirection.ltr,
                    smartQuotesType: SmartQuotesType.disabled,
                    smartDashesType: SmartDashesType.disabled,
                    textAlign: TextAlign.start,
                    autofocus: false,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: (_isDirty && !_isSaving) ? _saveEmail : null,
            child: const Text('שמור'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveEmail() async {
    if (_isSaving) return;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final bloc = context.read<UserSelectionBloc>();
    final currentState = bloc.state;

    if (currentState is! UserAuthenticated) {
      // Prevent stuck loading state
      if (mounted) {
        setState(() => _isSaving = false);
      }
      return;
    }

    final trimmed = _emailController.text.trim();
    final newEmail = trimmed.isEmpty ? null : trimmed;

    try {
      // Update email via existing event in your project
      bloc.add(UpdateEmail(newEmail));

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newEmail == null ? 'כתובת אימייל הוסר' : 'כתובת אימייל עודכנה',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בעדכון כתובת אימייל: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
