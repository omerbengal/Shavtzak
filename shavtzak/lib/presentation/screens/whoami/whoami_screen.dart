import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_event.dart';
import '../../bloc/user_selection/user_selection_state.dart';

/// Screen for user selection - "מי את/ה?"
class WhoamiScreen extends StatefulWidget {
  const WhoamiScreen({super.key});

  @override
  State<WhoamiScreen> createState() => _WhoamiScreenState();
}

class _WhoamiScreenState extends State<WhoamiScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    debugPrint('🏠 WHOAMI SCREEN: initState() called');
    // Trigger initial check and load team members
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('🏠 WHOAMI SCREEN: Adding CheckCachedUser event');
      context.read<UserSelectionBloc>().add(const CheckCachedUser());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SafeArea(
          child: BlocConsumer<UserSelectionBloc, UserSelectionState>(
            listener: (context, state) {
              if (state is UserAuthenticated) {
                // Navigate will be handled by router redirect logic
              }
            },
            builder: (context, state) {
              if (state is UserSelectionLoading) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('בודק את הזהות שלך...'),
                    ],
                  ),
                );
              }

              if (state is UserSelectionError) {
                return _buildErrorState(state.message);
              }

              if (state is UserSignedOut) {
                return _buildWhoamiContent();
              }

              if (state is TeamMembersLoaded) {
                return _buildTeamMembersList(state);
              }

              if (state is UserSelectionRequired ||
                  state is UserSelectionValidationError) {
                return _buildWhoamiContent();
              }

              // Default case - show whoami content
              return _buildWhoamiContent();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              'אירעה שגיאה',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                context.read<UserSelectionBloc>().add(const CheckCachedUser());
              },
              child: const Text('נסה שוב'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWhoamiContent() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 40),

          // Title
          Text(
            'מי את/ה?',
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 16),

          // Subtitle
          Text(
            'בחר/י את עצמך מרשימת חברי הצוות',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 32),

          // Search field
          TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            decoration: const InputDecoration(
              hintText: 'חפש/י את השם שלך...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (query) {
              context.read<UserSelectionBloc>().add(SearchTeamMembers(query));
            },
          ),

          const SizedBox(height: 24),

          // Load all team members button
          ElevatedButton.icon(
            onPressed: () {
              context.read<UserSelectionBloc>().add(const LoadAllTeamMembers());
              _searchFocusNode.unfocus();
            },
            icon: const Icon(Icons.list),
            label: const Text('הצג את כל חברי הצוות'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamMembersList(TeamMembersLoaded state) {
    final teamMembers = state.filteredMembers;

    if (teamMembers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Back to search
            IconButton(
              onPressed: () {
                _searchController.clear();
                context.read<UserSelectionBloc>().add(const SearchTeamMembers(''));
              },
              icon: const Icon(Icons.arrow_back),
            ),

            const SizedBox(height: 20),

            Text(
              state.searchQuery != null && state.searchQuery!.isNotEmpty
                  ? 'לא נמצאו חברי צוות עם השם "${state.searchQuery}"'
                  : 'אין חברי צוות במערכת',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Search bar and back
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              IconButton(
                onPressed: () {
                  _searchController.clear();
                  context.read<UserSelectionBloc>().add(const SearchTeamMembers(''));
                },
                icon: const Icon(Icons.arrow_back),
              ),

              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  decoration: const InputDecoration(
                    hintText: 'חפש/י את השם שלך...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (query) {
                    context.read<UserSelectionBloc>().add(SearchTeamMembers(query));
                  },
                ),
              ),
            ],
          ),
        ),

        // Results count
        if (state.searchQuery != null && state.searchQuery!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'נמצאו ${teamMembers.length} תוצאות',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
            ),
          ),

        // Team members list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: teamMembers.length,
            itemBuilder: (context, index) {
              final teamMember = teamMembers[index];
              return _TeamMemberCard(
                teamMember: teamMember,
                onTap: () {
                  debugPrint('🏠 WHOAMI SCREEN: User tapped on ${teamMember.name}, isAdmin=${teamMember.isAdmin}');
                  context.read<UserSelectionBloc>().add(SelectUser(teamMember.uniqueKey));
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TeamMemberCard extends StatelessWidget {
  final teamMember;
  final VoidCallback onTap;

  const _TeamMemberCard({
    required this.teamMember,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12.0),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 24,
                backgroundColor: teamMember.isActive
                    ? Theme.of(context).primaryColor
                    : Colors.grey[400],
                child: Text(
                  teamMember.name.isNotEmpty ? teamMember.name[0] : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),

              const SizedBox(width: 16),

              // Name and status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      teamMember.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (!teamMember.isActive)
                      Text(
                        'לא פעיל/ה',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                  ],
                ),
              ),

              // Arrow icon
              const Icon(
                Icons.arrow_back_ios,
                size: 16,
                color: Colors.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }
}