import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/track.dart';

class ApiService {
  static String _customBaseUrl = '';
  static String get baseUrl {
    if (_customBaseUrl.isNotEmpty) return _customBaseUrl;
    if (kIsWeb) {
      final host = Uri.base.host;
      if (host.isNotEmpty && host != 'localhost' && host != '127.0.0.1') {
        return '${Uri.base.scheme}://$host:8888';
      }
    }
    return 'http://139.180.216.110:8888';
  }
  static set baseUrl(String url) {
    _customBaseUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('bm_dj_custom_base_url', _customBaseUrl);
    });
  }

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString('bm_dj_custom_base_url');
      if (savedUrl != null && savedUrl.isNotEmpty) {
        _customBaseUrl = savedUrl.trim().replaceAll(RegExp(r'/+$'), '');
      }
    } catch (_) {}
  }

  static String? authToken;
  static bool isTestMode = false;

  static Map<String, String> get headers {
    final map = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (authToken != null && authToken!.isNotEmpty) {
      map['Authorization'] = 'Token $authToken';
    }
    return map;
  }

  static final YoutubeExplode _ytExplode = YoutubeExplode();

  static String extractVideoId(String videoIdOrUrl) {
    final v = videoIdOrUrl.trim();
    final reg = RegExp(r'(?:v=|youtu\.be/|shorts/)([a-zA-Z0-9_-]{11})');
    final match = reg.firstMatch(v);
    if (match != null) {
      return match.group(1)!;
    }
    if (v.length == 11 && !v.contains('/') && !v.contains('.')) {
      return v;
    }
    return v;
  }

  /// Resolves video_id or query/URL to track info with direct stream URL
  static Future<Track?> resolveStream(String videoIdOrUrl) async {
    if (isTestMode) return null;
    final actualId = extractVideoId(videoIdOrUrl);

    // 1. Try Backend Stream Resolver (fast timeout)
    try {
      final uri = Uri.parse('$baseUrl/api/v1/stream/resolve').replace(
        queryParameters: {'video_id': actualId.isNotEmpty ? actualId : videoIdOrUrl},
      );

      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['status'] == 'success' && body['data'] != null) {
          final data = Map<String, dynamic>.from(body['data']);
          final sUrl = data['stream_url']?.toString();
          if (sUrl != null && sUrl.startsWith('/')) {
            data['stream_url'] = '$baseUrl$sUrl';
          }
          return Track.fromJson(data);
        }
      } else {
        debugPrint('Backend stream resolve status ${response.statusCode}, activating local fallback');
      }
    } catch (e) {
      debugPrint('Backend stream resolve error: $e, activating local fallback');
    }

    // 2. High-Performance Client Fallback (Direct via YoutubeExplode)
    // Runs on the user's connection, bypassing datacenter IP bans and cloud server issues!
    if (!kIsWeb && actualId.isNotEmpty) {
      try {
        final manifest = await _ytExplode.videos.streamsClient.getManifest(actualId);
        // Prefer MP4 / AAC (mp4a) audio format because Windows Media Foundation (WinRT MediaPlayer)
        // natively supports MP4/AAC without extra codec packs. WebM/Opus causes Item error on Windows!
        final mp4Streams = manifest.audioOnly.where(
          (s) => s.container.name.toLowerCase() == 'mp4' || s.audioCodec.toLowerCase().contains('mp4a'),
        );
        final audioStream = mp4Streams.isNotEmpty
            ? mp4Streams.withHighestBitrate()
            : manifest.audioOnly.withHighestBitrate();
        final sUrl = audioStream.url.toString();
        if (sUrl.isNotEmpty) {
          debugPrint('[LOCAL_RESOLVER] Successfully resolved MP4 AAC audio stream on client for: $actualId');
          return Track(
            videoId: actualId,
            title: '',
            artist: '',
            durationSeconds: 0,
            streamUrl: sUrl,
            source: 'youtube',
          );
        }
      } catch (e) {
        debugPrint('[LOCAL_RESOLVER] Local stream resolution failed: $e');
      }
    }

    return null;
  }

  /// Search YouTube or YouTube Music for tracks, matching playlists, channels, and albums
  static Future<Map<String, dynamic>> searchWithPlaylists(
    String query, {
    String source = 'youtube',
    String filter = 'all',
    int limit = 14,
  }) async {
    if (isTestMode) return {'tracks': <Track>[], 'playlists': [], 'channels': [], 'albums': []};
    try {
      final uri = Uri.parse('$baseUrl/api/v1/stream/search').replace(
        queryParameters: {
          'q': query,
          'source': source,
          'filter': filter,
          'limit': limit.toString(),
        },
      );

      var response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 25));
      if (response.statusCode == 401 && authToken != null) {
        // Token was rejected, clear it and retry as guest
        authToken = null;
        SharedPreferences.getInstance().then((p) => p.remove('bm_dj_token'));
        response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 25));
      }
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final rawTracks = (body['data'] is List) ? (body['data'] as List) : [];
        final tracks = rawTracks.map((item) => Track.fromJson(item)).toList();
        final rawPlaylists = (body['playlists'] is List) ? (body['playlists'] as List) : [];
        final playlists = rawPlaylists.map((p) => p as Map<String, dynamic>).toList();
        final rawChannels = (body['channels'] is List) ? (body['channels'] as List) : [];
        final channels = rawChannels.map((c) => c as Map<String, dynamic>).toList();
        final rawAlbums = (body['albums'] is List) ? (body['albums'] as List) : [];
        final albums = rawAlbums.map((a) => a as Map<String, dynamic>).toList();

        return {
          'tracks': tracks,
          'playlists': playlists,
          'channels': channels,
          'albums': albums,
          'source': body['source'] ?? source,
          'is_playlist': body['is_playlist'] == true,
          'playlist_title': body['playlist_title'],
        };
      }
    } catch (e) {
      debugPrint('Error searching tracks & playlists: $e');
    }
    return {'tracks': <Track>[], 'playlists': [], 'channels': [], 'albums': []};
  }

  /// Search YouTube or YouTube Music for tracks (legacy helper)
  static Future<List<Track>> searchTracks(
    String query, {
    String source = 'youtube',
    String filter = 'all',
    int limit = 10,
  }) async {
    final res = await searchWithPlaylists(query, source: source, filter: filter, limit: limit);
    return (res['tracks'] as List<Track>?) ?? [];
  }

  /// Fetch related songs/videos (Up Next / Radio recommendations)
  static Future<List<Track>> getRelatedTracks(
    String videoId, {
    String source = 'youtube',
    String? title,
  }) async {
    if (isTestMode) return [];
    try {
      final queryParams = {'video_id': videoId, 'source': source};
      if (title != null && title.isNotEmpty) queryParams['title'] = title;

      final uri = Uri.parse('$baseUrl/api/v1/stream/related').replace(queryParameters: queryParams);
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final raw = (body['data'] is List) ? (body['data'] as List) : [];
        return raw.map((item) => Track.fromJson(item)).toList();
      }
    } catch (e) {
      debugPrint('Error fetching related tracks: $e');
    }
    return [];
  }

  /// Fetch channel or artist page details and all their uploaded videos/songs
  static Future<Map<String, dynamic>> getChannelDetails({
    String? channelId,
    String? name,
    String source = 'youtube',
  }) async {
    if (isTestMode) return {'tracks': <Track>[]};
    try {
      final queryParams = <String, String>{'source': source};
      if (channelId != null && channelId.isNotEmpty) queryParams['channel_id'] = channelId;
      if (name != null && name.isNotEmpty) queryParams['name'] = name;

      final uri = Uri.parse('$baseUrl/api/v1/stream/channel').replace(queryParameters: queryParams);
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final data = body['data'] as Map<String, dynamic>? ?? {};
        final rawTracks = (data['tracks'] is List) ? (data['tracks'] as List) : [];
        final tracks = rawTracks.map((item) => Track.fromJson(item)).toList();

        return {
          'channel_id': data['channel_id'],
          'name': data['name'] ?? name ?? 'Channel',
          'thumbnail': data['thumbnail'],
          'subscribers': data['subscribers'],
          'description': data['description'] ?? '',
          'tracks': tracks,
        };
      }
    } catch (e) {
      debugPrint('Error fetching channel details: $e');
    }
    return {'name': name ?? 'Channel', 'tracks': <Track>[]};
  }

  /// Fetch Explore / Home data (categories, trending playlists, recommended tracks, user_sections)
  static Future<Map<String, dynamic>> getExploreData({
    String category = 'dj',
    String source = 'youtube',
  }) async {
    if (isTestMode) return {'categories': [], 'playlists': [], 'tracks': <Track>[]};
    try {
      final uri = Uri.parse('$baseUrl/api/v1/stream/explore').replace(
        queryParameters: {'category': category, 'source': source},
      );

      var response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 20));
      if (response.statusCode == 401 && authToken != null) {
        authToken = null;
        SharedPreferences.getInstance().then((p) => p.remove('bm_dj_token'));
        response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 20));
      }
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final rawTracks = (body['tracks'] is List) ? (body['tracks'] as List) : [];
        final tracks = rawTracks.map((item) => Track.fromJson(item)).toList();
        final rawPlaylists = (body['playlists'] is List) ? (body['playlists'] as List) : [];
        final playlists = rawPlaylists.map((p) => p as Map<String, dynamic>).toList();
        final rawCats = (body['categories'] is List) ? (body['categories'] as List) : [];
        final categories = rawCats.map((c) => c as Map<String, dynamic>).toList();
        final userSectionsRaw = (body['user_sections'] is Map) ? (body['user_sections'] as Map) : {};
        final Map<String, dynamic> userSections = {};
        userSectionsRaw.forEach((k, v) {
          final keyStr = k.toString();
          if ((keyStr == 'listen_again' || keyStr == 'liked_songs') && v is List) {
            userSections[keyStr] = v
                .whereType<Map<String, dynamic>>()
                .map((item) => Track.fromJson(item))
                .toList();
          } else {
            userSections[keyStr] = v;
          }
        });

        return {
          'categories': categories,
          'playlists': playlists,
          'tracks': tracks,
          'user_sections': userSections,
        };
      }
    } catch (e) {
      debugPrint('Error fetching explore data: $e');
    }
    return {'categories': [], 'playlists': [], 'tracks': <Track>[]};
  }

  /// Fetch all tracks inside any public YouTube or YouTube Music playlist
  static Future<Map<String, dynamic>> getPlaylistTracks(String playlistIdOrUrl) async {
    if (isTestMode) return {'playlist': null, 'tracks': <Track>[]};
    try {
      final uri = Uri.parse('$baseUrl/api/v1/stream/playlist').replace(
        queryParameters: {'id': playlistIdOrUrl},
      );

      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 25));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final rawTracks = (body['data'] is List) ? (body['data'] as List) : [];
        final tracks = rawTracks.map((item) => Track.fromJson(item)).toList();
        final playlistMeta = body['playlist'] as Map<String, dynamic>?;

        return {
          'playlist': playlistMeta,
          'tracks': tracks,
        };
      }
    } catch (e) {
      debugPrint('Error fetching playlist tracks: $e');
    }
    return {'playlist': null, 'tracks': <Track>[]};
  }

  /// Fetch YouTube Music library (History, Liked Songs, Playlists)
  static Future<Map<String, dynamic>> getYTMusicLibrary() async {
    if (authToken == null) {
      return {'history': <Track>[], 'liked_songs': <Track>[], 'playlists': []};
    }

    try {
      final uri = Uri.parse('$baseUrl/api/v1/user/ytmusic/library');
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['status'] == 'success' && body['data'] != null) {
          final data = body['data'];
          final historyList = (data['history'] as List? ?? [])
              .map((item) => Track.fromJson(item))
              .toList();
          final likedList = (data['liked_songs'] as List? ?? [])
              .map((item) => Track.fromJson(item))
              .toList();
          final playlists = (data['playlists'] as List? ?? [])
              .map((item) => item as Map<String, dynamic>)
              .toList();

          return {
            'history': historyList,
            'liked_songs': likedList,
            'playlists': playlists,
            'warning': data['warning'],
            'warning_message': data['warning_message'],
            'enable_url': data['enable_url'],
          };
        }
      }
    } catch (e) {
      debugPrint('Error fetching YTMusic library: $e');
    }

    return {'history': <Track>[], 'liked_songs': <Track>[], 'playlists': []};
  }

  /// Fetch tracks inside a specific YouTube Music playlist
  static Future<List<Track>> getYTMusicPlaylist(String playlistId) async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/user/ytmusic/playlist/$playlistId');
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['status'] == 'success' && body['data'] is List) {
          return (body['data'] as List)
              .map((item) => Track.fromJson(item))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('Error fetching playlist tracks: $e');
    }
    return [];
  }
}
