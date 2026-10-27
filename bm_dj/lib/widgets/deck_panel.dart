import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../controllers/dj_deck_manager.dart';
import '../models/track.dart';
import '../services/auth_service.dart';
import 'auth_dialog.dart';
import 'deck_performance_pads.dart';
import 'turntable_widget.dart';
import 'video_theater_dialog.dart';
import 'vu_meter_widget.dart';

class DeckPanel extends StatefulWidget {
  final ActiveDeck deck;
  final DJDeckManager manager;
  final Color accentColor;
  final String deckName;
  final bool isCompact;
  final VoidCallback? onLoadTrackPressed;

  const DeckPanel({
    super.key,
    required this.deck,
    required this.manager,
    required this.accentColor,
    required this.deckName,
    this.isCompact = false,
    this.onLoadTrackPressed,
  });

  @override
  State<DeckPanel> createState() => _DeckPanelState();
}

class _DeckPanelState extends State<DeckPanel> {
  // Toggle between YouDJ 16:9 Video Screen and Turntable Vinyl
  bool _showTurntable = false;

  @override
  Widget build(BuildContext context) {
    final isDeckA = widget.deck == ActiveDeck.deckA;
    final AudioPlayer player = isDeckA ? widget.manager.deckA : widget.manager.deckB;
    final Track? track = isDeckA ? widget.manager.trackA : widget.manager.trackB;
    final bool isAudible = (isDeckA && widget.manager.crossfadePosition < 0.5) ||
                           (!isDeckA && widget.manager.crossfadePosition >= 0.5);
    final double speed = isDeckA ? widget.manager.speedDeckA : widget.manager.speedDeckB;
    final bool isTurbo = isDeckA ? widget.manager.isTurboA : widget.manager.isTurboB;
    final bool isRollingInStandby = !isAudible && player.playing;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: widget.isCompact ? 8 : 10,
        vertical: widget.isCompact ? 3 : 8,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF13161F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isAudible
              ? widget.accentColor.withAlpha(140)
              : (isRollingInStandby ? Colors.amberAccent.withAlpha(120) : Colors.white12),
          width: isAudible ? 1.5 : 1.0,
        ),
        boxShadow: widget.manager.lowSpecMode
            ? null
            : [
                BoxShadow(
                  color: isAudible
                      ? widget.accentColor.withAlpha(35)
                      : (isRollingInStandby ? Colors.amber.withAlpha(25) : Colors.black45),
                  blurRadius: 10,
                  spreadRadius: isAudible ? 1 : 0,
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header: Deck Badge, Status & Fullscreen / Mode Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: widget.isCompact ? 6 : 8,
                      vertical: widget.isCompact ? 1 : 2,
                    ),
                    decoration: BoxDecoration(
                      color: widget.accentColor.withAlpha(50),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: widget.accentColor, width: 1),
                    ),
                    child: Text(
                      widget.deckName,
                      style: TextStyle(
                        color: widget.accentColor,
                        fontWeight: FontWeight.bold,
                        fontSize: widget.isCompact ? 10 : 12,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (track?.isResolving == true)
                    const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                ],
              ),

              // Header actions: Switch Disc/Video view + Expand Video Theater
              Row(
                children: [
                  // Audibility status pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: isAudible
                          ? Colors.green.withAlpha(45)
                          : (isRollingInStandby ? Colors.amber.withAlpha(45) : Colors.white.withAlpha(12)),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isAudible
                            ? Colors.greenAccent
                            : (isRollingInStandby ? Colors.amberAccent : Colors.white24),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isAudible
                                ? Colors.greenAccent
                                : (isRollingInStandby ? Colors.amberAccent : Colors.grey),
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          isAudible
                              ? '${(player.volume * 100).toInt()}%'
                              : (player.duration != null
                                  ? (player.playing ? 'ROLLING' : 'READY')
                                  : 'STANDBY'),
                          style: TextStyle(
                            color: isAudible
                                ? Colors.greenAccent
                                : (isRollingInStandby ? Colors.amberAccent : Colors.grey[400]),
                            fontSize: 8.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),

                  // Toggle Vinyl / Video Mode
                  IconButton(
                    tooltip: _showTurntable ? 'สลับไปจอวิดีโอ (YouDJ Style)' : 'สลับไปแผ่นเสียง Vinyl',
                    icon: Icon(
                      _showTurntable ? Icons.smart_display : Icons.album,
                      color: Colors.white70,
                      size: widget.isCompact ? 15 : 17,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => setState(() => _showTurntable = !_showTurntable),
                  ),
                  const SizedBox(width: 6),

                  // Fullscreen / Enlarge Video Button (ขยายภาพใหญ่)
                  IconButton(
                    tooltip: 'ขยายภาพวิดีโอจอใหญ่ (Fullscreen Theater)',
                    icon: Icon(Icons.fullscreen, color: Colors.white, size: widget.isCompact ? 17 : 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: track != null
                        ? () => VideoTheaterDialog.show(
                              context,
                              track: track,
                              deck: widget.deck,
                              manager: widget.manager,
                            )
                        : null,
                  ),
                ],
              ),
            ],
          ),

          SizedBox(height: widget.isCompact ? 2 : 4),

          // Main Deck Display: 16:9 Video Screen (YouDJ Style) or Turntable Vinyl
          if (_showTurntable)
            TurntableWidget(
              isPlaying: player.playing,
              albumArtUrl: track?.thumbnailUrl,
              accentColor: widget.accentColor,
              size: widget.isCompact ? 70 : 120,
              isLowSpec: widget.manager.lowSpecMode,
            )
          else
            _buildYouDjVideoScreen(track, player),

          SizedBox(height: widget.isCompact ? 2 : 4),

          // Track Title & Artist with Like Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        track?.title ?? 'No Track Loaded',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: widget.isCompact ? 10 : 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        track?.artist ?? 'Select from Search or Queue below',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: widget.isCompact ? 8.5 : 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                if (track != null)
                  ListenableBuilder(
                    listenable: AuthService.instance,
                    builder: (context, _) {
                      final auth = AuthService.instance;
                      final isLiked = auth.isTrackLiked(track.videoId);
                      return Tooltip(
                        message: isLiked ? 'ลบออกจากเพลงที่ชอบ' : 'กดไลค์ / เพิ่มลงในเพลงที่ชอบ (Like)',
                        child: InkWell(
                          onTap: () async {
                            if (!auth.isLoggedIn) {
                              showDialog(context: context, builder: (_) => const AuthDialog());
                            } else {
                              final messenger = ScaffoldMessenger.of(context);
                              final isLikedNow = await auth.toggleLikeTrack(track);
                              if (mounted) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      isLikedNow
                                          ? '❤️ เพิ่ม "${track.title}" ลงในเพลงที่ชอบแล้ว'
                                          : 'ลบออกจากเพลงที่ชอบแล้ว',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    duration: const Duration(seconds: 2),
                                    backgroundColor: isLikedNow ? const Color(0xFFFF2A85) : Colors.grey[900],
                                  ),
                                );
                              }
                            }
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: isLiked ? const Color(0xFFFF2A85).withAlpha(40) : Colors.white10,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isLiked ? const Color(0xFFFF2A85) : Colors.white24,
                                width: 1,
                              ),
                            ),
                            child: Icon(
                              isLiked ? Icons.favorite : Icons.favorite_border,
                              color: isLiked ? const Color(0xFFFF2A85) : Colors.white70,
                              size: widget.isCompact ? 14 : 17,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),

          SizedBox(height: widget.isCompact ? 2 : 4),

          // Stream position & duration slider
          StreamBuilder<Duration>(
            stream: player.positionStream,
            builder: (context, snapshot) {
              final position = snapshot.data ?? Duration.zero;
              final duration = player.duration ?? Duration.zero;
              final double maxVal = duration.inMilliseconds.toDouble();
              final double currentVal = position.inMilliseconds
                  .toDouble()
                  .clamp(0.0, maxVal > 0 ? maxVal : 1.0);

              return Column(
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: widget.isCompact ? 3.5 : 5.0,
                      thumbShape: RoundSliderThumbShape(enabledThumbRadius: widget.isCompact ? 6.0 : 8.0, elevation: 3),
                      overlayShape: RoundSliderOverlayShape(overlayRadius: widget.isCompact ? 12.0 : 15.0),
                      activeTrackColor: widget.accentColor,
                      inactiveTrackColor: Colors.white12,
                      thumbColor: widget.accentColor,
                    ),
                    child: Slider(
                      value: currentVal,
                      min: 0.0,
                      max: maxVal > 0 ? maxVal : 1.0,
                      onChanged: (val) {
                        widget.manager.seek(widget.deck, Duration(milliseconds: val.toInt()));
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(position),
                          style: TextStyle(color: Colors.grey[400], fontSize: widget.isCompact ? 8 : 9),
                        ),
                        Text(
                          _formatDuration(duration),
                          style: TextStyle(color: Colors.grey[400], fontSize: widget.isCompact ? 8 : 9),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),

          SizedBox(height: widget.isCompact ? 1 : 2),

          // Dynamic VU Meter (compact height)
          VuMeterWidget(
            isPlaying: player.playing,
            volume: player.volume,
            activeColor: widget.accentColor,
            barCount: widget.isCompact ? 8 : (widget.manager.lowSpecMode ? 8 : 14),
            height: widget.isCompact ? 10 : 14,
            isLowSpec: widget.manager.lowSpecMode,
          ),

          SizedBox(height: widget.isCompact ? 3 : 4),

          // Bottom Controls: CUE, PLAY/PAUSE, Tempo Slider
          Row(
            children: [
              // CUE button (seek to start)
              OutlinedButton(
                onPressed: () => widget.manager.seek(widget.deck, Duration.zero),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.isCompact ? 5 : 10,
                    vertical: widget.isCompact ? 2 : 6,
                  ),
                  minimumSize: Size(0, widget.isCompact ? 22 : 26),
                ),
                child: Text('CUE', style: TextStyle(fontSize: widget.isCompact ? 9 : 10, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 5),

              // Play/Pause button
              ElevatedButton.icon(
                onPressed: () => widget.manager.toggleDeckPlay(widget.deck),
                icon: Icon(player.playing ? Icons.pause : Icons.play_arrow, size: widget.isCompact ? 12 : 14),
                label: Text(
                  player.playing ? 'PAUSE' : 'PLAY',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: widget.isCompact ? 9 : 10),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.accentColor,
                  foregroundColor: Colors.black,
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.isCompact ? 6 : 12,
                    vertical: widget.isCompact ? 2 : 6,
                  ),
                  minimumSize: Size(0, widget.isCompact ? 22 : 26),
                ),
              ),

              const SizedBox(width: 6),

              // Tempo slider with Turbo Boost
              Expanded(
                child: Row(
                  children: [
                    Text(
                      'TEMPO',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: widget.isCompact ? 8 : 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: widget.isCompact ? 2.5 : 3.5,
                          thumbShape: RoundSliderThumbShape(enabledThumbRadius: widget.isCompact ? 5.0 : 6.5),
                          overlayShape: RoundSliderOverlayShape(overlayRadius: widget.isCompact ? 10.0 : 13.0),
                          activeTrackColor: isTurbo ? const Color(0xFFFF9100) : widget.accentColor,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: isTurbo ? const Color(0xFFFF9100) : widget.accentColor,
                        ),
                        child: Slider(
                          value: speed.clamp(0.70, 1.50),
                          min: 0.70,
                          max: 1.50,
                          divisions: 80,
                          onChanged: (val) {
                            widget.manager.setPlaybackSpeed(val, deck: widget.deck);
                          },
                        ),
                      ),
                    ),
                    Tooltip(
                      message: 'คลิกเพื่อรีเซ็ตความเร็วกลับเป็น 1.00x',
                      child: InkWell(
                        onTap: () => widget.manager.setPlaybackSpeed(1.0, deck: widget.deck),
                        child: Text(
                          '${speed.toStringAsFixed(2)}x',
                          style: TextStyle(
                            color: isTurbo
                                ? const Color(0xFFFF9100)
                                : (speed == 1.0 ? Colors.white60 : widget.accentColor),
                            fontSize: widget.isCompact ? 8 : 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),

                    // Turbo Boost Button (เทอร์โบบูส ⚡)
                    Tooltip(
                      message: 'เทอร์โบบูส (Turbo Boost): เร่งความเร็วเพลงเป็น 1.25x ทันที (หรือคลิกซ้ำเพื่อกลับสู่ 1.00x)',
                      child: InkWell(
                        onTap: () => widget.manager.toggleTurboBoost(widget.deck),
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: widget.isCompact ? 4 : 6,
                            vertical: widget.isCompact ? 1.5 : 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: isTurbo ? const Color(0xFFFF9100) : const Color(0xFF1B2030),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isTurbo ? Colors.white : const Color(0xFFFF9100).withAlpha(120),
                              width: isTurbo ? 1.0 : 0.7,
                            ),
                            boxShadow: isTurbo
                                ? [const BoxShadow(color: Color(0xFFFF9100), blurRadius: 6)]
                                : null,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.bolt,
                                size: widget.isCompact ? 9 : 11,
                                color: isTurbo ? Colors.black : const Color(0xFFFF9100),
                              ),
                              Text(
                                'TURBO',
                                style: TextStyle(
                                  color: isTurbo ? Colors.black : const Color(0xFFFF9100),
                                  fontSize: widget.isCompact ? 7.0 : 8.0,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // DJ Performance Pads: HOT CUES, LOOPS, EQ/FILTER, SAMPLER
          DeckPerformancePads(
            deck: widget.deck,
            manager: widget.manager,
            accentColor: widget.accentColor,
            isCompact: widget.isCompact,
          ),
        ],
      ),
    );
  }

  /// 16:9 Video / Screen Display with large central Red YouTube-style Play button
  Widget _buildYouDjVideoScreen(Track? track, AudioPlayer player) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: widget.isCompact ? 68 : 110,
        ),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.isCompact ? 6 : 8),
            child: Container(
              color: const Color(0xFF0A0C10),
              child: Stack(
                fit: StackFit.expand,
                alignment: Alignment.center,
                children: [
                  // Thumbnail background
                  if (track?.thumbnailUrl != null)
                    Image.network(
                      track!.thumbnailUrl!,
                      fit: BoxFit.cover,
                      cacheWidth: 320,
                      cacheHeight: 180,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: const Color(0xFF161A24),
                        child: Icon(Icons.music_note, color: Colors.white24, size: widget.isCompact ? 24 : 40),
                      ),
                    )
                  else
                    Container(
                      color: const Color(0xFF161A24),
                      child: Icon(Icons.music_note, color: Colors.white24, size: widget.isCompact ? 24 : 40),
                    ),

                  // Gradient Overlay for text contrast
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.transparent, Colors.black87],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),

                  // Center Big Red YouTube-style Play button (YouDJ icon style)
                  Center(
                    child: GestureDetector(
                      onTap: () => widget.manager.toggleDeckPlay(widget.deck),
                      child: Container(
                        width: widget.isCompact ? 32 : 50,
                        height: widget.isCompact ? 22 : 34,
                        decoration: BoxDecoration(
                          color: Colors.red.withAlpha(player.playing ? 180 : 240),
                          borderRadius: BorderRadius.circular(widget.isCompact ? 6 : 10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withAlpha(player.playing ? 60 : 120),
                              blurRadius: widget.isCompact ? 8 : 12,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            player.playing ? Icons.pause : Icons.play_arrow,
                            color: Colors.white,
                            size: widget.isCompact ? 15 : 24,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Top right: Clickable Expand Video Badge
                  if (track != null)
                    Positioned(
                      top: widget.isCompact ? 4 : 6,
                      right: widget.isCompact ? 4 : 6,
                      child: GestureDetector(
                        onTap: () => VideoTheaterDialog.show(
                          context,
                          track: track,
                          deck: widget.deck,
                          manager: widget.manager,
                        ),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: widget.isCompact ? 4 : 6,
                            vertical: widget.isCompact ? 2 : 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(180),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.fullscreen, color: Colors.white, size: widget.isCompact ? 10 : 13),
                              const SizedBox(width: 2),
                              Text(
                                'ขยายจอ',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: widget.isCompact ? 8 : 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
