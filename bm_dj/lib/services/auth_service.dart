import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/track.dart';
import '../models/user_account.dart';
import 'api_service.dart';

class AuthService extends ChangeNotifier {
  static final AuthService instance = AuthService._internal();
  factory AuthService() => instance;
  AuthService._internal();

  UserAccount? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;

  UserAccount? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isYTMusicConnected => _currentUser?.ytmusicConnected ?? false;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;


  List<Track> get likedTracks => _currentUser?.likedTracks ?? [];

  /// Initialize and attempt auto-login from stored SharedPreferences
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('bm_dj_token');
      if (token != null && token.isNotEmpty) {
        ApiService.authToken = token;
        await fetchCurrentUser();
      }
    } catch (e) {
      debugPrint('[AUTH] Auto-login error: $e');
    }
  }

  /// Register a new account
  Future<bool> register(String username, String password, {String email = ''}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final uri = Uri.parse('${ApiService.baseUrl}/api/v1/auth/register');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username.trim(),
          'password': password.trim(),
          'email': email.trim(),
        }),
      ).timeout(const Duration(seconds: 15));

      final body = jsonDecode(res.body);
      if (res.statusCode == 201 && body['status'] == 'success') {
        final token = body['token'] as String;
        ApiService.authToken = token;
        _currentUser = UserAccount.fromJson(body, token);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('bm_dj_token', token);
        await prefs.setString('bm_dj_username', username);

        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = body['error'] ?? 'Registration failed';
      }
    } catch (e) {
      _errorMessage = 'Connection error: $e';
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  /// Login with username and password
  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final uri = Uri.parse('${ApiService.baseUrl}/api/v1/auth/login');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username.trim(),
          'password': password.trim(),
        }),
      ).timeout(const Duration(seconds: 15));

      final body = jsonDecode(res.body);
      if (res.statusCode == 200 && body['status'] == 'success') {
        final token = body['token'] as String;
        ApiService.authToken = token;
        _currentUser = UserAccount.fromJson(body, token);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('bm_dj_token', token);
        await prefs.setString('bm_dj_username', username);

        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = body['error'] ?? 'Login failed';
      }
    } catch (e) {
      _errorMessage = 'Connection error: $e';
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  /// Start Google OAuth 2.0 Sign-In flow
  /// 1. Fetches auth URL from backend
  /// 2. Launches Google OAuth in Chrome / default browser
  /// 3. Polls /api/v1/auth/google/check until success or timeout
  Future<bool> startGoogleSignIn({Function(String statusMessage)? onStatusUpdate}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      onStatusUpdate?.call('กำลังเตรียมหน้าเข้าสู่ระบบ Google...');
      final uri = Uri.parse('${ApiService.baseUrl}/api/v1/auth/google/url?format=json');
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        _errorMessage = 'ไม่สามารถดึง URL เข้าสู่ระบบ Google ได้';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final data = jsonDecode(res.body);
      final authUrlStr = data['auth_url'] as String?;
      final state = data['state'] as String?;

      if (authUrlStr == null || state == null) {
        _errorMessage = 'ข้อมูลการเชื่อมต่อ Google ไม่ถูกต้อง';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // Open in Chrome / system default browser
      final authUri = Uri.parse(authUrlStr);
      await launchUrl(authUri, mode: LaunchMode.externalApplication);

      onStatusUpdate?.call('เปิดเบราว์เซอร์ Google Chrome แล้ว กรุณากดเลือกบัญชีในเบราว์เซอร์...');

      // Poll for completion (up to 120 seconds, every 1.5 seconds)
      const maxAttempts = 80;
      for (int i = 0; i < maxAttempts; i++) {
        await Future.delayed(const Duration(milliseconds: 1500));
        if (!_isLoading) return false; // user cancelled

        try {
          final checkUri = Uri.parse('${ApiService.baseUrl}/api/v1/auth/google/check?state=$state');
          final checkRes = await http.get(checkUri).timeout(const Duration(seconds: 4));
          if (checkRes.statusCode == 200) {
            final checkData = jsonDecode(checkRes.body);
            if (checkData['status'] == 'success') {
              final token = checkData['token'] as String;
              ApiService.authToken = token;
              _currentUser = UserAccount.fromJson(checkData, token);

              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('bm_dj_token', token);
              await prefs.setString('bm_dj_username', _currentUser!.username);

              onStatusUpdate?.call('เข้าสู่ระบบและเชื่อมต่อ Google สำเร็จ!');
              _isLoading = false;
              notifyListeners();
              return true;
            } else if (checkData['status'] == 'error') {
              _errorMessage = checkData['message'] ?? 'การเข้าสู่ระบบ Google ล้มเหลว';
              _isLoading = false;
              notifyListeners();
              return false;
            }
          }
        } catch (_) {}
      }

      _errorMessage = 'หมดเวลาการเข้าสู่ระบบ กรุณาลองใหม่อีกครั้ง';
    } catch (e) {
      _errorMessage = 'เกิดข้อผิดพลาดในการเชื่อมต่อ Google: $e';
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  void cancelGoogleSignIn() {
    _isLoading = false;
    notifyListeners();
  }

  /// Fetch current user and fresh memories from backend
  Future<void> fetchCurrentUser() async {
    if (ApiService.authToken == null) return;
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/api/v1/auth/me');
      final res = await http.get(
        uri,
        headers: ApiService.headers,
      ).timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['status'] == 'success') {
          _currentUser = UserAccount.fromJson(body, ApiService.authToken!);
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('[AUTH] Fetch user failed: $e');
    }
  }

  /// Logout
  Future<void> logout() async {
    _currentUser = null;
    ApiService.authToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('bm_dj_token');
    await prefs.remove('bm_dj_username');
    notifyListeners();
  }

  final List<String> _guestSearchHistory = [
    'dj',
    'ไทยบ้านๆ',
    'สายย่อ 2026',
    'วิทยาลัย หลายใจ',
    'แดนซ์ในผับ',
    'remix tiktok',
    'terompet kemenangan',
    'loop',
    'edm bounce',
    'เบสหนักๆ',
  ];

  List<String> get searchHistory => _currentUser?.searchHistory ?? _guestSearchHistory;

  /// Add or bump search history query
  Future<void> addSearchHistory(String query) async {
    final text = query.trim();
    if (text.isEmpty || text.startsWith('http')) return;

    if (_currentUser != null) {
      _currentUser!.searchHistory.removeWhere((item) => item.trim().toLowerCase() == text.toLowerCase());
      _currentUser!.searchHistory.insert(0, text);
      if (_currentUser!.searchHistory.length > 40) {
        _currentUser!.searchHistory.removeLast();
      }
      notifyListeners();

      try {
        final uri = Uri.parse('${ApiService.baseUrl}/api/v1/user/history');
        await http.post(
          uri,
          headers: ApiService.headers,
          body: jsonEncode({'query': text}),
        );
      } catch (_) {}
    } else {
      _guestSearchHistory.removeWhere((item) => item.trim().toLowerCase() == text.toLowerCase());
      _guestSearchHistory.insert(0, text);
      if (_guestSearchHistory.length > 40) {
        _guestSearchHistory.removeLast();
      }
      notifyListeners();
    }
  }

  /// Delete a single search history item
  Future<void> deleteSearchHistoryItem(String query) async {
    final text = query.trim();
    if (text.isEmpty) return;

    if (_currentUser != null) {
      _currentUser!.searchHistory.removeWhere((item) => item.trim().toLowerCase() == text.toLowerCase());
      notifyListeners();

      try {
        final uri = Uri.parse('${ApiService.baseUrl}/api/v1/user/history');
        await http.delete(
          uri,
          headers: ApiService.headers,
          body: jsonEncode({'query': text}),
        );
      } catch (_) {}
    } else {
      _guestSearchHistory.removeWhere((item) => item.trim().toLowerCase() == text.toLowerCase());
      notifyListeners();
    }
  }

  /// Delete multiple search history items (batch delete)
  Future<void> deleteMultipleSearchHistory(List<String> queries) async {
    if (queries.isEmpty) return;
    final lowerSet = queries.map((q) => q.trim().toLowerCase()).toSet();

    if (_currentUser != null) {
      _currentUser!.searchHistory.removeWhere((item) => lowerSet.contains(item.trim().toLowerCase()));
      notifyListeners();

      try {
        final uri = Uri.parse('${ApiService.baseUrl}/api/v1/user/history');
        await http.delete(
          uri,
          headers: ApiService.headers,
          body: jsonEncode({'queries': queries}),
        );
      } catch (_) {}
    } else {
      _guestSearchHistory.removeWhere((item) => lowerSet.contains(item.trim().toLowerCase()));
      notifyListeners();
    }
  }

  /// Clear all search history
  Future<void> clearAllSearchHistory() async {
    if (_currentUser != null) {
      _currentUser!.searchHistory.clear();
      notifyListeners();

      try {
        final uri = Uri.parse('${ApiService.baseUrl}/api/v1/user/history');
        await http.delete(
          uri,
          headers: ApiService.headers,
        );
      } catch (_) {}
    } else {
      _guestSearchHistory.clear();
      notifyListeners();
    }
  }

  /// Toggle liked track
  Future<bool> toggleLikeTrack(Track track) async {
    if (_currentUser == null) return false;

    final existingIndex = _currentUser!.likedTracks.indexWhere((t) => t.videoId == track.videoId);
    final isLikedNow = existingIndex == -1;

    if (isLikedNow) {
      _currentUser!.likedTracks.insert(0, track);
    } else {
      _currentUser!.likedTracks.removeAt(existingIndex);
    }
    notifyListeners();

    try {
      final uri = Uri.parse('${ApiService.baseUrl}/api/v1/user/liked');
      await http.post(
        uri,
        headers: ApiService.headers,
        body: jsonEncode({
          'video_id': track.videoId,
          'title': track.title,
          'artist': track.artist,
          'duration': track.durationSeconds,
          'thumbnail': track.thumbnailUrl ?? '',
          'source': track.source,
        }),
      );
    } catch (_) {}

    return isLikedNow;
  }

  bool isTrackLiked(String videoId) {
    if (_currentUser == null) return false;
    return _currentUser!.likedTracks.any((t) => t.videoId == videoId);
  }

  /// Sync active DJ queue to user's account
  Future<void> syncQueue(List<Track> queue) async {
    if (_currentUser == null) return;
    _currentUser!.savedQueue = List.from(queue);

    try {
      final uri = Uri.parse('${ApiService.baseUrl}/api/v1/user/queue');
      await http.post(
        uri,
        headers: ApiService.headers,
        body: jsonEncode({
          'queue': queue.map((t) => t.toJson()).toList(),
        }),
      );
    } catch (_) {}
  }

  /// Sync settings
  Future<void> syncSettings(Map<String, dynamic> settings) async {
    if (_currentUser == null) return;
    _currentUser!.settings = settings;

    try {
      final uri = Uri.parse('${ApiService.baseUrl}/api/v1/user/memories');
      await http.post(
        uri,
        headers: ApiService.headers,
        body: jsonEncode({'settings': settings}),
      );
    } catch (_) {}
  }

  /// Connect YouTube Music using Cookie or Raw Headers
  Future<bool> connectYouTubeMusic(String cookieOrHeaders) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final uri = Uri.parse('${ApiService.baseUrl}/api/v1/user/ytmusic/connect');
      final res = await http.post(
        uri,
        headers: ApiService.headers,
        body: jsonEncode({'cookie': cookieOrHeaders.trim()}),
      ).timeout(const Duration(seconds: 25));

      final body = jsonDecode(res.body);
      if (res.statusCode == 200 && body['status'] == 'success') {
        if (_currentUser != null) {
          _currentUser!.ytmusicConnected = true;
          _currentUser!.ytmusicUserName = body['data']?['user_name'] ?? 'Connected';
        }
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = body['error'] ?? 'Connection to YouTube Music failed';
      }
    } catch (e) {
      _errorMessage = 'Error connecting YouTube Music: $e';
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  /// Disconnect YouTube Music
  Future<bool> disconnectYouTubeMusic() async {
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/api/v1/user/ytmusic/disconnect');
      final res = await http.post(uri, headers: ApiService.headers);
      if (res.statusCode == 200) {
        if (_currentUser != null) {
          _currentUser!.ytmusicConnected = false;
          _currentUser!.ytmusicUserName = '';
        }
        notifyListeners();
        return true;
      }
    } catch (_) {}
    return false;
  }
}
