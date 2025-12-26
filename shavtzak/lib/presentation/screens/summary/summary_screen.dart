import 'package:flutter/material.dart';

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
        ),
        body: const SafeArea(
          child: Center(
            child: Text('תוכן מסך מנהלים'),
          ),
        ),
      ),
    );
  }
}
