import 'package:flutter/material.dart';
import '../controllers/dj_deck_manager.dart';

enum PadMode { hotCue, loop, eq, sampler }

/// Modern DJ Performance Pad Controller for each Deck.
/// Provides Hot Cues (1-4), Auto Beat Looping, 3-Band EQ & Filter, and DJ Sound Sampler.
class DeckPerformancePads extends StatefulWidget {
  final ActiveDeck deck;
  final DJDeckManager manager;
  final Color accentColor;
  final bool isCompact;

  const DeckPerformancePads({
    super.key,
    required this.deck,
    required this.manager,
    required this.accentColor,
    this.isCompact = false,
  });

  @override
  State<DeckPerformancePads> createState() => _DeckPerformancePadsState();
}

class _DeckPerformancePadsState extends State<DeckPerformancePads> {
  PadMode _activeMode = PadMode.hotCue;

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0xFF0C0E14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mode Switcher Tabs
          Row(
            children: [
              _buildModeTab('HOT CUE', PadMode.hotCue, Icons.bookmark),
              _buildModeTab('LOOP', PadMode.loop, Icons.repeat),
              _buildModeTab('EQ & FILTER', PadMode.eq, Icons.tune),
              _buildModeTab('SAMPLER', PadMode.sampler, Icons.graphic_eq),
            ],
          ),
          const SizedBox(height: 5),

          // Active Mode Content
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _buildModeContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildModeTab(String label, PadMode mode, IconData icon) {
    final bool isSelected = _activeMode == mode;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _activeMode = mode),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 2.5),
          decoration: BoxDecoration(
            color: isSelected ? widget.accentColor.withAlpha(45) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? widget.accentColor : Colors.transparent,
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 9,
                color: isSelected ? widget.accentColor : Colors.white38,
              ),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white38,
                  fontSize: 7.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeContent() {
    switch (_activeMode) {
      case PadMode.hotCue:
        return _buildHotCuesTab();
      case PadMode.loop:
        return _buildLoopTab();
      case PadMode.eq:
        return _buildEqTab();
      case PadMode.sampler:
        return _buildSamplerTab();
    }
  }

  // --- 1. HOT CUES TAB ---
  Widget _buildHotCuesTab() {
    final isDeckA = widget.deck == ActiveDeck.deckA;
    final cues = isDeckA ? widget.manager.hotCuesA : widget.manager.hotCuesB;

    const padColors = [
      Color(0xFF00F2FE), // Pad 1 - Cyan
      Color(0xFF00E676), // Pad 2 - Green
      Color(0xFFFF9100), // Pad 3 - Orange
      Color(0xFFFF2A85), // Pad 4 - Pink
    ];

    return Row(
      children: List.generate(4, (index) {
        final cueIndex = index + 1;
        final hasCue = cues.containsKey(cueIndex);
        final color = padColors[index];

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: InkWell(
              onTap: () => widget.manager.setOrJumpHotCue(widget.deck, cueIndex),
              onLongPress: () {
                if (hasCue) {
                  widget.manager.clearHotCue(widget.deck, cueIndex);
                }
              },
              borderRadius: BorderRadius.circular(6),
              child: Container(
                height: widget.isCompact ? 26 : 30,
                decoration: BoxDecoration(
                  color: hasCue ? color.withAlpha(50) : const Color(0xFF161A24),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: hasCue ? color : Colors.white12,
                    width: hasCue ? 1.2 : 0.8,
                  ),
                  boxShadow: hasCue
                      ? [BoxShadow(color: color.withAlpha(40), blurRadius: 4)]
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'CUE $cueIndex',
                      style: TextStyle(
                        color: hasCue ? color : Colors.white54,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      hasCue ? _formatDuration(cues[cueIndex]!) : '+SET',
                      style: TextStyle(
                        color: hasCue ? Colors.white : Colors.white24,
                        fontSize: 7.5,
                        fontFamily: hasCue ? 'monospace' : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  // --- 2. AUTO BEAT LOOP TAB ---
  Widget _buildLoopTab() {
    final isDeckA = widget.deck == ActiveDeck.deckA;
    final isLooping = isDeckA ? widget.manager.isLoopingA : widget.manager.isLoopingB;
    final activeBeats = isDeckA ? widget.manager.loopBeatsA : widget.manager.loopBeatsB;

    final loopOptions = [0.5, 1.0, 2.0, 4.0, 8.0, 16.0];

    return Row(
      children: [
        // Loop buttons
        ...loopOptions.map((beats) {
          final isThisActive = isLooping && activeBeats == beats;
          final label = beats == 0.5 ? '1/2' : beats.toInt().toString();

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: InkWell(
                onTap: () => widget.manager.toggleLoop(widget.deck, beats),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  height: widget.isCompact ? 26 : 28,
                  decoration: BoxDecoration(
                    color: isThisActive
                        ? const Color(0xFFFF9100)
                        : const Color(0xFF161A24),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isThisActive ? Colors.white : Colors.white12,
                      width: isThisActive ? 1.0 : 0.6,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: isThisActive ? Colors.black : Colors.white70,
                        fontSize: 8.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),

        const SizedBox(width: 3),

        // Exit / Toggle Loop button
        InkWell(
          onTap: () => widget.manager.exitLoop(widget.deck),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: widget.isCompact ? 26 : 28,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: isLooping
                  ? Colors.redAccent.withAlpha(50)
                  : const Color(0xFF1A1F2C),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isLooping ? Colors.redAccent : Colors.white12,
              ),
            ),
            child: Center(
              child: Text(
                isLooping ? 'EXIT' : 'LOOP',
                style: TextStyle(
                  color: isLooping ? Colors.redAccent : Colors.white38,
                  fontSize: 7.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- 3. 3-BAND EQ & FILTER TAB ---
  Widget _buildEqTab() {
    final isDeckA = widget.deck == ActiveDeck.deckA;
    final low = isDeckA ? widget.manager.eqLowA : widget.manager.eqLowB;
    final mid = isDeckA ? widget.manager.eqMidA : widget.manager.eqMidB;
    final high = isDeckA ? widget.manager.eqHighA : widget.manager.eqHighB;
    final filter = isDeckA ? widget.manager.filterA : widget.manager.filterB;
    final isBassKilled = isDeckA ? widget.manager.isBassKilledA : widget.manager.isBassKilledB;
    final isMidKilled = isDeckA ? widget.manager.isMidKilledA : widget.manager.isMidKilledB;
    final isHighKilled = isDeckA ? widget.manager.isHighKilledA : widget.manager.isHighKilledB;
    final isModified = low != 1.0 || mid != 1.0 || high != 1.0 || filter != 0.0 || isBassKilled || isMidKilled || isHighKilled;

    return Row(
      children: [
        // 1. LOW (เบส) - with instant Kill Bass switch
        _buildMiniEqSlider(
          name: 'LOW (เบส)',
          val: low,
          isKilled: isBassKilled,
          labelColor: const Color(0xFFFF9100),
          onToggleKill: () => widget.manager.toggleKillBass(widget.deck),
          onChanged: (v) => widget.manager.setEQ(widget.deck, low: v),
        ),

        const SizedBox(width: 4),

        // 2. MID (กลาง) - with instant Kill Mid/Vocals switch
        _buildMiniEqSlider(
          name: 'MID (กลาง)',
          val: mid,
          isKilled: isMidKilled,
          labelColor: const Color(0xFF00E676),
          onToggleKill: () => widget.manager.toggleKillMid(widget.deck),
          onChanged: (v) => widget.manager.setEQ(widget.deck, mid: v),
        ),

        const SizedBox(width: 4),

        // 3. HIGH (แหลม) - with instant Kill High/Hi-Hat switch
        _buildMiniEqSlider(
          name: 'HIGH (แหลม)',
          val: high,
          isKilled: isHighKilled,
          labelColor: const Color(0xFF00F2FE),
          onToggleKill: () => widget.manager.toggleKillHigh(widget.deck),
          onChanged: (v) => widget.manager.setEQ(widget.deck, high: v),
        ),

        const SizedBox(width: 4),

        // 4. Filter Slider (LPF <-> HPF)
        Expanded(
          flex: 4,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('LPF', style: TextStyle(color: Colors.cyanAccent, fontSize: 6.5, fontWeight: FontWeight.bold)),
                  Text(
                    filter == 0.0 ? 'FILTER' : (filter < 0 ? 'LPF ${(filter.abs() * 100).toInt()}%' : 'HPF ${(filter * 100).toInt()}%'),
                    style: const TextStyle(color: Colors.white54, fontSize: 6.5),
                  ),
                  const Text('HPF', style: TextStyle(color: Colors.amberAccent, fontSize: 6.5, fontWeight: FontWeight.bold)),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2.0,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 3.5),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 6),
                  activeTrackColor: widget.accentColor,
                  inactiveTrackColor: Colors.white12,
                  thumbColor: Colors.white,
                ),
                child: Slider(
                  value: filter,
                  min: -1.0,
                  max: 1.0,
                  onChanged: (v) => widget.manager.setFilter(widget.deck, v),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 4),

        // 5. RESET EQ Button
        Tooltip(
          message: 'รีเซ็ต EQ (เบส, กลาง, แหลม, ฟิลเตอร์) ทั้งหมดกลับเป็น 100% Flat',
          child: InkWell(
            onTap: () => widget.manager.resetEQ(widget.deck),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: widget.isCompact ? 28 : 34,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: isModified ? Colors.amber.withAlpha(35) : const Color(0xFF181C28),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isModified ? Colors.amberAccent : Colors.white24,
                  width: isModified ? 1 : 0.8,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.restart_alt,
                    size: 11,
                    color: isModified ? Colors.amberAccent : Colors.white60,
                  ),
                  Text(
                    'RESET',
                    style: TextStyle(
                      color: isModified ? Colors.amberAccent : Colors.white54,
                      fontSize: 6.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMiniEqSlider({
    required String name,
    required double val,
    required bool isKilled,
    required Color labelColor,
    required VoidCallback onToggleKill,
    required ValueChanged<double> onChanged,
  }) {
    final int percent = isKilled ? 0 : (val * 100).toInt();

    return Expanded(
      flex: 3,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Instant Kill frequency button
              Tooltip(
                message: 'ตัดเสียง $name ออกทันที (Kill switch)',
                child: InkWell(
                  onTap: onToggleKill,
                  borderRadius: BorderRadius.circular(3),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
                    decoration: BoxDecoration(
                      color: isKilled ? const Color(0xFFFF0055) : const Color(0xFF1E2435),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: isKilled ? Colors.white : Colors.white24,
                        width: 0.6,
                      ),
                    ),
                    child: Text(
                      isKilled ? 'CUT' : 'KILL',
                      style: TextStyle(
                        color: isKilled ? Colors.white : Colors.white54,
                        fontSize: 5.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 3),
              Text(
                name,
                style: TextStyle(
                  color: isKilled ? const Color(0xFFFF0055) : labelColor,
                  fontSize: 6.5,
                  fontWeight: FontWeight.bold,
                  decoration: isKilled ? TextDecoration.lineThrough : null,
                ),
              ),
              const SizedBox(width: 2),
              Text(
                isKilled ? 'CUT' : '$percent%',
                style: TextStyle(
                  color: isKilled ? const Color(0xFFFF0055) : Colors.white38,
                  fontSize: 6.0,
                  fontWeight: isKilled ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.0,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 3.0),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 5),
              activeTrackColor: isKilled ? Colors.grey : labelColor,
              inactiveTrackColor: Colors.white12,
              thumbColor: isKilled ? Colors.grey : labelColor,
            ),
            child: Slider(
              value: isKilled ? 0.0 : val,
              min: 0.0,
              max: 1.5,
              onChanged: (v) {
                if (isKilled) onToggleKill();
                onChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- 4. SAMPLER FX TAB ---
  Widget _buildSamplerTab() {
    final samples = [
      {'name': '📢 AIR HORN', 'id': 'airhorn', 'color': const Color(0xFFFF0055)},
      {'name': '🚨 SIREN', 'id': 'siren', 'color': const Color(0xFFFF9900)},
      {'name': '💿 SCRATCH', 'id': 'scratch', 'color': const Color(0xFF00F2FE)},
      {'name': '⚡ DROP', 'id': 'laser', 'color': const Color(0xFF00FF88)},
    ];

    return Row(
      children: samples.map((s) {
        final color = s['color'] as Color;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: InkWell(
              onTap: () => widget.manager.playSample(s['id'] as String),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                height: widget.isCompact ? 26 : 28,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color.withAlpha(70), color.withAlpha(25)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: color.withAlpha(150), width: 0.8),
                ),
                child: Center(
                  child: Text(
                    s['name'] as String,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 7.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
