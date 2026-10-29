import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/track.dart';
import '../models/user_account.dart';
import '../models/time_package.dart';
import 'api_service.dart';

class AuthService extends ChangeNotifier {
  static final AuthService instance = AuthService._internal();
  factory AuthService() => instance;
  AuthService._internal();

  UserAccount? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;

  Timer? _heartbeatTimer;
  Timer? _localTickTimer;
  VoidCallback? onSubscriptionExpired;

  UserAccount? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null && _currentUser!.token.isNotEmpty && _currentUser!.token != 'local_standalone';
  bool get hasActiveSubscription => _currentUser != null && _currentUser!.hasActiveSubscription;
  bool get isYTMusicConnected => _currentUser?.ytmusicConnected ?? false;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  List<Track> get likedTracks => _currentUser?.likedTracks ?? [];

  /// Initialize and attempt auto-login from stored SharedPreferences
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedYtmCookie = prefs.getString('bm_dj_ytmusic_cookie');
      if (savedYtmCookie != null && savedYtmCookie.isNotEmpty) {
        ApiService.ytMusicCookie = savedYtmCookie;
      }

      final token = prefs.getString('bm_dj_token');
      if (token != null && token.isNotEmpty && token != 'local_standalone') {
        ApiService.authToken = token;
        await fetchCurrentUser();
        if (_currentUser != null) {
          startHeartbeat();
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[AUTH] Auto-login error: $e');
    }
  }

  /// Start Anti-Cheat Server Heartbeat
  void startHeartbeat() {
    stopHeartbeat();
    if (!isLoggedIn) return;

    // 1. Initial heartbeat right away
    sendHeartbeat();

    // 2. Periodic 60-second anti-cheat server heartbeat
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      sendHeartbeat();
    });

    // 3. Local 1-second countdown for smooth real-time UI display
    _localTickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_currentUser != null && !_currentUser!.isVipUnlimited && _currentUser!.remainingSeconds > 0) {
        _currentUser!.remainingSeconds -= 1;
        if (_currentUser!.remainingSeconds <= 0) {
          _currentUser!.hasActiveSubscription = false;
          notifyListeners();
          onSubscriptionExpired?.call();
        } else {
          notifyListeners();
        }
      }
    });
  }

  void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _localTickTimer?.cancel();
    _localTickTimer = null;
  }

  /// Send Heartbeat to Django Backend (Anti-Cheat: server deducts time using its own clock)
  Future<bool> sendHeartbeat() async {
    if (!isLoggedIn || ApiService.authToken == null) return false;

    try {
      final uri = Uri.parse('${ApiService.baseUrl}/api/v1/auth/heartbeat');
      final res = await http.post(
        uri,
        headers: ApiService.headers,
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['status'] == 'success' && _currentUser != null) {
          final int serverSecs = (data['remaining_seconds'] as num?)?.toInt() ?? _currentUser!.remainingSeconds;
          final double serverBal = (data['wallet_balance'] as num?)?.toDouble() ?? _currentUser!.walletBalance;
          final bool vip = data['is_vip_unlimited'] == true;
          final bool active = data['active'] == true;
          final String rDisp = data['remaining_display']?.toString() ?? '';

          _currentUser!.remainingSeconds = serverSecs;
          _currentUser!.walletBalance = serverBal;
          _currentUser!.isVipUnlimited = vip;
          _currentUser!.hasActiveSubscription = active;
          if (rDisp.isNotEmpty) {
            _currentUser!.remainingDisplay = rDisp;
          }

          notifyListeners();

          if (!active) {
            onSubscriptionExpired?.call();
          }
          return active;
        }
      } else if (res.statusCode == 401) {
        debugPrint('[AUTH] Heartbeat 401 Unauthorized -> Logging out');
        await logout();
      } else if (res.statusCode == 403) {
        final data = jsonDecode(res.body);
        if (_currentUser != null) {
          _currentUser!.isLocked = true;
          _currentUser!.lockReason = data['message'] ?? 'บัญชีถูกระงับ';
          _currentUser!.hasActiveSubscription = false;
          notifyListeners();
          onSubscriptionExpired?.call();
        }
      }
    } catch (e) {
      debugPrint('[AUTH] Heartbeat network check: $e');
    }
    return _currentUser?.hasActiveSubscription ?? false;
  }

  Map<String, dynamic>? _safeParseJson(http.Response res) {
    try {
      final contentType = res.headers['content-type'] ?? '';
      final bodyStr = res.body.trim();
      if (bodyStr.startsWith('<') || (!contentType.contains('json') && !bodyStr.startsWith('{'))) {
        _errorMessage = 'เซิร์ฟเวอร์ตอบกลับไม่ถูกต้อง (HTTP ${res.statusCode})\n'
            'กรุณาตรวจสอบว่าเซิร์ฟเวอร์ Backend กำลังทำงาน หรือเลือกเชื่อมต่อ Localhost (127.0.0.1:8000)';
        return null;
      }
      return jsonDecode(bodyStr) as Map<String, dynamic>;
    } catch (e) {
      _errorMessage = 'ข้อผิดพลาดในการอ่านข้อมูลจากเซิร์ฟเวอร์: $e';
      return null;
    }
  }

  /// Register a new account (receives 48 hours free trial automatically)
  Future<bool> register(String username, String password, {String email = ''}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final uri = Uri.parse('${ApiService.baseUrl}/api/v1/auth/register');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({
          'username': username.trim(),
          'password': password.trim(),
          'email': email.trim(),
        }),
      ).timeout(const Duration(seconds: 15));

      final body = _safeParseJson(res);
      if (body == null) {
        if (ApiService.baseUrl != ApiService.localServerUrl) {
          debugPrint('[AUTH] Primary server returned non-JSON. Retrying with local server: ${ApiService.localServerUrl}');
          ApiService.baseUrl = ApiService.localServerUrl;
          return await register(username, password, email: email);
        }
        _isLoading = false;
        notifyListeners();
        return false;
      }

      if (res.statusCode == 201 && body['status'] == 'success') {
        final token = body['token'] as String;
        ApiService.authToken = token;
        _currentUser = UserAccount.fromJson(body, token);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('bm_dj_token', token);
        await prefs.setString('bm_dj_username', username);

        _isLoading = false;
        startHeartbeat();
        notifyListeners();
        return true;
      } else {
        _errorMessage = body['error'] ?? 'Registration failed';
      }
    } catch (e) {
      if (ApiService.baseUrl != ApiService.localServerUrl) {
        debugPrint('[AUTH] Connection exception on primary. Retrying with local server: ${ApiService.localServerUrl}');
        ApiService.baseUrl = ApiService.localServerUrl;
        return register(username, password, email: email);
      }
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
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({
          'username': username.trim(),
          'password': password.trim(),
        }),
      ).timeout(const Duration(seconds: 15));

      final body = _safeParseJson(res);
      if (body == null) {
        if (ApiService.baseUrl != ApiService.localServerUrl) {
          debugPrint('[AUTH] Primary server returned non-JSON. Retrying login with local server: ${ApiService.localServerUrl}');
          ApiService.baseUrl = ApiService.localServerUrl;
          return await login(username, password);
        }
        _isLoading = false;
        notifyListeners();
        return false;
      }

      if (res.statusCode == 200 && body['status'] == 'success') {
        final token = body['token'] as String;
        ApiService.authToken = token;
        _currentUser = UserAccount.fromJson(body, token);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('bm_dj_token', token);
        await prefs.setString('bm_dj_username', username);

        _isLoading = false;
        startHeartbeat();
        notifyListeners();
        return true;
      } else {
        _errorMessage = body['error'] ?? 'Login failed';
      }
    } catch (e) {
      if (ApiService.baseUrl != ApiService.localServerUrl) {
        debugPrint('[AUTH] Connection exception on primary. Retrying login with local server: ${ApiService.localServerUrl}');
        ApiService.baseUrl = ApiService.localServerUrl;
        return login(username, password);
      }
      _errorMessage = 'Connection error: $e';
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  /// Start Google OAuth 2.0 Sign-In flow
  Future<bool> startGoogleSignIn({Function(String statusMessage)? onStatusUpdate}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final urlUri = Uri.parse('${ApiService.baseUrl}/api/v1/auth/google/url');
      final initRes = await http.get(urlUri, headers: ApiService.headers).timeout(const Duration(seconds: 10));
      if (initRes.statusCode != 200) {
        _errorMessage = 'Cannot reach auth server';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final initData = jsonDecode(initRes.body);
      final authUrl = initData['auth_url'] as String;
      final sessionId = initData['session_id'] as String;

      final uriToLaunch = Uri.parse(authUrl);
      if (await canLaunchUrl(uriToLaunch)) {
        await launchUrl(uriToLaunch, mode: LaunchMode.externalApplication);
      } else {
        _errorMessage = 'Could not launch Google OAuth URL';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      onStatusUpdate?.call('กำลังรอการยืนยันจาก Google Browser...');

      const pollInterval = Duration(seconds: 2);
      const maxAttempts = 60; // 2 minutes timeout
      for (int i = 0; i < maxAttempts; i++) {
        await Future.delayed(pollInterval);
        try {
          final checkUri = Uri.parse('${ApiService.baseUrl}/api/v1/auth/google/check?session_id=$sessionId');
          final checkRes = await http.get(checkUri).timeout(const Duration(seconds: 5));
          if (checkRes.statusCode == 200) {
            final checkData = jsonDecode(checkRes.body);
            final authStatus = checkData['status'] as String;

            if (authStatus == 'success') {
              final token = checkData['token'] as String;
              ApiService.authToken = token;
              _currentUser = UserAccount.fromJson(checkData, token);

              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('bm_dj_token', token);
              await prefs.setString('bm_dj_username', _currentUser!.username);

              _isLoading = false;
              startHeartbeat();
              notifyListeners();
              return true;
            } else if (authStatus == 'failed') {
              _errorMessage = checkData['error'] ?? 'Google sign-in was cancelled or failed';
              _isLoading = false;
              notifyListeners();
              return false;
            }
          }
        } catch (_) {}
      }

      _errorMessage = 'Google Sign-In timed out. Please try again.';
    } catch (e) {
      _errorMessage = 'Google OAuth error: $e';
    }

    _isLoading = false;
    notifyListeners();
    return false;
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
      } else if (res.statusCode == 401) {
        debugPrint('[AUTH] Stored token is invalid or expired. Clearing auth token.');
        await logout();
      }
    } catch (e) {
      debugPrint('[AUTH] Fetch user failed: $e');
    }
  }

  /// Logout
  Future<void> logout() async {
    stopHeartbeat();
    _currentUser = null;
    ApiService.authToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('bm_dj_token');
    await prefs.remove('bm_dj_username');
    notifyListeners();
  }

  // ===========================================================================
  // PACKAGE STORE & WALLET TOP-UP METHODS
  // ===========================================================================

  /// Fetch list of available packages from backend
  Future<List<TimePackageModel>> fetchPackages() async {
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/api/v1/packages/');
      final res = await http.get(uri, headers: ApiService.headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['packages'] is List) {
          return (body['packages'] as List)
              .map((p) => TimePackageModel.fromJson(p as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[STORE] Error fetching packages: $e');
    }
    return [];
  }

  /// Buy a package using wallet balance
  Future<Map<String, dynamic>> buyPackage(int packageId) async {
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/api/v1/packages/buy');
      final res = await http.post(
        uri,
        headers: ApiService.headers,
        body: jsonEncode({'package_id': packageId}),
      ).timeout(const Duration(seconds: 15));

      final body = jsonDecode(res.body);
      if (res.statusCode == 200 && body['status'] == 'success') {
        if (_currentUser != null) {
          _currentUser!.walletBalance = (body['wallet_balance'] as num).toDouble();
          _currentUser!.remainingSeconds = (body['remaining_seconds'] as num).toInt();
          _currentUser!.isVipUnlimited = body['is_vip_unlimited'] == true;
          _currentUser!.hasActiveSubscription = true;
          _currentUser!.remainingDisplay = body['remaining_display'] ?? '';
          notifyListeners();
        }
        return {'success': true, 'message': body['message']};
      } else {
        return {
          'success': false,
          'error': body['error'] ?? 'ไม่สามารถซื้อแพ็คเกจได้',
          'need_topup': body['need_topup'] == true,
        };
      }
    } catch (e) {
      return {'success': false, 'error': 'การเชื่อมต่อผิดพลาด: $e'};
    }
  }

  /// Top up wallet by uploading transfer slip
  Future<Map<String, dynamic>> topUpWallet({
    required double amount,
    String? slipBase64,
  }) async {
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/api/v1/wallet/topup');
      final res = await http.post(
        uri,
        headers: ApiService.headers,
        body: jsonEncode({
          'amount': amount,
          'slip_base64': slipBase64 ?? '',
        }),
      ).timeout(const Duration(seconds: 25));

      final body = jsonDecode(res.body);
      if (res.statusCode == 201 && body['status'] == 'success') {
        return {'success': true, 'message': body['message']};
      } else {
        return {'success': false, 'error': body['error'] ?? 'ไม่สามารถส่งข้อมูลสลิปได้'};
      }
    } catch (e) {
      return {'success': false, 'error': 'เกิดข้อผิดพลาดในการส่งข้อมูล: $e'};
    }
  }

  /// Fetch wallet status and payment details
  Future<Map<String, dynamic>?> fetchWalletStatus() async {
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/api/v1/wallet/status');
      final res = await http.get(uri, headers: ApiService.headers).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[WALLET] Error fetching wallet status: $e');
    }
    return null;
  }

  // ===========================================================================
  // SEARCH HISTORY, LIKES, QUEUE & YOUTUBE MUSIC
  // ===========================================================================

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
    }
  }

  Future<void> removeSearchHistory(String query) async {
    if (_currentUser != null) {
      _currentUser!.searchHistory.removeWhere((item) => item.trim().toLowerCase() == query.trim().toLowerCase());
      notifyListeners();
    }
  }

  Future<void> clearAllSearchHistory() async {
    if (_currentUser != null) {
      _currentUser!.searchHistory.clear();
      notifyListeners();
    }
  }

  Future<void> deleteMultipleSearchHistory(List<String> items) async {
    if (_currentUser != null) {
      final set = items.map((e) => e.trim().toLowerCase()).toSet();
      _currentUser!.searchHistory.removeWhere((item) => set.contains(item.trim().toLowerCase()));
      notifyListeners();
    }
  }

  Future<void> deleteSearchHistoryItem(String item) async {
    await removeSearchHistory(item);
  }

  void cancelGoogleSignIn() {}

  Future<bool> toggleLikeTrack(Track track) async {
    if (_currentUser == null) return false;

    final index = _currentUser!.likedTracks.indexWhere((t) => t.videoId == track.videoId);
    final wasLiked = index != -1;
    final isLikedNow = !wasLiked;

    if (wasLiked) {
      _currentUser!.likedTracks.removeAt(index);
    } else {
      _currentUser!.likedTracks.insert(0, track);
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
          'thumbnail': track.thumbnailUrl,
          'source': track.source,
          'liked': isLikedNow,
        }),
      );
    } catch (_) {}
    return isLikedNow;
  }

  bool isTrackLiked(String videoId) {
    if (_currentUser == null) return false;
    return _currentUser!.likedTracks.any((t) => t.videoId == videoId);
  }

  Future<void> syncQueue(List<Track> queue) async {
    if (_currentUser == null) return;
    _currentUser!.savedQueue = List.from(queue);

    try {
      final uri = Uri.parse('${ApiService.baseUrl}/api/v1/user/queue');
      final tracksData = queue.map((t) => {
        'video_id': t.videoId,
        'title': t.title,
        'artist': t.artist,
        'duration': t.durationSeconds,
        'thumbnail': t.thumbnailUrl,
        'source': t.source,
      }).toList();

      await http.post(
        uri,
        headers: ApiService.headers,
        body: jsonEncode({'queue': tracksData}),
      );
    } catch (_) {}
  }

  Future<void> saveSettings(Map<String, dynamic> settings) async {
    if (_currentUser == null) return;
    _currentUser!.settings = Map.from(settings);

    try {
      final uri = Uri.parse('${ApiService.baseUrl}/api/v1/user/memories');
      await http.post(
        uri,
        headers: ApiService.headers,
        body: jsonEncode({'settings': settings}),
      );
    } catch (_) {}
  }

  Future<void> syncSettings(Map<String, dynamic> settings) => saveSettings(settings);

  /// Connect YouTube Music / YouTube Music Premium using Cookie
  Future<bool> connectYouTubeMusic(String cookieOrHeaders) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final cleanedCookie = ApiService.normalizeCookieString(cookieOrHeaders);
      if (cleanedCookie.isEmpty ||
          (!cleanedCookie.contains('SAPISID') &&
              !cleanedCookie.contains('SID') &&
              !cleanedCookie.contains('LOGIN_INFO'))) {
        _errorMessage = 'ไม่พบข้อมูล Cookie ของบัญชี Google/YouTube (เช่น SAPISID หรือ SID) กรุณาคัดลอก Cookie จากหน้า music.youtube.com อีกครั้งครับ';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      ApiService.ytMusicCookie = cleanedCookie;
      const defaultName = 'บุนมี คำทา - ENGINEER BM GROUP';
      if (_currentUser != null) {
        _currentUser!.ytmusicConnected = true;
        if (_currentUser!.ytmusicUserName.isEmpty) {
          _currentUser!.ytmusicUserName = defaultName;
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('bm_dj_ytmusic_cookie', cleanedCookie);
      await prefs.setString('bm_dj_ytmusic_name', _currentUser?.ytmusicUserName ?? defaultName);

      // Save cookie to backend if logged in
      if (isLoggedIn) {
        try {
          final uri = Uri.parse('${ApiService.baseUrl}/api/v1/user/ytmusic/connect');
          await http.post(
            uri,
            headers: ApiService.headers,
            body: jsonEncode({'cookie': cleanedCookie}),
          );
        } catch (_) {}
      }

      _isLoading = false;
      notifyListeners();
      return true;
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
      ApiService.ytMusicCookie = null;
      if (_currentUser != null) {
        _currentUser!.ytmusicConnected = false;
        _currentUser!.ytmusicUserName = '';
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('bm_dj_ytmusic_cookie');
      notifyListeners();
      return true;
    } catch (_) {}
    return false;
  }
}
