import 'package:flutter/material.dart';
import '../controllers/dj_deck_manager.dart';
import '../models/track.dart';
import '../services/api_service.dart';

class ChannelViewDialog extends StatefulWidget {
  final String? channelId;
  final String name;
  final String source;
  final DJDeckManager manager;

  const ChannelViewDialog({
    super.key,
    this.channelId,
    required this.name,
    this.source = 'youtube',
    required this.manager,
  });

  static Future<void> show(
    BuildContext context, {
    String? channelId,
    required String name,
    String source = 'youtube',
    required DJDeckManager manager,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => ChannelViewDialog(
        channelId: channelId,
        name: name,
        source: source,
        manager: manager,
      ),
    );
  }

  @override
  State<ChannelViewDialog> createState() => _ChannelViewDialogState();
}

class _ChannelViewDialogState extends State<ChannelViewDialog> {
  bool _isLoading = true;
  String _channelName = '';
  String? _thumbnail;
  String? _subscribers;
  List<Track> _tracks = [];

  @override
  void initState() {
    super.initState();
    _channelName = widget.name;
    _fetchChannelDetails();
  }

  Future<void> _fetchChannelDetails() async {
    setState(() => _isLoading = true);
    final data = await ApiService.getChannelDetails(
      channelId: widget.channelId,
      name: widget.name,
      source: widget.source,
    );

    if (mounted) {
      setState(() {
        _channelName = data['name'] ?? widget.name;
        _thumbnail = data['thumbnail'];
        final rawTracks = data['tracks'];
        if (rawTracks is List) {
          _tracks = rawTracks.whereType<Track>().toList();
        } else {
          _tracks = [];
        }
        _isLoading = false;
      });
    }
  }

  void _loadDeck(ActiveDeck deck, Track track) {
    widget.manager.loadTrackToDeck(deck, track);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('ใส่เพลง "${track.title}" ใน ${deck == ActiveDeck.deckA ? 'Deck A' : 'Deck B'} สำเร็จ'),
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
    for (final track in _tracks) {
      widget.manager.addToQueue(track);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('เพิ่ม ${_tracks.length} เพลงจากช่อง "$_channelName" ลงใน Queue แล้ว!'),
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
        side: BorderSide(color: accentColor.withAlpha(80), width: 1.2),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 680),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Channel Header Bar
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF161A26),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                border: const Border(bottom: BorderSide(color: Colors.white12)),
              ),
              child: Row(
                children: [
                  // Channel Avatar
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: accentColor, width: 2),
                      color: const Color(0xFF22283A),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _thumbnail != null
                        ? Image.network(
                            _thumbnail!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Icon(
                              isYtMusic ? Icons.album : Icons.play_circle_fill,
                              color: accentColor,
                              size: 32,
                            ),
                          )
                        : Icon(
                            isYtMusic ? Icons.album : Icons.play_circle_fill,
                            color: accentColor,
                            size: 32,
                          ),
                  ),
                  const SizedBox(width: 14),

                  // Channel Name, Badge & Subscribers
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                _channelName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(Icons.check_circle, color: accentColor, size: 15),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: accentColor.withAlpha(35),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: accentColor.withAlpha(120), width: 0.8),
                              ),
                              child: Text(
                                isYtMusic ? 'YT MUSIC ARTIST' : 'YOUTUBE CHANNEL',
                                style: TextStyle(
                                  color: accentColor,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        if (_subscribers != null && _subscribers!.isNotEmpty)
                          Text(
                            _subscribers!,
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                          )
                        else
                          Text(
                            'ช่องผู้อัปโหลดบน ${isYtMusic ? 'YouTube Music' : 'YouTube'}',
                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                      ],
                    ),
                  ),

                  // Close Button
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
            ),

            // Action toolbar (Add all to queue, etc.)
            if (!_isLoading && _tracks.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: const Color(0xFF131722),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'รายการวิดีโอ & เพลงทั้งหมด (${_tracks.length} รายการ)',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _addAllToQueue,
                      icon: const Icon(Icons.playlist_add, size: 15),
                      label: const Text('ใส่ทั้งหมดลง Queue', style: TextStyle(fontSize: 11)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0072FF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: const Size(0, 30),
                      ),
                    ),
                  ],
                ),
              ),

            // Tracks List / Loading State
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(strokeWidth: 2.5),
                          SizedBox(height: 12),
                          Text('กำลังโหลดรายการเพลงจากช่อง...', style: TextStyle(color: Colors.white60)),
                        ],
                      ),
                    )
                  : _tracks.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.video_library_outlined, size: 40, color: Colors.white24),
                              const SizedBox(height: 8),
                              const Text(
                                'ไม่พบรายการวิดีโอในช่องนี้',
                                style: TextStyle(color: Colors.white54, fontSize: 13),
                              ),
                              const SizedBox(height: 10),
                              ElevatedButton.icon(
                                onPressed: _fetchChannelDetails,
                                icon: const Icon(Icons.refresh, size: 14),
                                label: const Text('ลองโหลดใหม่'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF161A26),
                                  foregroundColor: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _tracks.length,
                          separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 1),
                          itemBuilder: (context, index) {
                            final track = _tracks[index];
                            return Container(
                              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                              child: Row(
                                children: [
                                  // Index
                                  SizedBox(
                                    width: 26,
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

                                  // Title & Duration
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
                                            const SizedBox(width: 8),
                                            Text(
                                              track.artist,
                                              style: TextStyle(color: Colors.grey[400], fontSize: 10),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Play into Deck A
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

                                  // Play into Deck B
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
