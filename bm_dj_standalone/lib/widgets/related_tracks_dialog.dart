import 'package:flutter/material.dart';
import '../controllers/dj_deck_manager.dart';
import '../models/track.dart';
import '../services/api_service.dart';
import 'channel_view_dialog.dart';

class RelatedTracksDialog extends StatefulWidget {
  final Track seedTrack;
  final DJDeckManager manager;
  final String source;

  const RelatedTracksDialog({
    super.key,
    required this.seedTrack,
    required this.manager,
    this.source = 'youtube',
  });

  static Future<void> show(
    BuildContext context, {
    required Track seedTrack,
    required DJDeckManager manager,
    String source = 'youtube',
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => RelatedTracksDialog(
        seedTrack: seedTrack,
        manager: manager,
        source: source,
      ),
    );
  }

  @override
  State<RelatedTracksDialog> createState() => _RelatedTracksDialogState();
}

class _RelatedTracksDialogState extends State<RelatedTracksDialog> {
  bool _isLoading = true;
  List<Track> _relatedTracks = [];

  @override
  void initState() {
    super.initState();
    _fetchRelated();
  }

  Future<void> _fetchRelated() async {
    setState(() => _isLoading = true);
    final results = await ApiService.getRelatedTracks(
      widget.seedTrack.videoId,
      source: widget.source,
      title: widget.seedTrack.title,
    );

    if (mounted) {
      setState(() {
        _relatedTracks = results;
        _isLoading = false;
      });
    }
  }

  void _loadDeck(ActiveDeck deck, Track track) {
    widget.manager.loadTrackToDeck(deck, track);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('ใส่ "${track.title}" ใน ${deck == ActiveDeck.deckA ? 'Deck A' : 'Deck B'} สำเร็จ'),
        backgroundColor: const Color(0xFF202738),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _addToQueue(Track track) {
    widget.manager.addToQueue(track);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('เพิ่ม "${track.title}" ลงใน Queue สำเร็จ'),
        backgroundColor: const Color(0xFF202738),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _addAllToQueue() {
    for (final track in _relatedTracks) {
      widget.manager.addToQueue(track);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('เพิ่ม ${_relatedTracks.length} เพลงที่เกี่ยวข้องลงใน Queue แล้ว!'),
        backgroundColor: const Color(0xFF0072FF),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isYtMusic = widget.source == 'ytmusic';
    final accentColor = isYtMusic ? const Color(0xFFFF0033) : const Color(0xFFFF0000);

    return Dialog(
      backgroundColor: const Color(0xFF10131B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: accentColor.withAlpha(90), width: 1.2),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 660),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: Seed track details
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: Color(0xFF161A26),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(bottom: BorderSide(color: Colors.white12)),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      width: 52,
                      height: 38,
                      color: const Color(0xFF22283A),
                      child: widget.seedTrack.thumbnailUrl != null
                          ? Image.network(
                              widget.seedTrack.thumbnailUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => const Icon(Icons.music_note, color: Colors.white24),
                            )
                          : const Icon(Icons.music_note, color: Colors.white24),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.auto_awesome, color: Colors.amberAccent, size: 14),
                            const SizedBox(width: 5),
                            const Text(
                              'วิดีโอ & เพลงที่เกี่ยวข้อง (Related / Up Next)',
                              style: TextStyle(
                                color: Colors.amberAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        SelectableText(
                          widget.seedTrack.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            height: 1.25,
                          ),
                          maxLines: 2,
                        ),
                        Text(
                          widget.seedTrack.artist,
                          style: TextStyle(color: Colors.grey[400], fontSize: 10),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
            ),

            // Sub-toolbar
            if (!_isLoading && _relatedTracks.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                color: const Color(0xFF131722),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'คำแนะนำจาก ${isYtMusic ? 'YouTube Music' : 'YouTube'} (${_relatedTracks.length} เพลง)',
                      style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    ElevatedButton.icon(
                      onPressed: _addAllToQueue,
                      icon: const Icon(Icons.playlist_add, size: 14),
                      label: const Text('ใส่ทั้งหมดลง Queue', style: TextStyle(fontSize: 10.5)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0072FF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: const Size(0, 28),
                      ),
                    ),
                  ],
                ),
              ),

            // Content List
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(strokeWidth: 2.5),
                          SizedBox(height: 12),
                          Text('กำลังค้นหาวิดีโอที่เกี่ยวข้อง...', style: TextStyle(color: Colors.white60)),
                        ],
                      ),
                    )
                  : _relatedTracks.isEmpty
                      ? const Center(
                          child: Text(
                            'ไม่พบวิดีโอที่เกี่ยวข้องเพิ่มเติม',
                            style: TextStyle(color: Colors.white54),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _relatedTracks.length,
                          separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 1),
                          itemBuilder: (context, index) {
                            final track = _relatedTracks[index];
                            return Container(
                              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                              child: Row(
                                children: [
                                  // Index
                                  SizedBox(
                                    width: 24,
                                    child: Text(
                                      '${index + 1}',
                                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Thumbnail
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Container(
                                      width: 52,
                                      height: 38,
                                      color: const Color(0xFF1E2433),
                                      child: Image.network(
                                        track.displayThumbnailUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) => Image.network(
                                          'https://i.ytimg.com/vi/${track.videoId}/hqdefault.jpg',
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => Image.network(
                                            'https://i.ytimg.com/vi/${track.videoId}/mqdefault.jpg',
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error, stackTrace) => const Icon(
                                              Icons.music_note,
                                              color: Colors.white24,
                                              size: 20,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Title & Artist
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        SelectableText(
                                          track.title,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12.2,
                                            fontWeight: FontWeight.bold,
                                            height: 1.25,
                                          ),
                                          maxLines: 2,
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Text(
                                              track.formattedDuration,
                                              style: const TextStyle(color: Colors.white54, fontSize: 10),
                                            ),
                                            const SizedBox(width: 6),
                                            // Clickable Artist name
                                            InkWell(
                                              onTap: () {
                                                ChannelViewDialog.show(
                                                  context,
                                                  channelId: track.channelId,
                                                  name: track.artist,
                                                  source: track.source,
                                                  manager: widget.manager,
                                                );
                                              },
                                              child: Text(
                                                track.artist,
                                                style: const TextStyle(
                                                  color: Color(0xFF00F2FE),
                                                  fontSize: 10,
                                                  decoration: TextDecoration.underline,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Load Deck A
                                  OutlinedButton(
                                    onPressed: () => _loadDeck(ActiveDeck.deckA, track),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF00F2FE),
                                      side: const BorderSide(color: Color(0xFF00F2FE)),
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      minimumSize: const Size(0, 26),
                                    ),
                                    child: const Text('▶ 1', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(width: 5),

                                  // Load Deck B
                                  OutlinedButton(
                                    onPressed: () => _loadDeck(ActiveDeck.deckB, track),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFFFF2A85),
                                      side: const BorderSide(color: Color(0xFFFF2A85)),
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      minimumSize: const Size(0, 26),
                                    ),
                                    child: const Text('▶ 2', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(width: 5),

                                  // Add to Queue
                                  IconButton(
                                    tooltip: 'เพิ่มใน Queue',
                                    onPressed: () => _addToQueue(track),
                                    icon: const Icon(Icons.add, color: Colors.white70, size: 18),
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.all(4),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
