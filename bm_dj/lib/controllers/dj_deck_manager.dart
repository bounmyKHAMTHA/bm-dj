import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/dj_audio_synthesizer.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ActiveDeck { deckA, deckB }

class DJDeckManager extends ChangeNotifier {
  final AudioPlayer deckA = AudioPlayer();
  final AudioPlayer deckB = AudioPlayer();
  final AudioPlayer samplerPlayer = AudioPlayer();

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

  void toggleLowSpecMode() {
    lowSpecMode = !lowSpecMode;
    AuthService.instance.syncSettings({
      'lowSpecMode': lowSpecMode,
      'transitionDurationSeconds': transitionDurationSeconds,
    });
    notifyListeners();
  }

  bool _disposed = false;
  StreamSubscription? _posSubA;
  StreamSubscription? _posSubB;
  StreamSubscription? _stateSubA;
  StreamSubscription? _stateSubB;

  AudioPlayer get activePlayer => isDeckAPlaying ? deckA : deckB;
  AudioPlayer get standbyPlayer => isDeckAPlaying ? deckB : deckA;
  Track? get activeTrack => isDeckAPlaying ? trackA : trackB;
  Track? get standbyTrack => isDeckAPlaying ? trackB : trackA;

  DJDeckManager() {
    _initEngine();
  }

  void _initEngine() {
    _loadMasterVolumeFromPrefs();
    _applyCrossfaderVolumesFast();

    // Listen to positions to monitor auto-crossfade and beat loops
    _posSubA = deckA.positionStream.listen((pos) {
      _checkLoop(ActiveDeck.deckA, pos);
      _checkAutoCrossfade(ActiveDeck.deckA, pos);
    });
    _posSubB = deckB.positionStream.listen((pos) {
      _checkLoop(ActiveDeck.deckB, pos);
      _checkAutoCrossfade(ActiveDeck.deckB, pos);
    });

    // Listen to playback states
    _stateSubA = deckA.playerStateStream.listen((_) {
      if (!_disposed) notifyListeners();
    });
    _stateSubB = deckB.playerStateStream.listen((_) {
      if (!_disposed) notifyListeners();
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

    final isThisActive = (deck == ActiveDeck.deckA && crossfadePosition < 0.5) ||
                         (deck == ActiveDeck.deckB && crossfadePosition >= 0.5);
    if (!isThisActive) return;

    final player = (deck == ActiveDeck.deckA) ? deckA : deckB;
    final duration = player.duration;
    if (duration == null || duration.inSeconds < 10) return;

    final remaining = duration - position;

    // Proactively prepare standby deck when song has 15 seconds remaining
    if (remaining.inSeconds <= 15 && standbyTrack == null) {
      _checkAndPreloadNextQueueItem();
    }

    if (remaining.inSeconds <= transitionDurationSeconds && standbyTrack != null) {
      executeSmoothSkip(durationSeconds: transitionDurationSeconds);
    }
  }

  // Pre-load track into the standby deck
  Future<void> preloadStandbyTrack(Track track) async {
    try {
      if (isDeckAPlaying) {
        trackB = track;
      } else {
        trackA = track;
      }
      notifyListeners();

      String? streamUrl = track.streamUrl;
      if (streamUrl == null || streamUrl.isEmpty) {
        track.isResolving = true;
        notifyListeners();
        final resolved = await ApiService.resolveStream(track.videoId);
        track.isResolving = false;
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
          if (isDeckAPlaying) {
            trackB = track;
          } else {
            trackA = track;
          }
        }
        notifyListeners();
      }

      if (streamUrl != null && streamUrl.isNotEmpty) {
        final target = standbyPlayer;
        try {
          if (target.playing) {
            await target.stop();
          }
        } catch (_) {}
        await target.setUrl(streamUrl);
        await target.setVolume(0.0);
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error preloading standby track: $e");
    }
  }

  // Load track into deck while preserving playback state:
  // If the target deck was currently playing, it plays immediately.
  // If the target deck was paused/standby, it stays paused at 0:00 (READY).
  // In either case, the crossfader is NOT snapped and the other deck is NOT interrupted!
  Future<void> loadTrackToDeck(ActiveDeck deck, Track track, {bool? autoPlay}) {
    final player = (deck == ActiveDeck.deckA) ? deckA : deckB;
    final wasThisDeckPlaying = player.playing;
    final shouldPlay = autoPlay ?? wasThisDeckPlaying;
    return loadAndPlayTrack(deck, track, autoPlay: shouldPlay);
  }

  // Load (and optionally play) track on specific deck
  Future<void> loadAndPlayTrack(ActiveDeck deck, Track track, {bool autoPlay = false}) async {
    try {
      final isDeckA = (deck == ActiveDeck.deckA);
      final player = isDeckA ? deckA : deckB;

      // 1. Immediately stop current playback on this deck to prevent old audio from continuing
      // and to free the browser HTMLMediaElement so setUrl won't abort/restart the old song!
      try {
        await player.stop();
      } catch (_) {}

      // 2. Assign track to deck immediately so UI updates instantly
      if (isDeckA) {
        trackA = track;
      } else {
        trackB = track;
      }
      notifyListeners();

      // 3. Resolve stream URL if not already present
      String? streamUrl = track.streamUrl;
      if (streamUrl == null || streamUrl.isEmpty) {
        track.isResolving = true;
        notifyListeners();

        try {
          final resolved = await ApiService.resolveStream(track.videoId);
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
        } catch (e) {
          debugPrint("[RESOLVER] Error resolving stream for ${track.title}: $e");
        } finally {
          track.isResolving = false;
        }

        if (isDeckA) {
          trackA = track;
        } else {
          trackB = track;
        }
        notifyListeners();
      }

      // 4. Set stream URL and handle playback
      if (streamUrl != null && streamUrl.isNotEmpty) {
        // Ensure player is stopped before setting new URL
        try {
          await player.stop();
        } catch (_) {}

        debugPrint("[LOAD_TRACK] Setting deck ${isDeckA ? 'A' : 'B'} to URL: $streamUrl");
        await player.setUrl(streamUrl);

        if (autoPlay) {
          // Play immediately on this deck, respecting current crossfade volumes
          await _applyCrossfaderVolumes();
          unawaited(player.play().catchError((e) => debugPrint("[LOAD_TRACK] Play error: $e")));
        } else {
          // Keep this player paused and cued at start (STANDBY / READY)
          try {
            if (player.playing) {
              await player.pause();
            }
          } catch (_) {}
          // Keep the existing crossfade and volume untouched so the currently playing deck
          // continues playing without interruption!
          await _applyCrossfaderVolumes();
        }
        notifyListeners();

        // 5. Automatically trigger pre-buffering next track into standby ONLY if standby is empty
        _checkAndPreloadNextQueueItem();
      } else {
        debugPrint("[LOAD_TRACK] Could not resolve stream URL for track: ${track.title}");
        notifyListeners();
      }
    } catch (e, stack) {
      debugPrint("[LOAD_TRACK] Error loading and playing track: $e\n$stack");
    }
  }


  // Smooth Crossfade Skip (Equal-Power Curve)
  Future<void> executeSmoothSkip({int? durationSeconds}) async {
    final duration = durationSeconds ?? transitionDurationSeconds;
    if (isTransitioning) return;

    // Immediately lock transition to prevent concurrent triggers from Auto-DJ or rapid clicks
    isTransitioning = true;
    notifyListeners();

    // Safety watchdog timer: guarantees isTransitioning is restored even if browser audio halts
    final watchdogTimer = Timer(Duration(seconds: duration + 4), () {
      if (isTransitioning) {
        debugPrint("[SMOOTH_SKIP] Watchdog triggered: Forcing isTransitioning = false.");
        isTransitioning = false;
        notifyListeners();
      }
    });

    try {
      // 1. Determine transition direction based on CURRENT crossfader position:
      // If crossfader is on Deck A side (< 0.5), transition to Deck B.
      // If crossfader is on Deck B side (>= 0.5), transition to Deck A.
      final bool movingToDeckB = crossfadePosition < 0.5;
      final outgoing = movingToDeckB ? deckA : deckB;
      final incoming = movingToDeckB ? deckB : deckA;
      final targetDeck = movingToDeckB ? ActiveDeck.deckB : ActiveDeck.deckA;
      var targetTrack = movingToDeckB ? trackB : trackA;

      // 2. If target deck is empty, try to populate from user queue
      if (targetTrack == null && queue.isNotEmpty) {
        final nextTrack = queue.removeAt(0);
        AuthService.instance.syncQueue(queue);
        await loadTrackToDeck(targetDeck, nextTrack, autoPlay: false);
        targetTrack = movingToDeckB ? trackB : trackA;
      }

      if (targetTrack == null) {
        debugPrint("[SMOOTH_SKIP] Standby deck ${movingToDeckB ? 'B' : 'A'} has no track to crossfade to.");
        return;
      }

      // 3. If target track is currently resolving, wait with timeout
      if (targetTrack.isResolving) {
        int waitCount = 0;
        while (targetTrack.isResolving && waitCount < 20) {
          await Future.delayed(const Duration(milliseconds: 100));
          waitCount++;
        }
      }

      // 4. Ensure target track stream URL is resolved
      if (targetTrack.streamUrl == null || targetTrack.streamUrl!.isEmpty) {
        try {
          final resolved = await ApiService.resolveStream(targetTrack.videoId).timeout(const Duration(seconds: 3));
          if (resolved != null && resolved.streamUrl != null && resolved.streamUrl!.isNotEmpty) {
            targetTrack.streamUrl = resolved.streamUrl;
            if (movingToDeckB) {
              trackB = targetTrack;
            } else {
              trackA = targetTrack;
            }
          }
        } catch (_) {}
      }

      // 5. Ensure incoming player has its stream loaded
      if (incoming.duration == null && targetTrack.streamUrl != null && targetTrack.streamUrl!.isNotEmpty) {
        try {
          await incoming.setUrl(targetTrack.streamUrl!).timeout(const Duration(seconds: 3));
        } catch (e) {
          debugPrint("[SMOOTH_SKIP] Error loading stream into incoming deck: $e");
        }
      }

      // 6. Start incoming deck playing if not already playing.
      // CRITICAL: In just_audio, play() returns a Future that only completes when audio finishes
      // or is paused. We MUST NOT await it, otherwise it blocks until the entire song ends!
      if (!incoming.playing) {
        if (incoming.position == Duration.zero) {
          try {
            await incoming.seek(Duration.zero).timeout(const Duration(milliseconds: 300));
          } catch (_) {}
        }
        await incoming.setVolume(0.0);
        unawaited(incoming.play().catchError((e) => debugPrint("[SMOOTH_SKIP] incoming.play error: $e")));
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

      // Pause outgoing player now that it is completely muted
      try {
        await outgoing.pause();
      } catch (_) {}
    } catch (e, stack) {
      debugPrint("[SMOOTH_SKIP] Error during smooth skip: $e\n$stack");
    } finally {
      watchdogTimer.cancel();
      isTransitioning = false;
      notifyListeners();
    }

    // Pre-buffer next track if the now-standby deck is empty
    _checkAndPreloadNextQueueItem();
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
    final player = (targetDeck == ActiveDeck.deckA) ? deckA : deckB;

    if (targetDeck == ActiveDeck.deckA) {
      speedDeckA = speed;
    } else {
      speedDeckB = speed;
    }

    await player.setPitch(useKeyLock ? 1.0 : speed);
    await player.setSpeed(speed);
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
    await deckA.setVolume(volA);
    await deckB.setVolume(volB);
  }

  void _applyCrossfaderVolumesFast() {
    final double baseA = math.cos(crossfadePosition * (math.pi / 2)) * volumeGainA * _getDeckVolumeMultiplier(ActiveDeck.deckA);
    final double baseB = math.sin(crossfadePosition * (math.pi / 2)) * volumeGainB * _getDeckVolumeMultiplier(ActiveDeck.deckB);
    final double volA = (baseA * masterVolume).clamp(0.0, 1.0);
    final double volB = (baseB * masterVolume).clamp(0.0, 1.0);
    deckA.setVolume(volA);
    deckB.setVolume(volB);
  }

  // --- Hot Cues (1..4) ---
  void setOrJumpHotCue(ActiveDeck deck, int index) {
    final player = (deck == ActiveDeck.deckA) ? deckA : deckB;
    final map = (deck == ActiveDeck.deckA) ? hotCuesA : hotCuesB;
    if (map.containsKey(index)) {
      seek(deck, map[index]!);
      if (!player.playing) {
        unawaited(player.play().catchError((e) => debugPrint("[HOT_CUE] Play error: $e")));
      }
    } else {
      map[index] = player.position;
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
    final player = isDeckA ? deckA : deckB;
    final currentLooping = isDeckA ? isLoopingA : isLoopingB;
    final currentBeats = isDeckA ? loopBeatsA : loopBeatsB;

    if (currentLooping && currentBeats == beats) {
      exitLoop(deck);
      return;
    }

    if (isDeckA) {
      isLoopingA = true;
      loopBeatsA = beats;
      loopStartA = player.position;
    } else {
      isLoopingB = true;
      loopBeatsB = beats;
      loopStartB = player.position;
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
    final AudioPlayer targetPlayer = isSourceA ? deckB : deckA;
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
    final currentPosMs = targetPlayer.position.inMilliseconds;
    final targetBeatPos = (currentPosMs / beatMs).round() * beatMs;
    seek(targetDeck, Duration(milliseconds: targetBeatPos.toInt()));

    notifyListeners();
  }

  // --- DJ Sampler FX Player ---
  Future<void> playSample(String type) async {
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

    try {
      await samplerPlayer.stop();
      await samplerPlayer.setAudioSource(
        AudioSource.uri(Uri.dataFromBytes(bytes, mimeType: 'audio/wav')),
      );
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
    await _applyCrossfaderVolumes();
    if (trackA != null && deckA.duration != null) {
      unawaited(deckA.play().catchError((e) => debugPrint("[PLAYBOTH A] Error: $e")));
    }
    if (trackB != null && deckB.duration != null) {
      unawaited(deckB.play().catchError((e) => debugPrint("[PLAYBOTH B] Error: $e")));
    }
    notifyListeners();
  }

  // Master Play / Pause
  Future<void> toggleMasterPlay() async {
    if (deckA.playing || deckB.playing) {
      await Future.wait([
        if (deckA.playing) deckA.pause(),
        if (deckB.playing) deckB.pause(),
      ]);
    } else {
      unawaited(activePlayer.play().catchError((e) => debugPrint("[MASTER] Error: $e")));
    }
    notifyListeners();
  }

  Future<void> toggleDeckPlay(ActiveDeck deck) async {
    final player = (deck == ActiveDeck.deckA) ? deckA : deckB;
    if (player.playing) {
      await player.pause();
    } else {
      // Start this deck playing according to current crossfader position!
      // Do NOT snap crossfader! The DJ can let it roll in standby,
      // and then smooth-skip or drag crossfader when ready!
      await _applyCrossfaderVolumes();
      unawaited(player.play().catchError((e) => debugPrint("[TOGGLE] Error: $e")));
    }
    notifyListeners();
  }

  Future<void> seek(ActiveDeck deck, Duration position) async {
    final player = (deck == ActiveDeck.deckA) ? deckA : deckB;
    await player.seek(position);
    notifyListeners();
  }

  // Queue Management
  void addToQueue(Track track) {
    // If standby deck is empty and active is playing, preload immediately!
    if (standbyTrack == null && activePlayer.playing) {
      preloadStandbyTrack(track);
    } else if (trackA == null && !deckA.playing) {
      loadAndPlayTrack(ActiveDeck.deckA, track);
    } else if (trackB == null && !deckB.playing && standbyTrack == null) {
      preloadStandbyTrack(track);
    } else {
      queue.add(track);
      AuthService.instance.syncQueue(queue);
      notifyListeners();
    }
  }

  void addMultipleToQueue(List<Track> tracks) {
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
    _recordingTimer?.cancel();
    AuthService.instance.removeListener(_onAuthChanged);
    _posSubA?.cancel();
    _posSubB?.cancel();
    _stateSubA?.cancel();
    _stateSubB?.cancel();
    deckA.dispose();
    deckB.dispose();
    samplerPlayer.dispose();
    super.dispose();
  }
}
