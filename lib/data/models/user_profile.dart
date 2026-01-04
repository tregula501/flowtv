import 'package:isar/isar.dart';

part 'user_profile.g.dart';

/// Access level for parental controls
enum AccessLevel {
  full,       // Full access to all content
  restricted, // Limited access (parental controls)
  kids,       // Kids-only content
}

/// User profile model - for parental controls and personalization
@collection
class UserProfile {
  Id id = Isar.autoIncrement;

  /// Profile name
  @Index()
  late String name;

  /// Profile avatar/icon identifier
  String? avatarId;

  /// PIN code for accessing this profile (hashed)
  String? pinHash;

  /// Is this the master/admin profile?
  bool isMaster = false;

  @Enumerated(EnumType.name)
  late AccessLevel accessLevel;

  /// List of locked channel IDs
  List<int> lockedChannels = [];

  /// List of locked category names
  List<String> lockedCategories = [];

  /// Daily viewing time limit in minutes (0 = unlimited)
  int dailyTimeLimitMinutes = 0;

  /// Allowed viewing hours start (0-23)
  int? allowedHoursStart;

  /// Allowed viewing hours end (0-23)
  int? allowedHoursEnd;

  /// Is this profile active?
  bool isActive = false;

  /// Creation timestamp
  late DateTime createdAt;

  UserProfile();

  factory UserProfile.create({
    required String name,
    required AccessLevel accessLevel,
    bool isMaster = false,
    String? avatarId,
  }) {
    return UserProfile()
      ..name = name
      ..accessLevel = accessLevel
      ..isMaster = isMaster
      ..avatarId = avatarId
      ..createdAt = DateTime.now();
  }

  factory UserProfile.master() {
    return UserProfile()
      ..name = 'Admin'
      ..accessLevel = AccessLevel.full
      ..isMaster = true
      ..isActive = true
      ..createdAt = DateTime.now();
  }
}
