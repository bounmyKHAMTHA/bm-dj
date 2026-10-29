class Track {
  final String videoId;
  final String title;
  final String artist;
  final int durationSeconds;
  final String? thumbnailUrl;
  final String source; // 'youtube' or 'ytmusic'
  final String? channelId;
  final String? channelUrl;
  String? streamUrl;
  String? videoStreamUrl;
  bool isResolving;

  Duration get duration => Duration(seconds: durationSeconds);

  Track({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.durationSeconds,
    String? thumbnailUrl,
    this.source = 'youtube',
    this.channelId,
    this.channelUrl,
    this.streamUrl,
    this.videoStreamUrl,
    this.isResolving = false,
  }) : thumbnailUrl = (thumbnailUrl != null && thumbnailUrl.isNotEmpty && thumbnailUrl.startsWith('http'))
            ? thumbnailUrl
            : (videoId.isNotEmpty ? 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg' : null);

  bool get isYtMusic => source == 'ytmusic';
  bool get isYouTube => source != 'ytmusic';

  String get displayThumbnailUrl {
    final t = thumbnailUrl?.trim();
    if (t != null && t.isNotEmpty && t.startsWith('http')) {
      return t;
    }
    if (videoId.isNotEmpty) {
      return 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
    }
    return '';
  }

  String get formattedDuration {
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      videoId: json['video_id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Unknown Title',
      artist: json['artist']?.toString() ?? 'Unknown Artist',
      durationSeconds: (json['duration'] is num) ? (json['duration'] as num).toInt() : 0,
      thumbnailUrl: json['thumbnail']?.toString(),
      source: json['source']?.toString() ?? 'youtube',
      channelId: json['channel_id']?.toString(),
      channelUrl: json['channel_url']?.toString(),
      streamUrl: json['stream_url']?.toString(),
      videoStreamUrl: json['video_stream_url']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'video_id': videoId,
      'title': title,
      'artist': artist,
      'duration': durationSeconds,
      'thumbnail': thumbnailUrl,
      'source': source,
      'channel_id': channelId,
      'channel_url': channelUrl,
      'stream_url': streamUrl,
      'video_stream_url': videoStreamUrl,
    };
  }

  Track copyWith({
    String? videoId,
    String? title,
    String? artist,
    int? durationSeconds,
    String? thumbnailUrl,
    String? source,
    String? channelId,
    String? channelUrl,
    String? streamUrl,
    String? videoStreamUrl,
    bool? isResolving,
  }) {
    return Track(
      videoId: videoId ?? this.videoId,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      source: source ?? this.source,
      channelId: channelId ?? this.channelId,
      channelUrl: channelUrl ?? this.channelUrl,
      streamUrl: streamUrl ?? this.streamUrl,
      videoStreamUrl: videoStreamUrl ?? this.videoStreamUrl,
      isResolving: isResolving ?? this.isResolving,
    );
  }
}
