import 'package:flutter/material.dart';

/// Search box that narrows a dialog's list of people by name. Pair it with
/// `nameMatchesSearch` and show [NameSearchNoResults] when nothing matches.
class NameSearchField extends StatelessWidget {
  final ValueChanged<String> onChanged;

  const NameSearchField({super.key, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      decoration: const InputDecoration(
        hintText: 'חיפוש לפי שם',
        prefixIcon: Icon(Icons.search),
        isDense: true,
        border: OutlineInputBorder(),
      ),
      onChanged: onChanged,
    );
  }
}

/// Shown in place of the list when the search matches no one.
class NameSearchNoResults extends StatelessWidget {
  const NameSearchNoResults({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Text(
        'לא נמצאו אנשים בשם הזה',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey.shade700),
      ),
    );
  }
}
