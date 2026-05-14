import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/link.dart';

import '../../../core/services/environment_service.dart';
import '../../../core/utils/rtl_text_field_utils.dart';
import '../../../domain/entities/team_member.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_event.dart';
import '../../bloc/user_selection/user_selection_state.dart';
import '../../widgets/loading_overlay.dart';
import '../../widgets/passcode_verification_dialog.dart';
import '../../widgets/test_environment_indicator.dart';

/// Screen for user selection - "מי את/ה?"
class WhoamiScreen extends StatefulWidget {
  const WhoamiScreen({super.key});

  @override
  State<WhoamiScreen> createState() => _WhoamiScreenState();
}

class _WhoamiScreenState extends State<WhoamiScreen> {
  final TextEditingController _searchController = TextEditingController();
  late final FocusNode _searchFocusNode;

  List<TeamMember> _allTeamMembers = [];
  List<TeamMember> _filteredTeamMembers = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String? _errorMessage;
  bool _isAuthenticating = false;

  @override
  void initState() {
    super.initState();
    _searchFocusNode = createRtlCursorFixedFocusNode(_searchController);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final bloc = context.read<UserSelectionBloc>();
      bloc.add(const CheckCachedUser());
      bloc.add(const LoadAllTeamMembers());
    });

    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _applySearchFilter() {
    if (_searchQuery.isEmpty) {
      _filteredTeamMembers = List.from(_allTeamMembers);
      return;
    }

    _filteredTeamMembers = _allTeamMembers.where((member) {
      return member.name.toLowerCase().contains(_searchQuery);
    }).toList();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      _searchQuery = query;
      _applySearchFilter();
    });
  }

  void _updateMembers(List<TeamMember> members) {
    _allTeamMembers = members.where((member) => !member.allowMultipleAssignments).toList();
    _applySearchFilter();
  }

  Future<void> _handleTeamMemberSelection(
    BuildContext context,
    TeamMember teamMember,
  ) async {
    setState(() => _isAuthenticating = true);

    try {
      if (teamMember.hasPasscode && teamMember.passcodeLength != null) {
        setState(() => _isAuthenticating = false);

        final enteredPasscode = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (context) => PasscodeVerificationDialog(
            passcodeLength: teamMember.passcodeLength!,
          ),
        );

        if (enteredPasscode != null && enteredPasscode.isNotEmpty && context.mounted) {
          setState(() => _isAuthenticating = true);
          context
              .read<UserSelectionBloc>()
              .add(SelectUser(teamMember.uniqueKey, enteredPasscode));
        }
      } else {
        setState(() => _isAuthenticating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('לחשבון זה לא מוגדר קוד גישה. יש לפנות למנהל/ת.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      setState(() => _isAuthenticating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('שגיאה בבחירת משתמש: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _handleUserSelectionState(BuildContext context, UserSelectionState state) {
    if (state is UserSelectionLoading) {
      if (_allTeamMembers.isEmpty && !_isAuthenticating) {
        setState(() {
          _isLoading = true;
          _errorMessage = null;
        });
      }
      return;
    }

    if (state is TeamMembersLoaded) {
      setState(() {
        _isLoading = false;
        _errorMessage = null;
        _updateMembers(state.teamMembers);
      });
      return;
    }

    if (state is UserSelectionValidationError) {
      setState(() {
        _isAuthenticating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(state.message),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (state is UserSelectionError) {
      setState(() {
        _isLoading = false;
        _isAuthenticating = false;
        _errorMessage = state.message;
      });
      return;
    }

    if (state is UserAuthenticated) {
      setState(() {
        _isAuthenticating = false;
      });
      return;
    }

    if (state is UserSelectionRequired) {
      if (_allTeamMembers.isNotEmpty) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('שבצק - Shavtzak'),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.cleaning_services),
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
            child: BlocConsumer<UserSelectionBloc, UserSelectionState>(
              listener: _handleUserSelectionState,
              builder: (context, state) {
                return _buildSingleScreenLayout(context);
              },
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
    }
  }

  Widget _buildSingleScreenLayout(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            Container(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 40),
                  Text(
                    'מי את/ה?',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'חפש/י את עצמך ברשימת חברי הצוות',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.grey[600],
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    decoration: const InputDecoration(
                      hintText: 'חפש/י את השם שלך...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _buildTeamMembersListWidget(context),
            ),
            _buildFooter(context),
          ],
        ),
        LoadingOverlay(
          isLoading: _isAuthenticating,
          message: 'מאמת...',
        ),
      ],
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24.0, 12.0, 24.0, 16.0),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(
          top: BorderSide(color: Colors.grey.shade300, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Link(
            uri: Uri.parse(
              '${EnvironmentService.instance.routePrefix}/privacy-policy',
            ),
            target: LinkTarget.self,
            builder: (context, followLink) => TextButton.icon(
              onPressed: followLink,
              icon: const Icon(Icons.privacy_tip_outlined, size: 18),
              label: const Text(
                'מדיניות פרטיות',
                style: TextStyle(decoration: TextDecoration.underline),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'שבצק היא מערכת לניהול צוותים ושיבוץ חברי צוות לאירועים. '
            'מנהלים יוצרים אירועים, מגדירים את התפקידים הנדרשים ומשבצים '
            'חברי צוות בהתאם לזמינות וליכולות שלהם. חברי הצוות יכולים '
            'לצפות בשיבוצים האישיים שלהם, לעדכן את זמינותם ולתאם את ההגעה '
            'לאירועים בקלות ובמקום אחד.',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTeamMembersListWidget(BuildContext context) {
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
                  _isLoading = true;
                });
                context.read<UserSelectionBloc>().add(const LoadAllTeamMembers());
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
              onPressed: () {
                setState(() => _isLoading = true);
                context.read<UserSelectionBloc>().add(const LoadAllTeamMembers());
              },
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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (teamMember.hasPasscode) ...[
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
