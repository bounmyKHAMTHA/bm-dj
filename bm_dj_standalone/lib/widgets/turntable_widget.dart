import 'dart:math' as math;
import 'package:flutter/material.dart';

class TurntableWidget extends StatefulWidget {
  final bool isPlaying;
  final String? albumArtUrl;
  final Color accentColor;
  final double size;
  final bool isLowSpec;

  const TurntableWidget({
    super.key,
    required this.isPlaying,
    this.albumArtUrl,
    required this.accentColor,
    this.size = 200,
    this.isLowSpec = false,
  });

  @override
  State<TurntableWidget> createState() => _TurntableWidgetState();
}

class _TurntableWidgetState extends State<TurntableWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );

    if (widget.isPlaying && !widget.isLowSpec) {
      _animController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant TurntableWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLowSpec) {
      if (_animController.isAnimating) _animController.stop();
    } else {
      if (widget.isPlaying && !_animController.isAnimating) {
        _animController.repeat();
      } else if (!widget.isPlaying && _animController.isAnimating) {
        _animController.stop();
      }
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;

    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer Turntable Platter
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF14171E),
              boxShadow: widget.isLowSpec
                  ? null
                  : [
                      BoxShadow(
                        color: widget.isPlaying
                            ? widget.accentColor.withAlpha((255 * 0.35).round())
                            : Colors.black54,
                        blurRadius: 18,
                        spreadRadius: widget.isPlaying ? 2 : 0,
                      ),
                    ],
              border: Border.all(
                color: widget.accentColor.withAlpha((255 * 0.5).round()),
                width: 2,
              ),
            ),
          ),

          // Vinyl Record with Grooves and Album Art
          AnimatedBuilder(
            animation: _animController,
            builder: (context, child) {
              return Transform.rotate(
                angle: widget.isLowSpec ? 0.0 : _animController.value * 2 * math.pi,
                child: child,
              );
            },
            child: Container(
              width: size * 0.88,
              height: size * 0.88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [
                    Color(0xFF232832),
                    Color(0xFF11141A),
                    Color(0xFF090A0D),
                  ],
                  stops: [0.35, 0.75, 1.0],
                ),
                border: Border.all(
                  color: Colors.white12,
                  width: 1.5,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Vinyl Grooves (rings)
                  CustomPaint(
                    size: Size(size * 0.88, size * 0.88),
                    painter: _VinylGroovePainter(),
                  ),

                  // Center Label with Memory Caching
                  Container(
                    width: size * 0.36,
                    height: size * 0.36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.accentColor,
                        width: 2,
                      ),
                      boxShadow: widget.isLowSpec
                          ? null
                          : [
                              BoxShadow(
                                color: Colors.black.withAlpha((255 * 0.6).round()),
                                blurRadius: 6,
                              ),
                            ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: widget.albumArtUrl != null
                        ? Image.network(
                            widget.albumArtUrl!,
                            fit: BoxFit.cover,
                            cacheWidth: (size * 0.5).toInt().clamp(60, 250),
                            cacheHeight: (size * 0.5).toInt().clamp(60, 250),
                            errorBuilder: (context, error, stackTrace) => _buildDefaultCenter(),
                          )
                        : _buildDefaultCenter(),
                  ),

                  // Center Spindle Hole
                  Container(
                    width: size * 0.07,
                    height: size * 0.07,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFD6DBE4),
                      boxShadow: widget.isLowSpec
                          ? null
                          : const [
                              BoxShadow(
                                color: Colors.black54,
                                blurRadius: 3,
                              ),
                            ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Stylized Tonearm
          Positioned(
            right: 0,
            top: 4,
            child: Transform.rotate(
              angle: widget.isPlaying ? 0.38 : 0.08,
              alignment: Alignment.topRight,
              child: Container(
                width: 10,
                height: size * 0.62,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFB0B7C3), Color(0xFF4A5568)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(5),
                  boxShadow: widget.isLowSpec
                      ? null
                      : const [
                          BoxShadow(
                            color: Colors.black54,
                            blurRadius: 4,
                            offset: Offset(2, 2),
                          ),
                        ],
                ),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: 14,
                    height: 18,
                    decoration: BoxDecoration(
                      color: widget.accentColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultCenter() {
    return Container(
      color: const Color(0xFF1E232E),
      child: Center(
        child: Icon(
          Icons.album,
          color: widget.accentColor,
          size: widget.size * 0.2,
        ),
      ),
    );
  }
}

class _VinylGroovePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = Colors.white.withAlpha((255 * 0.05).round())
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final maxRadius = size.width / 2 - 4;
    const minRadius = 40.0;
    const step = 8.0;

    for (double r = minRadius; r < maxRadius; r += step) {
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
