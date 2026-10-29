import 'track.dart';

class UserAccount {
  final int id;
  final String username;
  final String email;
  final String token;
  bool ytmusicConnected;
  String ytmusicUserName;
  List<String> searchHistory;
  List<Track> likedTracks;
  List<Track> savedQueue;
  Map<String, dynamic> settings;

  // Billing, Wallet and Time Limits (Anti-Cheat Server Synced)
  double walletBalance;
  int remainingSeconds;
  bool isVipUnlimited;
  bool isLocked;
  String lockReason;
  String remainingDisplay;
  bool hasActiveSubscription;
  int totalUsedSeconds;

  UserAccount({
    required this.id,
    required this.username,
    required this.email,
    required this.token,
    this.ytmusicConnected = false,
    this.ytmusicUserName = '',
    List<String>? searchHistory,
    List<Track>? likedTracks,
    List<Track>? savedQueue,
    Map<String, dynamic>? settings,
    this.walletBalance = 0.0,
    this.remainingSeconds = 172800, // 48 hours default trial
    this.isVipUnlimited = false,
    this.isLocked = false,
    this.lockReason = '',
    this.remainingDisplay = '48 ชม. 0 นาที',
    this.hasActiveSubscription = true,
    this.totalUsedSeconds = 0,
  })  : searchHistory = searchHistory ?? [],
        likedTracks = likedTracks ?? [],
        savedQueue = savedQueue ?? [],
        settings = settings ?? {};

  String get remainingFormatted {
    if (isVipUnlimited) return '👑 VIP ไม่จำกัดเวลา';
    if (remainingSeconds <= 0) return '⛔ หมดเวลาการใช้งาน';
    final hrs = remainingSeconds ~/ 3600;
    final mins = (remainingSeconds % 3600) ~/ 60;
    final secs = remainingSeconds % 60;
    if (hrs > 0) {
      return '$hrs ชม. $mins นาที';
    } else {
      return '$mins นาที $secs วิ';
    }
  }

  String get walletBalanceFormatted => '${walletBalance.toStringAsFixed(2)} ฿';

  factory UserAccount.fromJson(Map<String, dynamic> json, String token) {
    final userMap = json['user'] is Map<String, dynamic> ? json['user'] : json;
    final memories = json['memories'] is Map<String, dynamic> ? json['memories'] : {};
    final billing = memories['billing'] is Map<String, dynamic>
        ? memories['billing'] as Map<String, dynamic>
        : (json['billing'] is Map<String, dynamic> ? json['billing'] as Map<String, dynamic> : {});

    List<String> history = [];
    if (memories['search_history'] is List) {
      history = (memories['search_history'] as List).map((e) => e.toString()).toList();
    }

    List<Track> liked = [];
    if (memories['liked_tracks'] is List) {
      liked = (memories['liked_tracks'] as List)
          .map((e) => Track.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    List<Track> queue = [];
    if (memories['queue'] is List) {
      queue = (memories['queue'] as List)
          .map((e) => Track.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    final rawBalance = billing['wallet_balance'];
    final double bal = (rawBalance is num) ? rawBalance.toDouble() : 0.0;

    final rawSecs = billing['remaining_seconds'];
    final int secs = (rawSecs is num) ? rawSecs.toInt() : 172800;

    final bool vip = billing['is_vip_unlimited'] == true;
    final bool locked = billing['is_locked'] == true;
    final String lReason = billing['lock_reason']?.toString() ?? '';
    final String rDisplay = billing['remaining_display']?.toString() ?? '';
    final bool active = !locked && (vip || secs > 0);
    final int usedSecs = (billing['total_used_seconds'] is num) ? (billing['total_used_seconds'] as num).toInt() : 0;

    return UserAccount(
      id: userMap['id'] is num ? (userMap['id'] as num).toInt() : 0,
      username: userMap['username']?.toString() ?? 'User',
      email: userMap['email']?.toString() ?? '',
      token: token,
      ytmusicConnected: memories['ytmusic_connected'] == true,
      ytmusicUserName: memories['ytmusic_user_name']?.toString() ?? '',
      searchHistory: history,
      likedTracks: liked,
      savedQueue: queue,
      settings: memories['settings'] is Map<String, dynamic> ? memories['settings'] : {},
      walletBalance: bal,
      remainingSeconds: secs,
      isVipUnlimited: vip,
      isLocked: locked,
      lockReason: lReason,
      remainingDisplay: rDisplay.isNotEmpty ? rDisplay : '$secs วิ',
      hasActiveSubscription: active,
      totalUsedSeconds: usedSecs,
    );
  }
}
