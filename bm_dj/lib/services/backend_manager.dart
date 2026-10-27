import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class BackendProcessManager {
  static Process? _backendProcess;

  /// Ensures that a backend server is running.
  /// If neither port 8000 nor 8888 responds, silently launches Python backend in the background!
  static Future<void> ensureBackendRunning() async {
    if (!Platform.isWindows) return;

    // 1. Quick check if localhost is already active on 8000 or 8888
    final isAlreadyRunning = await _isPortAlive('http://127.0.0.1:8000') ||
        await _isPortAlive('http://127.0.0.1:8888');
    if (isAlreadyRunning) {
      debugPrint('[BACKEND_MGR] Local backend is already running.');
      return;
    }

    // 2. Locate backend directory relative to project root
    try {
      final currentDir = Directory.current.path;
      final candidates = [
        '$currentDir/../backend',
        '$currentDir/backend',
      ];

      Directory? backendDir;
      for (final p in candidates) {
        final d = Directory(p);
        if (d.existsSync()) {
          backendDir = d;
          break;
        }
      }

      if (backendDir == null) {
        debugPrint('[BACKEND_MGR] Could not locate backend directory.');
        return;
      }

      final pythonExe = '${backendDir.path}/.venv/Scripts/python.exe';
      final managePy = '${backendDir.path}/manage.py';

      if (!File(pythonExe).existsSync() || !File(managePy).existsSync()) {
        debugPrint('[BACKEND_MGR] python.exe or manage.py not found in ${backendDir.path}');
        return;
      }

      debugPrint('[BACKEND_MGR] Silently starting Python backend in background...');
      _backendProcess = await Process.start(
        pythonExe,
        ['manage.py', 'runserver', '127.0.0.1:8000'],
        workingDirectory: backendDir.path,
        mode: ProcessStartMode.detached,
      );

      debugPrint('[BACKEND_MGR] Backend process started with PID: ${_backendProcess?.pid}');
    } catch (e) {
      debugPrint('[BACKEND_MGR] Failed to launch backend: $e');
    }
  }

  static Future<bool> _isPortAlive(String url) async {
    try {
      final res = await http.get(Uri.parse('$url/')).timeout(const Duration(milliseconds: 400));
      return res.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  /// Terminates the spawned background process if any
  static void stopBackend() {
    try {
      _backendProcess?.kill();
      _backendProcess = null;
    } catch (_) {}
  }
}
