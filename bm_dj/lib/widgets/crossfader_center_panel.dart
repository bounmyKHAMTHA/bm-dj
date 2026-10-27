import 'package:flutter/material.dart';
import '../controllers/dj_deck_manager.dart';

class CrossfaderCenterPanel extends StatelessWidget {
  final DJDeckManager manager;

  const CrossfaderCenterPanel({
    super.key,
    required this.manager,
  });

  @override
  Widget build(BuildContext context) {
    const colorA = Color(0xFF00F2FE);
    const colorB = Color(0xFFFF2A85);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF141722),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // BPM & SYNC Header (Interactive DJ controls)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 1. BPM display with TAP button (Left)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Text(
                      '${(manager.isDeckAPlaying ? manager.bpmDeckA : manager.bpmDeckB).toStringAsFixed(1)} BPM',
                      style: const TextStyle(
                        color: Colors.amberAccent,
                        fontSize: 8.5,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                  InkWell(
                    onTap: () => manager.tapTempo(manager.isDeckAPlaying ? ActiveDeck.deckA : ActiveDeck.deckB),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: Colors.amber.withAlpha(30),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.amber.withAlpha(120), width: 0.8),
                      ),
                      child: const Text('TAP', style: TextStyle(color: Colors.amberAccent, fontSize: 7.5, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),

              // 2. Auto-DJ & SYNC (Right)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Auto-DJ Endless Nonstop Toggle Pill
                  Tooltip(
                    message: manager.autoQueueEnabled
                        ? 'Auto-DJ: เปิดอยู่ (เมื่อจบเพลงจะเติมเพลงแนะนำเข้าคิวและสลับให้อัตโนมัติ)'
                        : 'Auto-DJ: ปิดอยู่ (คลิกเพื่อเปิดระบบเล่นเพลงต่อเนื่องอัตโนมัติ)',
                    child: InkWell(
                      onTap: () => manager.toggleAutoQueue(),
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: manager.autoQueueEnabled
                              ? const Color(0xFFFF0033).withAlpha(50)
                              : Colors.white10,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: manager.autoQueueEnabled
                                ? const Color(0xFFFF0033)
                                : Colors.white24,
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 9,
                              color: manager.autoQueueEnabled
                                  ? const Color(0xFFFF4066)
                                  : Colors.white38,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'AUTO-DJ',
                              style: TextStyle(
                                color: manager.autoQueueEnabled ? Colors.white : Colors.white38,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),

                  // SYNC Button (Matches BPM & aligns beat phase!)
                  Tooltip(
                    message: 'SYNC: ซิงค์ความเร็ว BPM และจังหวะกลองของทั้ง 2 Deck ให้ตรงกันเป๊ะ',
                    child: InkWell(
                      onTap: () => manager.syncDecks(),
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF0072FF), Color(0xFF00F2FE)]),
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(color: const Color(0xFF00F2FE).withAlpha(80), blurRadius: 4),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.sync, size: 9, color: Colors.black),
                            SizedBox(width: 2),
                            Text(
                              'SYNC',
                              style: TextStyle(color: Colors.black, fontSize: 8.5, fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 2),

          // Dual Vertical Volume Faders (YouDJ Mixer style)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Deck A Volume Fader
              Column(
                children: [
                  Text('VOL A ${(manager.volumeGainA * 100).toInt()}%', style: const TextStyle(color: colorA, fontSize: 8.0, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 1),
                  SizedBox(
                    height: 44,
                    child: RotatedBox(
                      quarterTurns: -1,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2.2,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4.5),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                          activeTrackColor: colorA,
                          inactiveTrackColor: Colors.white12,
                          thumbColor: colorA,
                        ),
                        child: Slider(
                          value: manager.volumeGainA,
                          min: 0.0,
                          max: 1.0,
                          onChanged: (val) => manager.setDeckGain(ActiveDeck.deckA, val),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // Center Action Buttons (Master Play, Play A+B, Smooth Skip)
              Column(
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Master Play/Pause
                      IconButton.filled(
                        tooltip: 'Master Play/Pause [Space]',
                        onPressed: () => manager.toggleMasterPlay(),
                        iconSize: 16,
                        icon: Icon(
                          (manager.deckA.playing || manager.deckB.playing)
                              ? Icons.pause
                              : Icons.play_arrow,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white12,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.all(4),
                        ),
                      ),
                      const SizedBox(width: 6),

                      // PLAY A+B Button (Like YouDJ)
                      ElevatedButton.icon(
                        onPressed: () => manager.playBoth(),
                        icon: const Icon(Icons.compare_arrows, size: 11),
                        label: const Text('PLAY A+B', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF202738),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          minimumSize: const Size(0, 22),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 3),

                  // Smooth Skip Button
                  SizedBox(
                    height: 21,
                    child: ElevatedButton.icon(
                      onPressed: manager.isTransitioning ? null : () => manager.executeSmoothSkip(),
                      icon: const Icon(Icons.fast_forward, size: 11, color: Colors.white),
                      label: Text(
                        manager.isTransitioning
                            ? 'FADING...'
                            : 'SMOOTH SKIP (${manager.transitionDurationSeconds}s)',
                        style: const TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0072FF),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                  ),
                ],
              ),

              // Deck B Volume Fader
              Column(
                children: [
                  Text('VOL B ${(manager.volumeGainB * 100).toInt()}%', style: const TextStyle(color: colorB, fontSize: 8.0, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 1),
                  SizedBox(
                    height: 44,
                    child: RotatedBox(
                      quarterTurns: -1,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2.2,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4.5),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                          activeTrackColor: colorB,
                          inactiveTrackColor: Colors.white12,
                          thumbColor: colorB,
                        ),
                        child: Slider(
                          value: manager.volumeGainB,
                          min: 0.0,
                          max: 1.0,
                          onChanged: (val) => manager.setDeckGain(ActiveDeck.deckB, val),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 3),

          // 3-Band EQ Mixer Strip for Deck A and Deck B (Middle Mixer)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Deck A EQ (HI, MID, LOW)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildMiniEqRow(
                      context: context,
                      label: 'HI',
                      value: manager.eqHighA,
                      isKilled: manager.isHighKilledA,
                      color: const Color(0xFF00F2FE),
                      onChanged: (val) => manager.setEQ(ActiveDeck.deckA, high: val),
                      onKillPressed: () => manager.toggleKillHigh(ActiveDeck.deckA),
                    ),
                    _buildMiniEqRow(
                      context: context,
                      label: 'MID',
                      value: manager.eqMidA,
                      isKilled: manager.isMidKilledA,
                      color: const Color(0xFF00E676),
                      onChanged: (val) => manager.setEQ(ActiveDeck.deckA, mid: val),
                      onKillPressed: () => manager.toggleKillMid(ActiveDeck.deckA),
                    ),
                    _buildMiniEqRow(
                      context: context,
                      label: 'LOW',
                      value: manager.eqLowA,
                      isKilled: manager.isBassKilledA,
                      color: const Color(0xFFFFB300),
                      onChanged: (val) => manager.setEQ(ActiveDeck.deckA, low: val),
                      onKillPressed: () => manager.toggleKillBass(ActiveDeck.deckA),
                    ),
                  ],
                ),

                // Center EQ Label & Reset All button
                Column(
                  children: [
                    const Text(
                      '🎛️ EQ',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 8.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Tooltip(
                      message: 'รีเซ็ต EQ ทั้งสอง Deck กลับเป็น 100% Flat',
                      child: InkWell(
                        onTap: () {
                          manager.resetEQ(ActiveDeck.deckA);
                          manager.resetEQ(ActiveDeck.deckB);
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.white24, width: 0.7),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.restart_alt, size: 9, color: Colors.white70),
                              SizedBox(width: 2),
                              Text('RESET', style: TextStyle(color: Colors.white70, fontSize: 7.5, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // Deck B EQ (HI, MID, LOW)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildMiniEqRow(
                      context: context,
                      label: 'HI',
                      value: manager.eqHighB,
                      isKilled: manager.isHighKilledB,
                      color: const Color(0xFF00F2FE),
                      onChanged: (val) => manager.setEQ(ActiveDeck.deckB, high: val),
                      onKillPressed: () => manager.toggleKillHigh(ActiveDeck.deckB),
                      isRightAligned: true,
                    ),
                    _buildMiniEqRow(
                      context: context,
                      label: 'MID',
                      value: manager.eqMidB,
                      isKilled: manager.isMidKilledB,
                      color: const Color(0xFF00E676),
                      onChanged: (val) => manager.setEQ(ActiveDeck.deckB, mid: val),
                      onKillPressed: () => manager.toggleKillMid(ActiveDeck.deckB),
                      isRightAligned: true,
                    ),
                    _buildMiniEqRow(
                      context: context,
                      label: 'LOW',
                      value: manager.eqLowB,
                      isKilled: manager.isBassKilledB,
                      color: const Color(0xFFFFB300),
                      onChanged: (val) => manager.setEQ(ActiveDeck.deckB, low: val),
                      onKillPressed: () => manager.toggleKillBass(ActiveDeck.deckB),
                      isRightAligned: true,
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 3),

          // Big Prominent Horizontal Crossfader (YouDJ Pro DJ Mixer style)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colorA.withAlpha(35),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: colorA.withAlpha(120), width: 1),
                ),
                child: const Text('DECK A', style: TextStyle(color: colorA, fontWeight: FontWeight.bold, fontSize: 9.5)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white24, width: 0.8),
                ),
                child: Text(
                  'CROSSFADER ${(manager.crossfadePosition * 100).toInt()}%',
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colorB.withAlpha(35),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: colorB.withAlpha(120), width: 1),
                ),
                child: const Text('DECK B', style: TextStyle(color: colorB, fontWeight: FontWeight.bold, fontSize: 9.5)),
              ),
            ],
          ),

          const SizedBox(height: 4),

          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 7.0, // Big thick track for clear visibility
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 11.0, // Much bigger knob for easy mouse click & drag
                elevation: 4.0,
                pressedElevation: 6.0,
              ),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18.0), // Large responsive click area
              activeTrackColor: colorA,
              inactiveTrackColor: colorB,
              thumbColor: Colors.white,
            ),
            child: Slider(
              value: manager.crossfadePosition,
              min: 0.0,
              max: 1.0,
              onChanged: (val) => manager.setManualCrossfader(val),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniEqRow({
    required BuildContext context,
    required String label,
    required double value,
    required bool isKilled,
    required Color color,
    required ValueChanged<double> onChanged,
    required VoidCallback onKillPressed,
    bool isRightAligned = false,
  }) {
    final killBtn = InkWell(
      onTap: onKillPressed,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: isKilled ? const Color(0xFFFF0033) : Colors.white10,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: isKilled ? const Color(0xFFFF0033) : Colors.white24,
            width: 0.6,
          ),
        ),
        child: Text(
          isKilled ? 'CUT' : label,
          style: TextStyle(
            color: isKilled ? Colors.white : color,
            fontSize: 7.5,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );

    final slider = SizedBox(
      width: 56,
      height: 14,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 2.0,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 3.5),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 6),
          activeTrackColor: isKilled ? Colors.grey : color,
          inactiveTrackColor: Colors.white12,
          thumbColor: isKilled ? Colors.grey : color,
        ),
        child: Slider(
          value: isKilled ? 0.0 : value.clamp(0.0, 1.5),
          min: 0.0,
          max: 1.5,
          onChanged: onChanged,
        ),
      ),
    );

    if (isRightAligned) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          slider,
          const SizedBox(width: 2),
          killBtn,
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        killBtn,
        const SizedBox(width: 2),
        slider,
      ],
    );
  }
}
