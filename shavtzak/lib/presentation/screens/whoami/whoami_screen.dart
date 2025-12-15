import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/entities/team_member.dart';
import '../../../data/repositories/user_selection_repository.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_event.dart';
import '../../bloc/user_selection/user_selection_state.dart';
import '../../widgets/test_environment_indicator.dart';
import '../../widgets/passcode_verification_dialog.dart';

/// Screen for user selection - "מי את/ה?"
class WhoamiScreen extends StatefulWidget {
  const WhoamiScreen({super.key});

  @override
  State<WhoamiScreen> createState() => _WhoamiScreenState();
}

class _WhoamiScreenState extends State<WhoamiScreen> {
  final TextEditingController _searchController = TextEditingController();

  List<TeamMember> _allTeamMembers = [];
  List<TeamMember> _filteredTeamMembers = [];
  bool _isLoading = false;
  String _searchQuery = '';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Trigger initial check and load team members
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UserSelectionBloc>().add(const CheckCachedUser());
      _loadAllTeamMembers();
    });

    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredTeamMembers = List.from(_allTeamMembers);
      } else {
        _filteredTeamMembers = _allTeamMembers.where((member) =>
          member.name.toLowerCase().contains(query)
        ).toList();
      }
    });
  }

  Future<void> _handleTeamMemberSelection(BuildContext context, TeamMember teamMember) async {
    // Check if team member has passcode
    if (teamMember.passcode != null && teamMember.passcodeLength != null) {
      // Show passcode verification dialog with ZERO transition duration
      // This is critical for mobile keyboard auto-open: by removing the animation,
      // we keep the focus request closer to the original user tap gesture,
      // giving the browser a better chance to allow keyboard popup
      final verified = await showGeneralDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierLabel: 'Passcode Dialog',
        barrierColor: Colors.black54,
        transitionDuration: Duration.zero, // Instant dialog - no animation
        pageBuilder: (context, animation, secondaryAnimation) => PasscodeVerificationDialog(
          passcodeLength: teamMember.passcodeLength!,
          correctPasscode: teamMember.passcode!,
        ),
      );

      if (verified == true) {
        // Passcode verified, proceed with selection
        if (context.mounted) {
          context.read<UserSelectionBloc>().add(SelectUser(teamMember.uniqueKey));
        }
      }
      // If verified is false or null, do nothing (user cancelled or verification failed)
    } else {
      // No passcode set, proceed directly
      context.read<UserSelectionBloc>().add(SelectUser(teamMember.uniqueKey));
    }
  }

  Future<void> _loadAllTeamMembers() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userSelectionRepo = context.read<UserSelectionRepository>();
      final teamMembers = await userSelectionRepo.getAllTeamMembers();
      setState(() {
        _allTeamMembers = teamMembers;
        _filteredTeamMembers = List.from(teamMembers);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('בחירת משתמש'),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'ניקוי מטמון',
              onPressed: () => _showClearCacheDialog(context),
              iconSize: 24,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              constraints: const BoxConstraints(minWidth: 56, minHeight: 44),
            ),
          ],
        ),
        body: TestEnvironmentIndicator(
          child: SafeArea(
            child: BlocListener<UserSelectionBloc, UserSelectionState>(
              listener: (context, state) {
                if (state is UserAuthenticated) {
                  // Navigate will be handled by router redirect logic
                }
              },
              child: _buildSingleScreenLayout(),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showClearCacheDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('ניקוי מטמון'),
          content: const Text('האם את/ה בטוח/ה שברצונך לנקות את המטמון ולהתחיל מחדש?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('נקה מטמון'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && context.mounted) {
      context.read<UserSelectionBloc>().add(const SignOut());
      // Since we're already on whoami, we don't need to navigate
      // The router redirect logic will handle clearing any cached state
    }
  }

  Widget _buildSingleScreenLayout() {
    return Column(
      children: [
        // Header with title and search
        Container(
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
                'חפש/י את עצמך ברשימת חברי הצוות',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 32),

              // Search field
              TextField(
                controller: _searchController,
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(
                  hintText: 'חפש/י את השם שלך...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),

        // Team members list
        Expanded(
          child: _buildTeamMembersListWidget(),
        ),
      ],
    );
  }

  Widget _buildTeamMembersListWidget() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('טוען רשימת חברי צוות...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red[400],
            ),
            const SizedBox(height: 16),
            Text(
              'שגיאה בטעינת נתונים',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.red[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.red[400],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _errorMessage = null;
                });
                _loadAllTeamMembers();
              },
              child: const Text('נסה שוב'),
            ),
          ],
        ),
      );
    }

    if (_allTeamMembers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'אין חברי צוות במערכת',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _loadAllTeamMembers(),
              child: const Text('רענן'),
            ),
          ],
        ),
      );
    }

    if (_filteredTeamMembers.isEmpty && _searchQuery.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'לא נמצאו חברי צוות עם השם "$_searchQuery"',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'נסה/י לשנות את מונח החיפוש',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Results count (only show when searching)
        if (_searchQuery.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'נמצאו ${_filteredTeamMembers.length} תוצאות',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
            ),
          ),

        // Team members list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            itemCount: _filteredTeamMembers.length,
            itemBuilder: (context, index) {
              final teamMember = _filteredTeamMembers[index];
              return _TeamMemberCard(
                teamMember: teamMember,
                onTap: () async {
                  await _handleTeamMemberSelection(context, teamMember);
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
  final TeamMember teamMember;
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

              // Arrow icon with optional lock indicator
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (teamMember.passcode != null) ...[
                    Icon(
                      Icons.lock,
                      size: 16,
                      color: Theme.of(context).primaryColor,
                    ),
                    const SizedBox(width: 4),
                  ],
                  const Icon(
                    Icons.arrow_back_ios,
                    size: 16,
                    color: Colors.grey,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}