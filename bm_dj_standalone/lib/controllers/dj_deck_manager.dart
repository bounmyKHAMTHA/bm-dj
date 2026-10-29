import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';
import '../models/track.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ActiveDeck { deckA, deckB }

class DJDeckManager extends ChangeNotifier {
  final AudioPlayer deckA = AudioPlayer(
    handleInterruptions: false,
    handleAudioSessionActivation: false,
    androidApplyAudioAttributes: false,
  );
  final AudioPlayer deckB = AudioPlayer(
    handleInterruptions: false,
    handleAudioSessionActivation: false,
    androidApplyAudioAttributes: false,
  );
  final AudioPlayer samplerPlayer = AudioPlayer(
    handleInterruptions: false,
    handleAudioSessionActivation: false,
    androidApplyAudioAttributes: false,
  );

  /// Windows native IMFMediaEngine controllers (video_player_win) — marshals all events
  /// safely onto the Flutter platform thread and plays both Audio + MV video without stalling!
  VideoPlayerController? videoControllerA;
  VideoPlayerController? videoControllerB;
  bool useVideoEngineA = false;
  bool useVideoEngineB = false;

  final StreamController<Duration> _deckPosControllerA = StreamController<Duration>.broadcast();
  final StreamController<Duration> _deckPosControllerB = StreamController<Duration>.broadcast();
  Timer? _uiTickTimer;
  double _lastAppliedVolA = 1.0;
  double _lastAppliedVolB = 0.0;

  bool _wantPlayingA = false;
  bool _wantPlayingB = false;
  String? _mountedVideoIdA;
  String? _mountedVideoIdB;
  Duration _maxPositionReachedA = Duration.zero;
  Duration _maxPositionReachedB = Duration.zero;
  int _loadTokenA = 0;
  int _loadTokenB = 0;

  bool isDeckAPlaying = true;
  bool isTransitioning = false;
  double crossfadePosition = 0.0; // 0.0 = A, 1.0 = B
  int transitionDurationSeconds = 4;
  bool autoCrossfadeEnabled = true;
  bool keyLockEnabled = true;

  // Master Output Volume (Controls both Deck A & Deck B throughout usage)
  double masterVolume = 1.0;
  double _prevMasterVolume = 1.0;
  double volumeGainA = 1.0;
  double volumeGainB = 1.0;

  double speedDeckA = 1.0;
  double speedDeckB = 1.0;

  // Hot Cues: index 1..4 -> Duration
  final Map<int, Duration> hotCuesA = {};
  final Map<int, Duration> hotCuesB = {};

  // Auto Beat Looping
  bool isLoopingA = false;
  Duration? loopStartA;
  double loopBeatsA = 4.0;

  bool isLoopingB = false;
  Duration? loopStartB;
  double loopBeatsB = 4.0;

  // 3-Band EQ & Filter
  double eqLowA = 1.0;
  double eqMidA = 1.0;
  double eqHighA = 1.0;
  double filterA = 0.0;
  bool isBassKilledA = false;
  bool isMidKilledA = false;
  bool isHighKilledA = false;

  double eqLowB = 1.0;
  double eqMidB = 1.0;
  double eqHighB = 1.0;
  double filterB = 0.0;
  bool isBassKilledB = false;
  bool isMidKilledB = false;
  bool isHighKilledB = false;

  // Turbo Boost Mode (1.25x speed boost)
  bool isTurboA = false;
  bool isTurboB = false;

  // BPM & Beat Sync & Tap Tempo
  double bpmDeckA = 128.0;
  double bpmDeckB = 128.0;
  final List<DateTime> _tapTimesA = [];
  final List<DateTime> _tapTimesB = [];

  // Live Recording Session Tracking
  bool isRecording = false;
  Duration recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  final List<String> recordedTracklist = [];

  Track? trackA;
  Track? trackB;
  final List<Track> queue = [];

  // Low-Spec & Eco Mode: optimizes animations, lowers redraw rates, and reduces memory consumption
  bool lowSpecMode = false;

  // Hide URL selector & diagnostic tools on the main Deck UI by default (accessible in Settings ⚙️)
  bool showUrlDiagnosticTools = false;

  void toggleLowSpecMode() {
    lowSpecMode = !lowSpecMode;
    AuthService.instance.syncSettings({
      'lowSpecMode': lowSpecMode,
      'transitionDurationSeconds': transitionDurationSeconds,
    });
    notifyListeners();
  }

  void toggleShowUrlDiagnosticTools([bool? value]) {
    showUrlDiagnosticTools = value ?? !showUrlDiagnosticTools;
    notifyListeners();
  }

  bool _disposed = false;
  StreamSubscription? _posSubA;
  StreamSubscription? _posSubB;
  StreamSubscription? _stateSubA;
  StreamSubscription? _stateSubB;
  StreamSubscription? _eventSubA;
  StreamSubscription? _eventSubB;

  AudioPlayer get activePlayer => isDeckAPlaying ? deckA : deckB;
  AudioPlayer get standbyPlayer => isDeckAPlaying ? deckB : deckA;
  Track? get activeTrack {
    final playA = isDeckPlaying(ActiveDeck.deckA);
    final playB = isDeckPlaying(ActiveDeck.deckB);
    if (playA && !playB) return trackA;
    if (playB && !playA) return trackB;
    return (crossfadePosition <= 0.5) ? (trackA ?? trackB) : (trackB ?? trackA);
  }

  Track? get standbyTrack {
    final playA = isDeckPlaying(ActiveDeck.deckA);
    final playB = isDeckPlaying(ActiveDeck.deckB);
    if (playA && !playB) return trackB;
    if (playB && !playA) return trackA;
    return (crossfadePosition <= 0.5) ? trackB : trackA;
  }

  // --- Unified Dual-Engine Deck Getters (MediaEngine + JustAudio) ---
  bool isDeckPlaying(ActiveDeck deck) {
    final isA = deck == ActiveDeck.deckA;
    if (isA ? useVideoEngineA : useVideoEngineB) {
      final vc = isA ? videoControllerA : videoControllerB;
      return vc != null && vc.value.isInitialized && vc.value.isPlaying;
    }
    return (isA ? deckA : deckB).playing;
  }

  Duration getDeckPosition(ActiveDeck deck) {
    final isA = deck == ActiveDeck.deckA;
    if (isA ? useVideoEngineA : useVideoEngineB) {
      final vc = isA ? videoControllerA : videoControllerB;
      if (vc != null && vc.value.isInitialized) {
        return vc.value.position;
      }
      return Duration.zero;
    }
    return (isA ? deckA : deckB).position;
  }

  Duration getDeckDuration(ActiveDeck deck) {
    final isA = deck == ActiveDeck.deckA;
    final track = isA ? trackA : trackB;
    if (isA ? useVideoEngineA : useVideoEngineB) {
      final vc = isA ? videoControllerA : videoControllerB;
      if (vc != null && vc.value.isInitialized && vc.value.duration > Duration.zero) {
        return vc.value.duration;
      }
    } else {
      final d = (isA ? deckA : deckB).duration;
      if (d != null && d > Duration.zero) return d;
    }
    return Duration(seconds: track?.durationSeconds ?? 0);
  }

  Duration getDeckBuffered(ActiveDeck deck) {
    final isA = deck == ActiveDeck.deckA;
    if (isA ? useVideoEngineA : useVideoEngineB) {
      final vc = isA ? videoControllerA : videoControllerB;
      if (vc != null && vc.value.isInitialized) {
        if (vc.value.buffered.isNotEmpty) {
          return vc.value.buffered.last.end;
        }
        return vc.value.duration;
      }
      return Duration.zero;
    }
    return (isA ? deckA : deckB).bufferedPosition;
  }

  double getDeckVolume(ActiveDeck deck) {
    final isA = deck == ActiveDeck.deckA;
    if (isA ? useVideoEngineA : useVideoEngineB) {
      return isA ? _lastAppliedVolA : _lastAppliedVolB;
    }
    return (isA ? deckA : deckB).volume;
  }

  Stream<Duration> getDeckPositionStream(ActiveDeck deck) {
    return (deck == ActiveDeck.deckA)
        ? _deckPosControllerA.stream
        : _deckPosControllerB.stream;
  }

  VideoPlayerController? getDeckVideoController(ActiveDeck deck) {
    final isA = deck == ActiveDeck.deckA;
    final vc = isA ? videoControllerA : videoControllerB;
    if ((isA ? useVideoEngineA : useVideoEngineB) && vc != null && vc.value.isInitialized) {
      return vc;
    }
    return null;
  }

  DJDeckManager() {
    _initEngine();
  }

  void _initEngine() {
    _loadMasterVolumeFromPrefs();
    _applyCrossfaderVolumesFast();

    AuthService.instance.onSubscriptionExpired = () {
      pauseAllDecks();
    };

    // Periodic 100ms UI & Engine Heartbeat:
    // 1. Broadcasts real hardware positions for both MediaEngine and JustAudio
    // 2. Keeps the Dart event loop awake on Windows so non-platform thread messages never stall
    // 3. Checks beat loops, auto-crossfade, and track completion
    _uiTickTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_disposed) return;

      final posA = getDeckPosition(ActiveDeck.deckA);
      final posB = getDeckPosition(ActiveDeck.deckB);
      if (posA > _maxPositionReachedA) _maxPositionReachedA = posA;
      if (posB > _maxPositionReachedB) _maxPositionReachedB = posB;

      if (!_deckPosControllerA.isClosed) _deckPosControllerA.add(posA);
      if (!_deckPosControllerB.isClosed) _deckPosControllerB.add(posB);

      if (isDeckPlaying(ActiveDeck.deckA)) {
        _checkLoop(ActiveDeck.deckA, posA);
        _checkAutoCrossfade(ActiveDeck.deckA, posA);
      }
      if (isDeckPlaying(ActiveDeck.deckB)) {
        _checkLoop(ActiveDeck.deckB, posB);
        _checkAutoCrossfade(ActiveDeck.deckB, posB);
      }

      // Check MediaEngine track completion reliably
      if (useVideoEngineA && videoControllerA != null && videoControllerA!.value.isInitialized) {
        final v = videoControllerA!.value;
        final nearEnd = v.position >= v.duration - const Duration(milliseconds: 1800) ||
            _maxPositionReachedA >= v.duration - const Duration(milliseconds: 2500);
        if (_wantPlayingA &&
            !isTransitioning &&
            v.duration.inSeconds >= 8 &&
            (v.isCompleted || (!v.isPlaying && nearEnd))) {
          _onDeckPlaybackCompleted(ActiveDeck.deckA);
        }
      }
      if (useVideoEngineB && videoControllerB != null && videoControllerB!.value.isInitialized) {
        final v = videoControllerB!.value;
        final nearEnd = v.position >= v.duration - const Duration(milliseconds: 1800) ||
            _maxPositionReachedB >= v.duration - const Duration(milliseconds: 2500);
        if (_wantPlayingB &&
            !isTransitioning &&
            v.duration.inSeconds >= 8 &&
            (v.isCompleted || (!v.isPlaying && nearEnd))) {
          _onDeckPlaybackCompleted(ActiveDeck.deckB);
        }
      }
    });

    // Listen to JustAudio positions to monitor auto-crossfade and beat loops
    _posSubA = deckA.positionStream.listen((pos) {
      if (!useVideoEngineA) {
        if (!_deckPosControllerA.isClosed) _deckPosControllerA.add(pos);
        _checkLoop(ActiveDeck.deckA, pos);
        _checkAutoCrossfade(ActiveDeck.deckA, pos);
      }
    });
    _posSubB = deckB.positionStream.listen((pos) {
      if (!useVideoEngineB) {
        if (!_deckPosControllerB.isClosed) _deckPosControllerB.add(pos);
        _checkLoop(ActiveDeck.deckB, pos);
        _checkAutoCrossfade(ActiveDeck.deckB, pos);
      }
    });

    // Listen to playback events & low-level platform/codec errors on Deck A & B
    _eventSubA = deckA.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) {
        if (useVideoEngineA) return;
        final cand = trackA != null ? LocalAudioProxy.getSelectedCandidate(trackA!.videoId) : null;
        cand?.lastPlaybackError = e.toString();
        StreamDiagnosticLogger.instance.log(
          'PLAYER_A',
          'Deck A เกิดข้อผิดพลาดขณะเล่น (${cand?.shortLabel ?? "URL"}): $e',
          level: 'ERROR',
          details: st.toString(),
          deck: 'A',
        );
        notifyListeners();
      },
    );
    _eventSubB = deckB.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) {
        if (useVideoEngineB) return;
        final cand = trackB != null ? LocalAudioProxy.getSelectedCandidate(trackB!.videoId) : null;
        cand?.lastPlaybackError = e.toString();
        StreamDiagnosticLogger.instance.log(
          'PLAYER_B',
          'Deck B เกิดข้อผิดพลาดขณะเล่น (${cand?.shortLabel ?? "URL"}): $e',
          level: 'ERROR',
          details: st.toString(),
          deck: 'B',
        );
        notifyListeners();
      },
    );

    // Listen to playback states and song completions
    _stateSubA = deckA.playerStateStream.listen((state) {
      if (!_disposed && !useVideoEngineA) {
        if (state.processingState == ProcessingState.completed) {
          _onDeckPlaybackCompleted(ActiveDeck.deckA);
        }
        notifyListeners();
      }
    });
    _stateSubB = deckB.playerStateStream.listen((state) {
      if (!_disposed && !useVideoEngineB) {
        if (state.processingState == ProcessingState.completed) {
          _onDeckPlaybackCompleted(ActiveDeck.deckB);
        }
        notifyListeners();
      }
    });

    // Listen to AuthService for user login memory restoration
    AuthService.instance.addListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    final user = AuthService.instance.currentUser;
    if (user != null) {
      // Restore user settings
      if (user.settings.containsKey('lowSpecMode')) {
        lowSpecMode = user.settings['lowSpecMode'] == true;
      }
      if (user.settings.containsKey('transitionDurationSeconds')) {
        transitionDurationSeconds = (user.settings['transitionDurationSeconds'] as num).toInt();
      }
      // Restore queue if empty and user has a saved queue
      if (queue.isEmpty && user.savedQueue.isNotEmpty) {
        queue.addAll(user.savedQueue);
      }
      notifyListeners();
    }
  }

  // Continuous Auto-DJ Mode (Auto-Queue & Auto-DJ endless nonstop)
  bool autoQueueEnabled = true;
  bool _isFetchingAutoQueue = false;

  void toggleAutoQueue() {
    autoQueueEnabled = !autoQueueEnabled;
    if (autoQueueEnabled && queue.isEmpty && standbyTrack == null) {
      _checkAndPreloadNextQueueItem();
    }
    notifyListeners();
  }

  void _checkAutoCrossfade(ActiveDeck deck, Duration position) {
    if (!autoCrossfadeEnabled || isTransitioning) return;

    final otherDeck = deck == ActiveDeck.deckA ? ActiveDeck.deckB : ActiveDeck.deckA;
    final isThisActive = (deck == ActiveDeck.deckA && crossfadePosition <= 0.5) ||
        (deck == ActiveDeck.deckB && crossfadePosition >= 0.5) ||
        !isDeckPlaying(otherDeck);
    if (!isThisActive) return;

    final duration = getDeckDuration(deck);
    if (duration.inSeconds < 10) return;

    final remaining = duration - position;

    // Proactively prepare standby deck once the current track has played at least 3 seconds
    // or when song has <= 45 seconds remaining
    if ((position.inSeconds >= 3 || remaining.inSeconds <= 45) && standbyTrack == null) {
      _checkAndPreloadNextQueueItem();
    }

    // Trigger smooth skip transition when remaining time matches transition duration
    if (remaining.inMilliseconds <= transitionDurationSeconds * 1000 &&
        remaining.inMilliseconds > -2000 &&
        position.inSeconds >= 3) {
      executeSmoothSkip(durationSeconds: transitionDurationSeconds);
    }
  }

  /// When a song finishes playing completely
  Future<void> _onDeckPlaybackCompleted(ActiveDeck deck) async {
    final isDeckA = (deck == ActiveDeck.deckA);
    final pos = getDeckPosition(deck);
    final maxPos = isDeckA ? _maxPositionReachedA : _maxPositionReachedB;
    final effectivePos = pos > maxPos ? pos : maxPos;
    final dur = getDeckDuration(deck);

    // Guard against false-positive completion when position is near 0
    if (dur.inSeconds < 5 || (effectivePos.inSeconds < 3 && (dur - effectivePos).inSeconds > 5)) {
      return;
    }

    if (isDeckA) {
      _wantPlayingA = false;
    } else {
      _wantPlayingB = false;
    }

    final otherDeck = isDeckA ? ActiveDeck.deckB : ActiveDeck.deckA;
    final isThisActive = (isDeckA && crossfadePosition <= 0.5) ||
        (!isDeckA && crossfadePosition >= 0.5) ||
        !isDeckPlaying(otherDeck);
    if (!isThisActive || isTransitioning) return;

    debugPrint("[AUTO-DJ] Deck ${isDeckA ? 'A' : 'B'} completed playback. Advancing to next track.");
    await executeSmoothSkip(durationSeconds: 2);
  }

  Future<void> _pauseDeckInternal(ActiveDeck deck) async {
    final isDeckA = deck == ActiveDeck.deckA;
    final vc = isDeckA ? videoControllerA : videoControllerB;
    final player = isDeckA ? deckA : deckB;
    try {
      if (vc != null && vc.value.isInitialized && vc.value.isPlaying) {
        await vc.pause();
      }
    } catch (_) {}
    try {
      if (player.playing) {
        await player.pause();
      }
    } catch (_) {}
  }

  /// Mounts the chosen [StreamCandidate] onto [deck] using either Windows IMFMediaEngine
  /// (`VideoPlayerController`) or `just_audio` (`AudioPlayer`), downloading the local `.mp4`
  /// file via 8 parallel Range connections first if `cand.isLocalFile` is true.
  Future<bool> _mountCandidateOnDeck(
    ActiveDeck deck,
    Track track,
    StreamCandidate cand, {
    int? expectedToken,
  }) async {
    final isDeckA = deck == ActiveDeck.deckA;
    final deckLabel = isDeckA ? 'A' : 'B';
    final player = isDeckA ? deckA : deckB;
    final speed = isDeckA ? speedDeckA : speedDeckB;

    bool isStale() {
      if (_disposed) return true;
      if (expectedToken != null && (isDeckA ? _loadTokenA : _loadTokenB) != expectedToken) {
        return true;
      }
      final currentTrack = isDeckA ? trackA : trackB;
      if (currentTrack?.videoId != track.videoId) return true;
      return false;
    }

    if (ApiService.isTestMode) {
      try {
        await player.setUrl(cand.playbackUrl);
      } catch (_) {}
      return true;
    }

    // 1. If candidate uses Local File Cache (or RAM Proxy), ensure the 8-connection download completes!
    String? localPath = cand.localFilePath;
    if (cand.isLocalFile || cand.useProxy) {
      localPath = await LocalAudioProxy.ensureLocalFileCached(
        track.videoId,
        rawUrlOverride: cand.rawUrl,
        deckLabel: deckLabel,
      );
      if (isStale()) return false;
      if (localPath != null) {
        cand.localFilePath = localPath;
        if (cand.isLocalFile) {
          cand.playbackUrl = localPath;
        }
      } else if (cand.isLocalFile && !cand.useMediaEngine) {
        cand.lastPlaybackError = 'ดาวน์โหลดไฟล์แคชไม่สำเร็จ';
        cand.status = 'failed';
        cand.statusDetail = '❌ ดาวน์โหลดไฟล์แคชลงเครื่องไม่สำเร็จ';
        return false;
      }
    }

    // 2. Mount on Windows IMFMediaEngine (video_player_win) if requested
    if (cand.useMediaEngine) {
      if (isStale()) return false;
      try {
        await player.stop();
      } catch (_) {}

      final oldVc = isDeckA ? videoControllerA : videoControllerB;
      if (isDeckA) {
        videoControllerA = null;
        useVideoEngineA = true;
      } else {
        videoControllerB = null;
        useVideoEngineB = true;
      }
      if (oldVc != null) {
        unawaited(Future.delayed(const Duration(milliseconds: 200), () {
          try {
            oldVc.dispose();
          } catch (_) {}
        }));
      }

      VideoPlayerController vc;
      if (cand.isLocalFile && localPath != null && File(localPath).existsSync()) {
        vc = VideoPlayerController.file(File(localPath));
      } else {
        // Long mix (>30MB) or direct/proxy stream: stream directly via IMFMediaEngine!
        final streamTarget = (cand.isLocalFile && localPath == null) ? cand.rawUrl : cand.playbackUrl;
        vc = VideoPlayerController.networkUrl(Uri.parse(streamTarget));
      }

      await vc.initialize().timeout(const Duration(seconds: 15));
      if (isStale()) {
        try {
          await vc.dispose();
        } catch (_) {}
        return false;
      }
      if (vc.value.hasError) {
        final err = vc.value.errorDescription ?? 'Unknown IMFMediaEngine error';
        try {
          await vc.dispose();
        } catch (_) {}
        throw Exception(err);
      }

      if (isDeckA) {
        videoControllerA = vc;
        useVideoEngineA = true;
      } else {
        videoControllerB = vc;
        useVideoEngineB = true;
      }

      vc.addListener(() {
        if (!_disposed) {
          if (vc.value.hasError) {
            cand.lastPlaybackError = vc.value.errorDescription;
            StreamDiagnosticLogger.instance.log(
              'PLAYER_$deckLabel',
              'MediaEngine แจ้ง Error บน Deck $deckLabel: ${vc.value.errorDescription}',
              level: 'ERROR',
              deck: deckLabel,
            );
          }
          notifyListeners();
        }
      });

      await _applyCrossfaderVolumes();
      try {
        await vc.setPlaybackSpeed(speed.clamp(0.5, 2.0));
      } catch (_) {}

      cand.lastPlaybackError = null;
      cand.status = 'ok';
      if (isDeckA) {
        _mountedVideoIdA = track.videoId;
        _maxPositionReachedA = Duration.zero;
      } else {
        _mountedVideoIdB = track.videoId;
        _maxPositionReachedB = Duration.zero;
      }
      StreamDiagnosticLogger.instance.log(
        'PLAYER_$deckLabel',
        'โหลด ${cand.shortLabel} สำเร็จ! (Engine: MediaEngine, ความยาว: ${_formatDurationBrief(vc.value.duration)})',
        level: 'SUCCESS',
        deck: deckLabel,
      );
      return true;
    }

    // 3. Otherwise mount on JustAudio (just_audio_windows)
    final oldVc = isDeckA ? videoControllerA : videoControllerB;
    if (isDeckA) {
      videoControllerA = null;
      useVideoEngineA = false;
    } else {
      videoControllerB = null;
      useVideoEngineB = false;
    }
    if (oldVc != null) {
      unawaited(Future.delayed(const Duration(milliseconds: 200), () {
        try {
          oldVc.dispose();
        } catch (_) {}
      }));
    }

    // Keep Dart event loop awake every 40ms while just_audio_windows loads on background WinRT thread
    final wakeTimer = Timer.periodic(const Duration(milliseconds: 40), (_) {});
    try {
      await player.stop();
      if (cand.isLocalFile && localPath != null && File(localPath).existsSync()) {
        await player.setFilePath(localPath).timeout(const Duration(seconds: 15));
      } else {
        await player.setUrl(cand.playbackUrl).timeout(const Duration(seconds: 15));
      }
      await _applyCrossfaderVolumes();
      cand.lastPlaybackError = null;
      cand.status = 'ok';
      if (isDeckA) {
        _mountedVideoIdA = track.videoId;
        _maxPositionReachedA = Duration.zero;
      } else {
        _mountedVideoIdB = track.videoId;
        _maxPositionReachedB = Duration.zero;
      }
      StreamDiagnosticLogger.instance.log(
        'PLAYER_$deckLabel',
        'โหลด ${cand.shortLabel} สำเร็จ! (Engine: JustAudio, ความยาว: ${_formatDurationBrief(player.duration ?? Duration.zero)})',
        level: 'SUCCESS',
        deck: deckLabel,
      );
      return true;
    } finally {
      wakeTimer.cancel();
    }
  }

  String _formatDurationBrief(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Ensures the target deck plays reliably and verifies real hardware position progression!
  Future<bool> _forcePlayDeck(ActiveDeck deck, {bool adjustCrossfaderIfMuted = true}) async {
    final isDeckA = (deck == ActiveDeck.deckA);
    final deckLabel = isDeckA ? 'A' : 'B';
    final player = isDeckA ? deckA : deckB;
    final track = isDeckA ? trackA : trackB;
    final otherDeck = isDeckA ? ActiveDeck.deckB : ActiveDeck.deckA;

    if (isDeckA) {
      _wantPlayingA = true;
    } else {
      _wantPlayingB = true;
    }

    // 1. Ensure master volume & deck gain are audible
    if (masterVolume <= 0.02) {
      masterVolume = 1.0;
    }
    if (isDeckA && volumeGainA <= 0.02) {
      volumeGainA = 1.0;
    } else if (!isDeckA && volumeGainB <= 0.02) {
      volumeGainB = 1.0;
    }

    // 2. Ensure crossfader does not leave this deck muted at 0% volume!
    if (adjustCrossfaderIfMuted) {
      final otherIsPlaying = isDeckPlaying(otherDeck) && (isDeckA ? _wantPlayingB : _wantPlayingA);
      if (!otherIsPlaying) {
        crossfadePosition = isDeckA ? 0.0 : 1.0;
        isDeckAPlaying = isDeckA;
      } else {
        if (isDeckA && crossfadePosition > 0.80) {
          crossfadePosition = 0.5;
          isDeckAPlaying = true;
        } else if (!isDeckA && crossfadePosition < 0.20) {
          crossfadePosition = 0.5;
          isDeckAPlaying = false;
        }
      }
    }

    await _applyCrossfaderVolumes();
    notifyListeners();

    // Proactively preload the standby deck 2 seconds after playback starts if standby is empty
    unawaited(Future.delayed(const Duration(seconds: 2), () {
      if (!_disposed && isDeckPlaying(deck) && standbyTrack == null && (queue.isNotEmpty || autoQueueEnabled)) {
        _checkAndPreloadNextQueueItem();
      }
    }));

    if (ApiService.isTestMode) {
      unawaited(player.play().catchError((_) {}));
      return true;
    }

    final useMediaEngine = isDeckA ? useVideoEngineA : useVideoEngineB;
    final vc = isDeckA ? videoControllerA : videoControllerB;
    final cand = track != null ? LocalAudioProxy.getSelectedCandidate(track.videoId) : null;
    final volPct = (getDeckVolume(deck) * 100).round();

    // 3. If using Windows IMFMediaEngine (video_player_win)
    if (useMediaEngine && vc != null && vc.value.isInitialized) {
      final dur = vc.value.duration;
      if (dur.inSeconds > 5 && vc.value.position >= dur - const Duration(seconds: 2)) {
        try {
          await vc.seekTo(Duration.zero);
        } catch (_) {}
      }

      StreamDiagnosticLogger.instance.log(
        'PLAYER_$deckLabel',
        '▶ สั่งเริ่มเล่นเสียง (MediaEngine Play) บน Deck $deckLabel (${cand?.shortLabel ?? "MediaEngine"}, ระดับเสียง $volPct%)',
        level: 'INFO',
        deck: deckLabel,
      );

      final startPosMs = vc.value.position.inMilliseconds;
      for (int attempt = 1; attempt <= 6; attempt++) {
        if (_disposed) return false;
        if (!(isDeckA ? _wantPlayingA : _wantPlayingB)) return false;

        await _applyCrossfaderVolumes();
        if (!vc.value.isPlaying) {
          try {
            await vc.play();
          } catch (e, st) {
            cand?.lastPlaybackError = e.toString();
            StreamDiagnosticLogger.instance.log(
              'PLAYER_$deckLabel',
              'MediaEngine play() ล้มเหลวบน Deck $deckLabel: $e',
              level: 'ERROR',
              details: st.toString(),
              deck: deckLabel,
            );
          }
        }

        await Future.delayed(const Duration(milliseconds: 220));
        notifyListeners();

        final nowPosMs = vc.value.position.inMilliseconds;
        if (vc.value.isPlaying && (nowPosMs > startPosMs + 40 || nowPosMs > 80)) {
          StreamDiagnosticLogger.instance.log(
            'PLAYER_$deckLabel',
            '🔊 Deck $deckLabel กำลังเล่นเสียง+วิดีโอออกลำโพงจริงแล้ว! (ตำแหน่งจริง: ${nowPosMs}ms, เสียง: ${(getDeckVolume(deck) * 100).round()}%)',
            level: 'SUCCESS',
            deck: deckLabel,
          );
          return true;
        }
      }

      if (vc.value.isPlaying) {
        return true;
      }
      StreamDiagnosticLogger.instance.log(
        'PLAYER_$deckLabel',
        '⚠️ MediaEngine บน Deck $deckLabel ยังไม่เดินหน้า (Pos=${vc.value.position.inMilliseconds}ms, Err=${vc.value.errorDescription})',
        level: 'WARN',
        deck: deckLabel,
      );
      return false;
    }

    // 4. Fallback / Explicit JustAudio engine path
    if (player.processingState == ProcessingState.idle &&
        track?.streamUrl != null &&
        track!.streamUrl!.isNotEmpty) {
      try {
        await player.setUrl(track.streamUrl!);
      } catch (e, st) {
        StreamDiagnosticLogger.instance.log(
          'PLAYER_$deckLabel',
          'โหลด URL ก่อนเล่นไม่สำเร็จบน Deck $deckLabel: $e',
          level: 'ERROR',
          details: st.toString(),
          deck: deckLabel,
        );
        return false;
      }
    }

    final dur = player.duration;
    if (dur != null && dur.inSeconds > 5 && player.position >= dur - const Duration(seconds: 2)) {
      try {
        await player.seek(Duration.zero);
      } catch (_) {}
    }

    StreamDiagnosticLogger.instance.log(
      'PLAYER_$deckLabel',
      '▶ สั่งเริ่มเล่นเสียง (JustAudio Play) บน Deck $deckLabel (${cand?.shortLabel ?? "Stream"}, ระดับเสียง $volPct%)',
      level: 'INFO',
      deck: deckLabel,
    );

    for (int attempt = 1; attempt <= 6; attempt++) {
      if (_disposed) return false;
      final stillWantPlay = isDeckA ? _wantPlayingA : _wantPlayingB;
      if (!stillWantPlay) return false;

      await _applyCrossfaderVolumes();

      if (!player.playing) {
        unawaited(
          player.play().catchError((Object e, StackTrace st) {
            cand?.lastPlaybackError = e.toString();
            StreamDiagnosticLogger.instance.log(
              'PLAYER_$deckLabel',
              'คำสั่ง play() ล้มเหลวบน Deck $deckLabel: $e',
              level: 'ERROR',
              details: st.toString(),
              deck: deckLabel,
            );
          }),
        );
      }

      // Wait 350ms to verify whether Buffering/Opening reset `player.playing` back to false!
      await Future.delayed(const Duration(milliseconds: 350));
      notifyListeners();

      // Only accept playback as truly running if `player.playing` is STILL true after 350ms
      // and processingState is ready (not stuck buffering at 0ms)
      if (player.playing &&
          player.processingState == ProcessingState.ready &&
          player.position.inMilliseconds > 250) {
        // Double-check 250ms later that it didn't immediately drop into Buffering/Paused
        await Future.delayed(const Duration(milliseconds: 250));
        if (player.playing && player.position.inMilliseconds > 400) {
          StreamDiagnosticLogger.instance.log(
            'PLAYER_$deckLabel',
            '🔊 Deck $deckLabel กำลังเล่นเสียงออกลำโพงแล้ว! (ตำแหน่ง: ${player.position.inMilliseconds}ms, เสียง: ${(player.volume * 100).round()}%)',
            level: 'SUCCESS',
            deck: deckLabel,
          );
          return true;
        }
      }
    }

    StreamDiagnosticLogger.instance.log(
      'PLAYER_$deckLabel',
      '⚠️ JustAudio บน Deck $deckLabel สั่ง play() แล้วแต่สถานะหยุดหรือค้าง (Playing=${player.playing}, State=${player.processingState.name}, Pos=${player.position.inMilliseconds}ms)',
      level: 'WARN',
      deck: deckLabel,
    );
    return player.playing;
  }

  // Pre-load track into the standby deck
  Future<void> preloadStandbyTrack(Track track) async {
    try {
      final playA = isDeckPlaying(ActiveDeck.deckA);
      final playB = isDeckPlaying(ActiveDeck.deckB);
      final ActiveDeck targetDeck;
      if (playA && !playB) {
        targetDeck = ActiveDeck.deckB;
      } else if (playB && !playA) {
        targetDeck = ActiveDeck.deckA;
      } else if (trackA != null && trackB == null) {
        targetDeck = ActiveDeck.deckB;
      } else if (trackB != null && trackA == null) {
        targetDeck = ActiveDeck.deckA;
      } else {
        targetDeck = (crossfadePosition <= 0.5) ? ActiveDeck.deckB : ActiveDeck.deckA;
      }

      // Do not overwrite a deck that is currently playing!
      if (isDeckPlaying(targetDeck)) return;

      final isTargetA = targetDeck == ActiveDeck.deckA;
      final myToken = isTargetA ? (++_loadTokenA) : (++_loadTokenB);
      if (isTargetA) {
        trackA = track;
        _wantPlayingA = false;
        _mountedVideoIdA = null;
      } else {
        trackB = track;
        _wantPlayingB = false;
        _mountedVideoIdB = null;
      }
      notifyListeners();

      String? streamUrl = track.streamUrl;
      if (streamUrl == null || streamUrl.isEmpty || LocalAudioProxy.getCandidatesFor(track.videoId).isEmpty) {
        track.isResolving = true;
        notifyListeners();
        final resolved = await ApiService.resolveStream(track.videoId);
        track.isResolving = false;
        if ((isTargetA ? _loadTokenA : _loadTokenB) != myToken) return;
        if (resolved != null && resolved.streamUrl != null && resolved.streamUrl!.isNotEmpty) {
          streamUrl = resolved.streamUrl;
          track.streamUrl = streamUrl;
          track = track.copyWith(
            title: resolved.title.isNotEmpty ? resolved.title : track.title,
            artist: resolved.artist.isNotEmpty ? resolved.artist : track.artist,
            durationSeconds: resolved.durationSeconds > 0 ? resolved.durationSeconds : track.durationSeconds,
            thumbnailUrl: resolved.thumbnailUrl ?? track.thumbnailUrl,
            streamUrl: streamUrl,
            videoStreamUrl: resolved.videoStreamUrl ?? track.videoStreamUrl,
          );
          if (targetDeck == ActiveDeck.deckA && trackA?.videoId == track.videoId) {
            trackA = track;
          } else if (targetDeck == ActiveDeck.deckB && trackB?.videoId == track.videoId) {
            trackB = track;
          }
        }
        notifyListeners();
      }

      if (!ApiService.isTestMode && streamUrl != null && streamUrl.isNotEmpty) {
        final otherDeck = (targetDeck == ActiveDeck.deckA) ? ActiveDeck.deckB : ActiveDeck.deckA;
        if (!isDeckPlaying(otherDeck)) {
          await Future.delayed(const Duration(milliseconds: 800));
        }
        if ((isTargetA ? _loadTokenA : _loadTokenB) != myToken) return;
        // Ensure user hasn't loaded a different track onto targetDeck while resolving
        final currentOnTarget = targetDeck == ActiveDeck.deckA ? trackA : trackB;
        if (currentOnTarget?.videoId != track.videoId || isDeckPlaying(targetDeck)) return;

        final cand = LocalAudioProxy.getSelectedCandidate(track.videoId);
        if (cand != null && !(cand.id == 'backend_8000' && cand.status == 'failed')) {
          try {
            final mounted = await _mountCandidateOnDeck(targetDeck, track, cand, expectedToken: myToken);
            if (mounted && (isTargetA ? _loadTokenA : _loadTokenB) == myToken) {
              await _pauseDeckInternal(targetDeck);
            }
          } catch (_) {}
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error preloading standby track: $e");
    }
  }

  // Load track into deck: ONLY auto-play if that target deck is ALREADY playing
  // (unless `autoPlay` is explicitly specified). If the target deck is stopped, only select/cue it!
  Future<void> loadTrackToDeck(ActiveDeck deck, Track track, {bool? autoPlay}) {
    final isDeckA = deck == ActiveDeck.deckA;
    final wasPlaying = isDeckPlaying(deck) || (isDeckA ? _wantPlayingA : _wantPlayingB);
    final shouldPlay = autoPlay ?? wasPlaying;
    return loadAndPlayTrack(deck, track, autoPlay: shouldPlay);
  }

  /// Allows the user to manually click and switch between candidate URLs for the track on [deck]
  Future<void> switchStreamCandidate(ActiveDeck deck, int candidateIndex, {bool autoPlay = true}) async {
    final isDeckA = (deck == ActiveDeck.deckA);
    final deckLabel = isDeckA ? 'A' : 'B';
    final track = isDeckA ? trackA : trackB;
    if (track == null) return;

    final myToken = isDeckA ? (++_loadTokenA) : (++_loadTokenB);
    if (isDeckA) {
      _wantPlayingA = false;
    } else {
      _wantPlayingB = false;
    }

    StreamDiagnosticLogger.instance.clearDeckError(deckLabel);
    LocalAudioProxy.selectCandidate(track.videoId, candidateIndex);
    final cand = LocalAudioProxy.getSelectedCandidate(track.videoId);
    if (cand == null) return;

    await _pauseDeckInternal(deck);
    if ((isDeckA ? _loadTokenA : _loadTokenB) != myToken) return;

    final newUrl = cand.playbackUrl;
    track.streamUrl = newUrl;
    track.videoStreamUrl = newUrl;
    notifyListeners();

    StreamDiagnosticLogger.instance.log(
      'PLAYER_$deckLabel',
      'กำลังสลับ Deck $deckLabel ไปใช้ ${cand.shortLabel}...',
      level: 'INFO',
      details: 'URL: $newUrl',
      deck: deckLabel,
    );

    try {
      final mounted = await _mountCandidateOnDeck(deck, track, cand, expectedToken: myToken);
      if ((isDeckA ? _loadTokenA : _loadTokenB) != myToken) return;
      if (!mounted) {
        notifyListeners();
        return;
      }
    } catch (e, st) {
      cand.lastPlaybackError = e.toString();
      cand.status = 'failed';
      cand.statusDetail = '❌ เปิดเล่นไม่สำเร็จ: $e';
      StreamDiagnosticLogger.instance.log(
        'PLAYER_$deckLabel',
        'เปิดเพลงด้วย ${cand.shortLabel} ไม่สำเร็จ: $e',
        level: 'ERROR',
        details: 'URL: $newUrl\nStack: $st',
        deck: deckLabel,
      );
      notifyListeners();
      return;
    }

    if (autoPlay && (isDeckA ? _loadTokenA : _loadTokenB) == myToken) {
      await _forcePlayDeck(deck, adjustCrossfaderIfMuted: true);
    }
    notifyListeners();
  }

  // Load (and optionally play) track on specific deck with automatic multi-URL/multi-engine fallback
  Future<void> loadAndPlayTrack(ActiveDeck deck, Track track, {bool autoPlay = false}) async {
    final isDeckA = (deck == ActiveDeck.deckA);
    final deckLabel = isDeckA ? 'A' : 'B';
    if (autoPlay && !checkActiveSubscriptionOrPause()) {
      autoPlay = false;
    }
    final myToken = isDeckA ? (++_loadTokenA) : (++_loadTokenB);
    try {
      if (isDeckA) {
        _wantPlayingA = false;
      } else {
        _wantPlayingB = false;
      }
      StreamDiagnosticLogger.instance.clearDeckError(deckLabel);

      // 1. Assign track to deck immediately and synchronously so UI updates instantly
      if (isDeckA) {
        if (_mountedVideoIdA != track.videoId) {
          _mountedVideoIdA = null;
          _maxPositionReachedA = Duration.zero;
        }
        trackA = track;
      } else {
        if (_mountedVideoIdB != track.videoId) {
          _mountedVideoIdB = null;
          _maxPositionReachedB = Duration.zero;
        }
        trackB = track;
      }
      notifyListeners();

      // 2. Immediately pause current playback on this deck
      await _pauseDeckInternal(deck);
      if ((isDeckA ? _loadTokenA : _loadTokenB) != myToken) return;

      // 3. Resolve stream URL if not already present (or if only backend_8000 is cached)
      String? streamUrl = track.streamUrl;
      final existingCands = LocalAudioProxy.getCandidatesFor(track.videoId);
      final hasRealCands = existingCands.any((c) => c.id != 'backend_8000');
      if (streamUrl == null || streamUrl.isEmpty || !hasRealCands) {
        track.isResolving = true;
        notifyListeners();

        try {
          final resolved = await ApiService.resolveStream(track.videoId);
          if ((isDeckA ? _loadTokenA : _loadTokenB) != myToken) return;
          if (resolved != null && resolved.streamUrl != null && resolved.streamUrl!.isNotEmpty) {
            streamUrl = resolved.streamUrl;
            track.streamUrl = streamUrl;
            track = track.copyWith(
              title: resolved.title.isNotEmpty ? resolved.title : track.title,
              artist: resolved.artist.isNotEmpty ? resolved.artist : track.artist,
              durationSeconds: resolved.durationSeconds > 0 ? resolved.durationSeconds : track.durationSeconds,
              thumbnailUrl: resolved.thumbnailUrl ?? track.thumbnailUrl,
              streamUrl: streamUrl,
              videoStreamUrl: resolved.videoStreamUrl ?? track.videoStreamUrl,
            );
          }
        } catch (e, st) {
          StreamDiagnosticLogger.instance.log(
            'RESOLVE',
            'ไม่สามารถดึง URL สำหรับ "${track.title}" (${track.videoId}): $e',
            level: 'ERROR',
            details: st.toString(),
            deck: deckLabel,
          );
        } finally {
          track.isResolving = false;
        }

        if ((isDeckA ? _loadTokenA : _loadTokenB) != myToken) return;
        if (isDeckA) {
          trackA = track;
        } else {
          trackB = track;
        }
        notifyListeners();
      }

      if (ApiService.isTestMode) {
        if (streamUrl != null && streamUrl.isNotEmpty) {
          final player = isDeckA ? deckA : deckB;
          try {
            await player.setUrl(streamUrl);
          } catch (_) {}
          if (autoPlay) {
            await _forcePlayDeck(deck, adjustCrossfaderIfMuted: true);
          }
        }
        notifyListeners();
        return;
      }

      // 4. Try candidates in priority order (#1 LocalFile+MediaEngine -> #2 LocalFile+JustAudio -> #3 RAMProxy+MediaEngine...)
      final candidates = LocalAudioProxy.getCandidatesFor(track.videoId);
      if (candidates.isNotEmpty) {
        final startIdx = LocalAudioProxy.getSelectedIndex(track.videoId);
        final orderedIndices = <int>[
          startIdx,
          for (int i = 0; i < candidates.length; i++)
            if (i != startIdx) i,
        ];

        for (final idx in orderedIndices.take(4)) {
          if ((isDeckA ? _loadTokenA : _loadTokenB) != myToken) return;
          final cand = candidates[idx];
          // Skip offline Python backend (:8000) during automatic fallback so we don't waste 15s timing out
          if (cand.id == 'backend_8000' && cand.status == 'failed') {
            continue;
          }

          LocalAudioProxy.selectCandidate(track.videoId, idx);
          track.streamUrl = cand.playbackUrl;
          track.videoStreamUrl = cand.playbackUrl;
          notifyListeners();

          StreamDiagnosticLogger.instance.log(
            'PLAYER_$deckLabel',
            'กำลังโหลดเพลง "${track.title}" เข้า Deck $deckLabel ด้วย ${cand.shortLabel}',
            level: 'INFO',
            details: 'URL: ${cand.playbackUrl}',
            deck: deckLabel,
          );

          try {
            final mounted = await _mountCandidateOnDeck(deck, track, cand, expectedToken: myToken);
            if ((isDeckA ? _loadTokenA : _loadTokenB) != myToken) return;
            if (!mounted) continue;

            if (autoPlay) {
              final playingOk = await _forcePlayDeck(deck, adjustCrossfaderIfMuted: true);
              if ((isDeckA ? _loadTokenA : _loadTokenB) != myToken) return;
              if (playingOk) {
                StreamDiagnosticLogger.instance.clearDeckError(deckLabel);
                notifyListeners();
                return;
              } else {
                StreamDiagnosticLogger.instance.log(
                  'PLAYER_$deckLabel',
                  '⚠️ ${cand.shortLabel} ไม่เริ่มเดินเวลา จึงสลับไปลอง URL ถัดไปให้อัตโนมัติ...',
                  level: 'WARN',
                  deck: deckLabel,
                );
              }
            } else {
              await _pauseDeckInternal(deck);
              await _applyCrossfaderVolumes();
              notifyListeners();
              return;
            }
          } catch (e, st) {
            if ((isDeckA ? _loadTokenA : _loadTokenB) != myToken) return;
            cand.lastPlaybackError = e.toString();
            cand.status = 'failed';
            cand.statusDetail = '❌ โหลดไม่สำเร็จ: $e';
            StreamDiagnosticLogger.instance.log(
              'PLAYER_$deckLabel',
              'โหลด ${cand.shortLabel} ไม่สำเร็จบน Deck $deckLabel: $e (กำลังลองตัวเลือกถัดไป...)',
              level: 'WARN',
              details: st.toString(),
              deck: deckLabel,
            );
          }
        }
      } else if (streamUrl != null && streamUrl.isNotEmpty) {
        final player = isDeckA ? deckA : deckB;
        await player.setUrl(streamUrl);
        if (autoPlay) {
          await _forcePlayDeck(deck, adjustCrossfaderIfMuted: true);
        }
        notifyListeners();
      } else {
        StreamDiagnosticLogger.instance.log(
          'PLAYER_$deckLabel',
          'ไม่พบ Stream URL ที่ใช้งานได้สำหรับเพลง "${track.title}" (${track.videoId})',
          level: 'ERROR',
          deck: deckLabel,
        );
        notifyListeners();
      }
    } catch (e, stack) {
      StreamDiagnosticLogger.instance.log(
        'PLAYER_$deckLabel',
        'เกิดข้อผิดพลาดร้ายแรงขณะโหลดเพลงลง Deck $deckLabel: $e',
        level: 'ERROR',
        details: stack.toString(),
        deck: deckLabel,
      );
    }
  }


  // Smooth Crossfade Skip (Equal-Power Curve)
  Future<void> executeSmoothSkip({int? durationSeconds}) async {
    final duration = durationSeconds ?? transitionDurationSeconds;
    if (isTransitioning) return;

    // Immediately lock transition to prevent concurrent triggers from Auto-DJ or rapid clicks
    isTransitioning = true;
    notifyListeners();

    // Safety watchdog timer: guarantees isTransitioning is restored even if audio halts
    final watchdogTimer = Timer(Duration(seconds: duration + 20), () {
      if (isTransitioning) {
        debugPrint("[SMOOTH_SKIP] Watchdog triggered: Forcing isTransitioning = false.");
        isTransitioning = false;
        notifyListeners();
      }
    });

    try {
      final playA = isDeckPlaying(ActiveDeck.deckA);
      final playB = isDeckPlaying(ActiveDeck.deckB);
      final bool movingToDeckB;
      if (playA && !playB) {
        movingToDeckB = true;
      } else if (playB && !playA) {
        movingToDeckB = false;
      } else {
        movingToDeckB = crossfadePosition <= 0.5;
      }

      final outgoingDeck = movingToDeckB ? ActiveDeck.deckA : ActiveDeck.deckB;
      final targetDeck = movingToDeckB ? ActiveDeck.deckB : ActiveDeck.deckA;
      final outgoingTrack = movingToDeckB ? trackA : trackB;
      var targetTrack = movingToDeckB ? trackB : trackA;

      // 1. If Auto-DJ is currently fetching recommendations in the background, wait up to 4 seconds
      if (targetTrack == null && _isFetchingAutoQueue) {
        int waitFetch = 0;
        while (_isFetchingAutoQueue && waitFetch < 40) {
          await Future.delayed(const Duration(milliseconds: 100));
          waitFetch++;
        }
        targetTrack = movingToDeckB ? trackB : trackA;
      }

      // 2. If target deck is still empty, pull from user queue
      if (targetTrack == null && queue.isNotEmpty) {
        final nextTrack = queue.removeAt(0);
        AuthService.instance.syncQueue(queue);
        targetTrack = nextTrack;
        if (movingToDeckB) {
          trackB = targetTrack;
        } else {
          trackA = targetTrack;
        }
        notifyListeners();
      }

      // 3. If target deck is STILL empty and Auto-DJ (autoQueueEnabled) is ON, fetch related tracks right now!
      if (targetTrack == null && autoQueueEnabled) {
        final seed = outgoingTrack ?? activeTrack ?? trackA ?? trackB;
        if (seed != null && seed.videoId.isNotEmpty) {
          _isFetchingAutoQueue = true;
          try {
            debugPrint('[SMOOTH_SKIP] Standby & Queue empty. Fetching Auto-DJ related tracks for: ${seed.title}');
            final suggestions = await ApiService.getRelatedTracks(
              seed.videoId,
              source: seed.source,
              title: seed.title,
            );
            if (suggestions.isNotEmpty) {
              final currentIds = {trackA?.videoId, trackB?.videoId}.whereType<String>().toSet();
              final candidate = suggestions.firstWhere(
                (t) => !currentIds.contains(t.videoId),
                orElse: () => suggestions.first,
              );
              final more = suggestions
                  .where((t) => t.videoId != candidate.videoId && !currentIds.contains(t.videoId))
                  .take(6)
                  .toList();
              if (more.isNotEmpty) {
                queue.addAll(more);
                AuthService.instance.syncQueue(queue);
              }
              targetTrack = candidate;
              if (movingToDeckB) {
                trackB = targetTrack;
              } else {
                trackA = targetTrack;
              }
              notifyListeners();
            }
          } catch (e) {
            debugPrint('[SMOOTH_SKIP] Auto-DJ fetch error: $e');
          } finally {
            _isFetchingAutoQueue = false;
          }
        }
      }

      if (targetTrack == null) {
        debugPrint("[SMOOTH_SKIP] Standby deck ${movingToDeckB ? 'B' : 'A'} has no track to crossfade to.");
        return;
      }

      // 4. If target track is currently resolving, wait with timeout
      if (targetTrack.isResolving) {
        int waitCount = 0;
        while (targetTrack.isResolving && waitCount < 45) {
          await Future.delayed(const Duration(milliseconds: 100));
          waitCount++;
        }
        targetTrack = (movingToDeckB ? trackB : trackA) ?? targetTrack;
      }

      // 5. Ensure target track is resolved, cached, and mounted on targetDeck at 0:00
      if (!ApiService.isTestMode) {
        final mountedId = movingToDeckB ? _mountedVideoIdB : _mountedVideoIdA;
        if (mountedId != targetTrack.videoId) {
          await loadAndPlayTrack(targetDeck, targetTrack, autoPlay: false);
          targetTrack = (movingToDeckB ? trackB : trackA) ?? targetTrack;
        }
        await seek(targetDeck, Duration.zero);
      } else {
        final targetPlayer = movingToDeckB ? deckB : deckA;
        if (targetTrack.streamUrl == null || targetTrack.streamUrl!.isEmpty) {
          await loadAndPlayTrack(targetDeck, targetTrack, autoPlay: false);
        } else {
          try {
            await targetPlayer.setUrl(targetTrack.streamUrl!);
          } catch (_) {}
        }
      }

      if (movingToDeckB) {
        _wantPlayingB = true;
      } else {
        _wantPlayingA = true;
      }

      // 6. Start incoming deck playing before crossfading in!
      final nowUseVideo = movingToDeckB ? useVideoEngineB : useVideoEngineA;
      final nowVc = movingToDeckB ? videoControllerB : videoControllerA;
      final targetPlayer = movingToDeckB ? deckB : deckA;
      if (nowUseVideo && nowVc != null && nowVc.value.isInitialized) {
        await nowVc.setVolume(0.0);
        unawaited(nowVc.play().catchError((e) => debugPrint("[SMOOTH_SKIP] vc.play error: $e")));
      } else {
        await targetPlayer.setVolume(0.0);
        unawaited(targetPlayer.play().catchError((e) => debugPrint("[SMOOTH_SKIP] incoming.play error: $e")));
      }

      final int steps = lowSpecMode ? 16 : 36;
      final int stepDurationMs = (duration * 1000) ~/ steps;
      final double startCrossfade = crossfadePosition;
      final double targetCrossfade = movingToDeckB ? 1.0 : 0.0;

      for (int i = 1; i <= steps; i++) {
        final double fraction = i / steps; // 0.0 -> 1.0
        crossfadePosition = (startCrossfade + (targetCrossfade - startCrossfade) * fraction).clamp(0.0, 1.0);

        _applyCrossfaderVolumesFast();
        notifyListeners();

        await Future.delayed(Duration(milliseconds: stepDurationMs));
      }

      // Finish crossfade at exact target position
      crossfadePosition = targetCrossfade;
      isDeckAPlaying = !movingToDeckB;
      await _applyCrossfaderVolumes();

      // Verify incoming deck is actively playing with audible volume
      if (!ApiService.isTestMode && !isDeckPlaying(targetDeck)) {
        await _forcePlayDeck(targetDeck, adjustCrossfaderIfMuted: false);
      }

      // Pause outgoing player now that it is completely muted
      if (movingToDeckB) {
        _wantPlayingA = false;
      } else {
        _wantPlayingB = false;
      }
      await _pauseDeckInternal(outgoingDeck);

      // Clear the finished track from outgoing deck so it's ready for the next queue item
      if (movingToDeckB) {
        trackA = null;
        _mountedVideoIdA = null;
        _maxPositionReachedA = Duration.zero;
      } else {
        trackB = null;
        _mountedVideoIdB = null;
        _maxPositionReachedB = Duration.zero;
      }
      notifyListeners();
    } catch (e, stack) {
      debugPrint("[SMOOTH_SKIP] Error during smooth skip: $e\n$stack");
    } finally {
      watchdogTimer.cancel();
      isTransitioning = false;
      notifyListeners();
    }

    // Immediately load next track from queue or Auto-DJ into the now-empty standby deck!
    unawaited(_checkAndPreloadNextQueueItem());
  }


  /// Automatically ensures standby deck has a track ready:
  /// 1. Takes from user queue if available.
  /// 2. If queue is empty and autoQueueEnabled is true, fetches related/recommended tracks automatically!
  Future<void> _checkAndPreloadNextQueueItem() async {
    // If standby deck already has a track (e.g. user manually loaded one), do NOT overwrite it!
    if (standbyTrack != null) {
      return;
    }

    if (queue.isNotEmpty) {
      final next = queue.removeAt(0);
      AuthService.instance.syncQueue(queue);
      await preloadStandbyTrack(next);
      return;
    }

    // If queue is empty and autoQueueEnabled is on, auto-generate next track!
    if (autoQueueEnabled && !_isFetchingAutoQueue) {
      final playingTrack = activeTrack;
      if (playingTrack == null || playingTrack.videoId.isEmpty) return;

      _isFetchingAutoQueue = true;
      try {
        debugPrint('[AUTO-DJ] Queue is empty. Auto-fetching related tracks for: ${playingTrack.title}');
        final suggestions = await ApiService.getRelatedTracks(
          playingTrack.videoId,
          source: playingTrack.source,
          title: playingTrack.title,
        );

        if (suggestions.isNotEmpty) {
          // Avoid immediately repeating current tracks
          final currentIds = {trackA?.videoId, trackB?.videoId}.whereType<String>().toSet();
          final candidate = suggestions.firstWhere(
            (t) => !currentIds.contains(t.videoId),
            orElse: () => suggestions.first,
          );

          // Add remainder of recommendations to queue for future uninterrupted mixes
          final more = suggestions
              .where((t) => t.videoId != candidate.videoId && !currentIds.contains(t.videoId))
              .take(6)
              .toList();
          if (more.isNotEmpty) {
            queue.addAll(more);
            AuthService.instance.syncQueue(queue);
          }

          // Preload candidate to standby deck
          await preloadStandbyTrack(candidate);
        }
      } catch (e) {
        debugPrint('[AUTO-DJ] Error auto-fetching next track: $e');
      } finally {
        _isFetchingAutoQueue = false;
      }
    }
  }


  // Tempo & Key-Locked Pitch adjustment for active or specific deck
  Future<void> setPlaybackSpeed(double speed, {ActiveDeck? deck, bool? preservePitch}) async {
    final useKeyLock = preservePitch ?? keyLockEnabled;
    final targetDeck = deck ?? (isDeckAPlaying ? ActiveDeck.deckA : ActiveDeck.deckB);
    final isA = targetDeck == ActiveDeck.deckA;
    final player = isA ? deckA : deckB;
    final vc = isA ? videoControllerA : videoControllerB;

    if (isA) {
      speedDeckA = speed;
    } else {
      speedDeckB = speed;
    }

    if ((isA ? useVideoEngineA : useVideoEngineB) && vc != null && vc.value.isInitialized) {
      try {
        await vc.setPlaybackSpeed(speed.clamp(0.5, 2.0));
      } catch (_) {}
    } else {
      try {
        await player.setPitch(useKeyLock ? 1.0 : speed);
        await player.setSpeed(speed);
      } catch (_) {}
    }
    notifyListeners();
  }

  double _getDeckVolumeMultiplier(ActiveDeck deck) {
    final isA = deck == ActiveDeck.deckA;
    double low = isA ? eqLowA : eqLowB;
    double mid = isA ? eqMidA : eqMidB;
    double high = isA ? eqHighA : eqHighB;
    final isBassKilled = isA ? isBassKilledA : isBassKilledB;
    final isMidKilled = isA ? isMidKilledA : isMidKilledB;
    final isHighKilled = isA ? isHighKilledA : isHighKilledB;
    final filter = isA ? filterA : filterB;

    if (isBassKilled) low = 0.0;
    if (isMidKilled) mid = 0.0;
    if (isHighKilled) high = 0.0;

    // Normalize so default flat EQ (1.0, 1.0, 1.0) equals exactly 1.0 (100%)
    double mult = (low * 0.40 + mid * 0.35 + high * 0.25);
    if (filter != 0.0) {
      mult *= (1.0 - filter.abs() * 0.25);
    }
    return mult.clamp(0.0, 1.5);
  }

  Future<void> _loadMasterVolumeFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble('dj_master_volume');
      if (saved != null) {
        masterVolume = saved.clamp(0.0, 1.0);
        _prevMasterVolume = masterVolume > 0 ? masterVolume : 1.0;
        _applyCrossfaderVolumesFast();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _saveMasterVolumeToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('dj_master_volume', masterVolume);
    } catch (_) {}
  }

  Future<void> setMasterVolume(double volume) async {
    masterVolume = volume.clamp(0.0, 1.0);
    if (masterVolume > 0) {
      _prevMasterVolume = masterVolume;
    }
    await _applyCrossfaderVolumes();
    notifyListeners();
    _saveMasterVolumeToPrefs();
  }

  void toggleMuteMaster() {
    if (masterVolume > 0.0) {
      _prevMasterVolume = masterVolume;
      setMasterVolume(0.0);
    } else {
      setMasterVolume(_prevMasterVolume > 0.0 ? _prevMasterVolume : 1.0);
    }
  }

  Future<void> setDeckGain(ActiveDeck deck, double gain) async {
    if (deck == ActiveDeck.deckA) {
      volumeGainA = gain.clamp(0.0, 1.0);
    } else {
      volumeGainB = gain.clamp(0.0, 1.0);
    }
    await _applyCrossfaderVolumes();
    notifyListeners();
  }

  Future<void> _applyCrossfaderVolumes() async {
    final double baseA = math.cos(crossfadePosition * (math.pi / 2)) * volumeGainA * _getDeckVolumeMultiplier(ActiveDeck.deckA);
    final double baseB = math.sin(crossfadePosition * (math.pi / 2)) * volumeGainB * _getDeckVolumeMultiplier(ActiveDeck.deckB);
    final double volA = (baseA * masterVolume).clamp(0.0, 1.0);
    final double volB = (baseB * masterVolume).clamp(0.0, 1.0);
    _lastAppliedVolA = volA;
    _lastAppliedVolB = volB;

    if (useVideoEngineA && videoControllerA != null && videoControllerA!.value.isInitialized) {
      try {
        await videoControllerA!.setVolume(volA);
      } catch (_) {}
    } else {
      try {
        await deckA.setVolume(volA);
      } catch (_) {}
    }

    if (useVideoEngineB && videoControllerB != null && videoControllerB!.value.isInitialized) {
      try {
        await videoControllerB!.setVolume(volB);
      } catch (_) {}
    } else {
      try {
        await deckB.setVolume(volB);
      } catch (_) {}
    }
  }

  void _applyCrossfaderVolumesFast() {
    final double baseA = math.cos(crossfadePosition * (math.pi / 2)) * volumeGainA * _getDeckVolumeMultiplier(ActiveDeck.deckA);
    final double baseB = math.sin(crossfadePosition * (math.pi / 2)) * volumeGainB * _getDeckVolumeMultiplier(ActiveDeck.deckB);
    final double volA = (baseA * masterVolume).clamp(0.0, 1.0);
    final double volB = (baseB * masterVolume).clamp(0.0, 1.0);
    _lastAppliedVolA = volA;
    _lastAppliedVolB = volB;

    if (useVideoEngineA && videoControllerA != null && videoControllerA!.value.isInitialized) {
      try {
        videoControllerA!.setVolume(volA);
      } catch (_) {}
    } else {
      try {
        deckA.setVolume(volA);
      } catch (_) {}
    }

    if (useVideoEngineB && videoControllerB != null && videoControllerB!.value.isInitialized) {
      try {
        videoControllerB!.setVolume(volB);
      } catch (_) {}
    } else {
      try {
        deckB.setVolume(volB);
      } catch (_) {}
    }
  }

  // --- Hot Cues (1..4) ---
  void setOrJumpHotCue(ActiveDeck deck, int index) {
    final map = (deck == ActiveDeck.deckA) ? hotCuesA : hotCuesB;
    if (map.containsKey(index)) {
      seek(deck, map[index]!);
      if (!isDeckPlaying(deck)) {
        unawaited(_forcePlayDeck(deck, adjustCrossfaderIfMuted: false));
      }
    } else {
      map[index] = getDeckPosition(deck);
      notifyListeners();
    }
  }

  void clearHotCue(ActiveDeck deck, int index) {
    final map = (deck == ActiveDeck.deckA) ? hotCuesA : hotCuesB;
    map.remove(index);
    notifyListeners();
  }

  // --- Auto Beat Looping ---
  Duration _getLoopDuration(double beats, double bpm) {
    final double seconds = (60.0 / bpm) * beats;
    return Duration(milliseconds: (seconds * 1000).toInt());
  }

  void _checkLoop(ActiveDeck deck, Duration pos) {
    final isA = deck == ActiveDeck.deckA;
    final isLooping = isA ? isLoopingA : isLoopingB;
    final start = isA ? loopStartA : loopStartB;
    final beats = isA ? loopBeatsA : loopBeatsB;
    final bpm = isA ? bpmDeckA : bpmDeckB;

    if (isLooping && start != null) {
      final loopDuration = _getLoopDuration(beats, bpm);
      if (pos >= start + loopDuration || pos < start) {
        seek(deck, start);
      }
    }
  }

  void toggleLoop(ActiveDeck deck, double beats) {
    final isDeckA = deck == ActiveDeck.deckA;
    final currentLooping = isDeckA ? isLoopingA : isLoopingB;
    final currentBeats = isDeckA ? loopBeatsA : loopBeatsB;

    if (currentLooping && currentBeats == beats) {
      exitLoop(deck);
      return;
    }

    if (isDeckA) {
      isLoopingA = true;
      loopBeatsA = beats;
      loopStartA = getDeckPosition(ActiveDeck.deckA);
    } else {
      isLoopingB = true;
      loopBeatsB = beats;
      loopStartB = getDeckPosition(ActiveDeck.deckB);
    }
    notifyListeners();
  }

  void exitLoop(ActiveDeck deck) {
    if (deck == ActiveDeck.deckA) {
      isLoopingA = false;
      loopStartA = null;
    } else {
      isLoopingB = false;
      loopStartB = null;
    }
    notifyListeners();
  }

  // --- 3-Band EQ & Filter ---
  void toggleKillBass(ActiveDeck deck) {
    if (deck == ActiveDeck.deckA) {
      isBassKilledA = !isBassKilledA;
    } else {
      isBassKilledB = !isBassKilledB;
    }
    _applyCrossfaderVolumesFast();
    notifyListeners();
  }

  void toggleKillMid(ActiveDeck deck) {
    if (deck == ActiveDeck.deckA) {
      isMidKilledA = !isMidKilledA;
    } else {
      isMidKilledB = !isMidKilledB;
    }
    _applyCrossfaderVolumesFast();
    notifyListeners();
  }

  void toggleKillHigh(ActiveDeck deck) {
    if (deck == ActiveDeck.deckA) {
      isHighKilledA = !isHighKilledA;
    } else {
      isHighKilledB = !isHighKilledB;
    }
    _applyCrossfaderVolumesFast();
    notifyListeners();
  }

  void setEQ(ActiveDeck deck, {double? low, double? mid, double? high}) {
    if (deck == ActiveDeck.deckA) {
      if (low != null) eqLowA = low;
      if (mid != null) eqMidA = mid;
      if (high != null) eqHighA = high;
    } else {
      if (low != null) eqLowB = low;
      if (mid != null) eqMidB = mid;
      if (high != null) eqHighB = high;
    }
    _applyCrossfaderVolumesFast();
    notifyListeners();
  }

  void setFilter(ActiveDeck deck, double filterVal) {
    if (deck == ActiveDeck.deckA) {
      filterA = filterVal.clamp(-1.0, 1.0);
    } else {
      filterB = filterVal.clamp(-1.0, 1.0);
    }
    _applyCrossfaderVolumesFast();
    notifyListeners();
  }

  void resetEQ(ActiveDeck deck) {
    if (deck == ActiveDeck.deckA) {
      eqLowA = 1.0;
      eqMidA = 1.0;
      eqHighA = 1.0;
      filterA = 0.0;
      isBassKilledA = false;
      isMidKilledA = false;
      isHighKilledA = false;
    } else {
      eqLowB = 1.0;
      eqMidB = 1.0;
      eqHighB = 1.0;
      filterB = 0.0;
      isBassKilledB = false;
      isMidKilledB = false;
      isHighKilledB = false;
    }
    _applyCrossfaderVolumesFast();
    notifyListeners();
  }

  // --- Turbo Boost Tempo (1.25x Dance Party Boost) ---
  void toggleTurboBoost(ActiveDeck deck) {
    final isA = deck == ActiveDeck.deckA;
    if (isA) {
      isTurboA = !isTurboA;
      final target = isTurboA ? 1.25 : 1.0;
      setPlaybackSpeed(target, deck: ActiveDeck.deckA);
    } else {
      isTurboB = !isTurboB;
      final target = isTurboB ? 1.25 : 1.0;
      setPlaybackSpeed(target, deck: ActiveDeck.deckB);
    }
    notifyListeners();
  }

  // --- BPM, Beat Sync & Tap Tempo ---
  void tapTempo(ActiveDeck deck) {
    final now = DateTime.now();
    final list = (deck == ActiveDeck.deckA) ? _tapTimesA : _tapTimesB;
    list.add(now);
    if (list.length > 5) list.removeAt(0);

    list.removeWhere((t) => now.difference(t).inMilliseconds > 2500);
    if (list.length >= 2) {
      double totalMs = 0;
      for (int i = 1; i < list.length; i++) {
        totalMs += list[i].difference(list[i - 1]).inMilliseconds;
      }
      final double avgMs = totalMs / (list.length - 1);
      if (avgMs > 0) {
        final double calculatedBpm = (60000.0 / avgMs).clamp(60.0, 190.0);
        if (deck == ActiveDeck.deckA) {
          bpmDeckA = double.parse(calculatedBpm.toStringAsFixed(1));
        } else {
          bpmDeckB = double.parse(calculatedBpm.toStringAsFixed(1));
        }
        notifyListeners();
      }
    }
  }

  void adjustBpm(ActiveDeck deck, double delta) {
    if (deck == ActiveDeck.deckA) {
      bpmDeckA = (bpmDeckA + delta).clamp(60.0, 200.0);
      setPlaybackSpeed(bpmDeckA / 128.0, deck: ActiveDeck.deckA);
    } else {
      bpmDeckB = (bpmDeckB + delta).clamp(60.0, 200.0);
      setPlaybackSpeed(bpmDeckB / 128.0, deck: ActiveDeck.deckB);
    }
    notifyListeners();
  }

  void syncDecks() {
    final isSourceA = isDeckAPlaying;
    final double sourceBpm = isSourceA ? bpmDeckA : bpmDeckB;
    final ActiveDeck targetDeck = isSourceA ? ActiveDeck.deckB : ActiveDeck.deckA;

    if (isSourceA) {
      bpmDeckB = sourceBpm;
    } else {
      bpmDeckA = sourceBpm;
    }
    final double speed = sourceBpm / 128.0;
    setPlaybackSpeed(speed, deck: targetDeck);

    // Align beat phase
    final beatMs = 60000.0 / sourceBpm;
    final currentPosMs = getDeckPosition(targetDeck).inMilliseconds;
    final targetBeatPos = (currentPosMs / beatMs).round() * beatMs;
    seek(targetDeck, Duration(milliseconds: targetBeatPos.toInt()));

    notifyListeners();
  }

  // --- DJ Sampler FX Player ---
  Future<void> playSample(String type) async {
    try {
      if (ApiService.isTestMode) return;
      await LocalAudioProxy.ensureStarted();
      final url = 'http://127.0.0.1:${LocalAudioProxy.port}/sampler/$type.wav';
      await samplerPlayer.stop();
      await samplerPlayer.setUrl(url);
      await samplerPlayer.seek(Duration.zero);
      await samplerPlayer.setVolume(masterVolume);
      unawaited(samplerPlayer.play().catchError((e) => debugPrint("[SAMPLER] Play error: $e")));
    } catch (e) {
      debugPrint("[SAMPLER] Error playing sample: $e");
    }
  }

  // --- Live Recording Tracking ---
  void toggleRecording() {
    isRecording = !isRecording;
    if (isRecording) {
      recordingDuration = Duration.zero;
      recordedTracklist.clear();
      if (activeTrack != null) {
        recordedTracklist.add('${activeTrack!.title} - ${activeTrack!.artist}');
      }
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!isRecording) {
          timer.cancel();
          return;
        }
        recordingDuration += const Duration(seconds: 1);
        notifyListeners();
      });
    } else {
      _recordingTimer?.cancel();
    }
    notifyListeners();
  }

  // Manual Crossfader Drag with Equal-Power curves
  Future<void> setManualCrossfader(double pos) async {
    crossfadePosition = pos.clamp(0.0, 1.0);
    // The deck on the louder side is treated as the active deck
    if (!isTransitioning) {
      isDeckAPlaying = crossfadePosition < 0.5;
    }
    notifyListeners();
    await _applyCrossfaderVolumes();
  }

  // Start both decks together (mix with the crossfader)
  Future<void> playBoth() async {
    if (isDeckPlaying(ActiveDeck.deckA) && isDeckPlaying(ActiveDeck.deckB)) {
      _wantPlayingA = false;
      _wantPlayingB = false;
      await Future.wait([
        _pauseDeckInternal(ActiveDeck.deckA),
        _pauseDeckInternal(ActiveDeck.deckB),
      ]);
      notifyListeners();
      return;
    }

    if (crossfadePosition <= 0.15 || crossfadePosition >= 0.85) {
      crossfadePosition = 0.5;
    }

    if (trackA != null) {
      if (trackA!.streamUrl == null || trackA!.streamUrl!.isEmpty) {
        unawaited(loadTrackToDeck(ActiveDeck.deckA, trackA!, autoPlay: true));
      } else {
        unawaited(_forcePlayDeck(ActiveDeck.deckA, adjustCrossfaderIfMuted: false));
      }
    }
    if (trackB != null) {
      if (trackB!.streamUrl == null || trackB!.streamUrl!.isEmpty) {
        unawaited(loadTrackToDeck(ActiveDeck.deckB, trackB!, autoPlay: true));
      } else {
        unawaited(_forcePlayDeck(ActiveDeck.deckB, adjustCrossfaderIfMuted: false));
      }
    }
    notifyListeners();
  }

  // Master Play / Pause
  Future<void> toggleMasterPlay() async {
    if (isDeckPlaying(ActiveDeck.deckA) || isDeckPlaying(ActiveDeck.deckB)) {
      _wantPlayingA = false;
      _wantPlayingB = false;
      await Future.wait([
        _pauseDeckInternal(ActiveDeck.deckA),
        _pauseDeckInternal(ActiveDeck.deckB),
      ]);
      notifyListeners();
    } else {
      final targetDeck = isDeckAPlaying
          ? (trackA != null ? ActiveDeck.deckA : ActiveDeck.deckB)
          : (trackB != null ? ActiveDeck.deckB : ActiveDeck.deckA);
      await toggleDeckPlay(targetDeck);
    }
  }

  bool checkActiveSubscriptionOrPause() {
    final auth = AuthService.instance;
    if (!auth.isLoggedIn || !auth.hasActiveSubscription) {
      pauseAllDecks();
      return false;
    }
    return true;
  }

  Future<void> pauseAllDecks() async {
    _wantPlayingA = false;
    _wantPlayingB = false;
    await _pauseDeckInternal(ActiveDeck.deckA);
    await _pauseDeckInternal(ActiveDeck.deckB);
    notifyListeners();
  }

  Future<void> toggleDeckPlay(ActiveDeck deck) async {
    final isDeckA = (deck == ActiveDeck.deckA);
    final deckLabel = isDeckA ? 'A' : 'B';
    final track = isDeckA ? trackA : trackB;

    if (isDeckPlaying(deck)) {
      if (isDeckA) {
        _wantPlayingA = false;
      } else {
        _wantPlayingB = false;
      }
      await _pauseDeckInternal(deck);
      StreamDiagnosticLogger.instance.log(
        'PLAYER_$deckLabel',
        '⏸ หยุดเล่นชั่วคราว (Pause) บน Deck $deckLabel',
        level: 'INFO',
        deck: deckLabel,
      );
      notifyListeners();
    } else {
      if (track == null) return;
      if (!checkActiveSubscriptionOrPause()) return;
      final mountedId = isDeckA ? _mountedVideoIdA : _mountedVideoIdB;
      if (track.streamUrl == null ||
          track.streamUrl!.isEmpty ||
          (!ApiService.isTestMode && mountedId != track.videoId)) {
        await loadAndPlayTrack(deck, track, autoPlay: true);
      } else {
        await _forcePlayDeck(deck, adjustCrossfaderIfMuted: true);
      }
    }
  }

  Future<void> seek(ActiveDeck deck, Duration position) async {
    final isA = deck == ActiveDeck.deckA;
    final vc = isA ? videoControllerA : videoControllerB;
    final player = isA ? deckA : deckB;
    if ((isA ? useVideoEngineA : useVideoEngineB) && vc != null && vc.value.isInitialized) {
      try {
        await vc.seekTo(position);
      } catch (_) {}
    } else {
      try {
        await player.seek(position);
      } catch (_) {}
    }
    notifyListeners();
  }

  // Queue Management
  void addToQueue(Track track) {
    if (!ApiService.isTestMode && track.videoId.isNotEmpty) {
      unawaited(LocalAudioProxy.prewarm(track.videoId));
    }
    if (trackA == null) {
      loadAndPlayTrack(ActiveDeck.deckA, track, autoPlay: isDeckPlaying(ActiveDeck.deckA));
    } else if (trackB == null) {
      preloadStandbyTrack(track);
    } else {
      queue.add(track);
      AuthService.instance.syncQueue(queue);
      notifyListeners();
    }
  }

  void addMultipleToQueue(List<Track> tracks) {
    if (!ApiService.isTestMode) {
      for (final t in tracks.take(4)) {
        if (t.videoId.isNotEmpty) {
          unawaited(LocalAudioProxy.prewarm(t.videoId));
        }
      }
    }
    queue.addAll(tracks);
    AuthService.instance.syncQueue(queue);
    notifyListeners();
  }

  void removeFromQueue(int index) {
    if (index >= 0 && index < queue.length) {
      queue.removeAt(index);
      AuthService.instance.syncQueue(queue);
      notifyListeners();
    }
  }

  void clearQueue() {
    queue.clear();
    AuthService.instance.syncQueue(queue);
    notifyListeners();
  }

  void setTransitionDuration(int seconds) {
    transitionDurationSeconds = seconds;
    AuthService.instance.syncSettings({
      'lowSpecMode': lowSpecMode,
      'transitionDurationSeconds': transitionDurationSeconds,
    });
    notifyListeners();
  }

  void toggleAutoCrossfade() {
    autoCrossfadeEnabled = !autoCrossfadeEnabled;
    notifyListeners();
  }

  void toggleKeyLock() {
    keyLockEnabled = !keyLockEnabled;
    setPlaybackSpeed(speedDeckA, deck: ActiveDeck.deckA);
    setPlaybackSpeed(speedDeckB, deck: ActiveDeck.deckB);
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _uiTickTimer?.cancel();
    _recordingTimer?.cancel();
    AuthService.instance.removeListener(_onAuthChanged);
    _posSubA?.cancel();
    _posSubB?.cancel();
    _stateSubA?.cancel();
    _stateSubB?.cancel();
    _eventSubA?.cancel();
    _eventSubB?.cancel();
    _deckPosControllerA.close();
    _deckPosControllerB.close();
    try {
      videoControllerA?.dispose();
      videoControllerB?.dispose();
      deckA.dispose();
      deckB.dispose();
      samplerPlayer.dispose();
    } catch (_) {}
    super.dispose();
  }
}
