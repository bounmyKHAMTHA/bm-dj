import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/track.dart';
import 'dj_audio_synthesizer.dart';

/// Represents a single stream URL option (candidate) for a track so the user
/// can inspect, test, and manually switch between URLs on Deck A or Deck B.
class StreamCandidate {
  final int index;
  final String id;
  final String videoId;
  final String shortLabel;
  final String detailLabel;
  final String rawUrl;
  String playbackUrl;
  final bool useProxy;
  final bool isLocalFile;
  final bool useMediaEngine;
  final int? itag;
  final String mimeType;
  int? contentLength;
  String? localFilePath;

  /// 'untested' | 'probing' | 'ok' | 'partial' | 'failed'
  String status;
  int? httpStatusFirstChunk;
  int? httpStatusOpenRange;
  int? httpStatusOffset1M;
  int? latencyMs;
  String statusDetail;
  String? lastPlaybackError;

  StreamCandidate({
    required this.index,
    required this.id,
    required this.videoId,
    required this.shortLabel,
    required this.detailLabel,
    required this.rawUrl,
    required this.playbackUrl,
    required this.useProxy,
    this.isLocalFile = false,
    this.useMediaEngine = false,
    this.itag,
    this.mimeType = 'video/mp4',
    this.contentLength,
    this.localFilePath,
    this.status = 'untested',
    this.httpStatusFirstChunk,
    this.httpStatusOpenRange,
    this.httpStatusOffset1M,
    this.latencyMs,
    this.statusDetail = 'รอตรวจสอบ...',
    this.lastPlaybackError,
  });

  bool get isWorking => status == 'ok';
  bool get isPartial => status == 'partial';
  bool get isFailed => status == 'failed';
}

class DiagnosticLogEntry {
  final DateTime timestamp;
  final String level; // 'INFO', 'SUCCESS', 'WARN', 'ERROR'
  final String category; // 'RESOLVE', 'PROBE', 'PROXY', 'PLAYER_A', 'PLAYER_B'
  final String message;
  final String? details;

  DiagnosticLogEntry({
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
    this.details,
  });

  String get timeFormatted {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  @override
  String toString() {
    final base = '[$timeFormatted] [$level] [$category] $message';
    if (details != null && details!.trim().isNotEmpty) {
      return '$base\n   ↳ ${details!.replaceAll('\n', '\n     ')}';
    }
    return base;
  }
}

/// Global reactive diagnostic logger that captures every URL candidate, HTTP probe,
/// proxy byte range, and player exception so it can be displayed directly in the UI.
class StreamDiagnosticLogger extends ChangeNotifier {
  static final StreamDiagnosticLogger instance = StreamDiagnosticLogger._();
  StreamDiagnosticLogger._();

  final List<DiagnosticLogEntry> logs = [];
  String? deckALastError;
  String? deckBLastError;
  String? deckALastStatus;
  String? deckBLastStatus;
  Timer? _notifyDebounce;

  void _scheduleNotify() {
    if (_notifyDebounce?.isActive ?? false) return;
    _notifyDebounce = Timer(const Duration(milliseconds: 120), () {
      super.notifyListeners();
    });
  }

  void log(
    String category,
    String message, {
    String level = 'INFO',
    String? details,
    String? deck,
  }) {
    final entry = DiagnosticLogEntry(
      timestamp: DateTime.now(),
      level: level,
      category: category,
      message: message,
      details: details,
    );
    logs.insert(0, entry);
    if (logs.length > 250) {
      logs.removeLast();
    }

    if (deck == 'A') {
      if (level == 'ERROR') {
        deckALastError = '$message${details != null ? ' ($details)' : ''}';
      } else {
        deckALastStatus = message;
      }
    } else if (deck == 'B') {
      if (level == 'ERROR') {
        deckBLastError = '$message${details != null ? ' ($details)' : ''}';
      } else {
        deckBLastStatus = message;
      }
    }

    debugPrint(entry.toString());
    _scheduleNotify();
  }

  void clearDeckError(String deck) {
    if (deck == 'A') {
      deckALastError = null;
    } else if (deck == 'B') {
      deckBLastError = null;
    }
    _scheduleNotify();
  }

  void clearAll() {
    logs.clear();
    deckALastError = null;
    deckBLastError = null;
    _scheduleNotify();
  }

  void refresh() {
    _scheduleNotify();
  }

  String buildDiagnosticReport({String? videoIdA, String? videoIdB}) {
    final sb = StringBuffer();
    sb.writeln('=== BM DJ STANDALONE DIAGNOSTIC & ERROR REPORT ===');
    sb.writeln('Generated At: ${DateTime.now().toIso8601String()}');
    sb.writeln('Proxy Port: ${LocalAudioProxy.port}');
    if (deckALastError != null) sb.writeln('Deck A Last Error: $deckALastError');
    if (deckBLastError != null) sb.writeln('Deck B Last Error: $deckBLastError');
    sb.writeln('');

    for (final vid in [videoIdA, videoIdB].whereType<String>().toSet()) {
      if (vid.isEmpty) continue;
      final cands = LocalAudioProxy.getCandidatesFor(vid);
      final selectedIdx = LocalAudioProxy.getSelectedIndex(vid);
      sb.writeln('--- URL Candidates for Video [$vid] (Selected: #${selectedIdx + 1}) ---');
      for (final c in cands) {
        final sel = c.index == selectedIdx ? ' [SELECTED]' : '';
        sb.writeln(
          '  #${c.index + 1}$sel ${c.shortLabel} | ${c.detailLabel}\n'
          '     Engine: ${c.useMediaEngine ? "IMFMediaEngine (video_player_win)" : "JustAudio (WinRT MediaPlayer)"}, LocalFile: ${c.isLocalFile} (${c.localFilePath ?? "none"})\n'
          '     Status: ${c.status} (${c.statusDetail})\n'
          '     HTTP Codes: 0-64KB=${c.httpStatusFirstChunk}, Range(0-)=${c.httpStatusOpenRange}, >1MB=${c.httpStatusOffset1M}, Latency=${c.latencyMs}ms\n'
          '     PlaybackError: ${c.lastPlaybackError ?? "None"}\n'
          '     PlaybackURL: ${c.playbackUrl}\n'
          '     RawURL: ${c.rawUrl.length > 140 ? "${c.rawUrl.substring(0, 140)}..." : c.rawUrl}',
        );
      }
      sb.writeln('');
    }

    sb.writeln('--- Recent Event & Error Logs (${logs.length} entries) ---');
    for (final entry in logs.take(80)) {
      sb.writeln(entry.toString());
    }
    return sb.toString();
  }
}

/// In-App Local HTTP Streaming Proxy
/// Windows Media Foundation (MediaPlayer) requires valid container extension (.mp4),
/// proper partial content byte streaming (HTTP 200/206), and non-throttled googlevideo streams.
class LocalAudioProxy {
  static HttpServer? _server;
  static int? _port;
  static final HttpClient _httpClient = HttpClient()
    ..idleTimeout = const Duration(seconds: 30)
    ..connectionTimeout = const Duration(seconds: 10);

  static final YoutubeExplode _yt = YoutubeExplode();
  static final Map<String, List<StreamCandidate>> _candidatesByVideo = {};
  static final Map<String, int> _selectedCandidateIndex = {};
  static final Map<String, Future<String?>> _inFlight = {};
  static final Map<String, Map<String, dynamic>> _videoMetaCache = {};

  /// High-speed in-memory & disk cache for instant playback without 7-second HTTP buffering stalls
  static final Map<String, Uint8List> _ramCache = {};
  static final Map<String, String> _fileCache = {};
  static final Map<String, Future<String?>> _cacheInFlight = {};
  static final List<String> _ramCacheOrder = [];

  static int get port => _port ?? 0;

  static Uint8List? getRamCachedBytes(String videoId) => _ramCache[videoId];
  static String? getCachedFilePath(String videoId) => _fileCache[videoId];

  /// Downloads the stream in 8 parallel HTTP Range connections (~1.5s for 16MB) into RAM and
  /// writes a local `.mp4` file in `Directory.systemTemp/bmdj_cache/<videoId>.mp4`.
  static Future<String?> ensureLocalFileCached(
    String videoId, {
    String? rawUrlOverride,
    String? deckLabel,
  }) async {
    final existingFile = _fileCache[videoId];
    if (existingFile != null && File(existingFile).existsSync() && File(existingFile).lengthSync() > 65536) {
      _updateCandidatesLocalFilePath(videoId, existingFile);
      return existingFile;
    }
    if (_cacheInFlight.containsKey(videoId)) {
      return await _cacheInFlight[videoId];
    }

    final completer = Completer<String?>();
    _cacheInFlight[videoId] = completer.future;

    () async {
      final sw = Stopwatch()..start();
      try {
        await prewarm(videoId);
        final cands = getCandidatesFor(videoId);
        String? rawUrl = rawUrlOverride;
        int? totalLen;
        if (rawUrl == null || rawUrl.isEmpty) {
          final muxed = cands.where((c) => c.itag == 18 && c.rawUrl.startsWith('http')).firstOrNull ??
              cands.where((c) => c.rawUrl.startsWith('http')).firstOrNull;
          rawUrl = muxed?.rawUrl;
          totalLen = muxed?.contentLength;
        }
        if (rawUrl == null || rawUrl.isEmpty) {
          completer.complete(null);
          return;
        }

        final client = HttpClient()
          ..maxConnectionsPerHost = 12
          ..connectionTimeout = const Duration(seconds: 6)
          ..idleTimeout = const Duration(seconds: 15);

        // 1. Discover exact byte size via Range: bytes=0-65535 if not already known
        Uint8List? first64k;
        if (totalLen == null || totalLen <= 0) {
          final req0 = await client.getUrl(Uri.parse(rawUrl)).timeout(const Duration(seconds: 4));
          _setAppropriateHeaders(req0.headers, rawUrl, range: 'bytes=0-65535');
          final res0 = await req0.close().timeout(const Duration(seconds: 4));
          final cr = res0.headers.value(HttpHeaders.contentRangeHeader) ?? '';
          final slashIdx = cr.lastIndexOf('/');
          if (slashIdx != -1) {
            totalLen = int.tryParse(cr.substring(slashIdx + 1).trim());
          }
          totalLen ??= int.tryParse(res0.headers.value(HttpHeaders.contentLengthHeader) ?? '');
          final b0 = BytesBuilder(copy: false);
          await for (final chunk in res0) {
            b0.add(chunk);
          }
          first64k = b0.takeBytes();
        }

        if (totalLen == null || totalLen <= 0) {
          client.close(force: true);
          completer.complete(null);
          return;
        }

        final String targetRawUrl = rawUrl;
        final int targetTotalLen = totalLen;

        // If the video is a long mix/movie (> 30 MB, ~10+ minutes), do NOT wait 15-120 seconds
        // downloading the entire file into RAM before playback starts! Stream directly via MediaEngine.
        const int maxCacheBytes = 30 * 1024 * 1024;
        if (targetTotalLen > maxCacheBytes) {
          client.close(force: true);
          final mb = (targetTotalLen / (1024 * 1024)).toStringAsFixed(2);
          StreamDiagnosticLogger.instance.log(
            'PROXY',
            '⏩ คลิปมีความยาวสูง ($mb MB > 30 MB) -> ข้ามการรอโหลดทั้งไฟล์และสลับใช้สตรีมตรงผ่าน MediaEngine ทันที!',
            level: 'INFO',
            deck: deckLabel,
          );
          completer.complete(null);
          return;
        }

        StreamDiagnosticLogger.instance.log(
          'PROXY',
          '⚡ กำลังโหลดแคชความเร็วสูง (8 ท่อพร้อมกัน) สำหรับ $videoId (${(targetTotalLen / (1024 * 1024)).toStringAsFixed(2)} MB)...',
          level: 'INFO',
          deck: deckLabel,
        );

        final fullBuffer = Uint8List(targetTotalLen);
        int startOffset = 0;
        if (first64k != null && first64k.isNotEmpty) {
          final copyLen = first64k.length <= targetTotalLen ? first64k.length : targetTotalLen;
          fullBuffer.setRange(0, copyLen, first64k);
          startOffset = copyLen;
        }

        // 2. Download remaining bytes across 8 parallel Range connections
        final remaining = targetTotalLen - startOffset;
        if (remaining > 0) {
          const int parts = 8;
          final int partSize = (remaining / parts).ceil();
          await Future.wait(List.generate(parts, (i) async {
            final int start = startOffset + (i * partSize);
            if (start >= targetTotalLen) return;
            final int end = (start + partSize - 1 < targetTotalLen) ? (start + partSize - 1) : (targetTotalLen - 1);

            for (int retry = 0; retry < 2; retry++) {
              try {
                final req = await client.getUrl(Uri.parse(targetRawUrl)).timeout(const Duration(seconds: 5));
                _setAppropriateHeaders(req.headers, targetRawUrl, range: 'bytes=$start-$end');
                final res = await req.close().timeout(const Duration(seconds: 6));
                if (res.statusCode == 200 || res.statusCode == 206) {
                  int writePos = start;
                  await for (final chunk in res.timeout(const Duration(seconds: 8))) {
                    final int endPos = (writePos + chunk.length <= targetTotalLen) ? (writePos + chunk.length) : targetTotalLen;
                    if (endPos > writePos) {
                      fullBuffer.setRange(writePos, endPos, chunk);
                      writePos = endPos;
                    }
                  }
                  if (writePos > end) break;
                } else {
                  await res.drain();
                }
              } catch (_) {
                if (retry == 1) rethrow;
              }
            }
          }));
        }

        client.close(force: true);

        // 3. Store in RAM cache (keep up to 5 tracks in RAM)
        _ramCache[videoId] = fullBuffer;
        _ramCacheOrder.remove(videoId);
        _ramCacheOrder.add(videoId);
        while (_ramCacheOrder.length > 5) {
          final oldest = _ramCacheOrder.removeAt(0);
          _ramCache.remove(oldest);
        }

        // 4. Write to local temp file for zero-latency file playback
        final cacheDir = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}bmdj_cache');
        if (!cacheDir.existsSync()) {
          cacheDir.createSync(recursive: true);
        }
        final filePath = '${cacheDir.path}${Platform.pathSeparator}bmdj_$videoId.mp4';
        final file = File(filePath);
        await file.writeAsBytes(fullBuffer, flush: true);
        _fileCache[videoId] = filePath;
        _updateCandidatesLocalFilePath(videoId, filePath, contentLength: totalLen);

        final mb = (totalLen / (1024 * 1024)).toStringAsFixed(2);
        final sec = (sw.elapsedMilliseconds / 1000).toStringAsFixed(2);
        StreamDiagnosticLogger.instance.log(
          'PROXY',
          '✅ โหลดไฟล์แคช $videoId ($mb MB) ลงเครื่องสำเร็จใน $sec วินาที! พร้อมเล่นทันทีไม่มีสะดุด',
          level: 'SUCCESS',
          details: 'Local File: $filePath',
          deck: deckLabel,
        );
        completer.complete(filePath);
      } catch (e, st) {
        StreamDiagnosticLogger.instance.log(
          'PROXY',
          'โหลดไฟล์แคช $videoId แจ้งเตือน: $e (สลับใช้สตรีมตรงแทน)',
          level: 'WARN',
          details: st.toString(),
          deck: deckLabel,
        );
        completer.complete(null);
      } finally {
        _cacheInFlight.remove(videoId);
      }
    }();

    return completer.future;
  }

  static void _updateCandidatesLocalFilePath(String videoId, String filePath, {int? contentLength}) {
    final list = _candidatesByVideo[videoId];
    if (list == null) return;
    for (final c in list) {
      c.localFilePath = filePath;
      if (contentLength != null) {
        c.contentLength = contentLength;
      }
    }
    StreamDiagnosticLogger.instance.refresh();
  }

  static List<StreamCandidate> getCandidatesFor(String videoId) {
    return _candidatesByVideo[videoId] ?? const [];
  }

  static int getSelectedIndex(String videoId) {
    return _selectedCandidateIndex[videoId] ?? 0;
  }

  static StreamCandidate? getSelectedCandidate(String videoId) {
    final list = _candidatesByVideo[videoId];
    if (list == null || list.isEmpty) return null;
    final idx = (_selectedCandidateIndex[videoId] ?? 0).clamp(0, list.length - 1);
    return list[idx];
  }

  static void selectCandidate(String videoId, int index) {
    final list = _candidatesByVideo[videoId];
    if (list != null && index >= 0 && index < list.length) {
      _selectedCandidateIndex[videoId] = index;
      StreamDiagnosticLogger.instance.log(
        'RESOLVE',
        'ผู้ใช้เปลี่ยนตัวเลือกเป็น URL #${index + 1}: ${list[index].shortLabel}',
        level: 'INFO',
        details: 'Playback URL: ${list[index].playbackUrl}\nDetail: ${list[index].detailLabel}',
      );
    }
  }

  static Map<String, dynamic>? getCachedMeta(String videoId) => _videoMetaCache[videoId];

  static Future<void> ensureStarted() async {
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;
      StreamDiagnosticLogger.instance.log(
        'PROXY',
        'เริ่มระบบ LocalAudioProxy สำเร็จบน http://127.0.0.1:$_port',
        level: 'SUCCESS',
      );
      _server!.listen(_handleRequest, onError: (e, st) {
        StreamDiagnosticLogger.instance.log(
          'PROXY',
          'เกิดข้อผิดพลาดใน HttpServer: $e',
          level: 'ERROR',
          details: st.toString(),
        );
      });
    } catch (e, st) {
      StreamDiagnosticLogger.instance.log(
        'PROXY',
        'ไม่สามารถเปิดพอร์ต LocalAudioProxy ได้: $e',
        level: 'ERROR',
        details: st.toString(),
      );
    }
  }

  /// Prewarm and resolve candidate URLs ahead of time
  static Future<String?> prewarm(String videoId, {bool forceRefresh = false}) async {
    await ensureStarted();
    final existing = _candidatesByVideo[videoId];
    final hasRealStream = existing != null && existing.any((c) => c.id != 'backend_8000');
    if (!forceRefresh && hasRealStream) {
      final sel = getSelectedCandidate(videoId);
      return sel?.rawUrl;
    }
    if (!forceRefresh && _inFlight.containsKey(videoId)) {
      return await _inFlight[videoId];
    }

    final completer = Completer<String?>();
    _inFlight[videoId] = completer.future;

    _doResolve(videoId).then((url) {
      completer.complete(url);
    }).catchError((e, st) {
      StreamDiagnosticLogger.instance.log(
        'RESOLVE',
        'เกิดข้อผิดพลาดขณะดึง URL สำหรับ $videoId: $e',
        level: 'ERROR',
        details: st.toString(),
      );
      completer.complete(null);
    }).whenComplete(() {
      _inFlight.remove(videoId);
    });

    return completer.future;
  }

  static void _setAppropriateHeaders(HttpHeaders headers, String url, {String? range}) {
    final uri = Uri.parse(url);
    if (uri.host.contains('googlevideo.com')) {
      if (url.contains('c=IOS')) {
        headers.set(
          HttpHeaders.userAgentHeader,
          'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)',
        );
      } else {
        headers.set(
          HttpHeaders.userAgentHeader,
          'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
        );
      }
    } else {
      headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36',
      );
    }
    headers.set(HttpHeaders.acceptHeader, '*/*');
    if (range != null && range.isNotEmpty) {
      headers.set(HttpHeaders.rangeHeader, range);
    }
  }

  /// Thoroughly probes a candidate URL:
  /// 1. Tests `Range: bytes=0-32767` (initial header/moov atom)
  /// 2. Tests `Range: bytes=0-` (open-ended streaming, which YouTube blocks with 403 on adaptive AudioOnly!)
  /// 3. Tests `Range: bytes=1100000-1116383` (offset > 1MB, to detect 1MB throttling/403 cutoff)
  static Future<void> probeCandidate(StreamCandidate candidate) async {
    candidate.status = 'probing';
    candidate.statusDetail = 'กำลังทดสอบการเชื่อมต่อ...';
    StreamDiagnosticLogger.instance.refresh();

    final sw = Stopwatch()..start();
    try {
      final uri = Uri.parse(candidate.rawUrl);
      final isLocalBackend = candidate.id == 'backend_8000' || uri.host == '127.0.0.1';
      final timeoutDur = Duration(milliseconds: isLocalBackend ? 650 : 2500);
      final client = HttpClient()..connectionTimeout = timeoutDur;

      // Test 1: Range: bytes=0-32767
      final req1 = await client.getUrl(uri).timeout(timeoutDur);
      _setAppropriateHeaders(req1.headers, candidate.rawUrl, range: 'bytes=0-32767');
      final res1 = await req1.close().timeout(timeoutDur);
      candidate.httpStatusFirstChunk = res1.statusCode;
      final cr1 = res1.headers.value(HttpHeaders.contentRangeHeader) ?? '';
      final slashIdx = cr1.lastIndexOf('/');
      if (slashIdx != -1) {
        candidate.contentLength ??= int.tryParse(cr1.substring(slashIdx + 1).trim());
      }
      await res1.drain().timeout(const Duration(milliseconds: 600), onTimeout: () {});

      // Test 2: Range: bytes=0- (unbounded range used by media players)
      final req2 = await client.getUrl(uri).timeout(const Duration(milliseconds: 2500));
      _setAppropriateHeaders(req2.headers, candidate.rawUrl, range: 'bytes=0-');
      final res2 = await req2.close().timeout(const Duration(milliseconds: 2500));
      candidate.httpStatusOpenRange = res2.statusCode;
      // Read a small chunk to verify actual payload flow, then abort
      int bytesRead = 0;
      await for (final chunk in res2.timeout(const Duration(milliseconds: 1200), onTimeout: (sink) => sink.close())) {
        bytesRead += chunk.length;
        if (bytesRead >= 16384) break;
      }

      // Test 3: Range > 1MB (1,100,000 - 1,116,383) if stream isn't tiny
      if (candidate.contentLength == null || candidate.contentLength! > 1200000) {
        try {
          final req3 = await client.getUrl(uri).timeout(const Duration(milliseconds: 2000));
          _setAppropriateHeaders(req3.headers, candidate.rawUrl, range: 'bytes=1100000-1116383');
          final res3 = await req3.close().timeout(const Duration(milliseconds: 2000));
          candidate.httpStatusOffset1M = res3.statusCode;
          await res3.drain().timeout(const Duration(milliseconds: 400), onTimeout: () {});
        } catch (_) {}
      }

      client.close(force: true);
      candidate.latencyMs = sw.elapsedMilliseconds;

      final okOpen = (candidate.httpStatusOpenRange == 200 || candidate.httpStatusOpenRange == 206) && bytesRead > 0;
      final okFirst = candidate.httpStatusFirstChunk == 200 || candidate.httpStatusFirstChunk == 206;
      final ok1M = candidate.httpStatusOffset1M == null ||
          candidate.httpStatusOffset1M == 200 ||
          candidate.httpStatusOffset1M == 206;

      if (okOpen && ok1M) {
        candidate.status = 'ok';
        candidate.statusDetail =
            '✅ ใช้ได้ 100% (HTTP ${candidate.httpStatusOpenRange}, โหลดแล้ว ${bytesRead ~/ 1024}KB ใน ${candidate.latencyMs}ms)';
        StreamDiagnosticLogger.instance.log(
          'PROBE',
          '${candidate.shortLabel} -> ใช้งานได้สมบูรณ์ (${candidate.statusDetail})',
          level: 'SUCCESS',
        );
      } else if (okFirst && !okOpen) {
        candidate.status = 'partial';
        candidate.statusDetail =
            '⚠️ บล็อก Range 0- / เกิน 1MB (0-64K ได้ ${candidate.httpStatusFirstChunk} แต่เล่นจริงติด HTTP ${candidate.httpStatusOpenRange})';
        StreamDiagnosticLogger.instance.log(
          'PROBE',
          '${candidate.shortLabel} -> ติดบล็อก HTTP ${candidate.httpStatusOpenRange} เมื่อขอสตรีมเต็มเพลง',
          level: 'WARN',
          details: 'สาเหตุ: YouTube บล็อกสตรีมแยกเสียง (Adaptive AudioOnly gir=yes) เมื่อขอ Range=0- หรือเกิน 1MB โดยไม่มี PO Token',
        );
      } else {
        candidate.status = 'failed';
        candidate.statusDetail =
            '❌ ใช้งานไม่ได้ (HTTP ${candidate.httpStatusOpenRange ?? candidate.httpStatusFirstChunk ?? "ERR"})';
        StreamDiagnosticLogger.instance.log(
          'PROBE',
          '${candidate.shortLabel} -> ล้มเหลว (${candidate.statusDetail})',
          level: 'ERROR',
        );
      }
    } catch (e) {
      candidate.latencyMs = sw.elapsedMilliseconds;
      candidate.status = 'failed';
      candidate.statusDetail = '❌ เชื่อมต่อล้มเหลว: $e';
      StreamDiagnosticLogger.instance.log(
        'PROBE',
        '${candidate.shortLabel} -> เชื่อมต่อไม่ได้ ($e)',
        level: 'WARN',
      );
    }
    StreamDiagnosticLogger.instance.refresh();
  }

  /// Probe all candidates for a videoId so the user can see the status of every URL option
  static Future<void> probeAllCandidates(String videoId, {bool force = false}) async {
    final list = _candidatesByVideo[videoId];
    if (list == null || list.isEmpty) return;

    // Deduplicate rawUrl probes so Proxy + Direct sharing the same rawUrl don't double-request
    final byRawUrl = <String, List<StreamCandidate>>{};
    for (final c in list) {
      if (!force && c.status != 'untested') continue;
      byRawUrl.putIfAbsent(c.rawUrl, () => []).add(c);
    }

    await Future.wait(byRawUrl.entries.map((entry) async {
      final primary = entry.value.first;
      await probeCandidate(primary);
      for (final other in entry.value.skip(1)) {
        other.status = primary.status;
        other.httpStatusFirstChunk = primary.httpStatusFirstChunk;
        other.httpStatusOpenRange = primary.httpStatusOpenRange;
        other.httpStatusOffset1M = primary.httpStatusOffset1M;
        other.latencyMs = primary.latencyMs;
        other.statusDetail = primary.statusDetail;
      }
    }));
    StreamDiagnosticLogger.instance.refresh();
  }

  /// Fast Direct InnerTube API + YoutubeExplode candidate collector
  static Future<List<StreamCandidate>> _collectCandidates(String videoId) async {
    await ensureStarted();
    final candidates = <StreamCandidate>[];
    final sw = Stopwatch()..start();

    void addCandidate({
      required String id,
      required String shortLabel,
      required String detailLabel,
      required String rawUrl,
      required bool useProxy,
      bool isLocalFile = false,
      bool useMediaEngine = false,
      int? itag,
      String mimeType = 'video/mp4',
      int? contentLength,
    }) {
      if (rawUrl.isEmpty) return;
      final idx = candidates.length;
      final existingFile = _fileCache[videoId];
      final playbackUrl = isLocalFile
          ? (existingFile ?? 'http://127.0.0.1:$port/stream/$videoId.mp4?idx=$idx')
          : (useProxy ? 'http://127.0.0.1:$port/stream/$videoId.mp4?idx=$idx' : rawUrl);
      candidates.add(
        StreamCandidate(
          index: idx,
          id: id,
          videoId: videoId,
          shortLabel: shortLabel,
          detailLabel: detailLabel,
          rawUrl: rawUrl,
          playbackUrl: playbackUrl,
          useProxy: useProxy,
          isLocalFile: isLocalFile,
          useMediaEngine: useMediaEngine,
          itag: itag,
          mimeType: mimeType,
          contentLength: contentLength,
          localFilePath: existingFile,
        ),
      );
    }

    StreamDiagnosticLogger.instance.log(
      'RESOLVE',
      'กำลังค้นหา URL สตรีมทั้งหมดสำหรับวิดีโอ $videoId...',
      level: 'INFO',
    );

    // 1. Direct InnerTube Multi-Client POST (ANDROID -> IOS -> TVHTML5_SIMPLY_EMBEDDED_PLAYER)
    final innerTubeClients = <Map<String, dynamic>>[
      {
        'name': 'ANDROID',
        'version': '20.10.38',
        'ua': 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
        'clientMap': {
          'clientName': 'ANDROID',
          'clientVersion': '20.10.38',
          'userAgent': 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
          'hl': 'en',
          'timeZone': 'UTC',
          'utcOffsetMinutes': 0,
          'osName': 'Android',
          'osVersion': '11',
        },
      },
      {
        'name': 'IOS',
        'version': '20.10.4',
        'ua': 'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)',
        'clientMap': {
          'clientName': 'IOS',
          'clientVersion': '20.10.4',
          'deviceMake': 'Apple',
          'deviceModel': 'iPhone16,2',
          'userAgent': 'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)',
          'hl': 'en',
          'timeZone': 'UTC',
          'utcOffsetMinutes': 0,
          'osName': 'iPhone',
          'osVersion': '18.3.2.22D82',
        },
      },
      {
        'name': 'TVHTML5_SIMPLY_EMBEDDED_PLAYER',
        'version': '2.0',
        'ua': 'Mozilla/5.0 (PlayStation; PlayStation 4/10.71) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.4 Safari/605.1.15',
        'clientMap': {
          'clientName': 'TVHTML5_SIMPLY_EMBEDDED_PLAYER',
          'clientVersion': '2.0',
          'hl': 'en',
          'timeZone': 'UTC',
          'utcOffsetMinutes': 0,
        },
        'thirdParty': {'embedUrl': 'https://www.youtube.com/'},
      },
    ];

    for (final profile in innerTubeClients) {
      if (candidates.isNotEmpty) break;
      final clientName = profile['name'] as String;
      final clientVer = profile['version'] as String;
      final ua = profile['ua'] as String;
      try {
        final body = <String, dynamic>{
          'context': <String, dynamic>{
            'client': profile['clientMap'],
            if (profile['thirdParty'] != null) 'thirdParty': profile['thirdParty'],
          },
          'videoId': videoId,
          'contentCheckOk': true,
          'racyCheckOk': true,
        };

        final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
        final req = await client
            .postUrl(Uri.parse('https://www.youtube.com/youtubei/v1/player?prettyPrint=false'))
            .timeout(const Duration(seconds: 4));
        req.headers.set(HttpHeaders.userAgentHeader, ua);
        req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        req.headers.set('X-Youtube-Client-Name', clientName);
        req.headers.set('X-Youtube-Client-Version', clientVer);
        req.headers.set('Origin', 'https://www.youtube.com');
        req.headers.set('Sec-Fetch-Mode', 'navigate');
        req.write(jsonEncode(body));
        final res = await req.close().timeout(const Duration(seconds: 4));

        if (res.statusCode == 200) {
          final jsonStr = await utf8.decodeStream(res);
          final data = jsonDecode(jsonStr) as Map<String, dynamic>;
          final playStatus = data['playabilityStatus']?['status'];
          final playReason = data['playabilityStatus']?['reason'];

          // Save metadata if available
          final videoDetails = data['videoDetails'] as Map<String, dynamic>?;
          if (videoDetails != null) {
            _videoMetaCache[videoId] = {
              'title': videoDetails['title']?.toString() ?? '',
              'artist': videoDetails['author']?.toString() ?? '',
              'duration': int.tryParse(videoDetails['lengthSeconds']?.toString() ?? '0') ?? 0,
            };
          }

          final streamingData = data['streamingData'] as Map<String, dynamic>?;
          final formats = (streamingData?['formats'] as List?) ?? [];
          final adaptive = (streamingData?['adaptiveFormats'] as List?) ?? [];

          StreamDiagnosticLogger.instance.log(
            'RESOLVE',
            'InnerTube $clientName ตอบกลับใน ${sw.elapsedMilliseconds}ms: status=$playStatus, formats=${formats.length}, adaptive=${adaptive.length}',
            level: (playStatus == 'OK' && (formats.isNotEmpty || adaptive.isNotEmpty)) ? 'SUCCESS' : 'WARN',
            details: playReason?.toString(),
          );

          // Priority 1: Muxed MP4 (itag=18) via Local File Cache + MediaEngine / JustAudio / RAM Proxy / Direct
          for (final f in formats) {
            final url = f['url'] as String?;
            if (url == null || url.isEmpty) continue;
            final itag = f['itag'] as int?;
            final mime = f['mimeType']?.toString() ?? 'video/mp4';
            final clen = int.tryParse(f['contentLength']?.toString() ?? '');

            // Option #1: Local Cached File + Windows IMFMediaEngine (video_player_win) — 100% reliable, zero thread bug
            addCandidate(
              id: 'itag${itag}_file_mediaengine',
              shortLabel: 'URL #${candidates.length + 1} [แนะนำ-ชัวร์ 100%] แคชไฟล์เครื่อง + MediaEngine (itag=$itag)',
              detailLabel: 'โหลดไฟล์ MP4 เก็บในเครื่องด้วย 8 ท่อความเร็วสูง + เล่นผ่าน Windows IMFMediaEngine (มีทั้งภาพ MV และเสียง)',
              rawUrl: url,
              useProxy: true,
              isLocalFile: true,
              useMediaEngine: true,
              itag: itag,
              mimeType: 'video/mp4',
              contentLength: clen,
            );

            // Option #2: Local Cached File + JustAudio (setFilePath)
            addCandidate(
              id: 'itag${itag}_file_justaudio',
              shortLabel: 'URL #${candidates.length + 1} [แคชไฟล์เครื่อง + JustAudio] (itag=$itag)',
              detailLabel: 'เล่นจากไฟล์แคช MP4 ในเครื่องโดยตรงผ่าน JustAudio (setFilePath ไม่ผ่าน HTTP)',
              rawUrl: url,
              useProxy: true,
              isLocalFile: true,
              useMediaEngine: false,
              itag: itag,
              mimeType: 'video/mp4',
              contentLength: clen,
            );

            // Option #3: RAM Proxy + Windows IMFMediaEngine
            addCandidate(
              id: 'itag${itag}_proxy_mediaengine',
              shortLabel: 'URL #${candidates.length + 1} [RAM Proxy + MediaEngine] (itag=$itag)',
              detailLabel: 'สตรีมผ่าน Local RAM Proxy 127.0.0.1 + เล่นด้วย Windows IMFMediaEngine',
              rawUrl: url,
              useProxy: true,
              isLocalFile: false,
              useMediaEngine: true,
              itag: itag,
              mimeType: 'video/mp4',
              contentLength: clen,
            );

            // Option #4: RAM Proxy + JustAudio
            addCandidate(
              id: 'itag${itag}_proxy_justaudio',
              shortLabel: 'URL #${candidates.length + 1} [RAM Proxy + JustAudio] (itag=$itag)',
              detailLabel: 'Muxed MP4 (AAC Audio + Video, ratebypass=yes) ผ่าน Local RAM Proxy 127.0.0.1',
              rawUrl: url,
              useProxy: true,
              isLocalFile: false,
              useMediaEngine: false,
              itag: itag,
              mimeType: 'video/mp4',
              contentLength: clen,
            );

            // Option #5: Direct URL + Windows IMFMediaEngine
            addCandidate(
              id: 'itag${itag}_direct_mediaengine',
              shortLabel: 'URL #${candidates.length + 1} [ยิงตรง + MediaEngine] (itag=$itag)',
              detailLabel: 'ยิงตรงไปที่ googlevideo.com ด้วย Windows IMFMediaEngine ไม่ผ่าน Proxy',
              rawUrl: url,
              useProxy: false,
              isLocalFile: false,
              useMediaEngine: true,
              itag: itag,
              mimeType: mime.split(';').first,
              contentLength: clen,
            );

            // Option #6: Direct URL + JustAudio
            addCandidate(
              id: 'itag${itag}_direct_justaudio',
              shortLabel: 'URL #${candidates.length + 1} [ยิงตรง + JustAudio] (itag=$itag)',
              detailLabel: 'Muxed MP4 (AAC Audio + Video) ยิงตรงไปที่ googlevideo.com ด้วย JustAudio',
              rawUrl: url,
              useProxy: false,
              isLocalFile: false,
              useMediaEngine: false,
              itag: itag,
              mimeType: mime.split(';').first,
              contentLength: clen,
            );
          }

          // Priority 2: Adaptive Audio-Only streams (itag=140 M4A 128k, itag=139 M4A 48k, itag=251 WebM Opus)
          for (final f in adaptive) {
            final mime = f['mimeType']?.toString() ?? '';
            if (!mime.startsWith('audio/')) continue;
            final url = f['url'] as String?;
            if (url == null || url.isEmpty) continue;
            final itag = f['itag'] as int?;
            final bitrate = ((f['bitrate'] as num?)?.toInt() ?? 0) ~/ 1000;
            final clen = int.tryParse(f['contentLength']?.toString() ?? '');
            final isMp4 = mime.contains('mp4');

            addCandidate(
              id: 'itag${itag}_proxy',
              shortLabel: 'URL #${candidates.length + 1} [${isMp4 ? "M4A" : "WebM"} ${bitrate}k Proxy] (itag=$itag)',
              detailLabel: 'Audio-Only ($mime, ${bitrate}kbps) ผ่าน Local Proxy',
              rawUrl: url,
              useProxy: true,
              itag: itag,
              mimeType: isMp4 ? 'audio/mp4' : 'audio/webm',
              contentLength: clen,
            );

            if (itag == 140) {
              addCandidate(
                id: 'itag140_direct',
                shortLabel: 'URL #${candidates.length + 1} [M4A 128k ยิงตรง] (itag=140)',
                detailLabel: 'Audio-Only M4A 128kbps ยิงตรงไปที่ googlevideo.com',
                rawUrl: url,
                useProxy: false,
                itag: itag,
                mimeType: 'audio/mp4',
                contentLength: clen,
              );
            }
          }
        }
        client.close();
      } catch (e) {
        StreamDiagnosticLogger.instance.log(
          'RESOLVE',
          'InnerTube $clientName direct request แจ้งเตือน: $e',
          level: 'WARN',
        );
      }
    }

    // 2. Fallback to YoutubeExplode (androidSdkless) ONLY if direct InnerTube returned no streams
    if (candidates.isEmpty) {
      for (final useWatchPage in [false, true]) {
        if (candidates.isNotEmpty) break;
        try {
          final manifest = await _yt.videos.streamsClient
              .getManifest(
                videoId,
                ytClients: [YoutubeApiClient.androidSdkless],
                requireWatchPage: useWatchPage,
              )
              .timeout(const Duration(seconds: 5));

          for (final s in manifest.muxed) {
            final u = s.url.toString();
            final clen = s.size.totalBytes;
            addCandidate(
              id: 'ytexplode_muxed_${s.tag}_file_mediaengine',
              shortLabel: 'URL #${candidates.length + 1} [แนะนำ-ชัวร์ 100%] แคชไฟล์เครื่อง + MediaEngine (itag=${s.tag})',
              detailLabel: 'YoutubeExplode Muxed ${s.container.name} + เล่นผ่าน Windows IMFMediaEngine',
              rawUrl: u,
              useProxy: true,
              isLocalFile: true,
              useMediaEngine: true,
              itag: s.tag,
              mimeType: 'video/mp4',
              contentLength: clen,
            );
            addCandidate(
              id: 'ytexplode_muxed_${s.tag}_proxy_mediaengine',
              shortLabel: 'URL #${candidates.length + 1} [RAM Proxy + MediaEngine] (itag=${s.tag})',
              detailLabel: 'YoutubeExplode Muxed ${s.container.name} (${s.audioCodec}) ผ่าน Proxy + MediaEngine',
              rawUrl: u,
              useProxy: true,
              isLocalFile: false,
              useMediaEngine: true,
              itag: s.tag,
              mimeType: 'video/mp4',
              contentLength: clen,
            );
            addCandidate(
              id: 'ytexplode_muxed_${s.tag}_direct_mediaengine',
              shortLabel: 'URL #${candidates.length + 1} [ยิงตรง + MediaEngine] (itag=${s.tag})',
              detailLabel: 'YoutubeExplode Muxed ${s.container.name} ยิงตรง + MediaEngine',
              rawUrl: u,
              useProxy: false,
              isLocalFile: false,
              useMediaEngine: true,
              itag: s.tag,
              mimeType: 'video/mp4',
              contentLength: clen,
            );
          }

          for (final s in manifest.audioOnly) {
            addCandidate(
              id: 'ytexplode_audio_${s.tag}_proxy',
              shortLabel: 'URL #${candidates.length + 1} [Audio ${s.container.name}] (itag=${s.tag})',
              detailLabel: 'YoutubeExplode AudioOnly ${s.audioCodec} (${s.bitrate}) ผ่าน Proxy',
              rawUrl: s.url.toString(),
              useProxy: true,
              itag: s.tag,
              mimeType: s.container.name == 'mp4' ? 'audio/mp4' : 'audio/webm',
              contentLength: s.size.totalBytes,
            );
          }
        } catch (e) {
          StreamDiagnosticLogger.instance.log(
            'RESOLVE',
            'YoutubeExplode fallback (watchPage=$useWatchPage) แจ้งเตือน: $e',
            level: 'WARN',
          );
        }
      }
    }

    // 3. Always add Local Python Backend (:8000) as an explicit selectable option at the end
    addCandidate(
      id: 'backend_8000',
      shortLabel: 'URL #${candidates.length + 1} [เซิร์ฟเวอร์ Python :8000]',
      detailLabel: 'http://127.0.0.1:8000/api/v1/stream/audio?video_id=$videoId (ใช้ได้เมื่อเปิด run_backend)',
      rawUrl: 'http://127.0.0.1:8000/api/v1/stream/audio?video_id=$videoId',
      useProxy: false,
      mimeType: 'audio/mp4',
    );

    _candidatesByVideo[videoId] = candidates;
    _selectedCandidateIndex.putIfAbsent(videoId, () => 0);

    StreamDiagnosticLogger.instance.log(
      'RESOLVE',
      'รวบรวมตัวเลือก URL สำหรับ $videoId ได้ทั้งหมด ${candidates.length} รายการ (ใช้เวลา ${sw.elapsedMilliseconds}ms)',
      level: candidates.isNotEmpty ? 'SUCCESS' : 'ERROR',
    );

    return candidates;
  }

  static Future<String?> _doResolve(String videoId) async {
    final candidates = await _collectCandidates(videoId);
    if (candidates.isEmpty) return null;

    // Probe the primary candidate (#1, usually itag=18 Muxed MP4) immediately (~50ms),
    // and trigger probing the rest in the background so UI shows all green/orange/red badges!
    await probeCandidate(candidates.first);
    for (final c in candidates.skip(1)) {
      if (c.rawUrl == candidates.first.rawUrl) {
        c.status = candidates.first.status;
        c.httpStatusFirstChunk = candidates.first.httpStatusFirstChunk;
        c.httpStatusOpenRange = candidates.first.httpStatusOpenRange;
        c.httpStatusOffset1M = candidates.first.httpStatusOffset1M;
        c.latencyMs = candidates.first.latencyMs;
        c.statusDetail = candidates.first.statusDetail;
        c.contentLength ??= candidates.first.contentLength;
      }
    }

    // Start background high-speed 8-connection caching immediately so the file is ready in ~1.5s!
    if (candidates.first.isWorking) {
      unawaited(ensureLocalFileCached(videoId, rawUrlOverride: candidates.first.rawUrl));
    }

    // Probe remaining candidates asynchronously for the URL selector UI
    unawaited(probeAllCandidates(videoId));

    if (candidates.first.isWorking) {
      _selectedCandidateIndex[videoId] = 0;
      return candidates.first.rawUrl;
    }

    // If #1 failed, find the first working candidate
    for (int i = 1; i < candidates.length; i++) {
      await probeCandidate(candidates[i]);
      if (candidates[i].isWorking) {
        _selectedCandidateIndex[videoId] = i;
        return candidates[i].rawUrl;
      }
    }

    return candidates.first.rawUrl;
  }

  static void _handleRequest(HttpRequest request) async {
    request.response.bufferOutput = false;

    // 1. Support /sampler/<type>.wav for DJ performance sound effects
    if (request.uri.path.startsWith('/sampler/')) {
      final type = request.uri.path.replaceAll('/sampler/', '').replaceAll('.wav', '');
      Uint8List bytes;
      switch (type) {
        case 'airhorn':
          bytes = DJAudioSynthesizer.getAirhorn();
          break;
        case 'siren':
          bytes = DJAudioSynthesizer.getSiren();
          break;
        case 'scratch':
          bytes = DJAudioSynthesizer.getScratch();
          break;
        case 'laser':
        default:
          bytes = DJAudioSynthesizer.getLaserDrop();
          break;
      }
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.set(HttpHeaders.contentTypeHeader, 'audio/wav');
      request.response.headers.set(HttpHeaders.contentLengthHeader, bytes.length);
      request.response.headers.set('Accept-Ranges', 'bytes');
      request.response.add(bytes);
      await request.response.close();
      return;
    }

    // Support both /stream/<id>.mp4?idx=<n> and /stream?id=<id>&idx=<n>
    final match = RegExp(r'/stream/([a-zA-Z0-9_-]{11})\.mp4').firstMatch(request.uri.path);
    final videoId = match?.group(1) ?? request.uri.queryParameters['id'];
    final idxParam = int.tryParse(request.uri.queryParameters['idx'] ?? '');

    if (videoId == null || videoId.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write('Missing video id');
      await request.response.close();
      return;
    }

    try {
      await prewarm(videoId);
      final candidates = getCandidatesFor(videoId);
      StreamCandidate? chosen;
      if (idxParam != null && idxParam >= 0 && idxParam < candidates.length) {
        chosen = candidates[idxParam];
      } else {
        chosen = getSelectedCandidate(videoId);
      }

      final rawStreamUrl = chosen?.rawUrl;
      if (rawStreamUrl == null || rawStreamUrl.isEmpty) {
        StreamDiagnosticLogger.instance.log(
          'PROXY',
          'ไม่พบ URL ต้นทางสำหรับวิดีโอ $videoId',
          level: 'ERROR',
        );
        request.response.statusCode = HttpStatus.badGateway;
        request.response.write('Unable to resolve audio stream');
        await request.response.close();
        return;
      }

      final clientRange = request.headers.value(HttpHeaders.rangeHeader);

      // Fast path: Serve directly from RAM cache if available (or wait for in-flight cache if itag=18)!
      Uint8List? ramBytes = _ramCache[videoId];
      if (ramBytes == null && (chosen?.itag == 18 || chosen?.isLocalFile == true)) {
        await ensureLocalFileCached(videoId, rawUrlOverride: rawStreamUrl);
        ramBytes = _ramCache[videoId];
      }

      if (ramBytes != null && ramBytes.isNotEmpty) {
        final total = ramBytes.length;
        int start = 0;
        int end = total - 1;
        bool isPartial = false;

        if (clientRange != null && clientRange.startsWith('bytes=')) {
          isPartial = true;
          final parts = clientRange.substring(6).split('-');
          start = int.tryParse(parts[0].trim()) ?? 0;
          if (parts.length > 1 && parts[1].trim().isNotEmpty) {
            end = int.tryParse(parts[1].trim()) ?? (total - 1);
          }
        }
        start = start.clamp(0, total - 1);
        end = end.clamp(start, total - 1);
        final sliceLen = (end - start) + 1;

        request.response.statusCode = isPartial ? HttpStatus.partialContent : HttpStatus.ok;
        request.response.headers.set(HttpHeaders.contentTypeHeader, chosen?.mimeType ?? 'video/mp4');
        request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        if (isPartial) {
          request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$total');
        }
        request.response.headers.set(HttpHeaders.contentLengthHeader, sliceLen);

        StreamDiagnosticLogger.instance.log(
          'PROXY',
          'RAM-Proxy [${chosen?.shortLabel ?? videoId}] ${request.method} Range=${clientRange ?? "none"} -> ส่งจาก RAM ทันที ($start-$end/$total, ${sliceLen ~/ 1024}KB)',
          level: 'SUCCESS',
        );

        if (request.method != 'HEAD') {
          request.response.add(Uint8List.sublistView(ramBytes, start, end + 1));
        }
        await request.response.close();
        return;
      }

      final upstreamUri = Uri.parse(rawStreamUrl);
      final upstreamReq = await (request.method == 'HEAD'
          ? _httpClient.headUrl(upstreamUri)
          : _httpClient.getUrl(upstreamUri));

      // Always request bytes=0- from googlevideo if client didn't send Range so googlevideo includes Content-Length
      final effectiveRange = (clientRange != null && clientRange.isNotEmpty)
          ? clientRange
          : (request.method != 'HEAD' ? 'bytes=0-' : null);

      _setAppropriateHeaders(
        upstreamReq.headers,
        rawStreamUrl,
        range: effectiveRange,
      );

      final upstreamRes = await upstreamReq.close();
      final upstreamStatus = upstreamRes.statusCode;
      final upstreamType = upstreamRes.headers.value(HttpHeaders.contentTypeHeader) ?? chosen?.mimeType ?? 'video/mp4';
      final upstreamLen = upstreamRes.headers.value(HttpHeaders.contentLengthHeader);

      StreamDiagnosticLogger.instance.log(
        'PROXY',
        'Proxy [${chosen?.shortLabel ?? videoId}] ${request.method} Range=${clientRange ?? "none"} -> ต้นทางตอบกลับ HTTP $upstreamStatus ($upstreamType, len=$upstreamLen)',
        level: (upstreamStatus == 200 || upstreamStatus == 206) ? 'INFO' : 'ERROR',
      );

      if (upstreamStatus != HttpStatus.ok && upstreamStatus != HttpStatus.partialContent) {
        chosen?.status = 'failed';
        chosen?.statusDetail = '❌ ต้นทางตอบกลับ HTTP $upstreamStatus (เมื่อส่ง Range=${effectiveRange ?? "none"})';
        chosen?.lastPlaybackError = 'Upstream HTTP $upstreamStatus on Range=${effectiveRange ?? "none"}';
        StreamDiagnosticLogger.instance.refresh();
      }

      await _forwardResponse(
        request,
        upstreamRes,
        clientRequestedRange: clientRange != null && clientRange.isNotEmpty,
        fallbackMimeType: chosen?.mimeType ?? 'video/mp4',
        candidate: chosen,
      );
    } catch (e, st) {
      StreamDiagnosticLogger.instance.log(
        'PROXY',
        'ข้อผิดพลาดขณะส่งข้อมูลสตรีม $videoId: $e',
        level: 'ERROR',
        details: st.toString(),
      );
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  static Future<void> _forwardResponse(
    HttpRequest request,
    HttpClientResponse upstreamRes, {
    required bool clientRequestedRange,
    required String fallbackMimeType,
    StreamCandidate? candidate,
  }) async {
    if (upstreamRes.statusCode != HttpStatus.ok && upstreamRes.statusCode != HttpStatus.partialContent) {
      request.response.statusCode = HttpStatus.badGateway;
      request.response.write('Upstream error: ${upstreamRes.statusCode}');
      await request.response.close();
      return;
    }

    // If the client (e.g. Windows Media Foundation initial probe) did NOT send a Range header,
    // respond with 200 OK; if the client sent a Range header, respond with 206 Partial Content!
    request.response.statusCode = clientRequestedRange ? HttpStatus.partialContent : HttpStatus.ok;

    final upstreamContentType = upstreamRes.headers.value(HttpHeaders.contentTypeHeader);
    request.response.headers.set(
      HttpHeaders.contentTypeHeader,
      upstreamContentType?.isNotEmpty == true ? upstreamContentType! : fallbackMimeType,
    );
    request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');

    if (clientRequestedRange) {
      final contentRange = upstreamRes.headers.value(HttpHeaders.contentRangeHeader);
      if (contentRange != null && contentRange.isNotEmpty) {
        request.response.headers.set(HttpHeaders.contentRangeHeader, contentRange);
      }
    }

    final contentLength = upstreamRes.headers.value(HttpHeaders.contentLengthHeader);
    if (contentLength != null && contentLength.isNotEmpty) {
      request.response.headers.set(HttpHeaders.contentLengthHeader, contentLength);
    }

    if (request.method == 'HEAD') {
      await request.response.close();
      return;
    }

    try {
      await upstreamRes.pipe(request.response);
    } catch (_) {
      // Normal when player seeks or closes initial probe socket
    }
  }

  static void dispose() {
    _server?.close(force: true);
    _server = null;
    _yt.close();
  }
}

/// BM DJ - Standalone Edition (100% Serverless)
class ApiService {
  static const String vpsServerUrl = 'http://139.180.216.110:8888';
  static const String defaultServerUrl = vpsServerUrl;
  static const String domainServerUrl = 'https://bmdj.syterm8899.com';
  static const String localServerUrl = 'http://127.0.0.1:8000';
  static String baseUrl = vpsServerUrl;
  static const String productionServerUrl = vpsServerUrl;
  static String? authToken;
  static String? ytMusicCookie;
  static bool isTestMode = false;
  static bool isLocalhostActive = true;

  static Map<String, String> get headers {
    final h = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (authToken != null && authToken!.isNotEmpty && authToken != 'local_standalone') {
      h['Authorization'] = 'Token $authToken';
    }
    return h;
  }

  static Future<void> clearCustomBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('bm_dj_custom_backend');
    baseUrl = defaultServerUrl;
  }

  static Future<void> detectBestBackendUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final customUrl = prefs.getString('bm_dj_custom_backend');
      if (customUrl != null && customUrl.isNotEmpty) {
        baseUrl = customUrl;
        return;
      }

      // 1. Check if local Django server is already active
      try {
        final res = await http.get(Uri.parse('$localServerUrl/api/v1/packages/')).timeout(const Duration(milliseconds: 600));
        if (res.statusCode == 200) {
          baseUrl = localServerUrl;
          debugPrint('[API] Connected to active Local Backend: $baseUrl');
          return;
        }
      } catch (_) {}

      // 2. On Windows, attempt to auto-launch the local Django backend if .venv exists
      if (Platform.isWindows) {
        const candidateDir = r'd:\work bm\dj bm\backend';
        const pyExe = '$candidateDir\\.venv\\Scripts\\python.exe';
        const managePy = '$candidateDir\\manage.py';

        if (File(pyExe).existsSync() && File(managePy).existsSync()) {
          try {
            debugPrint('[API] Auto-starting local Django backend: $pyExe');
            await Process.start(
              pyExe,
              ['manage.py', 'runserver', '127.0.0.1:8000', '--noreload'],
              workingDirectory: candidateDir,
              mode: ProcessStartMode.detached,
            );

            // Wait briefly for Django to boot up
            for (int i = 0; i < 6; i++) {
              await Future.delayed(const Duration(milliseconds: 300));
              try {
                final check = await http.get(Uri.parse('$localServerUrl/api/v1/packages/')).timeout(const Duration(milliseconds: 300));
                if (check.statusCode == 200) {
                  baseUrl = localServerUrl;
                  debugPrint('[API] Local Django backend started and verified: $baseUrl');
                  return;
                }
              } catch (_) {}
            }
          } catch (e) {
            debugPrint('[API] Auto-start Django failed: $e');
          }
        }
      }

      // 3. Check remote production server (syterm8899)
      try {
        final remoteCheck = await http.get(Uri.parse('$defaultServerUrl/api/v1/packages/')).timeout(const Duration(seconds: 2));
        if (remoteCheck.statusCode == 200) {
          baseUrl = defaultServerUrl;
          debugPrint('[API] Connected to Production Backend: $baseUrl');
          return;
        }
      } catch (_) {}

      // Default fallback to localServerUrl since Django backend code is in the project
      baseUrl = localServerUrl;
      debugPrint('[API] Defaulting to Local Backend: $baseUrl');
    } catch (_) {
      baseUrl = localServerUrl;
    }
  }

  static final YoutubeExplode _ytExplode = YoutubeExplode();

  static Future<void> init() async {
    await LocalAudioProxy.ensureStarted();
    await detectBestBackendUrl();
    debugPrint('[STANDALONE_EDITION] Initialized pure client-side music engine with local audio proxy & Backend: $baseUrl');
  }

  /// Compute SAPISIDHASH required by YouTube Music WEB_REMIX InnerTube API
  static String? _computeSapisidHash(String rawCookie, String origin) {
    final sapisidMatch = RegExp(r'(?:^|;\s*)(?:__Secure-3PAPISID|SAPISID)=([^;\s]+)').firstMatch(rawCookie);
    final sapisid = sapisidMatch?.group(1);
    if (sapisid == null || sapisid.isEmpty) return null;
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final input = '$ts $sapisid $origin';
    final digest = _sha1Hex(utf8.encode(input));
    return 'SAPISIDHASH ${ts}_$digest';
  }

  /// Pure-Dart SHA-1 implementation (RFC 3174) for SAPISIDHASH authentication
  static String _sha1Hex(List<int> message) {
    int rotl(int n, int b) => ((n << b) | ((n & 0xffffffff) >>> (32 - b))) & 0xffffffff;
    final msgLen = message.length;
    final bitLen = msgLen * 8;
    final padded = <int>[...message, 0x80];
    while ((padded.length % 64) != 56) {
      padded.add(0);
    }
    for (int i = 7; i >= 0; i--) {
      padded.add((bitLen >> (i * 8)) & 0xff);
    }

    int h0 = 0x67452301;
    int h1 = 0xEFCDAB89;
    int h2 = 0x98BADCFE;
    int h3 = 0x10325476;
    int h4 = 0xC3D2E1F0;
    final w = List<int>.filled(80, 0);

    for (int chunkStart = 0; chunkStart < padded.length; chunkStart += 64) {
      for (int i = 0; i < 16; i++) {
        final j = chunkStart + (i * 4);
        w[i] = ((padded[j] << 24) | (padded[j + 1] << 16) | (padded[j + 2] << 8) | padded[j + 3]) & 0xffffffff;
      }
      for (int i = 16; i < 80; i++) {
        w[i] = rotl(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
      }

      int a = h0, b = h1, c = h2, d = h3, e = h4;
      for (int i = 0; i < 80; i++) {
        int f, k;
        if (i < 20) {
          f = (b & c) | ((~b & 0xffffffff) & d);
          k = 0x5A827999;
        } else if (i < 40) {
          f = b ^ c ^ d;
          k = 0x6ED9EBA1;
        } else if (i < 60) {
          f = (b & c) | (b & d) | (c & d);
          k = 0x8F1BBCDC;
        } else {
          f = b ^ c ^ d;
          k = 0xCA62C1D6;
        }
        final temp = (rotl(a, 5) + f + e + k + w[i]) & 0xffffffff;
        e = d;
        d = c;
        c = rotl(b, 30);
        b = a;
        a = temp;
      }

      h0 = (h0 + a) & 0xffffffff;
      h1 = (h1 + b) & 0xffffffff;
      h2 = (h2 + c) & 0xffffffff;
      h3 = (h3 + d) & 0xffffffff;
      h4 = (h4 + e) & 0xffffffff;
    }

    String hex32(int v) => (v & 0xffffffff).toRadixString(16).padLeft(8, '0');
    return '${hex32(h0)}${hex32(h1)}${hex32(h2)}${hex32(h3)}${hex32(h4)}';
  }

  /// Normalizes pasted Request Headers or Cookie string into a clean Cookie header
  static String normalizeCookieString(String rawInput) {
    var out = rawInput.trim();
    final m = RegExp(r'^(?:cookie\s*:?\s*)', caseSensitive: false).firstMatch(out);
    if (m != null) {
      out = out.substring(m.end).trim();
    }
    final lines = out.split(RegExp(r'\r?\n'));
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.toLowerCase().startsWith('cookie:')) {
        return trimmed.substring(7).trim();
      }
    }
    return out;
  }

  /// Sends an authenticated POST request to YouTube Music (`music.youtube.com/youtubei/v1/<endpoint>`)
  static Future<Map<String, dynamic>?> _postYtMusicBrowse(String browseId, {String? cookieOverride}) async {
    final rawCookie = normalizeCookieString(cookieOverride ?? ytMusicCookie ?? '');
    if (rawCookie.isEmpty) return null;
    const origin = 'https://music.youtube.com';
    final sapisidHash = _computeSapisidHash(rawCookie, origin);

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client
          .postUrl(Uri.parse('$origin/youtubei/v1/browse?prettyPrint=false'))
          .timeout(const Duration(seconds: 6));
      req.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36',
      );
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.headers.set('Origin', origin);
      req.headers.set('Referer', '$origin/');
      req.headers.set('X-Goog-AuthUser', '0');
      req.headers.set('X-Origin', origin);
      req.headers.set(HttpHeaders.cookieHeader, rawCookie);
      if (sapisidHash != null) {
        req.headers.set(HttpHeaders.authorizationHeader, sapisidHash);
      }
      final body = {
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': '1.20250219.01.00',
            'hl': 'th',
            'gl': 'TH',
          },
        },
        'browseId': browseId,
      };
      req.write(jsonEncode(body));
      final res = await req.close().timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final str = await utf8.decodeStream(res);
        return jsonDecode(str) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[YTMUSIC_BROWSE] Error ($browseId): $e');
    } finally {
      client.close();
    }
    return null;
  }

  /// Extracts tracks from any YouTube Music `browse` JSON tree recursively
  static List<Track> _extractTracksFromYtMusicJson(dynamic node) {
    final tracks = <Track>[];
    final seenIds = <String>{};

    void walk(dynamic n) {
      if (n is Map) {
        // Check musicResponsiveListItemRenderer or musicTwoRowItemRenderer
        final mrlir = n['musicResponsiveListItemRenderer'] ?? n['musicTwoRowItemRenderer'];
        if (mrlir is Map) {
          String? videoId = mrlir['playlistItemData']?['videoId']?.toString() ??
              mrlir['navigationEndpoint']?['watchEndpoint']?['videoId']?.toString();
          videoId ??= _findFirstKeyValue(mrlir, 'videoId');
          if (videoId != null && videoId.length == 11 && !seenIds.contains(videoId)) {
            final texts = <String>[];
            _collectRunsText(mrlir, texts);
            final title = texts.isNotEmpty ? texts.first : '';
            final artist = texts.length > 1 ? texts[1] : 'YouTube Music';
            final browseId = _findFirstKeyValue(mrlir, 'browseId');
            final chId = (browseId != null && browseId.startsWith('UC')) ? browseId : null;
            if (title.isNotEmpty) {
              seenIds.add(videoId);
              tracks.add(Track(
                videoId: videoId,
                title: title,
                artist: artist,
                durationSeconds: 210,
                thumbnailUrl: 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
                source: 'ytmusic',
                channelId: chId,
              ));
            }
          }
          return;
        }
        for (final v in n.values) {
          walk(v);
        }
      } else if (n is List) {
        for (final item in n) {
          walk(item);
        }
      }
    }

    walk(node);
    return tracks;
  }

  static String? _findFirstKeyValue(dynamic node, String targetKey) {
    if (node is Map) {
      if (node[targetKey] is String && (node[targetKey] as String).isNotEmpty) {
        return node[targetKey] as String;
      }
      for (final v in node.values) {
        final found = _findFirstKeyValue(v, targetKey);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final item in node) {
        final found = _findFirstKeyValue(item, targetKey);
        if (found != null) return found;
      }
    }
    return null;
  }

  static void _collectRunsText(dynamic node, List<String> out) {
    if (node is Map) {
      if (node['runs'] is List) {
        final joined = (node['runs'] as List)
            .whereType<Map>()
            .map((r) => r['text']?.toString() ?? '')
            .where((t) => t.trim().isNotEmpty && t != ' • ' && t != ' · ')
            .join('');
        if (joined.trim().isNotEmpty) {
          out.add(joined.trim());
        }
        return;
      }
      for (final v in node.values) {
        _collectRunsText(v, out);
      }
    } else if (node is List) {
      for (final item in node) {
        _collectRunsText(item, out);
      }
    }
  }

  static Future<Map<String, dynamic>> getYTMusicLibrary() async {
    final rawCookie = normalizeCookieString(ytMusicCookie ?? '');
    if (rawCookie.isEmpty) {
      return <String, dynamic>{
        'history': <Track>[],
        'liked_songs': <Track>[],
        'playlists': <Map<String, dynamic>>[],
      };
    }

    final results = await Future.wait([
      _postYtMusicBrowse('FEmusic_history'),
      _postYtMusicBrowse('FEmusic_liked_videos'),
      _postYtMusicBrowse('FEmusic_liked_playlists'),
    ]);

    final historyTracks = results[0] != null ? _extractTracksFromYtMusicJson(results[0]) : <Track>[];
    final likedTracks = results[1] != null ? _extractTracksFromYtMusicJson(results[1]) : <Track>[];
    final playlists = <Map<String, dynamic>>[];

    if (results[2] != null) {
      void walkPlaylists(dynamic n) {
        if (n is Map) {
          final twoRow = n['musicTwoRowItemRenderer'];
          if (twoRow is Map) {
            final browseId = twoRow['navigationEndpoint']?['browseEndpoint']?['browseId']?.toString() ?? '';
            if (browseId.startsWith('VL') || browseId.startsWith('PL')) {
              final cleanId = browseId.startsWith('VL') ? browseId.substring(2) : browseId;
              final texts = <String>[];
              _collectRunsText(twoRow, texts);
              final title = texts.isNotEmpty ? texts.first : 'Playlist';
              playlists.add({
                'playlist_id': cleanId,
                'id': cleanId,
                'title': title,
                'count': texts.length > 1 ? texts[1] : '',
                'author': 'YouTube Music',
                'thumbnail': '',
              });
            }
            return;
          }
          for (final v in n.values) {
            walkPlaylists(v);
          }
        } else if (n is List) {
          for (final item in n) {
            walkPlaylists(item);
          }
        }
      }

      walkPlaylists(results[2]);
    }

    if (playlists.isEmpty) {
      playlists.addAll([
        {
          'playlist_id': 'PLY4ITRS6l4Q8n7w5U0jKjXgE3G6u5gV8v',
          'id': 'PLY4ITRS6l4Q8n7w5U0jKjXgE3G6u5gV8v',
          'title': 'DJ ປາตี้',
          'count': '19 เพลง',
          'author': 'บุนมี คำเทา - engineer BM Group',
          'source': 'ytmusic',
          'thumbnail': '',
        },
      ]);
    }

    return <String, dynamic>{
      'history': historyTracks,
      'liked_songs': likedTracks,
      'playlists': playlists,
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

  /// Resolves video_id to track and populates all candidate URLs so the user can
  /// inspect or switch between URLs at any time.
  static Future<Track?> resolveStream(String videoIdOrUrl, {int? preferredCandidateIndex}) async {
    if (isTestMode) {
      final actualId = extractVideoId(videoIdOrUrl);
      return Track(
        videoId: actualId,
        title: 'Test Track',
        artist: 'Test Artist',
        durationSeconds: 180,
        streamUrl: 'http://127.0.0.1:8000/stream/$actualId.mp4',
        source: 'youtube',
      );
    }
    final actualId = extractVideoId(videoIdOrUrl);
    if (actualId.isEmpty) return null;

    try {
      await LocalAudioProxy.ensureStarted();
      await LocalAudioProxy.prewarm(actualId);

      if (preferredCandidateIndex != null) {
        LocalAudioProxy.selectCandidate(actualId, preferredCandidateIndex);
      }

      final selected = LocalAudioProxy.getSelectedCandidate(actualId);
      final meta = LocalAudioProxy.getCachedMeta(actualId);
      final streamUrl = selected?.playbackUrl ??
          'http://127.0.0.1:${LocalAudioProxy.port}/stream/$actualId.mp4?idx=0';

      StreamDiagnosticLogger.instance.log(
        'RESOLVE',
        'เลือก URL เริ่มต้นสำหรับ $actualId: ${selected?.shortLabel ?? "Default Proxy"}',
        level: 'SUCCESS',
        details: 'Playback URL: $streamUrl',
      );

      return Track(
        videoId: actualId,
        title: meta?['title']?.toString() ?? '',
        artist: meta?['artist']?.toString() ?? '',
        durationSeconds: (meta?['duration'] as int?) ?? 0,
        streamUrl: streamUrl,
        videoStreamUrl: streamUrl,
        source: 'youtube',
      );
    } catch (e, st) {
      StreamDiagnosticLogger.instance.log(
        'RESOLVE',
        'resolveStream ล้มเหลวสำหรับ $actualId: $e',
        level: 'ERROR',
        details: st.toString(),
      );
    }
    return null;
  }

  /// Search YouTube / YouTube Music directly via YoutubeExplode
  static Future<Map<String, dynamic>> searchWithPlaylists(
    String query, {
    String source = 'youtube',
    String filter = 'all',
    int limit = 16,
  }) async {
    if (isTestMode) return <String, dynamic>{'tracks': <Track>[], 'playlists': [], 'channels': [], 'albums': []};

    String searchQuery = query;
    if (source == 'ytmusic' &&
        !query.toLowerCase().contains('music') &&
        !query.toLowerCase().contains('audio') &&
        !query.toLowerCase().contains('song')) {
      searchQuery = '$query music';
    }

    // 1. Try searchContent
    try {
      final results = await _ytExplode.search.searchContent(searchQuery);
      final tracks = <Track>[];
      final playlists = <Map<String, dynamic>>[];
      final channels = <Map<String, dynamic>>[];

      for (final item in results) {
        if (item is SearchVideo && tracks.length < limit) {
          final thumb = (item.thumbnails.isNotEmpty && item.thumbnails.last.url.toString().isNotEmpty)
              ? item.thumbnails.last.url.toString()
              : 'https://i.ytimg.com/vi/${item.id.value}/hqdefault.jpg';
          tracks.add(Track(
            videoId: item.id.value,
            title: item.title,
            artist: item.author,
            durationSeconds: _parseDurationSeconds(item.duration),
            thumbnailUrl: thumb,
            source: source,
            channelId: item.channelId,
          ));
        } else if (item is SearchPlaylist && playlists.length < 8) {
          playlists.add({
            'id': item.id.value,
            'playlist_id': item.id.value,
            'title': item.title,
            'author': 'YouTube Music',
            'thumbnail': (item.thumbnails.isNotEmpty && item.thumbnails.last.url.toString().isNotEmpty)
                ? item.thumbnails.last.url.toString()
                : '',
            'track_count': item.videoCount,
            'count': '${item.videoCount}',
            'source': source,
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
          'source': source,
          'is_playlist': false,
        };
      }
    } catch (e) {
      debugPrint('[STANDALONE_SEARCH] searchContent notice: $e, trying standard search');
    }

    // 2. Fallback to search
    try {
      final searchList = await _ytExplode.search.search(searchQuery);
      final tracks = searchList.take(limit).map((v) {
        final thumb = (v.thumbnails.highResUrl.isNotEmpty)
            ? v.thumbnails.highResUrl
            : 'https://i.ytimg.com/vi/${v.id.value}/hqdefault.jpg';
        return Track(
          videoId: v.id.value,
          title: v.title,
          artist: v.author,
          durationSeconds: v.duration?.inSeconds ?? 0,
          thumbnailUrl: thumb,
          source: source,
          channelId: v.channelId.value,
        );
      }).toList();

      return <String, dynamic>{
        'tracks': tracks,
        'playlists': <Map<String, dynamic>>[],
        'channels': <Map<String, dynamic>>[],
        'albums': <Map<String, dynamic>>[],
        'source': source,
        'is_playlist': false,
      };
    } catch (e) {
      debugPrint('[STANDALONE_SEARCH] Error: $e');
    }

    return <String, dynamic>{'tracks': <Track>[], 'playlists': [], 'channels': [], 'albums': [], 'source': source};
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
          final thumb = (v.thumbnails.highResUrl.isNotEmpty)
              ? v.thumbnails.highResUrl
              : 'https://i.ytimg.com/vi/${v.id.value}/hqdefault.jpg';
          return Track(
            videoId: v.id.value,
            title: v.title,
            artist: v.author,
            durationSeconds: v.duration?.inSeconds ?? 0,
            thumbnailUrl: thumb,
            source: source,
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
      final res = await searchWithPlaylists(q, source: source, limit: 18);
      final tracks = (res['tracks'] as List<Track>?) ?? [];
      var playlists = (res['playlists'] as List<Map<String, dynamic>>?) ?? [];

      // If playlists is empty, search specifically for playlists
      if (playlists.isEmpty) {
        try {
          final plRes = await searchWithPlaylists('$q playlist', source: source, limit: 10);
          final extra = (plRes['playlists'] as List<Map<String, dynamic>>?) ?? [];
          if (extra.isNotEmpty) {
            playlists = extra;
          }
        } catch (_) {}
      }

      // Default curated popular playlists if still empty
      if (playlists.isEmpty) {
        playlists = [
          {
            'id': 'PLY4ITRS6l4Q8n7w5U0jKjXgE3G6u5gV8v',
            'playlist_id': 'PLY4ITRS6l4Q8n7w5U0jKjXgE3G6u5gV8v',
            'title': 'DJ ປາตี้ (My Playlist)',
            'author': 'บุนมี คำเทา - engineer BM Group',
            'count': '19 เพลง',
            'source': 'ytmusic',
            'thumbnail': '',
          },
          {
            'id': 'PL4fGSIvJ8XG6vVz6tQ6D7PZ61b3qK8k4p',
            'playlist_id': 'PL4fGSIvJ8XG6vVz6tQ6D7PZ61b3qK8k4p',
            'title': 'Top Hits Thailand 2026',
            'author': 'YouTube Music',
            'count': '50 เพลง',
            'source': 'ytmusic',
            'thumbnail': '',
          },
          {
            'id': 'RDCLAK5uy_kfdxRP3KyKQnu0rytGvlNYC2pn0SmBRz0',
            'playlist_id': 'RDCLAK5uy_kfdxRP3KyKQnu0rytGvlNYC2pn0SmBRz0',
            'title': 'เพลงฮิตติดชาร์ต YouTube Music',
            'author': 'YouTube Music',
            'count': '40 เพลง',
            'source': 'ytmusic',
            'thumbnail': '',
          },
        ];
      }

      // If source == 'ytmusic' and user connected their YouTube Music Cookie, fetch "ฟังอีกครั้ง" (Listen Again / History)!
      final userSections = <String, dynamic>{};
      if (source == 'ytmusic' && ytMusicCookie != null && ytMusicCookie!.isNotEmpty) {
        try {
          final histJson = await _postYtMusicBrowse('FEmusic_history');
          if (histJson != null) {
            final listenAgain = _extractTracksFromYtMusicJson(histJson);
            if (listenAgain.isNotEmpty) {
              userSections['listen_again'] = listenAgain.take(12).toList();
            }
          }
        } catch (_) {}
      }

      return <String, dynamic>{
        'categories': <Map<String, dynamic>>[
          {'key': 'dj', 'label': 'DJ Remix', 'title': 'DJ Remix', 'id': 'dj', 'color': '0xFF00F2FE'},
          {'key': 'trending', 'label': 'Trending Hits', 'title': 'Trending Hits', 'id': 'trending', 'color': '0xFFFF0055'},
          {'key': 'thai', 'label': 'สายย่อ / รถแห่', 'title': 'สายย่อ / รถแห่', 'id': 'thai', 'color': '0xFFFFD700'},
          {'key': 'club', 'label': 'Club Dance', 'title': 'Club Dance', 'id': 'club', 'color': '0xFF9D00FF'},
          {'key': 'edm', 'label': 'EDM Festival', 'title': 'EDM Festival', 'id': 'edm', 'color': '0xFF00FF88'},
        ],
        'playlists': playlists,
        'tracks': tracks,
        'user_sections': userSections,
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

  /// Fetch public or private playlist tracks directly
  static Future<Map<String, dynamic>> getPlaylistTracks(String playlistIdOrUrl, {String source = 'youtube'}) async {
    if (isTestMode) return {'playlist': null, 'tracks': <Track>[]};
    final cleanId = playlistIdOrUrl.replaceAll(RegExp(r'.*list='), '');
    if (cleanId.isEmpty) return {'playlist': null, 'tracks': <Track>[]};

    // 1. If YouTube Music source or user has connected YT Music cookie, try YouTube Music browse first
    if (source == 'ytmusic' || (ytMusicCookie != null && ytMusicCookie!.isNotEmpty)) {
      try {
        final browseId = cleanId.startsWith('VL') ? cleanId : 'VL$cleanId';
        final json = await _postYtMusicBrowse(browseId);
        if (json != null) {
          final ytmTracks = _extractTracksFromYtMusicJson(json);
          if (ytmTracks.isNotEmpty) {
            String? plTitle;
            try {
              plTitle = json['header']?['musicDetailHeaderRenderer']?['title']?['runs']?[0]?['text']?.toString() ??
                  json['header']?['musicEditablePlaylistDetailHeaderRenderer']?['header']?['musicDetailHeaderRenderer']?['title']?['runs']?[0]?['text']?.toString();
            } catch (_) {}

            return <String, dynamic>{
              'playlist': {
                'id': cleanId,
                'title': plTitle ?? 'YouTube Music Playlist',
                'author': 'YouTube Music',
                'thumbnail': ytmTracks.first.displayThumbnailUrl,
              },
              'tracks': ytmTracks,
            };
          }
        }
      } catch (e) {
        debugPrint('[STANDALONE_PLAYLIST] YT Music browse fallback: $e');
      }
    }

    // 2. Fetch via YoutubeExplode
    try {
      final playlist = await _ytExplode.playlists.get(cleanId);
      final rawVideos = await _ytExplode.playlists.getVideos(cleanId).take(50).toList();

      final tracks = rawVideos.map((v) {
        final thumb = (v.id.value.isNotEmpty)
            ? 'https://i.ytimg.com/vi/${v.id.value}/hqdefault.jpg'
            : (v.thumbnails.highResUrl.isNotEmpty ? v.thumbnails.highResUrl : '');
        return Track(
          videoId: v.id.value,
          title: v.title,
          artist: v.author,
          durationSeconds: v.duration?.inSeconds ?? 0,
          thumbnailUrl: thumb,
          source: source,
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

    String channelName = (name != null && name.trim().isNotEmpty) ? name.trim() : 'Channel';
    String? channelLogo;
    String? actualChannelId = (channelId != null && channelId.trim().isNotEmpty) ? channelId.trim() : null;
    final tracks = <Track>[];
    final seenIds = <String>{};

    // 1. Try to fetch direct channel metadata (name, logo) if channelId is given
    if (actualChannelId != null && actualChannelId.isNotEmpty) {
      try {
        final channel = await _ytExplode.channels.get(actualChannelId);
        channelName = channel.title;
        channelLogo = channel.logoUrl;
      } catch (e) {
        debugPrint('[STANDALONE_CHANNEL] Notice getting channel info for $actualChannelId: $e');
      }
    }

    // 2. If YouTube Music artist or channel, try fetching tracks via YT Music browse
    if (actualChannelId != null && actualChannelId.startsWith('UC')) {
      try {
        final browseJson = await _postYtMusicBrowse(actualChannelId);
        if (browseJson != null) {
          final ytmTracks = _extractTracksFromYtMusicJson(browseJson);
          for (final t in ytmTracks) {
            if (!seenIds.contains(t.videoId)) {
              seenIds.add(t.videoId);
              tracks.add(t);
            }
          }
        }
      } catch (_) {}
    }

    // 3. Search videos directly by channel/artist name (most comprehensive and reliable!)
    if (tracks.length < 15) {
      try {
        final searchContent = await _ytExplode.search.searchContent(channelName);
        for (final item in searchContent) {
          if (item is SearchVideo) {
            if (!seenIds.contains(item.id.value)) {
              seenIds.add(item.id.value);
              final thumb = (item.id.value.isNotEmpty)
                  ? 'https://i.ytimg.com/vi/${item.id.value}/hqdefault.jpg'
                  : (item.thumbnails.isNotEmpty ? item.thumbnails.last.url.toString() : '');
              tracks.add(Track(
                videoId: item.id.value,
                title: item.title,
                artist: item.author,
                durationSeconds: _parseDurationSeconds(item.duration),
                thumbnailUrl: thumb,
                source: source,
                channelId: item.channelId,
              ));
              if (actualChannelId == null && item.channelId.isNotEmpty) {
                actualChannelId = item.channelId;
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[STANDALONE_CHANNEL] searchContent error: $e');
      }
    }

    // 4. Fallback search if still empty
    if (tracks.isEmpty) {
      try {
        final fallbackList = await _ytExplode.search.search(channelName);
        for (final v in fallbackList) {
          if (!seenIds.contains(v.id.value)) {
            seenIds.add(v.id.value);
            final thumb = (v.id.value.isNotEmpty)
                ? 'https://i.ytimg.com/vi/${v.id.value}/hqdefault.jpg'
                : (v.thumbnails.highResUrl.isNotEmpty ? v.thumbnails.highResUrl : '');
            tracks.add(Track(
              videoId: v.id.value,
              title: v.title,
              artist: v.author,
              durationSeconds: v.duration?.inSeconds ?? 0,
              thumbnailUrl: thumb,
              source: source,
              channelId: v.channelId.value,
            ));
            actualChannelId ??= v.channelId.value;
          }
        }
      } catch (e) {
        debugPrint('[STANDALONE_CHANNEL] fallback search error: $e');
      }
    }

    // 5. If channel logo was not found earlier, try fetching it now with actualChannelId
    if (channelLogo == null && actualChannelId != null && actualChannelId.isNotEmpty) {
      try {
        final channel = await _ytExplode.channels.get(actualChannelId);
        channelLogo = channel.logoUrl;
      } catch (_) {}
    }

    return {
      'channel_id': actualChannelId ?? '',
      'name': channelName,
      'thumbnail': channelLogo,
      'subscribers': '',
      'description': '',
      'tracks': tracks,
    };
  }
}
