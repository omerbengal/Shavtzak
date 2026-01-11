import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_event.dart';
import '../../bloc/user_selection/user_selection_state.dart';
import '../../../core/services/environment_service.dart';

/// Choice screen - allows users to choose between available areas
/// For admins: Personal area, Management, and Summary screen
/// For non-admins with summary access: Personal area and Summary screen
class AdminChoiceScreen extends StatelessWidget {
  const AdminChoiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: _buildAppBar(context),
        body: SafeArea(
          child: BlocBuilder<UserSelectionBloc, UserSelectionState>(
            builder: (context, state) {
              if (state is! UserAuthenticated) {
                return const Center(child: CircularProgressIndicator());
              }

              final isAdmin = state.isAdmin;
              final showManagementCard = isAdmin;
              final showSummaryCard = isAdmin || state.user.canAccessSummaryScreen;
              final cardCount = 1 + (showManagementCard ? 1 : 0) + (showSummaryCard ? 1 : 0);

              return LayoutBuilder(
                builder: (context, constraints) {
                  final envPrefix = EnvironmentService.instance.routePrefix;
                  final screenWidth = constraints.maxWidth;
                  final screenHeight = constraints.maxHeight;

                  // Responsive card width
                  final cardWidth = screenWidth > 400 ? 350.0 : screenWidth * 0.85;

                  // Determine if we need compact mode based on available height
                  final isCompact = cardCount > 2 && screenHeight < 600;
                  final cardSpacing = isCompact ? 12.0 : (cardCount > 2 ? 16.0 : 24.0);

                  return Center(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: isCompact ? 16 : 24,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'ברוכים הבאים לשבצק',
                              style: TextStyle(
                                fontSize: isCompact ? 26 : 32,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: isCompact ? 8 : 16),
                            Text(
                              'באיזה כובע תרצה/י להיכנס?',
                              style: TextStyle(
                                fontSize: isCompact ? 16 : 18,
                                color: Colors.grey,
                              ),
                            ),
                            SizedBox(height: isCompact ? 16 : 32),

                            // Personal Area Card (always shown)
                            _buildChoiceCard(
                              width: cardWidth,
                              icon: Icons.person,
                              iconColor: Colors.blue,
                              title: 'איזור אישי',
                              subtitle: 'צפה בשיבוצים ובקשות מגבלות',
                              isCompact: isCompact,
                              onTap: () => context.go('$envPrefix/user/assignments'),
                            ),

                            SizedBox(height: cardSpacing),

                            // Management Card (admin only)
                            if (showManagementCard) ...[
                              _buildChoiceCard(
                                width: cardWidth,
                                icon: Icons.admin_panel_settings,
                                iconColor: Colors.green,
                                title: 'ניהול שבצק',
                                subtitle: 'ניהול צוות, אירועים ושיבוצים',
                                isCompact: isCompact,
                                onTap: () => context.go('$envPrefix/admin/team-members'),
                              ),
                              SizedBox(height: cardSpacing),
                            ],

                            // Summary/Manager Screen Card
                            if (showSummaryCard)
                              _buildChoiceCard(
                                width: cardWidth,
                                icon: Icons.dashboard,
                                iconColor: Colors.purple,
                                title: 'מסך מנהלים',
                                subtitle: 'צפה בסיכום כללי',
                                isCompact: isCompact,
                                onTap: () => context.go('$envPrefix/summary'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  /// Build a choice card - no fixed height, content-sized
  Widget _buildChoiceCard({
    required double width,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool isCompact,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: width,
      child: Card(
        elevation: 4,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: isCompact ? 12 : 20,
              horizontal: 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: isCompact ? 32 : 48, color: iconColor),
                SizedBox(height: isCompact ? 4 : 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: isCompact ? 18 : 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: isCompact ? 2 : 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: isCompact ? 12 : 13,
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Build the app bar with user info and logout button
  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: BlocBuilder<UserSelectionBloc, UserSelectionState>(
        builder: (context, state) {
          if (state is! UserAuthenticated) {
            return AppBar(
              title: const Text('שבצק'),
              centerTitle: true,
            );
          }

          return AppBar(
            title: Text(
              'שלום, ${state.user.name}',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            centerTitle: true,
            leading: const SizedBox.shrink(), // Prevent automatic back arrow
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'התנתקות',
                onPressed: () => _showLogoutDialog(context),
                iconSize: 24,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                constraints: const BoxConstraints(minWidth: 56, minHeight: 44),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Show logout confirmation dialog
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
                  Navigator.of(context).pop();
                },
                child: const Text('ביטול'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
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
