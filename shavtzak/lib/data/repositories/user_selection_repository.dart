import '../../domain/entities/team_member.dart';
import '../../domain/entities/vehicle_info.dart';
import '../../core/services/user_cache_service.dart';
import '../data_sources/database_interface.dart';

/// Repository for user selection operations
/// Handles business logic for user authentication and session management
class UserSelectionRepository {
  final DatabaseInterface _database;
  final UserCacheService _cacheService;

  UserSelectionRepository({
    required DatabaseInterface database,
    required UserCacheService userCacheService,
  })  : _database = database,
        _cacheService = userCacheService;

  /// Select a user by their unique key and cache the selection
  /// Returns the selected team member or throws UserSelectionException if not found
  Future<TeamMember> selectUser(String uniqueKey) async {
    try {
      // Validate that the team member exists
      final teamMember = await _database.getTeamMemberByUniqueKey(uniqueKey);

      if (teamMember == null) {
        throw UserSelectionException('Team member not found with unique key: $uniqueKey');
      }

      // Cache the selection
      await _cacheService.saveSelectedUser(uniqueKey);

      return teamMember;
    } catch (e) {
      if (e is UserSelectionException) rethrow;
      throw UserSelectionException('Failed to select user: $e');
    }
  }

  /// Get the currently cached user
  /// Returns the team member if found, null if no cached user
  Future<TeamMember?> getCachedUser() async {
    try {
      final cachedUniqueKey = await _cacheService.getSelectedUser();

      if (cachedUniqueKey == null || cachedUniqueKey.isEmpty) {
        return null;
      }

      // Fetch the team member from database
      final teamMember = await _database.getTeamMemberByUniqueKey(cachedUniqueKey);

      if (teamMember == null) {
        // Cached user no longer exists in database, clear the cache
        await _cacheService.clearSelection();
        return null;
      }

      return teamMember;
    } catch (e) {
      throw UserSelectionException('Failed to get cached user: $e');
    }
  }

  /// Clear the current user selection from cache
  Future<void> clearUserSelection() async {
    try {
      await _cacheService.clearSelection();
    } catch (e) {
      throw UserSelectionException('Failed to clear user selection: $e');
    }
  }

  /// Check if there's a cached user selection
  Future<bool> hasCachedUser() async {
    try {
      return await _cacheService.hasCachedUser();
    } catch (e) {
      throw UserSelectionException('Failed to check cached user: $e');
    }
  }

  /// Get all team members for the whoami screen (includes active and inactive)
  Future<List<TeamMember>> getAllTeamMembers() async {
    try {
      return await _database.getTeamMembers();
    } catch (e) {
      throw UserSelectionException('Failed to get team members: $e');
    }
  }

  /// Search team members by name (case-insensitive partial match)
  Future<List<TeamMember>> searchTeamMembers(String query) async {
    try {
      final allMembers = await _database.getTeamMembers();

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
      final teamMember = await _database.getTeamMemberByUniqueKey(uniqueKey);
      return teamMember != null;
    } catch (e) {
      return false;
    }
  }

  /// Verify team member's passcode
  Future<bool> verifyTeamMemberPasscode(String uniqueKey, String enteredPasscode) async {
    try {
      final teamMember = await _database.getTeamMemberByUniqueKey(uniqueKey);
      if (teamMember == null || teamMember.passcode == null) {
        return false;
      }
      return teamMember.passcode == enteredPasscode;
    } catch (e) {
      throw UserSelectionException('Failed to verify passcode: $e');
    }
  }

  /// Set passcode for a team member
  /// Uses field-specific update to prevent race conditions with concurrent edits
  Future<void> setTeamMemberPasscode(String uniqueKey, String passcode, int length) async {
    try {
      final teamMember = await _database.getTeamMemberByUniqueKey(uniqueKey);
      if (teamMember == null) {
        throw UserSelectionException('Team member not found with unique key: $uniqueKey');
      }

      await _database.updateTeamMemberPasscode(teamMember.id, passcode, length);
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
        throw UserSelectionException('Team member not found with unique key: $uniqueKey');
      }

      await _database.clearTeamMemberPasscode(teamMember.id);
    } catch (e) {
      if (e is UserSelectionException) rethrow;
      throw UserSelectionException('Failed to clear passcode: $e');
    }
  }

  /// Check if team member has a passcode set
  Future<bool> hasTeamMemberPasscode(String uniqueKey) async {
    try {
      final teamMember = await _database.getTeamMemberByUniqueKey(uniqueKey);
      return teamMember?.passcode != null && teamMember?.passcode!.isNotEmpty == true;
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
  Future<void> updateTeamMemberPhoneNumber(String uniqueKey, String? phoneNumber) async {
    try {
      final teamMember = await _database.getTeamMemberByUniqueKey(uniqueKey);
      if (teamMember == null) {
        throw UserSelectionException('Team member not found with unique key: $uniqueKey');
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
  Future<void> updateTeamMemberBirthday(String uniqueKey, DateTime? birthday) async {
    try {
      final teamMember = await _database.getTeamMemberByUniqueKey(uniqueKey);
      if (teamMember == null) {
        throw UserSelectionException('Team member not found with unique key: $uniqueKey');
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
  Future<void> updateTeamMemberVehicleInfo(String uniqueKey, VehicleInfo? vehicleInfo) async {
    try {
      final teamMember = await _database.getTeamMemberByUniqueKey(uniqueKey);
      if (teamMember == null) {
        throw UserSelectionException('Team member not found with unique key: $uniqueKey');
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
}

/// Custom exception for user selection errors
class UserSelectionException implements Exception {
  final String message;
  UserSelectionException(this.message);

  @override
  String toString() => 'UserSelectionException: $message';
}