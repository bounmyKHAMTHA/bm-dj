import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../controllers/dj_deck_manager.dart';
import '../models/track.dart';

/// Fullscreen / Large Theater Video Dialog for watching music videos while DJing
class VideoTheaterDialog extends StatefulWidget {
  final Track track;
  final ActiveDeck deck;
  final DJDeckManager manager;

  const VideoTheaterDialog({
    super.key,
    required this.track,
    required this.deck,
    required this.manager,
  });

  static Future<void> show(
    BuildContext context, {
    required Track track,
    required ActiveDeck deck,
    required DJDeckManager manager,
  }) {
    return showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => VideoTheaterDialog(
        track: track,
        deck: deck,
        manager: manager,
      ),
    );
  }

  @override
  State<VideoTheaterDialog> createState() => _VideoTheaterDialogState();
}

class _VideoTheaterDialogState extends State<VideoTheaterDialog> {
  VideoPlayerController? _ownVideoController;
  bool _isVideoInitialized = false;
  bool _hasError = false;

  VideoPlayerController? get _activeVideoController =>
      widget.manager.getDeckVideoController(widget.deck) ?? _ownVideoController;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    final existing = widget.manager.getDeckVideoController(widget.deck);
    if (existing != null && existing.value.isInitialized) {
      setState(() => _isVideoInitialized = true);
      return;
    }

    final videoUrl = widget.track.videoStreamUrl ?? widget.track.streamUrl;
    if (videoUrl == null || videoUrl.isEmpty) {
      setState(() => _hasError = true);
      return;
    }

    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      _ownVideoController = controller;
      await controller.initialize();
      await controller.setVolume(0.0);

      final currentPos = widget.manager.getDeckPosition(widget.deck);
      await controller.seekTo(currentPos);
      if (widget.manager.isDeckPlaying(widget.deck)) {
        controller.play();
      }

      if (mounted) {
        setState(() {
          _isVideoInitialized = true;
        });
      }
    } catch (e) {
      debugPrint("Error initializing video player in theater mode: $e");
      if (mounted) {
        setState(() => _hasError = true);
      }
    }
  }

  @override
  void dispose() {
    _ownVideoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDeckA = widget.deck == ActiveDeck.deckA;
    final accentColor = isDeckA ? const Color(0xFF00F2FE) : const Color(0xFFFF2A85);
    final deckName = isDeckA ? 'DECK A' : 'DECK B';
    final isPlaying = widget.manager.isDeckPlaying(widget.deck);
    final vc = _activeVideoController;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Center(
        child: Container(
          width: 960,
          constraints: const BoxConstraints(maxHeight: 700),
          decoration: BoxDecoration(
            color: const Color(0xFF0C0E14),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accentColor.withAlpha(120), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: accentColor.withAlpha(60),
                blurRadius: 30,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Header Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: const BoxDecoration(
                  color: Color(0xFF141722),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: accentColor.withAlpha(50),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: accentColor),
                      ),
                      child: Text(
                        deckName,
                        style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.track.title,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            widget.track.artist,
                            style: const TextStyle(color: Colors.white60, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close Video Theater',
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Main Video Display Area (16:9 Aspect Ratio)
              Flexible(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(
                    color: Colors.black,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (_isVideoInitialized && vc != null && vc.value.isInitialized)
                          VideoPlayer(vc)
                        else if (widget.track.thumbnailUrl != null)
                          Image.network(
                            widget.track.thumbnailUrl!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            errorBuilder: (context, error, stackTrace) => Container(
                              color: Colors.black,
                              child: const Icon(Icons.videocam_off, color: Colors.white30, size: 48),
                            ),
                          )
                        else
                          Icon(_hasError ? Icons.videocam_off : Icons.music_video, color: Colors.white24, size: 64),

                        // Center Big Play / Pause Overlay Button
                        GestureDetector(
                          onTap: () async {
                            await widget.manager.toggleDeckPlay(widget.deck);
                            if (widget.manager.isDeckPlaying(widget.deck)) {
                              _ownVideoController?.play();
                            } else {
                              _ownVideoController?.pause();
                            }
                            setState(() {});
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.red.withAlpha(isPlaying ? 0 : 220),
                              boxShadow: isPlaying
                                  ? null
                                  : [
                                      BoxShadow(
                                        color: Colors.red.withAlpha(120),
                                        blurRadius: 20,
                                        spreadRadius: 4,
                                      ),
                                    ],
                            ),
                            child: Icon(
                              isPlaying ? Icons.pause_circle_filled : Icons.play_arrow,
                              color: Colors.white,
                              size: isPlaying ? 48 : 56,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Bottom DJ Mixer Dock (Seek, Volume, Crossfader while watching video)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  color: Color(0xFF11141D),
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(15)),
                ),
                child: Column(
                  children: [
                    // Position seek bar
                    StreamBuilder<Duration>(
                      stream: widget.manager.getDeckPositionStream(widget.deck),
                      builder: (context, snapshot) {
                        final pos = snapshot.data ?? widget.manager.getDeckPosition(widget.deck);
                        final dur = widget.manager.getDeckDuration(widget.deck);
                        final maxMs = dur.inMilliseconds.toDouble();
                        final curMs = pos.inMilliseconds.toDouble().clamp(0.0, maxMs > 0 ? maxMs : 1.0);

                        return Row(
                          children: [
                            Text(_formatTime(pos), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                  activeTrackColor: accentColor,
                                  thumbColor: accentColor,
                                ),
                                child: Slider(
                                  value: curMs,
                                  min: 0.0,
                                  max: maxMs > 0 ? maxMs : 1.0,
                                  onChanged: (val) {
                                    final seekPos = Duration(milliseconds: val.toInt());
                                    widget.manager.seek(widget.deck, seekPos);
                                    _ownVideoController?.seekTo(seekPos);
                                  },
                                ),
                              ),
                            ),
                            Text(_formatTime(dur), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 6),

                    // Controls row with Crossfader
                    Row(
                      children: [
                        // CUE
                        OutlinedButton(
                          onPressed: () {
                            widget.manager.seek(widget.deck, Duration.zero);
                            _ownVideoController?.seekTo(Duration.zero);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white24),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          ),
                          child: const Text('CUE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 8),

                        // PLAY / PAUSE
                        ElevatedButton.icon(
                          onPressed: () async {
                            await widget.manager.toggleDeckPlay(widget.deck);
                            if (widget.manager.isDeckPlaying(widget.deck)) {
                              _ownVideoController?.play();
                            } else {
                              _ownVideoController?.pause();
                            }
                            setState(() {});
                          },
                          icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow, size: 16),
                          label: Text(isPlaying ? 'PAUSE' : 'PLAY'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentColor,
                            foregroundColor: Colors.black,
                          ),
                        ),

                        const SizedBox(width: 20),

                        // Mini Crossfader for live mixing
                        Expanded(
                          child: Row(
                            children: [
                              const Text('DECK A', style: TextStyle(color: Color(0xFF00F2FE), fontSize: 11, fontWeight: FontWeight.bold)),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 4,
                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                                    activeTrackColor: const Color(0xFF00F2FE),
                                    inactiveTrackColor: const Color(0xFFFF2A85),
                                    thumbColor: Colors.white,
                                  ),
                                  child: Slider(
                                    value: widget.manager.crossfadePosition,
                                    min: 0.0,
                                    max: 1.0,
                                    onChanged: (val) => widget.manager.setManualCrossfader(val),
                                  ),
                                ),
                              ),
                              const Text('DECK B', style: TextStyle(color: Color(0xFFFF2A85), fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
