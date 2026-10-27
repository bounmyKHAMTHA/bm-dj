import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/track.dart';

/// In-App Local HTTP Streaming Proxy
/// Windows Media Foundation (MediaPlayer) blocks raw googlevideo.com URLs with HTTP 403.
/// This embedded Dart proxy runs directly inside the Flutter app process,
/// intercepts audio requests from just_audio on 127.0.0.1, fetches audio stream chunks
/// with proper browser User-Agent and Range headers, and pipes them back to just_audio.
/// Result: 100% Standalone, 0ms external dependency, Zero Python, Zero server needed!
class LocalAudioProxy {
  static HttpServer? _server;
  static int? _port;
  static final HttpClient _httpClient = HttpClient()
    ..idleTimeout = const Duration(seconds: 30)
    ..connectionTimeout = const Duration(seconds: 15);

  static final YoutubeExplode _yt = YoutubeExplode();
  static final Map<String, String> _urlCache = {};

  static int get port => _port ?? 0;

  static Future<void> ensureStarted() async {
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;
      debugPrint('[STANDALONE_PROXY] In-app audio proxy running on http://127.0.0.1:$_port');
      _server!.listen(_handleRequest, onError: (e) {
        debugPrint('[STANDALONE_PROXY] Server error: $e');
      });
    } catch (e) {
      debugPrint('[STANDALONE_PROXY] Failed to start local server: $e');
    }
  }

  static void _handleRequest(HttpRequest request) async {
    final videoId = request.uri.queryParameters['id'];
    if (videoId == null || videoId.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write('Missing video id');
      await request.response.close();
      return;
    }

    try {
      // 1. Resolve raw stream URL (with in-memory cache)
      String? rawStreamUrl = _urlCache[videoId];
      if (rawStreamUrl == null) {
        final manifest = await _yt.videos.streamsClient.getManifest(videoId);
        final mp4Streams = manifest.audioOnly.where(
          (s) => s.container.name.toLowerCase() == 'mp4' || s.audioCodec.toLowerCase().contains('mp4a'),
        );
        final streamInfo = mp4Streams.isNotEmpty
            ? mp4Streams.withHighestBitrate()
            : manifest.audioOnly.withHighestBitrate();
        rawStreamUrl = streamInfo.url.toString();
        _urlCache[videoId] = rawStreamUrl;
      }

      // 2. Forward request to upstream googlevideo with browser User-Agent and Range headers
      final upstreamUri = Uri.parse(rawStreamUrl);
      final upstreamReq = await _httpClient.getUrl(upstreamUri);
      upstreamReq.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36',
      );
      upstreamReq.headers.set(HttpHeaders.acceptHeader, '*/*');

      // Forward client Range header (critical for Windows seeking and partial buffering)
      final clientRange = request.headers.value(HttpHeaders.rangeHeader);
      if (clientRange != null && clientRange.isNotEmpty) {
        upstreamReq.headers.set(HttpHeaders.rangeHeader, clientRange);
      }

      final upstreamRes = await upstreamReq.close();

      // 3. Set response headers for just_audio
      request.response.statusCode = upstreamRes.statusCode;
      request.response.headers.set(HttpHeaders.contentTypeHeader, 'audio/mp4');
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');

      final contentRange = upstreamRes.headers.value(HttpHeaders.contentRangeHeader);
      if (contentRange != null) {
        request.response.headers.set(HttpHeaders.contentRangeHeader, contentRange);
      }

      final contentLength = upstreamRes.headers.value(HttpHeaders.contentLengthHeader);
      if (contentLength != null) {
        request.response.headers.set(HttpHeaders.contentLengthHeader, contentLength);
      }

      // Pipe chunks to Windows Media Player
      await upstreamRes.pipe(request.response);
    } catch (e) {
      // Stream aborted / client disconnected during track change or seek is normal
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  static void dispose() {
    _server?.close(force: true);
    _server = null;
    _yt.close();
  }
}

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
    await LocalAudioProxy.ensureStarted();
    debugPrint('[STANDALONE_EDITION] Initialized pure client-side music engine with local audio proxy.');
  }

  static Future<Map<String, dynamic>> getYTMusicLibrary() async {
    return <String, dynamic>{
      'history': <Track>[],
      'liked_songs': <Track>[],
      'playlists': <Map<String, dynamic>>[],
    };
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

  static int _parseDurationSeconds(dynamic duration) {
    if (duration == null) return 0;
    if (duration is int) return duration;
    if (duration is Duration) return duration.inSeconds;
    final str = duration.toString().trim();
    final parts = str.split(':');
    if (parts.length == 2) {
      final m = int.tryParse(parts[0]) ?? 0;
      final s = int.tryParse(parts[1]) ?? 0;
      return (m * 60) + s;
    } else if (parts.length == 3) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      final s = int.tryParse(parts[2]) ?? 0;
      return (h * 3600) + (m * 60) + s;
    }
    return int.tryParse(str) ?? 0;
  }

  /// Resolves video_id to track with native in-app audio proxy URL
  /// (Routes through 127.0.0.1:port to eliminate Windows 403 Item errors)
  static Future<Track?> resolveStream(String videoIdOrUrl) async {
    if (isTestMode) return null;
    final actualId = extractVideoId(videoIdOrUrl);
    if (actualId.isEmpty) return null;

    try {
      await LocalAudioProxy.ensureStarted();
      final localStreamUrl = 'http://127.0.0.1:${LocalAudioProxy.port}/stream?id=$actualId';
      debugPrint('[STANDALONE_RESOLVER] Routing stream through in-app proxy: $localStreamUrl');
      return Track(
        videoId: actualId,
        title: '',
        artist: '',
        durationSeconds: 0,
        streamUrl: localStreamUrl,
        source: 'youtube',
      );
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
    if (isTestMode) return <String, dynamic>{'tracks': <Track>[], 'playlists': [], 'channels': [], 'albums': []};

    // 1. Try searchContent (handles modern rich formats without throwing on "Streamed")
    try {
      final results = await _ytExplode.search.searchContent(query);
      final tracks = <Track>[];
      final playlists = <Map<String, dynamic>>[];
      final channels = <Map<String, dynamic>>[];

      for (final item in results) {
        if (item is SearchVideo && tracks.length < limit) {
          tracks.add(Track(
            videoId: item.id.value,
            title: item.title,
            artist: item.author,
            durationSeconds: _parseDurationSeconds(item.duration),
            thumbnailUrl: item.thumbnails.isNotEmpty ? item.thumbnails.last.url.toString() : '',
            source: 'youtube',
            channelId: item.channelId,
          ));
        } else if (item is SearchPlaylist && playlists.length < 5) {
          playlists.add({
            'id': item.id.value,
            'title': item.title,
            'author': '',
            'thumbnail': item.thumbnails.isNotEmpty ? item.thumbnails.last.url.toString() : '',
            'track_count': item.videoCount,
          });
        } else if (item is SearchChannel && channels.length < 5) {
          channels.add({
            'id': item.id.value,
            'name': item.name,
            'thumbnail': '',
          });
        }
      }

      if (tracks.isNotEmpty || playlists.isNotEmpty) {
        return <String, dynamic>{
          'tracks': tracks,
          'playlists': playlists,
          'channels': channels,
          'albums': <Map<String, dynamic>>[],
          'source': 'youtube',
          'is_playlist': false,
        };
      }
    } catch (e) {
      debugPrint('[STANDALONE_SEARCH] searchContent notice: $e, trying standard search');
    }

    // 2. Fallback to search
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

      return <String, dynamic>{
        'tracks': tracks,
        'playlists': <Map<String, dynamic>>[],
        'channels': <Map<String, dynamic>>[],
        'albums': <Map<String, dynamic>>[],
        'source': 'youtube',
        'is_playlist': false,
      };
    } catch (e) {
      debugPrint('[STANDALONE_SEARCH] Error: $e');
    }

    return <String, dynamic>{'tracks': <Track>[], 'playlists': [], 'channels': [], 'albums': []};
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
    if (isTestMode) {
      return <String, dynamic>{
        'categories': <Map<String, dynamic>>[],
        'playlists': <Map<String, dynamic>>[],
        'tracks': <Track>[],
        'user_sections': <String, dynamic>{},
      };
    }

    final queryMap = {
      'dj': 'dj remix 2026',
      'trending': 'เพลงฮิต 2026',
      'club': 'club dance mix 2026',
      'thai': 'เพลงแดนซ์มันๆ สายย่อ 2026',
      'edm': 'edm festival mix 2026',
    };

    final q = queryMap[category] ?? 'dj remix 2026';
    try {
      final res = await searchWithPlaylists(q, limit: 18);
      final tracks = (res['tracks'] as List<Track>?) ?? [];

      return <String, dynamic>{
        'categories': <Map<String, dynamic>>[
          {'key': 'dj', 'label': 'DJ Remix', 'title': 'DJ Remix', 'id': 'dj', 'color': '0xFF00F2FE'},
          {'key': 'trending', 'label': 'Trending Hits', 'title': 'Trending Hits', 'id': 'trending', 'color': '0xFFFF0055'},
          {'key': 'thai', 'label': 'สายย่อ / รถแห่', 'title': 'สายย่อ / รถแห่', 'id': 'thai', 'color': '0xFFFFD700'},
          {'key': 'club', 'label': 'Club Dance', 'title': 'Club Dance', 'id': 'club', 'color': '0xFF9D00FF'},
          {'key': 'edm', 'label': 'EDM Festival', 'title': 'EDM Festival', 'id': 'edm', 'color': '0xFF00FF88'},
        ],
        'playlists': <Map<String, dynamic>>[],
        'tracks': tracks,
        'user_sections': <String, dynamic>{},
      };
    } catch (e) {
      debugPrint('[STANDALONE_EXPLORE] Error: $e');
    }
    return <String, dynamic>{
      'categories': <Map<String, dynamic>>[],
      'playlists': <Map<String, dynamic>>[],
      'tracks': <Track>[],
      'user_sections': <String, dynamic>{},
    };
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

      return <String, dynamic>{
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

  /// Fetch channel or artist page details and all their uploaded videos/songs
  static Future<Map<String, dynamic>> getChannelDetails({
    String? channelId,
    String? name,
    String source = 'youtube',
  }) async {
    if (isTestMode) return {'name': name ?? 'Channel', 'tracks': <Track>[]};
    try {
      if (channelId != null && channelId.isNotEmpty) {
        final channel = await _ytExplode.channels.get(channelId);
        final uploads = await _ytExplode.channels.getUploads(channelId).take(30).toList();
        final tracks = uploads.map((v) {
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
          'channel_id': channel.id.value,
          'name': channel.title,
          'thumbnail': channel.logoUrl,
          'subscribers': '',
          'description': '',
          'tracks': tracks,
        };
      }
    } catch (e) {
      debugPrint('[STANDALONE_CHANNEL] Error: $e');
    }
    return {'name': name ?? 'Channel', 'tracks': <Track>[]};
  }
}
