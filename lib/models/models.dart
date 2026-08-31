import 'dart:convert';

/// User profile stored locally (secure storage) + server-side row.
class Profile {
  final String userId;
  final String callsign;
  final String? route;
  final String publicKeyPem;
  final int avatarColor; // index into palette

  const Profile({
    required this.userId,
    required this.callsign,
    this.route,
    required this.publicKeyPem,
    this.avatarColor = 0,
  });

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'callsign': callsign,
        'route': route,
        'public_key': publicKeyPem,
        'avatar_color': avatarColor,
      };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        userId: j['user_id'] as String,
        callsign: j['callsign'] as String,
        route: j['route'] as String?,
        publicKeyPem: j['public_key'] as String? ?? '',
        avatarColor: j['avatar_color'] as int? ?? 0,
      );

  Profile copyWith({String? callsign, String? route, int? avatarColor}) => Profile(
        userId: userId,
        callsign: callsign ?? this.callsign,
        route: route ?? this.route,
        publicKeyPem: publicKeyPem,
        avatarColor: avatarColor ?? this.avatarColor,
      );

  String encode() => jsonEncode(toJson());
  static Profile decode(String s) => Profile.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

class Channel {
  final int id;
  final String name;
  final bool isPrivate;
  final bool hasInviteCode;
  final int memberCount;
  final String? role; // null = not a member; 'creator' | 'admin' | 'member'

  const Channel({
    required this.id,
    required this.name,
    required this.isPrivate,
    this.hasInviteCode = false,
    this.memberCount = 0,
    this.role,
  });

  factory Channel.fromJson(Map<String, dynamic> j) => Channel(
        id: j['id'] as int,
        name: j['name'] as String,
        isPrivate: j['is_private'] as bool? ?? true,
        hasInviteCode: j['has_invite_code'] as bool? ?? false,
        memberCount: j['member_count'] as int? ?? 0,
        role: j['role'] as String?,
      );

  bool get isAdmin => role == 'creator' || role == 'admin';
  bool get isCreator => role == 'creator';
}

class Member {
  final String userId;
  final String callsign;
  final String? route;
  final String role;
  final bool online;
  final bool muted;
  final bool speaking;

  const Member({
    required this.userId,
    required this.callsign,
    this.route,
    this.role = 'member',
    this.online = false,
    this.muted = false,
    this.speaking = false,
  });

  Member copyWith({bool? online, bool? muted, bool? speaking, String? role}) => Member(
        userId: userId,
        callsign: callsign,
        route: route,
        role: role ?? this.role,
        online: online ?? this.online,
        muted: muted ?? this.muted,
        speaking: speaking ?? this.speaking,
      );

  factory Member.fromJson(Map<String, dynamic> j) => Member(
        userId: j['user_id'] as String,
        callsign: j['callsign'] as String,
        route: j['route'] as String?,
        role: j['role'] as String? ?? 'member',
        online: j['online'] as bool? ?? false,
        muted: j['muted'] as bool? ?? false,
      );

  String get initial => callsign.isEmpty ? '?' : callsign[0].toUpperCase();
}

class JoinRequest {
  final int id;
  final String userId;
  final String callsign;
  final String? route;
  final String createdAt;

  const JoinRequest({
    required this.id,
    required this.userId,
    required this.callsign,
    this.route,
    required this.createdAt,
  });

  factory JoinRequest.fromJson(Map<String, dynamic> j) => JoinRequest(
        id: j['id'] as int,
        userId: j['user_id'] as String,
        callsign: j['callsign'] as String,
        route: j['route'] as String?,
        createdAt: j['created_at'] as String? ?? '',
      );
}

class HistoryEntry {
  final String callsign;
  final String startedAt;
  final double durationSec;

  const HistoryEntry({
    required this.callsign,
    required this.startedAt,
    required this.durationSec,
  });

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        callsign: j['callsign'] as String? ?? '?',
        startedAt: j['started_at'] as String? ?? '',
        durationSec: (j['duration_sec'] as num?)?.toDouble() ?? 0,
      );
}
