import 'package:flutter/material.dart';

import '../../core/debug/logger.dart';
import '../../core/services/app_version_service.dart';

/// A global blocking overlay shown when the local app version is outdated.
class VersionBlockingOverlay extends StatelessWidget {
  final Widget child;

  const VersionBlockingOverlay({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppVersionService.instance,
      builder: (context, _) {
        final versionService = AppVersionService.instance;
        final isBlocked = versionService.isBlocked;

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Stack(
            children: [
              child,
              if (isBlocked)
                _VersionBlockingDialog(
                  whatsNewItems: versionService.whatsNewItems,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _VersionBlockingDialog extends StatelessWidget {
  final List<String> whatsNewItems;

  const _VersionBlockingDialog({
    required this.whatsNewItems,
  });

  @override
  Widget build(BuildContext context) {
    final maxDialogHeight = MediaQuery.sizeOf(context).height * 0.85;

    return Material(
      color: Colors.black54,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          constraints: BoxConstraints(
            maxWidth: 420,
            maxHeight: maxDialogHeight,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 520;
              final outerPadding = compact ? 16.0 : 24.0;
              final iconSize = compact ? 56.0 : 80.0;
              final iconInnerSize = compact ? 30.0 : 40.0;

              return Padding(
                padding: EdgeInsets.all(outerPadding),
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Container(
                      width: iconSize,
                      height: iconSize,
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.system_update_rounded,
                        size: iconInnerSize,
                        color: Colors.orange[700],
                      ),
                    ),
                    SizedBox(height: compact ? 12 : 20),
                    Text(
                      'נדרשת רענון אפליקציה',
                      style: TextStyle(
                        fontSize: compact ? 19 : 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[900],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: compact ? 8 : 12),
                    Text(
                      'זוהתה גרסה חדשה של המערכת.\n'
                      'יש לרענן את האפליקציה כדי להמשיך.',
                      style: TextStyle(
                        fontSize: compact ? 14 : 16,
                        color: Colors.grey[600],
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: compact ? 12 : 18),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'אז במה התחדשנו?',
                        style: TextStyle(
                          fontSize: compact ? 15 : 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey[900],
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    SizedBox(height: compact ? 6 : 10),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: whatsNewItems
                              .map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '• ',
                                        style: TextStyle(
                                          fontSize: compact ? 15 : 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          item,
                                          style: TextStyle(
                                            fontSize: compact ? 14 : 15,
                                            color: Colors.grey[700],
                                            height: 1.35,
                                          ),
                                          textAlign: TextAlign.right,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                    SizedBox(height: compact ? 12 : 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          Logger.action('tap:refreshApp');
                          await AppVersionService.instance.refreshApp();
                        },
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(
                            vertical: compact ? 11 : 14,
                          ),
                        ),
                        child: const Text('רענון האפליקציה'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
