import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

class VuMeterWidget extends StatefulWidget {
  final bool isPlaying;
  final double volume; // 0.0 to 1.0
  final Color activeColor;
  final int barCount;
  final bool isLowSpec;
  final double height;

  const VuMeterWidget({
    super.key,
    required this.isPlaying,
    required this.volume,
    required this.activeColor,
    this.barCount = 16,
    this.isLowSpec = false,
    this.height = 14,
  });

  @override
  State<VuMeterWidget> createState() => _VuMeterWidgetState();
}

class _VuMeterWidgetState extends State<VuMeterWidget> {
  Timer? _timer;
  final math.Random _random = math.Random();
  late List<double> _barRatios;

  @override
  void initState() {
    super.initState();
    _barRatios = List.filled(widget.barCount, 0.08);
    _updateTimer();
  }

  void _updateTimer() {
    _timer?.cancel();
    if (widget.isPlaying && !widget.isLowSpec) {
      // 10-12 FPS tick is perfectly smooth for an audio visualizer while saving 80% CPU
      _timer = Timer.periodic(const Duration(milliseconds: 90), (_) {
        if (!mounted) return;
        setState(() {
          for (int i = 0; i < widget.barCount; i++) {
            _barRatios[i] = (_random.nextDouble() * 0.7 + 0.3) * widget.volume;
          }
        });
      });
    } else {
      // In low-spec mode or paused, generate a static volume level with zero timer ticks
      for (int i = 0; i < widget.barCount; i++) {
        _barRatios[i] = widget.isPlaying ? (0.5 + (i % 3) * 0.15) * widget.volume : 0.08;
      }
    }
  }

  @override
  void didUpdateWidget(covariant VuMeterWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.barCount != _barRatios.length) {
      _barRatios = List.filled(widget.barCount, 0.08);
    }
    if (widget.isPlaying != oldWidget.isPlaying || widget.isLowSpec != oldWidget.isLowSpec) {
      _updateTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: CustomPaint(
        size: Size(double.infinity, widget.height),
        painter: _VuPainter(
          ratios: _barRatios,
          isPlaying: widget.isPlaying,
          activeColor: widget.activeColor,
          isLowSpec: widget.isLowSpec,
        ),
      ),
    );
  }
}

class _VuPainter extends CustomPainter {
  final List<double> ratios;
  final bool isPlaying;
  final Color activeColor;
  final bool isLowSpec;

  _VuPainter({
    required this.ratios,
    required this.isPlaying,
    required this.activeColor,
    required this.isLowSpec,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final int count = ratios.length;
    if (count == 0) return;

    const double barWidth = 4.0;
    const double barGap = 3.0;
    final double totalWidth = count * barWidth + (count - 1) * barGap;
    double startX = (size.width - totalWidth) / 2;
    if (startX < 0) startX = 0;

    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < count; i++) {
      Color barColor;
      if (i > count * 0.8) {
        barColor = Colors.redAccent;
      } else if (i > count * 0.6) {
        barColor = Colors.amberAccent;
      } else {
        barColor = activeColor;
      }

      paint.color = barColor.withAlpha((255 * (isPlaying ? 0.9 : 0.25)).round());

      final double maxH = size.height - 1;
      final double barHeight = (maxH * ratios[i]).clamp(2.5, maxH);
      final double left = startX + i * (barWidth + barGap);
      final double top = size.height - barHeight;

      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, barWidth, barHeight),
        const Radius.circular(1.5),
      );

      // In standard mode add subtle glow, in low-spec mode skip shadows completely
      if (isPlaying && !isLowSpec) {
        final shadowPaint = Paint()
          ..color = barColor.withAlpha(80)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
        canvas.drawRRect(rrect, shadowPaint);
      }

      canvas.drawRRect(rrect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VuPainter oldDelegate) {
    return isPlaying || oldDelegate.isPlaying != isPlaying || oldDelegate.isLowSpec != isLowSpec;
  }
}
