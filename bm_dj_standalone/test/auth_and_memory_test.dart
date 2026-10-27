import 'package:flutter_test/flutter_test.dart';
import 'package:bm_dj/models/user_account.dart';
import 'package:bm_dj/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserAccount Model & Memories Tests', () {
    test('UserAccount.fromJson correctly parses memories, search history, and liked songs', () {
      final json = {
        'user': {
          'id': 101,
          'username': 'dj_master',
          'email': 'dj@example.com',
        },
        'memories': {
          'search_history': ['dj remix', 'alan walker', 'สายย่อ'],
          'liked_tracks': [
            {
              'video_id': 'vid1',
              'title': 'Track 1',
              'artist': 'Artist 1',
              'duration': 210,
              'thumbnail': 'https://example.com/thumb1.jpg',
            }
          ],
          'queue': [
            {
              'video_id': 'vid2',
              'title': 'Track 2',
              'artist': 'Artist 2',
              'duration': 180,
            }
          ],
          'settings': {
            'lowSpecMode': true,
            'transitionDurationSeconds': 6,
          },
          'ytmusic_connected': true,
          'ytmusic_user_name': 'My YouTube Music Channel',
        }
      };

      final account = UserAccount.fromJson(json, 'dummy_token_123');

      expect(account.id, equals(101));
      expect(account.username, equals('dj_master'));
      expect(account.token, equals('dummy_token_123'));
      expect(account.ytmusicConnected, isTrue);
      expect(account.ytmusicUserName, equals('My YouTube Music Channel'));
      expect(account.searchHistory.length, equals(3));
      expect(account.searchHistory.first, equals('dj remix'));
      expect(account.likedTracks.length, equals(1));
      expect(account.likedTracks.first.title, equals('Track 1'));
      expect(account.savedQueue.length, equals(1));
      expect(account.settings['lowSpecMode'], isTrue);
      expect(account.settings['transitionDurationSeconds'], equals(6));
    });

    test('AuthService track liked checking and fallback defaults', () {
      final auth = AuthService.instance;
      expect(auth.isLoggedIn, isFalse);
      expect(auth.isYTMusicConnected, isFalse);
      expect(auth.searchHistory.isNotEmpty, isTrue);
      expect(auth.likedTracks, isEmpty);
      expect(auth.isTrackLiked('unknown_id'), isFalse);
    });
  });
}
