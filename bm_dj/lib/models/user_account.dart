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
  })  : searchHistory = searchHistory ?? [],
        likedTracks = likedTracks ?? [],
        savedQueue = savedQueue ?? [],
        settings = settings ?? {};

  factory UserAccount.fromJson(Map<String, dynamic> json, String token) {
    final userMap = json['user'] is Map<String, dynamic> ? json['user'] : json;
    final memories = json['memories'] is Map<String, dynamic> ? json['memories'] : {};

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
    );
  }
}
