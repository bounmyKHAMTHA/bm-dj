import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/track.dart';

/// BM DJ - Standalone Edition (100% Serverless)
/// No Python or backend server required. All search, streaming, and metadata
/// run directly on client device via high-performance Dart engines!
class ApiService {
  static String baseUrl = 'standalone://localhost';
  static const String productionServerUrl = 'standalone://localhost';
  static String? authToken;
  static bool isTestMode = false;
  static bool isLocalhostActive = true;

  static Map<String, String> get headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  static Future<void> clearCustomBaseUrl() async {}

  static final YoutubeExplode _ytExplode = YoutubeExplode();

  static Future<void> init() async {
    debugPrint('[STANDALONE_EDITION] Initialized pure client-side music engine.');
  }

  static Future<Map<String, dynamic>> getYTMusicLibrary() async {
    return {'history': <Track>[], 'liked_songs': <Track>[], 'playlists': []};
  }

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

  /// Resolves video_id to track with direct native MP4 AAC stream URL
  static Future<Track?> resolveStream(String videoIdOrUrl) async {
    if (isTestMode) return null;
    final actualId = extractVideoId(videoIdOrUrl);
    if (actualId.isEmpty) return null;

    try {
      final manifest = await _ytExplode.videos.streamsClient.getManifest(actualId);
      // Prefer MP4 / AAC format (mp4a) for 100% native Windows/Mobile support
      final mp4Streams = manifest.audioOnly.where(
        (s) => s.container.name.toLowerCase() == 'mp4' || s.audioCodec.toLowerCase().contains('mp4a'),
      );
      final audioStream = mp4Streams.isNotEmpty
          ? mp4Streams.withHighestBitrate()
          : manifest.audioOnly.withHighestBitrate();

      final sUrl = audioStream.url.toString();
      if (sUrl.isNotEmpty) {
        debugPrint('[STANDALONE_RESOLVER] Resolved direct MP4 AAC stream for: $actualId');
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
      debugPrint('[STANDALONE_RESOLVER] Error: $e');
    }
    return null;
  }

  /// Search YouTube directly via YoutubeExplode
  static Future<Map<String, dynamic>> searchWithPlaylists(
    String query, {
    String source = 'youtube',
    String filter = 'all',
    int limit = 16,
  }) async {
    if (isTestMode) return {'tracks': <Track>[], 'playlists': [], 'channels': [], 'albums': []};
    try {
      final searchList = await _ytExplode.search.search(query);
      final tracks = searchList.take(limit).map((v) {
        return Track(
          videoId: v.id.value,
          title: v.title,
          artist: v.author,
          durationSeconds: v.duration?.inSeconds ?? 0,
          thumbnailUrl: v.thumbnails.highResUrl,
          source: 'youtube',
          channelId: v.channelId.value,
        );
      }).toList();

      return {
        'tracks': tracks,
        'playlists': [],
        'channels': [],
        'albums': [],
        'source': 'youtube',
        'is_playlist': false,
      };
    } catch (e) {
      debugPrint('[STANDALONE_SEARCH] Error: $e');
    }
    return {'tracks': <Track>[], 'playlists': [], 'channels': [], 'albums': []};
  }

  /// Search YouTube for tracks
  static Future<List<Track>> searchTracks(
    String query, {
    String source = 'youtube',
    String filter = 'all',
    int limit = 12,
  }) async {
    final res = await searchWithPlaylists(query, source: source, filter: filter, limit: limit);
    return (res['tracks'] as List<Track>?) ?? [];
  }

  /// Fetch related songs/videos directly
  static Future<List<Track>> getRelatedTracks(
    String videoId, {
    String source = 'youtube',
    String? title,
  }) async {
    if (isTestMode) return [];
    try {
      final video = await _ytExplode.videos.get(videoId);
      final related = await _ytExplode.videos.getRelatedVideos(video);
      if (related != null && related.isNotEmpty) {
        return related.take(15).map((v) {
          return Track(
            videoId: v.id.value,
            title: v.title,
            artist: v.author,
            durationSeconds: v.duration?.inSeconds ?? 0,
            thumbnailUrl: v.thumbnails.highResUrl,
            source: 'youtube',
            channelId: v.channelId.value,
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('[STANDALONE_RELATED] Error: $e');
    }
    return [];
  }

  /// Fetch explore curated categories directly
  static Future<Map<String, dynamic>> getExploreData({
    String category = 'dj',
    String source = 'youtube',
  }) async {
    if (isTestMode) return {'categories': [], 'playlists': [], 'tracks': <Track>[]};

    final queryMap = {
      'dj': 'dj remix 2026',
      'trending': 'เพลงฮิต 2026',
      'club': 'club dance mix 2026',
      'thai': 'เพลงแดนซ์มันๆ สายย่อ 2026',
      'edm': 'edm festival mix 2026',
    };

    final q = queryMap[category] ?? 'dj remix 2026';
    try {
      final searchList = await _ytExplode.search.search(q);
      final tracks = searchList.take(18).map((v) {
        return Track(
          videoId: v.id.value,
          title: v.title,
          artist: v.author,
          durationSeconds: v.duration?.inSeconds ?? 0,
          thumbnailUrl: v.thumbnails.highResUrl,
          source: 'youtube',
          channelId: v.channelId.value,
        );
      }).toList();

      return {
        'categories': [
          {'id': 'dj', 'title': 'DJ Remix', 'color': '0xFF00F2FE'},
          {'id': 'trending', 'title': 'Trending Hits', 'color': '0xFFFF0055'},
          {'id': 'thai', 'title': 'สายย่อ / รถแห่', 'color': '0xFFFFD700'},
          {'id': 'club', 'title': 'Club Dance', 'color': '0xFF9D00FF'},
          {'id': 'edm', 'title': 'EDM Festival', 'color': '0xFF00FF88'},
        ],
        'playlists': [],
        'tracks': tracks,
        'user_sections': {},
      };
    } catch (e) {
      debugPrint('[STANDALONE_EXPLORE] Error: $e');
    }
    return {'categories': [], 'playlists': [], 'tracks': <Track>[]};
  }

  /// Fetch public playlist tracks directly
  static Future<Map<String, dynamic>> getPlaylistTracks(String playlistIdOrUrl) async {
    if (isTestMode) return {'playlist': null, 'tracks': <Track>[]};
    try {
      final cleanId = playlistIdOrUrl.replaceAll(RegExp(r'.*list='), '');
      final playlist = await _ytExplode.playlists.get(cleanId);
      final rawVideos = await _ytExplode.playlists.getVideos(cleanId).take(30).toList();

      final tracks = rawVideos.map((v) {
        return Track(
          videoId: v.id.value,
          title: v.title,
          artist: v.author,
          durationSeconds: v.duration?.inSeconds ?? 0,
          thumbnailUrl: v.thumbnails.highResUrl,
          source: 'youtube',
          channelId: v.channelId.value,
        );
      }).toList();

      return {
        'playlist': {
          'id': playlist.id.value,
          'title': playlist.title,
          'author': playlist.author,
          'thumbnail': playlist.thumbnails.highResUrl,
        },
        'tracks': tracks,
      };
    } catch (e) {
      debugPrint('[STANDALONE_PLAYLIST] Error: $e');
    }
    return {'playlist': null, 'tracks': <Track>[]};
  }

  static Future<Map<String, dynamic>> getChannelDetails({
    String? channelId,
    String? name,
    String source = 'youtube',
  }) async {
    if (isTestMode) return {'tracks': <Track>[]};
    try {
      if (channelId != null && channelId.isNotEmpty) {
        final channel = await _ytExplode.channels.get(channelId);
        final rawUploads = await _ytExplode.channels.getUploads(channelId).take(20).toList();
        final tracks = rawUploads.map((v) => Track(
          videoId: v.id.value,
          title: v.title,
          artist: v.author,
          durationSeconds: v.duration?.inSeconds ?? 0,
          thumbnailUrl: v.thumbnails.highResUrl,
          source: 'youtube',
          channelId: v.channelId.value,
        )).toList();

        return {
          'channel_id': channel.id.value,
          'name': channel.title,
          'thumbnail': channel.logoUrl,
          'subscribers': null,
          'description': '',
          'tracks': tracks,
        };
      }
    } catch (e) {
      debugPrint('[STANDALONE_CHANNEL] Error: $e');
    }
    return {'name': name ?? 'Channel', 'tracks': <Track>[]};
  }

  static Future<List<String>> getSearchSuggestions(String query) async {
    return [];
  }
}
