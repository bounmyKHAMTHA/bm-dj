import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../controllers/dj_deck_manager.dart';

/// Full-width continuous dual waveform strip across the top (like YouDJ Desktop)
class DualWaveformBar extends StatelessWidget {
  final DJDeckManager manager;

  const DualWaveformBar({super.key, required this.manager});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      decoration: const BoxDecoration(
        color: Color(0xFF090B0F),
        border: Border(
          top: BorderSide(color: Colors.white10, width: 0.8),
          bottom: BorderSide(color: Colors.white12, width: 0.8),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final halfWidth = constraints.maxWidth / 2;

          return Stack(
            children: [
              Row(
                children: [
                  // Deck A Waveform (Left Half)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (details) => _seekFromPosition(
                        ActiveDeck.deckA,
                        details.localPosition.dx,
                        halfWidth,
                      ),
                      child: StreamBuilder<Duration>(
                        stream: manager.getDeckPositionStream(ActiveDeck.deckA),
                        builder: (context, snapshot) {
                          final pos = snapshot.data ?? manager.getDeckPosition(ActiveDeck.deckA);
                          final dur = manager.getDeckDuration(ActiveDeck.deckA);
                          final progress = dur.inMilliseconds > 0
                              ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                              : 0.0;

                          final cueRatios = <int, double>{};
                          if (dur.inMilliseconds > 0) {
                            for (final e in manager.hotCuesA.entries) {
                              cueRatios[e.key] = (e.value.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
                            }
                          }
                          double? loopStartRatio;
                          double? loopEndRatio;
                          if (manager.isLoopingA && manager.loopStartA != null && dur.inMilliseconds > 0) {
                            loopStartRatio = (manager.loopStartA!.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
                            final loopMs = (60000.0 / manager.bpmDeckA) * manager.loopBeatsA;
                            loopEndRatio = ((manager.loopStartA!.inMilliseconds + loopMs) / dur.inMilliseconds).clamp(0.0, 1.0);
                          }

                          return CustomPaint(
                            painter: _WaveformPainter(
                              progress: progress,
                              isPlaying: manager.isDeckPlaying(ActiveDeck.deckA),
                              baseColor: const Color(0xFF00F2FE),
                              playedColor: const Color(0xFF0072FF),
                              seed: 101,
                              isLowSpec: manager.lowSpecMode,
                              trackName: manager.trackA?.title,
                              hotCues: cueRatios,
                              loopStartRatio: loopStartRatio,
                              loopEndRatio: loopEndRatio,
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  // Center Divider Needle
                  Container(
                    width: 2,
                    height: double.infinity,
                    color: Colors.white,
                  ),

                  // Deck B Waveform (Right Half)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (details) => _seekFromPosition(
                        ActiveDeck.deckB,
                        details.localPosition.dx,
                        halfWidth,
                      ),
                      child: StreamBuilder<Duration>(
                        stream: manager.getDeckPositionStream(ActiveDeck.deckB),
                        builder: (context, snapshot) {
                          final pos = snapshot.data ?? manager.getDeckPosition(ActiveDeck.deckB);
                          final dur = manager.getDeckDuration(ActiveDeck.deckB);
                          final progress = dur.inMilliseconds > 0
                              ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                              : 0.0;

                          final cueRatios = <int, double>{};
                          if (dur.inMilliseconds > 0) {
                            for (final e in manager.hotCuesB.entries) {
                              cueRatios[e.key] = (e.value.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
                            }
                          }
                          double? loopStartRatio;
                          double? loopEndRatio;
                          if (manager.isLoopingB && manager.loopStartB != null && dur.inMilliseconds > 0) {
                            loopStartRatio = (manager.loopStartB!.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
                            final loopMs = (60000.0 / manager.bpmDeckB) * manager.loopBeatsB;
                            loopEndRatio = ((manager.loopStartB!.inMilliseconds + loopMs) / dur.inMilliseconds).clamp(0.0, 1.0);
                          }

                          return CustomPaint(
                            painter: _WaveformPainter(
                              progress: progress,
                              isPlaying: manager.isDeckPlaying(ActiveDeck.deckB),
                              baseColor: const Color(0xFFFF2A85),
                              playedColor: const Color(0xFFFF7A00),
                              seed: 202,
                              isLowSpec: manager.lowSpecMode,
                              trackName: manager.trackB?.title,
                              hotCues: cueRatios,
                              loopStartRatio: loopStartRatio,
                              loopEndRatio: loopEndRatio,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  void _seekFromPosition(ActiveDeck deck, double dx, double totalWidth) {
    final dur = manager.getDeckDuration(deck);
    if (dur.inMilliseconds > 0 && totalWidth > 0) {
      final ratio = (dx / totalWidth).clamp(0.0, 1.0);
      final newPos = Duration(milliseconds: (dur.inMilliseconds * ratio).toInt());
      manager.seek(deck, newPos);
    }
  }
}

class _WaveformPainter extends CustomPainter {
  final double progress;
  final bool isPlaying;
  final Color baseColor;
  final Color playedColor;
  final int seed;
  final bool isLowSpec;
  final String? trackName;
  final Map<int, double> hotCues;
  final double? loopStartRatio;
  final double? loopEndRatio;

  _WaveformPainter({
    required this.progress,
    required this.isPlaying,
    required this.baseColor,
    required this.playedColor,
    required this.seed,
    required this.isLowSpec,
    this.trackName,
    this.hotCues = const {},
    this.loopStartRatio,
    this.loopEndRatio,
  });

  Color _getCueColor(int idx) {
    switch (idx) {
      case 1:
        return const Color(0xFF00F2FE);
      case 2:
        return const Color(0xFF00E676);
      case 3:
        return const Color(0xFFFF9100);
      case 4:
      default:
        return const Color(0xFFFF2A85);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final centerY = size.height / 2;
    final int barCount = (size.width / (isLowSpec ? 6.0 : 4.0)).floor();
    final double barWidth = isLowSpec ? 4.0 : 2.5;
    final double gap = isLowSpec ? 2.0 : 1.5;

    final paint = Paint()..style = PaintingStyle.fill;
    final playheadX = size.width * progress;

    // 1. Draw Active Loop Region Highlight
    if (loopStartRatio != null && loopEndRatio != null && loopEndRatio! > loopStartRatio!) {
      final loopRect = Rect.fromLTRB(
        size.width * loopStartRatio!,
        0,
        size.width * loopEndRatio!,
        size.height,
      );
      final loopPaint = Paint()..color = const Color(0xFFFF9100).withAlpha(55);
      canvas.drawRect(loopRect, loopPaint);

      final loopBorder = Paint()
        ..color = const Color(0xFFFF9100).withAlpha(180)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawRect(loopRect, loopBorder);
    }

    // 2. Draw Waveform Bars
    for (int i = 0; i < barCount; i++) {
      final x = i * (barWidth + gap);
      if (x > size.width) break;

      // Pseudo-random waveform amplitude generated from index + seed
      final double normalized = math.sin(i * 0.18 + seed) * 0.4 +
          math.cos(i * 0.08 + seed * 2) * 0.3 +
          math.sin(i * 0.4) * 0.3;
      final double amp = (normalized.abs().clamp(0.15, 1.0)) * (size.height * 0.42);

      final bool isPast = x <= playheadX;
      paint.color = isPast
          ? playedColor.withAlpha(240)
          : baseColor.withAlpha(trackName != null ? 100 : 35);

      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTRB(x, centerY - amp, x + barWidth, centerY + amp),
        const Radius.circular(1.0),
      );
      canvas.drawRRect(rrect, paint);
    }

    // 3. Draw Hot Cue Marker Flags on the waveform
    for (final entry in hotCues.entries) {
      final cueX = size.width * entry.value;
      final color = _getCueColor(entry.key);

      final cueLine = Paint()
        ..color = color.withAlpha(190)
        ..strokeWidth = 1.2;
      canvas.drawLine(Offset(cueX, 0), Offset(cueX, size.height), cueLine);

      final flagPaint = Paint()..color = color;
      canvas.drawCircle(Offset(cueX, 4), 2.5, flagPaint);
    }

    // 4. Draw playhead vertical line
    if (trackName != null) {
      final linePaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 2.0;
      canvas.drawLine(
        Offset(playheadX, 0),
        Offset(playheadX, size.height),
        linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.trackName != trackName ||
        oldDelegate.isLowSpec != isLowSpec ||
        oldDelegate.hotCues != hotCues ||
        oldDelegate.loopStartRatio != loopStartRatio ||
        oldDelegate.loopEndRatio != loopEndRatio;
  }
}
