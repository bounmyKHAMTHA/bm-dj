import 'dart:io';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() async {
  final yt = YoutubeExplode();
  final videoId = 'dQw4w9WgXcQ';
  print('Testing stream resolution for videoId: $videoId');

  print('--- Testing YoutubeApiClient.androidSdkless ---');
  try {
    final manifest = await yt.videos.streamsClient.getManifest(
      videoId,
      ytClients: [YoutubeApiClient.androidSdkless],
    ).timeout(Duration(seconds: 8));
    print('Manifest fetched successfully. audioOnly: ${manifest.audioOnly.length}, muxed: ${manifest.muxed.length}');
    for (final s in manifest.audioOnly) {
      print('  Audio stream: ${s.container.name}, ${s.bitrate}, url: ${s.url.toString().substring(0, 60)}...');
      // test probe
      final client = HttpClient();
      final req = await client.getUrl(s.url);
      req.headers.set('User-Agent', 'com.google.android.youtube/19.05.36 (Linux; U; Android 11; US) gzip');
      req.headers.set('Range', 'bytes=0-100');
      final res = await req.close();
      print('  -> Probe status: ${res.statusCode}');
      client.close();
    }
  } catch (e, st) {
    print('androidSdkless failed: $e');
  }

  print('--- Testing default client ---');
  try {
    final manifest = await yt.videos.streamsClient.getManifest(videoId).timeout(Duration(seconds: 8));
    print('Default manifest fetched. audioOnly: ${manifest.audioOnly.length}');
    for (final s in manifest.audioOnly) {
      print('  Audio stream: ${s.container.name}, ${s.bitrate}, url: ${s.url.toString().substring(0, 60)}...');
      final client = HttpClient();
      final req = await client.getUrl(s.url);
      req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36');
      req.headers.set('Range', 'bytes=0-100');
      final res = await req.close();
      print('  -> Probe status: ${res.statusCode}');
      client.close();
    }
  } catch (e) {
    print('Default client failed: $e');
  }

  yt.close();
}
