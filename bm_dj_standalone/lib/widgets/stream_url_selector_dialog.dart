import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controllers/dj_deck_manager.dart';
import '../models/track.dart';
import '../services/api_service.dart';

class StreamUrlSelectorDialog extends StatefulWidget {
  final ActiveDeck deck;
  final DJDeckManager manager;

  const StreamUrlSelectorDialog({
    super.key,
    required this.deck,
    required this.manager,
  });

  static Future<void> show(
    BuildContext context, {
    required ActiveDeck deck,
    required DJDeckManager manager,
  }) {
    return showDialog(
      context: context,
      builder: (_) => StreamUrlSelectorDialog(deck: deck, manager: manager),
    );
  }

  @override
  State<StreamUrlSelectorDialog> createState() => _StreamUrlSelectorDialogState();
}

class _StreamUrlSelectorDialogState extends State<StreamUrlSelectorDialog> {
  bool _isRefreshing = false;

  Track? get _track =>
      widget.deck == ActiveDeck.deckA ? widget.manager.trackA : widget.manager.trackB;

  Future<void> _refreshCandidates() async {
    final t = _track;
    if (t == null) return;
    setState(() => _isRefreshing = true);
    await LocalAudioProxy.prewarm(t.videoId, forceRefresh: true);
    await LocalAudioProxy.probeAllCandidates(t.videoId);
    if (mounted) {
      setState(() => _isRefreshing = false);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'ok':
        return Colors.greenAccent;
      case 'partial':
        return Colors.orangeAccent;
      case 'failed':
        return Colors.redAccent;
      case 'probing':
        return const Color(0xFF00F2FE);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDeckA = widget.deck == ActiveDeck.deckA;
    final deckLabel = isDeckA ? 'DECK A' : 'DECK B';
    final accentColor = isDeckA ? const Color(0xFF00F2FE) : const Color(0xFFFF2A85);

    return ListenableBuilder(
      listenable: Listenable.merge([widget.manager, StreamDiagnosticLogger.instance]),
      builder: (context, _) {
        final track = _track;
        final candidates = track != null
            ? LocalAudioProxy.getCandidatesFor(track.videoId)
            : const <StreamCandidate>[];
        final selectedIdx = track != null ? LocalAudioProxy.getSelectedIndex(track.videoId) : 0;
        final logger = StreamDiagnosticLogger.instance;
        final deckError = isDeckA ? logger.deckALastError : logger.deckBLastError;

        return Dialog(
          backgroundColor: const Color(0xFF0F131D),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: accentColor.withAlpha(150), width: 1.5),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920, maxHeight: 720),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: accentColor.withAlpha(40),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: accentColor),
                        ),
                        child: Text(
                          '$deckLabel • ตัวเลือก URL & วินิจฉัย Error',
                          style: TextStyle(
                            color: accentColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          track != null
                              ? '${track.title} (${track.videoId})'
                              : 'ยังไม่ได้โหลดเพลงลงใน $deckLabel',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (track != null)
                        OutlinedButton.icon(
                          onPressed: _isRefreshing ? null : _refreshCandidates,
                          icon: _isRefreshing
                              ? const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh, size: 15),
                          label: const Text('ดึง & ทดสอบทุก URL ใหม่', style: TextStyle(fontSize: 11)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF00F2FE),
                            side: const BorderSide(color: Color(0xFF00F2FE)),
                          ),
                        ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () {
                          final report = logger.buildDiagnosticReport(
                            videoIdA: widget.manager.trackA?.videoId,
                            videoIdB: widget.manager.trackB?.videoId,
                          );
                          Clipboard.setData(ClipboardData(text: report));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                '📋 คัดลอกรายงาน URL และ Error ทั้งหมดแล้ว! นำไปวางส่งให้ AI ได้เลยครับ',
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_all, size: 15),
                        label: const Text(
                          'คัดลอก Error ทั้งหมดส่งให้ AI',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF9100),
                          foregroundColor: Colors.black,
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, color: Colors.white70),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Active Deck Error Banner if any
                  if (deckError != null && deckError.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.withAlpha(40),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.redAccent),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SelectableText(
                              'Error ล่าสุดบน $deckLabel: $deckError',
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: deckError));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('คัดลอกข้อความ Error แล้ว')),
                              );
                            },
                            icon: const Icon(Icons.copy, size: 13, color: Colors.white),
                            label: const Text('คัดลอก', style: TextStyle(color: Colors.white, fontSize: 11)),
                          ),
                        ],
                      ),
                    ),

                  // Upper Half: Candidate URL Selector List
                  const Text(
                    '1. รายการ URL สตรีมทั้งหมดที่ตรวจพบ (กดเลือกปุ่มสีฟ้า/เขียวเพื่อสลับทดสอบเล่นได้ทันที):',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),

                  Expanded(
                    flex: 6,
                    child: candidates.isEmpty
                        ? Center(
                            child: Text(
                              track == null
                                  ? 'กรุณาเลือกเพลงเข้า $deckLabel ก่อน เพื่อดูตัวเลือก URL ทั้งหมด'
                                  : 'กำลังค้นหา URL สตรีมสำหรับเพลงนี้... กดปุ่ม "ดึง & ทดสอบทุก URL ใหม่" ด้านบนได้ครับ',
                              style: const TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                          )
                        : ListView.separated(
                            itemCount: candidates.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 6),
                            itemBuilder: (context, index) {
                              final c = candidates[index];
                              final isSelected = index == selectedIdx;
                              final sColor = _statusColor(c.status);

                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? accentColor.withAlpha(30)
                                      : const Color(0xFF161B28),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSelected ? accentColor : sColor.withAlpha(100),
                                    width: isSelected ? 1.8 : 1.0,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: sColor,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            c.shortLabel,
                                            style: TextStyle(
                                              color: isSelected ? accentColor : Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12.5,
                                            ),
                                          ),
                                        ),
                                        // Test Probe button
                                        OutlinedButton.icon(
                                          onPressed: () => LocalAudioProxy.probeCandidate(c),
                                          icon: const Icon(Icons.network_check, size: 13),
                                          label: const Text('เช็กสถานะ', style: TextStyle(fontSize: 10.5)),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.white70,
                                            side: const BorderSide(color: Colors.white24),
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            minimumSize: const Size(0, 26),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        // Play with this URL button
                                        ElevatedButton.icon(
                                          onPressed: () {
                                            widget.manager.switchStreamCandidate(
                                              widget.deck,
                                              index,
                                              autoPlay: true,
                                            );
                                          },
                                          icon: Icon(
                                            isSelected ? Icons.replay : Icons.play_arrow,
                                            size: 15,
                                          ),
                                          label: Text(
                                            isSelected ? 'กำลังใช้อันนี้ (กดเล่นซ้ำ)' : 'กดเล่นด้วย URL นี้',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: isSelected ? accentColor : Colors.greenAccent,
                                            foregroundColor: Colors.black,
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            minimumSize: const Size(0, 28),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${c.detailLabel}  |  ${c.statusDetail}',
                                      style: TextStyle(
                                        color: sColor,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (c.lastPlaybackError != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 3),
                                        child: SelectableText(
                                          '❗ Error ตอนสั่งเล่น URL นี้: ${c.lastPlaybackError}',
                                          style: const TextStyle(
                                            color: Colors.redAccent,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    const SizedBox(height: 2),
                                    SelectableText(
                                      'Playback URL: ${c.playbackUrl}',
                                      style: TextStyle(color: Colors.grey[400], fontSize: 10),
                                      maxLines: 1,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),

                  const SizedBox(height: 10),

                  // Lower Half: Verbose Real-Time Error & Event Log
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '2. บันทึกการทำงานและ Error แบบละเอียด (Real-Time Diagnostic Log):',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => logger.clearAll(),
                        icon: const Icon(Icons.delete_sweep, size: 14, color: Colors.grey),
                        label: const Text('ล้างประวัติ Log', style: TextStyle(color: Colors.grey, fontSize: 11)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  Expanded(
                    flex: 5,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF080A0F),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: logger.logs.isEmpty
                          ? const Center(
                              child: Text(
                                'ยังไม่มีบันทึกเหตุการณ์',
                                style: TextStyle(color: Colors.grey, fontSize: 11),
                              ),
                            )
                          : ListView.builder(
                              itemCount: logger.logs.length,
                              itemBuilder: (context, index) {
                                final log = logger.logs[index];
                                Color logColor = Colors.white70;
                                if (log.level == 'ERROR') {
                                  logColor = Colors.redAccent;
                                } else if (log.level == 'WARN') {
                                  logColor = Colors.orangeAccent;
                                } else if (log.level == 'SUCCESS') {
                                  logColor = Colors.greenAccent;
                                }

                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2.5),
                                  child: SelectableText(
                                    log.toString(),
                                    style: TextStyle(
                                      color: logColor,
                                      fontSize: 10.5,
                                      fontFamily: 'Consolas',
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

