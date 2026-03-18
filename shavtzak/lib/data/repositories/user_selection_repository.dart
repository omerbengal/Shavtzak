import 'dart:developer' as developer;

import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/entities/team_member.dart';
import '../../domain/entities/vehicle_info.dart';
import '../../core/services/backend_api_service.dart';
import '../../core/services/user_cache_service.dart';
import '../data_sources/database_interface.dart';

/// Repository for user selection operations
/// Handles business logic for user authentication and session management
class UserSelectionRepository {
  final DatabaseInterface _database;
  final UserCacheService _cacheService;
  final BackendApiService _backendApiService;
  final FirebaseAuth _firebaseAuth;

  UserSelectionRepository({
    required DatabaseInterface database,
    required UserCacheService userCacheService,
    BackendApiService? backendApiService,
    FirebaseAuth? firebaseAuth,
  })  : _database = database,
        _cacheService = userCacheService,
        _backendApiService = backendApiService ?? BackendApiService(),
        _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  /// Select a user by their unique key and cache the selection
  /// Returns the selected team member or throws UserSelectionException if not found
  Future<TeamMember> selectUser(String uniqueKey, String passcode) async {
    try {
      final authResponse = await _backendApiService.signInWithPasscode(
        uniqueKey: uniqueKey,
        passcode: passcode,
      );

      final customToken = authResponse['customToken'] as String?;
      if (customToken == null || customToken.isEmpty) {
        throw UserSelectionException('Missing Firebase custom token');
      }

      await _firebaseAuth.signInWithCustomToken(customToken);

      final memberId = authResponse['memberId'] as String?;
      TeamMember? teamMember;
      if (memberId != null && memberId.isNotEmpty) {
        teamMember = await _database.getTeamMemberById(memberId);
      }
      teamMember ??= await _database.getTeamMemberByUniqueKey(uniqueKey);

      if (teamMember == null) {
        throw UserSelectionException(
          'Team member not found after sign-in with unique key: $uniqueKey',
        );
      }

      await _cacheService.saveSelectedUser(teamMember.uniqueKey);
      await _cacheService.clearSessionToken();

      return teamMember;
    } catch (e) {
      if (e is FirebaseAuthException) {
        developer.log(
          'Firebase signInWithCustomToken failed: code=${e.code}, message=${e.message}',
          name: 'UserSelectionRepository',
          error: e,
        );
        throw UserSelectionException(
          'Firebase auth failed (${e.code}): ${e.message ?? 'Unknown Firebase Auth error'}',
        );
      }
      if (e is UserSelectionException) rethrow;
      throw UserSelectionException('Failed to select user: $e');
    }
  }

  /// Get the currently cached user
  /// Returns the team member if found, null if no cached user
  Future<TeamMember?> getCachedUser() async {
    try {
      final firebaseUser = _firebaseAuth.currentUser;
      if (firebaseUser == null) {
        return null;
      }

      await _backendApiService.validateSession();

      final teamMember = await _database.getTeamMemberById(firebaseUser.uid);
      if (teamMember == null) {
        await clearUserSelection();
        return null;
      }

      await _cacheService.saveSelectedUser(teamMember.uniqueKey);
      await _cacheService.clearSessionToken();
      return teamMember;
    } catch (e) {
      await clearUserSelection();
      throw UserSelectionException('Failed to get cached user: $e');
    }
  }

  /// Clear the current user selection from cache
  Future<void> clearUserSelection() async {
    try {
      await _backendApiService.signOut();
    } finally {
      await _cacheService.clearSelection();
    }
  }

  /// Check if there's a cached user selection or an active Firebase session.
  Future<bool> hasCachedUser() async {
    try {
      return _firebaseAuth.currentUser != null ||
          await _cacheService.hasCachedUser();
    } catch (e) {
      throw UserSelectionException('Failed to check cached user: $e');
    }
  }

  Future<List<TeamMember>> _loadSelectableMembers() async {
    final members = await _backendApiService.listSelectableMembers();
    final now = DateTime.now();

    return members.map((member) {
      final uniqueKey =
          member['uniqueKey'] as String? ?? member['id'] as String? ?? '';
      return TeamMember(
        id: member['id'] as String? ?? uniqueKey,
        name: member['name'] as String? ?? '',
        isActive: member['isActive'] == true,
        constraints: const [],
        roleCapabilities: const {},
        createdAt: now,
        updatedAt: now,
        uniqueKey: uniqueKey,
        passcodeLength: member['passcodeLength'] as int?,
        allowMultipleAssignments: member['allowMultipleAssignments'] == true,
      );
    }).toList();
  }

  /// Get all team members for the whoami screen (includes active and inactive)
  Future<List<TeamMember>> getAllTeamMembers() async {
    try {
      return await _loadSelectableMembers();
    } catch (e) {
      throw UserSelectionException('Failed to get team members: $e');
    }
  }

  /// Search team members by name (case-insensitive partial match)
  Future<List<TeamMember>> searchTeamMembers(String query) async {
    try {
      final allMembers = await _loadSelectableMembers();

      if (query.isEmpty) {
        return allMembers;
      }

      final lowerQuery = query.toLowerCase();
      return allMembers.where((member) {
        return member.name.toLowerCase().contains(lowerQuery);
      }).toList();
    } catch (e) {
      throw UserSelectionException('Failed to search team members: $e');
    }
  }

  /// Validate that a user selection is still valid (user exists and is active)
  Future<bool> validateUserSelection(String uniqueKey) async {
    try {
      if (_firebaseAuth.currentUser == null) {
        return false;
      }

      final sessionData = await _backendApiService.validateSession();
      final sessionUniqueKey = sessionData['uniqueKey'] as String?;
      if (sessionUniqueKey == null || sessionUniqueKey != uniqueKey) {
        return false;
      }
      final teamMember =
          await _database.getTeamMemberById(_firebaseAuth.currentUser!.uid);
      return teamMember != null &&
          teamMember.isActive &&
          !teamMember.isArchived;
    } catch (e) {
      return false;
    }
  }

  /// Verify team member's passcode without changing the current Firebase session.
  Future<bool> verifyTeamMemberPasscode(
    String uniqueKey,
    String enteredPasscode,
  ) async {
    try {
      await _backendApiService.signInWithPasscode(
        uniqueKey: uniqueKey,
        passcode: enteredPasscode,
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Set passcode for a team member
  /// Uses field-specific update to prevent race conditions with concurrent edits
  Future<void> setTeamMemberPasscode(
    String uniqueKey,
    String passcode,
    int length, {
    String? currentPasscode,
  }) async {
    try {
      final teamMember = await _database.getTeamMemberByUniqueKey(uniqueKey);
      if (teamMember == null) {
        throw UserSelectionException(
            'Team member not found with unique key: $uniqueKey');
      }

      await _backendApiService.mutate(
        'teamMember.updatePasscode',
        payload: {
          'memberId': teamMember.id,
          'passcode': passcode,
          'length': length,
          if (currentPasscode != null && currentPasscode.isNotEmpty)
            'currentPasscode': currentPasscode,
        },
      );
    } catch (e) {
      if (e is UserSelectionException) rethrow;
      throw UserSelectionException('Failed to set passcode: $e');
    }
  }

  /// Clear passcode for a team member
  /// Uses field-specific update to prevent race conditions with concurrent edits
  Future<void> clearTeamMemberPasscode(String uniqueKey) async {
    try {
      final teamMember = await _database.getTeamMemberByUniqueKey(uniqueKey);
      if (teamMember == null) {
        throw UserSelectionException(
            'Team member not found with unique key: $uniqueKey');
      }

      await _backendApiService.mutate(
        'teamMember.clearPasscode',
        payload: {
          'memberId': teamMember.id,
        },
      );
    } catch (e) {
      if (e is UserSelectionException) rethrow;
      throw UserSelectionException('Failed to clear passcode: $e');
    }
  }

  /// Reveal the current passcode for a team member.
  /// Existing hash-only passcodes may not be recoverable until they are reset.
  Future<String> getTeamMemberPasscode(String uniqueKey) async {
    try {
      final teamMember = await _database.getTeamMemberByUniqueKey(uniqueKey);
      if (teamMember == null) {
        throw UserSelectionException(
          'Team member not found with unique key: $uniqueKey',
        );
      }

      final response = await _backendApiService.mutate(
        'teamMember.getPasscode',
        payload: {
          'memberId': teamMember.id,
        },
      );

      final passcode = response['passcode'] as String?;
      if (passcode == null || passcode.isEmpty) {
        throw UserSelectionException('לא ניתן להציג את קוד הגישה הקיים');
      }

      return passcode;
    } catch (e) {
      if (e is UserSelectionException) rethrow;
      if (e is BackendApiException) {
        throw UserSelectionException(e.message);
      }
      throw UserSelectionException('Failed to get team member passcode: $e');
    }
  }

  /// Check if team member has a passcode set
  Future<bool> hasTeamMemberPasscode(String uniqueKey) async {
    try {
      final teamMember = await _database.getTeamMemberByUniqueKey(uniqueKey);
      return teamMember?.hasPasscode == true;
    } catch (e) {
      return false;
    }
  }

  /// Get passcode length for a team member
  Future<int?> getTeamMemberPasscodeLength(String uniqueKey) async {
    try {
      final teamMember = await _database.getTeamMemberByUniqueKey(uniqueKey);
      return teamMember?.passcodeLength;
    } catch (e) {
      return null;
    }
  }

  /// Update phone number for a team member
  Future<void> updateTeamMemberPhoneNumber(
      String uniqueKey, String? phoneNumber) async {
    try {
      final teamMember = await _database.getTeamMemberByUniqueKey(uniqueKey);
      if (teamMember == null) {
        throw UserSelectionException(
            'Team member not found with unique key: $uniqueKey');
      }

      final updatedMember = teamMember.copyWith(
        phoneNumber: phoneNumber,
        clearPhone: phoneNumber == null,
        updatedAt: DateTime.now(),
      );

      await _database.updateTeamMember(updatedMember);
    } catch (e) {
      if (e is UserSelectionException) rethrow;
      throw UserSelectionException('Failed to update phone number: $e');
    }
  }

  /// Update birthday for a team member
  Future<void> updateTeamMemberBirthday(
      String uniqueKey, DateTime? birthday) async {
    try {
      final teamMember = await _database.getTeamMemberByUniqueKey(uniqueKey);
      if (teamMember == null) {
        throw UserSelectionException(
            'Team member not found with unique key: $uniqueKey');
      }

      final updatedMember = teamMember.copyWith(
        birthday: birthday,
        clearBirthday: birthday == null,
        updatedAt: DateTime.now(),
      );

      await _database.updateTeamMember(updatedMember);
    } catch (e) {
      if (e is UserSelectionException) rethrow;
      throw UserSelectionException('Failed to update birthday: $e');
    }
  }

  /// Update vehicle info for a team member
  Future<void> updateTeamMemberVehicleInfo(
      String uniqueKey, VehicleInfo? vehicleInfo) async {
    try {
      final teamMember = await _database.getTeamMemberByUniqueKey(uniqueKey);
      if (teamMember == null) {
        throw UserSelectionException(
            'Team member not found with unique key: $uniqueKey');
      }

      final updatedMember = teamMember.copyWith(
        vehicleInfo: vehicleInfo,
        clearVehicleInfo: vehicleInfo == null,
        updatedAt: DateTime.now(),
      );

      await _database.updateTeamMember(updatedMember);
    } catch (e) {
      if (e is UserSelectionException) rethrow;
      throw UserSelectionException('Failed to update vehicle info: $e');
    }
  }

  /// Update email for a team member
  Future<void> updateTeamMemberEmail(String uniqueKey, String? email) async {
    try {
      final teamMember = await _database.getTeamMemberByUniqueKey(uniqueKey);
      if (teamMember == null) {
        throw UserSelectionException(
            'Team member not found with unique key: $uniqueKey');
      }

      final updatedMember = teamMember.copyWith(
        email: email,
        clearEmail: email == null,
        updatedAt: DateTime.now(),
      );

      await _database.updateTeamMember(updatedMember);
    } catch (e) {
      if (e is UserSelectionException) rethrow;
      throw UserSelectionException('Failed to update email: $e');
    }
  }
}

/// Custom exception for user selection errors
class UserSelectionException implements Exception {
  final String message;
  UserSelectionException(this.message);

  @override
  String toString() => 'UserSelectionException: $message';
}
