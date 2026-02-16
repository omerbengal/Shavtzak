import '../../domain/entities/team_member.dart';

/// Holds the currently authenticated user for centralized audit logging.
class AuditContextService {
  static final AuditContextService _instance = AuditContextService._internal();
  factory AuditContextService() => _instance;
  AuditContextService._internal();

  static AuditContextService get instance => _instance;

  TeamMember? _currentUser;

  TeamMember? get currentUser => _currentUser;

  void setCurrentUser(TeamMember? user) {
    _currentUser = user;
  }

  void clear() {
    _currentUser = null;
  }
}
