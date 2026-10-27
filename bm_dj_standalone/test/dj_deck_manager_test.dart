import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:bm_dj/controllers/dj_deck_manager.dart';
import 'package:bm_dj/models/track.dart';
import 'package:bm_dj/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    ApiService.isTestMode = true;
  });

  group('DJDeckManager Equal-Power & Dual Audio Engine Tests', () {
    test('Initial deck state verification', () {
      final manager = DJDeckManager();

      expect(manager.isDeckAPlaying, isTrue);
      expect(manager.isTransitioning, isFalse);
      expect(manager.crossfadePosition, equals(0.0));
      expect(manager.deckA.volume, equals(1.0));
      expect(manager.deckB.volume, equals(0.0));
      expect(manager.queue, isEmpty);

      manager.dispose();
    });

    test('Equal-Power Crossfade Math calculation', () {
      const double t = 0.5;
      final double volA = math.cos(t * (math.pi / 2));
      final double volB = math.sin(t * (math.pi / 2));

      expect(volA, closeTo(0.7071, 0.001));
      expect(volB, closeTo(0.7071, 0.001));
      expect((volA * volA) + (volB * volB), closeTo(1.0, 0.001));
    });

    test('Queue addition and track assignment', () async {
      final manager = DJDeckManager();

      final track1 = Track(
        videoId: 'abc12345678',
        title: 'Song 1',
        artist: 'Artist 1',
        durationSeconds: 180,
      );

      final track2 = Track(
        videoId: 'xyz87654321',
        title: 'Song 2',
        artist: 'Artist 2',
        durationSeconds: 210,
      );

      manager.addToQueue(track1);
      manager.addToQueue(track2);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(manager.trackA, isNotNull);
      expect(manager.trackB, isNotNull);

      manager.dispose();
    });

    test('Key Lock and Speed setting', () async {
      final manager = DJDeckManager();

      expect(manager.keyLockEnabled, isTrue);
      await manager.setPlaybackSpeed(1.25, deck: ActiveDeck.deckA);
      expect(manager.speedDeckA, equals(1.25));

      manager.dispose();
    });

    test('Low-Spec Mode toggle verification', () {
      final manager = DJDeckManager();

      expect(manager.lowSpecMode, isFalse);
      manager.toggleLowSpecMode();
      expect(manager.lowSpecMode, isTrue);
      manager.toggleLowSpecMode();
      expect(manager.lowSpecMode, isFalse);

      manager.dispose();
    });
  });
}
