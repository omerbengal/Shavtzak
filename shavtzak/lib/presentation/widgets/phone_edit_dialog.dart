import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/user_selection/user_selection_bloc.dart';
import '../bloc/user_selection/user_selection_state.dart';
import '../bloc/user_selection/user_selection_event.dart';
import '../../core/utils/validators.dart';
import '../../core/utils/phone_input_formatter.dart';

/// Dialog for editing user's phone number
class PhoneEditDialog extends StatefulWidget {
  const PhoneEditDialog({super.key});

  @override
  State<PhoneEditDialog> createState() => _PhoneEditDialogState();
}

class _PhoneEditDialogState extends State<PhoneEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _phoneController;
  bool _isDirty = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<UserSelectionBloc>().state;
    if (state is UserAuthenticated) {
      _phoneController = TextEditingController(
        text: state.user.phoneNumber ?? '',
      );
    } else {
      _phoneController = TextEditingController();
    }
    _phoneController.addListener(() => setState(() => _isDirty = true));
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.phone, color: Colors.blue),
            const SizedBox(width: 8),
            const Text('עריכת מספר טלפון'),
          ],
        ),
        content: SizedBox(
          width: 300,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'הזן את מספר הטלפון שלך',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(
                    labelText: 'מספר טלפון',
                    hintText: '05X-XXXXXXX',
                    prefixIcon: Icon(Icons.phone),
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  validator: Validators.validatePhoneNumber,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  smartQuotesType: SmartQuotesType.disabled,
                  smartDashesType: SmartDashesType.disabled,
                  textAlign: TextAlign.end, // Right-aligned like the team member modal
                  autofocus: true,
                  inputFormatters: [
                    PhoneNumberTextInputFormatter(),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'פורמט: 05X-XXXXXXX',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: _isDirty ? _savePhone : null,
            child: const Text('שמור'),
          ),
        ],
      ),
    );
  }

  void _savePhone() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final bloc = context.read<UserSelectionBloc>();
    final currentState = bloc.state;

    if (currentState is! UserAuthenticated) {
      return;
    }

    final newPhone = _phoneController.text.trim().isEmpty
        ? null
        : _phoneController.text.trim();

    try {
      // Use the UpdatePhoneNumber event to update the phone number
      bloc.add(UpdatePhoneNumber(newPhone));

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newPhone == null ? 'מספר טלפון הוסר' : 'מספר טלפון עודכן'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בעדכון מספר טלפון: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}