import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../controllers/dj_deck_manager.dart';
import '../models/track.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'auth_dialog.dart';
import 'channel_view_dialog.dart';
import 'related_tracks_dialog.dart';
import 'ytmusic_connect_dialog.dart';

class QueueAndSearchPanel extends StatefulWidget {
  final DJDeckManager manager;

  const QueueAndSearchPanel({
    super.key,
    required this.manager,
  });

  @override
  State<QueueAndSearchPanel> createState() => _QueueAndSearchPanelState();
}

class _QueueAndSearchPanelState extends State<QueueAndSearchPanel> {
  final TextEditingController _searchController = TextEditingController(text: 'dj');
  bool _isSearching = false;
  List<Track> _searchResults = [];
  List<Map<String, dynamic>> _matchingPlaylists = [];
  List<Map<String, dynamic>> _matchingChannels = [];
  List<Map<String, dynamic>> _matchingAlbums = [];
  String _searchFilter = 'all'; // 'all', 'songs', 'videos', 'playlists', 'channels', 'albums'
  String? _errorMessage;

  // Active search source mode: 'youtube' or 'ytmusic'
  String _searchSource = 'youtube';

  // Active navigation tab
  // 0: Presets (Star)
  // 1: YouTube Home & Explore (YouTube ธรรมดา)
  // 2: YouTube Music Home & Charts (YouTube Music)
  // 3: Deck Queue List
  // 4: Liked Songs
  int _activeNavIndex = 1;
  bool _isGridView = true;

  // Search History selection & batch management state
  bool _isHistorySelectMode = false;
  final Set<String> _selectedHistoryQueries = {};

  // YouTube Explore state
  String _selectedCategory = 'dj';
  bool _isLoadingExplore = false;
  List<Map<String, dynamic>> _explorePlaylists = [];
  List<Track> _exploreTracks = [];
  List<Map<String, dynamic>> _categories = [
    {'key': 'dj', 'label': '🎧 DJ Nonstop 2026'},
    {'key': 'party', 'label': '🔥 สายย่อ TikTok Remix'},
    {'key': 'edm', 'label': '⚡ EDM & Club Bounce'},
    {'key': 'trending', 'label': '📈 เพลงฮิตติดชาร์ต'},
    {'key': 'thai', 'label': '🌾 ไทบ้าน & ลูกทุ่งแดนซ์'},
    {'key': '90s', 'label': '📻 ยุค 90s Dance'},
  ];

  // YouTube Music Home sub-tabs
  // 0: หน้าแรก & ชาร์ตเพลง (Home & Charts)
  // 1: เพลย์ลิสต์แนะนำ (Trending Playlists)
  // 2: คลังเพลงส่วนตัว (My Library)
  int _ytmHomeSubTab = 0;
  bool _isLoadingYtmHome = false;
  List<Map<String, dynamic>> _ytmTrendingPlaylists = [];
  List<Track> _ytmChartTracks = [];

  // YouTube Music Library state (Connected user)
  int _ytmLibSubTab = 0; // 0: History, 1: Liked, 2: Playlists
  bool _isLoadingYtmLib = false;
  List<Track> _ytmHistory = [];
  List<Track> _ytmLiked = [];
  List<Map<String, dynamic>> _ytmUserPlaylists = [];
  String? _ytmWarning;
  String? _ytmEnableUrl;

  // Active Opened Playlist View
  String? _openedPlaylistTitle;
  String? _openedPlaylistAuthor;
  List<Track> _openedPlaylistTracks = [];
  bool _isLoadingPlaylist = false;

  final List<Map<String, String>> _demoPresets = [
    {
      'id': 'dQw4w9WgXcQ',
      'title': 'Never Gonna Give You Up',
      'artist': 'Rick Astley',
      'duration': '212',
    },
    {
      'id': '60ItHLz5WEA',
      'title': 'Faded',
      'artist': 'Alan Walker',
      'duration': '212',
    },
    {
      'id': 'kJQP7kiw5Fk',
      'title': 'Despacito',
      'artist': 'Luis Fonsi',
      'duration': '282',
    },
    {
      'id': 'JGwWNGJdvx8',
      'title': 'Shape of You',
      'artist': 'Ed Sheeran',
      'duration': '235',
    },
    {
      'id': 'fJ9rUzIMcZQ',
      'title': 'Bohemian Rhapsody',
      'artist': 'Queen',
      'duration': '359',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadYouTubeExplore('dj');
    _loadYouTubeMusicHome();
  }

  /// Load YouTube Explore data for a category
  Future<void> _loadYouTubeExplore(String category) async {
    setState(() {
      _selectedCategory = category;
      _isLoadingExplore = true;
      _openedPlaylistTitle = null;
    });

    final data = await ApiService.getExploreData(category: category, source: 'youtube');
    if (mounted) {
      setState(() {
        final rawCats = data['categories'] as List? ?? [];
        if (rawCats.isNotEmpty) {
          _categories = rawCats.map((c) => c as Map<String, dynamic>).toList();
        }
        final rawPlaylists = data['playlists'] as List? ?? [];
        _explorePlaylists = rawPlaylists.map((p) => p as Map<String, dynamic>).toList();
        _exploreTracks = _parseTracks(data['tracks']);
        _isLoadingExplore = false;
      });
    }
  }

  List<Track> _parseTracks(dynamic raw) {
    if (raw is! List) return [];
    return raw.map((e) {
      if (e is Track) return e;
      if (e is Map<String, dynamic>) return Track.fromJson(e);
      if (e is Map) return Track.fromJson(Map<String, dynamic>.from(e));
      return null;
    }).whereType<Track>().toList();
  }

  Map<String, dynamic> _ytmUserSections = {};

  /// Load YouTube Music Home / Charts data
  Future<void> _loadYouTubeMusicHome() async {
    setState(() => _isLoadingYtmHome = true);

    final data = await ApiService.getExploreData(category: 'trending', source: 'ytmusic');
    if (mounted) {
      setState(() {
        final rawPlaylists = data['playlists'] as List? ?? [];
        _ytmTrendingPlaylists = rawPlaylists.map((p) => p as Map<String, dynamic>).toList();
        _ytmChartTracks = _parseTracks(data['tracks']);
        _ytmUserSections = (data['user_sections'] as Map<String, dynamic>?) ?? {};
        _isLoadingYtmHome = false;
      });
    }
  }

  /// Perform Search or Resolve Playlist URL
  Future<void> _performSearch(String query, {String? filter}) async {
    final text = query.trim();
    if (text.isEmpty) return;

    if (filter != null) {
      _searchFilter = filter;
    }

    // Check if user entered bare home URLs
    if (text == 'https://www.youtube.com' || text == 'https://www.youtube.com/') {
      setState(() {
        _searchSource = 'youtube';
        _activeNavIndex = 1;
      });
      _loadYouTubeExplore('dj');
      return;
    }
    if (text == 'https://music.youtube.com' || text == 'https://music.youtube.com/') {
      setState(() {
        _searchSource = 'ytmusic';
        _activeNavIndex = 2;
      });
      _loadYouTubeMusicHome();
      return;
    }

    if (text.contains('music.youtube.com')) {
      _searchSource = 'ytmusic';
    }

    // Save to search history memories
    AuthService.instance.addSearchHistory(text);

    setState(() {
      _isSearching = true;
      _errorMessage = null;
      _openedPlaylistTitle = null;
      _activeNavIndex = 0; // Switch to Search Results View
    });

    // Check if it's a playlist URL or list= parameter
    if (text.contains('list=')) {
      await _loadPlaylist(text, _searchSource == 'ytmusic' ? 'YouTube Music Playlist' : 'YouTube Playlist');
      if (mounted) setState(() => _isSearching = false);
      return;
    }

    // Check if user entered direct video URL or 11-char video ID
    if ((text.contains('youtube.com/watch') || text.contains('youtu.be/')) ||
        (text.length == 11 && !text.contains(' '))) {
      final resolved = await ApiService.resolveStream(text);
      if (resolved != null && mounted) {
        setState(() {
          _searchResults = [
            resolved.copyWith(source: _searchSource)
          ];
          _matchingPlaylists = [];
          _matchingChannels = [];
          _matchingAlbums = [];
          _isSearching = false;
        });
        return;
      }
    }

    final result = await ApiService.searchWithPlaylists(
      text,
      source: _searchSource,
      limit: 18,
      filter: _searchFilter,
    );
    if (mounted) {
      setState(() {
        _searchResults = _parseTracks(result['tracks']);
        final rawP = result['playlists'] as List? ?? [];
        _matchingPlaylists = rawP.map((p) => p as Map<String, dynamic>).toList();
        final rawC = result['channels'] as List? ?? [];
        _matchingChannels = rawC.map((c) => c as Map<String, dynamic>).toList();
        final rawA = result['albums'] as List? ?? [];
        _matchingAlbums = rawA.map((a) => a as Map<String, dynamic>).toList();
        _isSearching = false;
        if (_searchResults.isEmpty && _matchingPlaylists.isEmpty && _matchingChannels.isEmpty && _matchingAlbums.isEmpty) {
          final sourceLabel = _searchSource == 'ytmusic' ? 'YouTube Music' : 'YouTube';
          _errorMessage = 'ไม่พบผลลัพธ์บน $sourceLabel ที่ตรงกับ "$text"';
        }
      });
    }
  }

  /// Load any playlist tracks (by ID or URL)
  Future<void> _loadPlaylist(String playlistIdOrUrl, String title, {String? author}) async {
    setState(() {
      _isLoadingPlaylist = true;
      _openedPlaylistTitle = title;
      _openedPlaylistAuthor = author;
      _openedPlaylistTracks = [];
    });

    final res = await ApiService.getPlaylistTracks(playlistIdOrUrl);
    if (mounted) {
      final tracks = _parseTracks(res['tracks']);
      final meta = res['playlist'] as Map<String, dynamic>?;
      setState(() {
        _openedPlaylistTracks = tracks;
        if (meta != null && meta['title'] != null) {
          _openedPlaylistTitle = meta['title'];
        }
        _isLoadingPlaylist = false;
      });
    }
  }

  /// Load connected YouTube Music private library
  Future<void> _loadYTMusicLibrary() async {
    if (!AuthService.instance.isYTMusicConnected) return;

    setState(() => _isLoadingYtmLib = true);

    final data = await ApiService.getYTMusicLibrary();
    if (mounted) {
      setState(() {
        _ytmHistory = _parseTracks(data['history']);
        _ytmLiked = _parseTracks(data['liked_songs']);
        final rawP = data['playlists'] as List? ?? [];
        _ytmUserPlaylists = rawP.map((p) => p as Map<String, dynamic>).toList();
        _ytmWarning = data['warning'] as String?;
        _ytmEnableUrl = data['enable_url'] as String?;
        _isLoadingYtmLib = false;
      });
    }
  }

  void _loadDemoPresets() {
    for (final item in _demoPresets) {
      final track = Track(
        videoId: item['id']!,
        title: item['title']!,
        artist: item['artist']!,
        durationSeconds: int.parse(item['duration']!),
        thumbnailUrl: 'https://i.ytimg.com/vi/${item['id']}/hqdefault.jpg',
      );
      widget.manager.addToQueue(track);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('โหลดเพลง DJ ตัวอย่างเข้าคิวเรียบร้อย!'),
        backgroundColor: Color(0xFF0072FF),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AuthService.instance,
      builder: (context, _) {
        final auth = AuthService.instance;

        return LayoutBuilder(
          builder: (context, constraints) {
            final showHistory = constraints.maxWidth >= 650;
            final showSidebar = constraints.maxWidth >= 340;

            return Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0F121A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left Navigation Sidebar
                  if (showSidebar) ...[
                    _buildSidebar(auth: auth, showHistory: showHistory),
                    Container(width: 1, color: Colors.white10),
                  ],

                  // Main Content Area
                  Expanded(
                    child: Column(
                      children: [
                        // Top Search Bar (YouDJ Style)
                        _buildSearchHeader(auth),

                        // Divider
                        Container(height: 1, color: Colors.white10),

                        // Active View Content
                        Expanded(
                          child: _buildMainContent(auth),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMainContent(AuthService auth) {
    // If a playlist is opened, show its tracks across any view
    if (_openedPlaylistTitle != null) {
      return _buildOpenedPlaylistView();
    }

    switch (_activeNavIndex) {
      case 1:
        // YouTube Home & Explore (YouTube ธรรมดา)
        return _buildYouTubeExploreView();
      case 2:
        // YouTube Music Home & Charts (YouTube Music)
        return _buildYouTubeMusicHomeView(auth);
      case 3:
        // Deck Queue List
        return _buildQueueView();
      case 4:
        // Liked Songs
        return _buildLikedSongsView(auth);
      case 0:
      default:
        // Search Results Grid or Presets
        return _buildSearchResultsGrid();
    }
  }

  /// Left Sidebar: Distinct branded logos for YouTube and YouTube Music + History
  Widget _buildSidebar({required AuthService auth, bool showHistory = true}) {
    final searchHistory = auth.searchHistory;

    return SizedBox(
      width: showHistory ? 190 : 52,
      child: Row(
        children: [
          // Vertical Icon Toolbar
          Container(
            width: 52,
            decoration: const BoxDecoration(
              color: Color(0xFF0A0C10),
              borderRadius: BorderRadius.horizontal(left: Radius.circular(13)),
            ),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 8),

                  // 1. YouTube ธรรมดา (Official Red Rectangle Logo)
                  _buildYouTubeLogoButton(
                    isSelected: _activeNavIndex == 1,
                    onTap: () {
                      setState(() {
                        _searchSource = 'youtube';
                        _activeNavIndex = 1;
                        _openedPlaylistTitle = null;
                      });
                      if (_exploreTracks.isEmpty) {
                        _loadYouTubeExplore(_selectedCategory);
                      }
                    },
                  ),
                  const SizedBox(height: 4),

                  // 2. YouTube Music (Official Red Circle Logo)
                  _buildYTMusicLogoButton(
                    isSelected: _activeNavIndex == 2,
                    isConnected: auth.isYTMusicConnected,
                    onTap: () {
                      setState(() {
                        _searchSource = 'ytmusic';
                        _activeNavIndex = 2;
                        _openedPlaylistTitle = null;
                      });
                      if (_ytmTrendingPlaylists.isEmpty) {
                        _loadYouTubeMusicHome();
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Container(width: 28, height: 1, color: Colors.white12),
                  const SizedBox(height: 8),

                  // 3. Search Icon
                  _buildSidebarIconButton(
                    icon: Icons.search,
                    index: 0,
                    tooltip: 'ค้นหาเพลง (Search)',
                    color: const Color(0xFF00F2FE),
                    onTap: () {
                      setState(() {
                        _activeNavIndex = 0;
                        _openedPlaylistTitle = null;
                      });
                    },
                  ),

                  // 4. Queue Icon
                  _buildSidebarIconButton(
                    icon: Icons.queue_music,
                    index: 3,
                    tooltip: 'รายการคิวเล่น (Deck Queue)',
                    color: const Color(0xFF00F2FE),
                    badgeCount: widget.manager.queue.length,
                    onTap: () {
                      setState(() {
                        _activeNavIndex = 3;
                        _openedPlaylistTitle = null;
                      });
                    },
                  ),

                  // 5. Liked Songs
                  _buildSidebarIconButton(
                    icon: Icons.favorite,
                    index: 4,
                    tooltip: 'เพลงที่ชอบ (Liked Songs)',
                    color: const Color(0xFFFF2A85),
                    badgeCount: auth.likedTracks.isNotEmpty ? auth.likedTracks.length : null,
                    onTap: () {
                      setState(() {
                        _activeNavIndex = 4;
                        _openedPlaylistTitle = null;
                      });
                    },
                  ),

                  // 6. Featured Presets Star
                  _buildSidebarIconButton(
                    icon: Icons.star,
                    index: 99,
                    tooltip: 'เพลงตัวอย่างยอดฮิต (DJ Presets)',
                    color: Colors.amberAccent,
                    onTap: () {
                      _loadDemoPresets();
                      setState(() => _activeNavIndex = 3);
                    },
                  ),

                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),

          // Search History Column (like YouDJ + Management Tools)
          if (showHistory)
            Expanded(
              child: Container(
                color: const Color(0xFF0D0F16),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Bar with Action Buttons
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Search history :',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (searchHistory.isNotEmpty) ...[
                          // Multi-select toggle button
                          Tooltip(
                            message: _isHistorySelectMode ? 'ยกเลิกการเลือก' : 'เลือกหลายรายการเพื่อลบ',
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _isHistorySelectMode = !_isHistorySelectMode;
                                  _selectedHistoryQueries.clear();
                                });
                              },
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: _isHistorySelectMode ? const Color(0xFF00F2FE).withAlpha(40) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Icon(
                                  _isHistorySelectMode ? Icons.checklist_rtl : Icons.check_box_outlined,
                                  size: 13,
                                  color: _isHistorySelectMode ? const Color(0xFF00F2FE) : Colors.white38,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),

                          // Clear All button
                          Tooltip(
                            message: 'ล้างประวัติการค้นหาทั้งหมด',
                            child: InkWell(
                              onTap: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor: const Color(0xFF161B26),
                                    title: const Text('ล้างประวัติการค้นหา', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                                    content: const Text('คุณต้องการลบประวัติการค้นหาทั้งหมดใช่หรือไม่?', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก', style: TextStyle(color: Colors.white54))),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF0033)),
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: const Text('ลบทั้งหมด', style: TextStyle(color: Colors.white)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await auth.clearAllSearchHistory();
                                  if (mounted) {
                                    setState(() {
                                      _selectedHistoryQueries.clear();
                                      _isHistorySelectMode = false;
                                    });
                                  }
                                }
                              },
                              borderRadius: BorderRadius.circular(4),
                              child: const Padding(
                                padding: EdgeInsets.all(3),
                                child: Icon(Icons.delete_sweep_outlined, size: 14, color: Colors.white38),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),

                    // Multi-select banner when in select mode
                    if (_isHistorySelectMode) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E2433),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFF00F2FE).withAlpha(60)),
                        ),
                        child: Row(
                          children: [
                            Text(
                              'เลือก ${_selectedHistoryQueries.length}',
                              style: const TextStyle(color: Color(0xFF00F2FE), fontSize: 9.5, fontWeight: FontWeight.bold),
                            ),
                            const Spacer(),
                            if (_selectedHistoryQueries.isNotEmpty)
                              InkWell(
                                onTap: () async {
                                  final toDelete = _selectedHistoryQueries.toList();
                                  await auth.deleteMultipleSearchHistory(toDelete);
                                  if (mounted) {
                                    setState(() {
                                      _selectedHistoryQueries.clear();
                                      _isHistorySelectMode = false;
                                    });
                                  }
                                },
                                borderRadius: BorderRadius.circular(4),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF0033),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: const Text('ลบ', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                                ),
                              ),
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: () {
                                setState(() {
                                  if (_selectedHistoryQueries.length == searchHistory.length) {
                                    _selectedHistoryQueries.clear();
                                  } else {
                                    _selectedHistoryQueries.addAll(searchHistory);
                                  }
                                });
                              },
                              child: Text(
                                _selectedHistoryQueries.length == searchHistory.length ? 'ยกเลิก' : 'ทั้งหมด',
                                style: const TextStyle(color: Colors.white60, fontSize: 9),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 6),
                    Expanded(
                      child: searchHistory.isEmpty
                          ? const Center(
                              child: Text(
                                'ไม่มีประวัติ',
                                style: TextStyle(color: Colors.white24, fontSize: 10),
                              ),
                            )
                          : ListView.builder(
                              itemCount: searchHistory.length,
                              itemBuilder: (context, index) {
                                final tag = searchHistory[index];
                                final isSelected = _searchController.text.trim().toLowerCase() == tag.toLowerCase();
                                final isChecked = _selectedHistoryQueries.contains(tag);

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 2),
                                  decoration: BoxDecoration(
                                    color: isChecked
                                        ? const Color(0xFF00F2FE).withAlpha(25)
                                        : (isSelected ? const Color(0xFF1E2433) : Colors.transparent),
                                    borderRadius: BorderRadius.circular(4),
                                    border: isChecked
                                        ? Border.all(color: const Color(0xFF00F2FE).withAlpha(80), width: 1)
                                        : null,
                                  ),
                                  child: InkWell(
                                    onTap: () {
                                      if (_isHistorySelectMode) {
                                        setState(() {
                                          if (isChecked) {
                                            _selectedHistoryQueries.remove(tag);
                                          } else {
                                            _selectedHistoryQueries.add(tag);
                                          }
                                        });
                                      } else {
                                        _searchController.text = tag;
                                        _performSearch(tag);
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(4),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                                      child: Row(
                                        children: [
                                          if (_isHistorySelectMode)
                                            Padding(
                                              padding: const EdgeInsets.only(right: 5),
                                              child: Icon(
                                                isChecked ? Icons.check_box : Icons.check_box_outline_blank,
                                                size: 13,
                                                color: isChecked ? const Color(0xFF00F2FE) : Colors.white38,
                                              ),
                                            )
                                          else
                                            Icon(
                                              Icons.history,
                                              size: 12,
                                              color: isSelected ? const Color(0xFF00F2FE) : Colors.white38,
                                            ),
                                          const SizedBox(width: 5),
                                          Expanded(
                                            child: Text(
                                              tag,
                                              style: TextStyle(
                                                color: isChecked
                                                    ? const Color(0xFF00F2FE)
                                                    : (isSelected ? Colors.white : Colors.white70),
                                                fontSize: 10.5,
                                                fontWeight: (isSelected || isChecked) ? FontWeight.bold : FontWeight.normal,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),

                                          // Single item quick delete icon (when not in select mode)
                                          if (!_isHistorySelectMode)
                                            InkWell(
                                              onTap: () => auth.deleteSearchHistoryItem(tag),
                                              borderRadius: BorderRadius.circular(10),
                                              child: const Padding(
                                                padding: EdgeInsets.all(2),
                                                child: Icon(
                                                  Icons.close,
                                                  size: 11,
                                                  color: Colors.white24,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Authentic YouTube (Red Rectangle) Logo Button
  Widget _buildYouTubeLogoButton({
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: 'หน้าแรก YouTube (YouTube Home & Playlists)',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 44,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFFF0000).withAlpha(40) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? const Color(0xFFFF0000) : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 19,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF0000),
                  borderRadius: BorderRadius.circular(5),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: const Color(0xFFFF0000).withAlpha(160),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: const Center(
                  child: Icon(Icons.play_arrow, size: 14, color: Colors.white),
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'YouTube',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 7.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Authentic YouTube Music (Red Circle) Logo Button
  Widget _buildYTMusicLogoButton({
    required bool isSelected,
    required bool isConnected,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: isConnected
          ? 'หน้าแรก YouTube Music (เชื่อมต่อบัญชีแล้ว)'
          : 'หน้าแรก YouTube Music (Home, Charts & Playlists)',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 44,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFFF0033).withAlpha(40) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? const Color(0xFFFF0033) : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF0033),
                      shape: BoxShape.circle,
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: const Color(0xFFFF0033).withAlpha(160),
                                blurRadius: 6,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: Container(
                        width: 15,
                        height: 15,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.2),
                        ),
                        child: const Center(
                          child: Icon(Icons.play_arrow, size: 9, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'YT Music',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 7.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
              if (isConnected)
                Positioned(
                  right: 2,
                  top: 0,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF00F2FE),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00F2FE).withAlpha(200),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarIconButton({
    required IconData icon,
    required int index,
    required String tooltip,
    required Color color,
    int? badgeCount,
    required VoidCallback onTap,
  }) {
    final isSelected = _activeNavIndex == index;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            tooltip: tooltip,
            icon: Icon(icon, size: 20),
            color: isSelected ? color : Colors.white38,
            style: IconButton.styleFrom(
              backgroundColor: isSelected ? color.withAlpha(35) : Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: onTap,
          ),
          if (badgeCount != null && badgeCount > 0)
            Positioned(
              right: 2,
              top: 2,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF00F2FE),
                ),
                child: Text(
                  '$badgeCount',
                  style: const TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Top search bar header with interactive YouTube vs YouTube Music mode selector & filter chips
  Widget _buildSearchHeader(AuthService auth) {
    final isYtm = _searchSource == 'ytmusic';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: const Color(0xFF131722),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // 1. YouTube vs YouTube Music Mode Selector
              Container(
                height: 32,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: const Color(0xFF0C0E14),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSourceModeButton(
                      title: 'YouTube',
                      sourceKey: 'youtube',
                      icon: Icons.play_arrow,
                      activeColor: const Color(0xFFFF0000),
                      isSelected: !isYtm,
                    ),
                    const SizedBox(width: 2),
                    _buildSourceModeButton(
                      title: 'YT Music',
                      sourceKey: 'ytmusic',
                      icon: Icons.music_note,
                      activeColor: const Color(0xFFFF0033),
                      isSelected: isYtm,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // 2. Search Field with Dynamic Logo Badge
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: isYtm
                          ? 'ค้นหาเพลง, Remix, DJ บน YouTube Music...'
                          : 'ค้นหาคลิป, เพลงแดนซ์, DJ Mix, MV บน YouTube...',
                      hintStyle: TextStyle(color: Colors.grey[500], fontSize: 11),
                      prefixIcon: Padding(
                        padding: const EdgeInsets.only(left: 6, right: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: isYtm ? const Color(0xFFFF0033) : const Color(0xFFFF0000),
                                borderRadius: BorderRadius.circular(isYtm ? 10 : 3),
                                boxShadow: [
                                  BoxShadow(
                                    color: (isYtm ? const Color(0xFFFF0033) : const Color(0xFFFF0000)).withAlpha(120),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isYtm ? Icons.music_note : Icons.play_arrow,
                                    size: 10,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    isYtm ? 'Music' : 'YouTube',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.search, color: Colors.grey, size: 14),
                          ],
                        ),
                      ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.grey, size: 14),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFF1B202D),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(
                          color: isYtm ? const Color(0xFFFF0033) : const Color(0xFFFF0000),
                        ),
                      ),
                    ),
                    onSubmitted: (val) => _performSearch(val),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Search button
              ElevatedButton(
                onPressed: () => _performSearch(_searchController.text),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isYtm ? const Color(0xFFFF0033) : const Color(0xFFFF0000),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  minimumSize: const Size(0, 32),
                ),
                child: const Text('SEARCH', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              ),

              const SizedBox(width: 8),

              // Grid / List toggle
              IconButton(
                tooltip: _isGridView ? 'สลับเป็นมุมมองรายการ' : 'สลับเป็นมุมมองการ์ด',
                icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view, color: Colors.white70, size: 18),
                onPressed: () => setState(() => _isGridView = !_isGridView),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),

              const SizedBox(width: 8),

              // AutoMIX playlist button (YouDJ style)
              OutlinedButton.icon(
                onPressed: _loadDemoPresets,
                icon: const Icon(Icons.bolt, size: 14, color: Colors.amberAccent),
                label: const Text('AutoMIX', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  minimumSize: const Size(0, 32),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // 3. Search Filter Chips (YouTube & YouTube Music Style)
          SizedBox(
            height: 25,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildSearchFilterChip('all', 'ทั้งหมด', Icons.all_inclusive, isYtm),
                const SizedBox(width: 5),
                _buildSearchFilterChip('songs', 'เพลง', Icons.music_note, isYtm),
                const SizedBox(width: 5),
                _buildSearchFilterChip('videos', 'วิดีโอ', Icons.smart_display, isYtm),
                const SizedBox(width: 5),
                _buildSearchFilterChip('playlists', 'เพลย์ลิสต์', Icons.queue_music, isYtm),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchFilterChip(String key, String label, IconData icon, bool isYtm) {
    final isSelected = _searchFilter == key;
    final activeColor = isYtm ? const Color(0xFFFF0033) : const Color(0xFFFF0000);

    return InkWell(
      onTap: () {
        setState(() => _searchFilter = key);
        if (_searchController.text.trim().isNotEmpty) {
          _performSearch(_searchController.text, filter: key);
        }
      },
      borderRadius: BorderRadius.circular(13),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : const Color(0xFF1B202D),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: isSelected ? activeColor : Colors.white12,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 11,
              color: isSelected ? Colors.white : Colors.white60,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 9.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceModeButton({
    required String title,
    required String sourceKey,
    required IconData icon,
    required Color activeColor,
    required bool isSelected,
  }) {
    return InkWell(
      onTap: () {
        setState(() {
          _searchSource = sourceKey;
          if (sourceKey == 'youtube') {
            _activeNavIndex = 1;
            if (_exploreTracks.isEmpty) _loadYouTubeExplore(_selectedCategory);
          } else {
            _activeNavIndex = 2;
            if (_ytmTrendingPlaylists.isEmpty) _loadYouTubeMusicHome();
          }
        });
      },
      borderRadius: BorderRadius.circular(4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withAlpha(45) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? activeColor : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 11,
              color: isSelected ? activeColor : Colors.white60,
            ),
            const SizedBox(width: 4),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white60,
                fontSize: 9.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // VIEW 1: YOUTUBE HOME & EXPLORE VIEW (หน้าแรก YouTube ธรรมดา)
  // =========================================================================
  Widget _buildYouTubeExploreView() {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFFF0000)));
    }

    return Column(
      children: [
        // YouTube Banner & Category Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: const Color(0xFF141722),
          child: Row(
            children: [
              // YouTube Brand Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF0000),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.play_arrow, size: 14, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'YouTube',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'หน้าแรก & เพลย์ลิสต์ยอดนิยม',
                style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'รีเฟรชหน้าแรก YouTube',
                icon: const Icon(Icons.refresh, size: 16, color: Colors.white60),
                onPressed: () => _loadYouTubeExplore(_selectedCategory),
              ),
            ],
          ),
        ),

        // Category Filter Chips
        Container(
          height: 38,
          color: const Color(0xFF10131C),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            itemCount: _categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final cat = _categories[index];
              final isSel = _selectedCategory == cat['key'];
              return ChoiceChip(
                label: Text(
                  cat['label'] ?? '',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                    color: isSel ? Colors.white : Colors.white70,
                  ),
                ),
                selected: isSel,
                selectedColor: const Color(0xFFFF0000),
                backgroundColor: const Color(0xFF1B202D),
                side: BorderSide(color: isSel ? const Color(0xFFFF0000) : Colors.white12),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                onSelected: (val) {
                  if (val) _loadYouTubeExplore(cat['key']!);
                },
              );
            },
          ),
        ),

        // Main Explore Content
        Expanded(
          child: _isLoadingExplore
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFFFF0000)),
                      SizedBox(height: 10),
                      Text('กำลังโหลดหน้าแรก YouTube & เพลย์ลิสต์...', style: TextStyle(color: Colors.white54, fontSize: 11)),
                    ],
                  ),
                )
              : CustomScrollView(
                  slivers: [
                    // Section 1: Matching / Featured Playlists
                    if (_explorePlaylists.isNotEmpty) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                          child: Row(
                            children: [
                              const Icon(Icons.playlist_play, size: 18, color: Color(0xFFFF0000)),
                              const SizedBox(width: 6),
                              Text(
                                'เพลย์ลิสต์แนะนำ (${_explorePlaylists.length} เพลย์ลิสต์) • คลิกเพื่อเปิดเพลงทั้งหมด',
                                style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 110,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            itemCount: _explorePlaylists.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 8),
                            itemBuilder: (context, index) => _buildPlaylistCardHorizontal(_explorePlaylists[index]),
                          ),
                        ),
                      ),
                    ],

                    // Section 2: Trending / Recommended Songs
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                        child: Row(
                          children: [
                            const Icon(Icons.whatshot, size: 16, color: Colors.orangeAccent),
                            const SizedBox(width: 6),
                            const Text(
                              'เพลงมาแรงในหมวดนี้ • เลือกโหลดเข้า DECK 1 หรือ DECK 2 ได้ทันที',
                              style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),

                    SliverPadding(
                      padding: const EdgeInsets.all(8),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 220,
                          childAspectRatio: 1.15,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _buildYouDjTrackCard(_exploreTracks[index]),
                          childCount: _exploreTracks.length,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  // =========================================================================
  // VIEW 2: YOUTUBE MUSIC HOME VIEW (หน้าแรก YouTube Music)
  // =========================================================================
  Widget _buildYouTubeMusicHomeView(AuthService auth) {
    return Column(
      children: [
        // YouTube Music Header Banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: const Color(0xFF141722),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF0033),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.play_circle_fill, size: 14, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'YouTube Music',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'หน้าแรก & ชาร์ตเพลงยอดนิยม',
                style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (auth.isYTMusicConnected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F2FE).withAlpha(30),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF00F2FE).withAlpha(100)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle, size: 12, color: Color(0xFF00F2FE)),
                      SizedBox(width: 4),
                      Text('เชื่อมต่อบัญชีแล้ว', style: TextStyle(color: Color(0xFF00F2FE), fontSize: 9.5)),
                    ],
                  ),
                )
              else
                TextButton.icon(
                  onPressed: () => showDialog(context: context, builder: (_) => const YTMusicConnectDialog()),
                  icon: const Icon(Icons.link, size: 13, color: Color(0xFFFF0033)),
                  label: const Text('เชื่อมต่อบัญชี Google / YT Music', style: TextStyle(color: Color(0xFFFF0033), fontSize: 10)),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                ),
              IconButton(
                tooltip: 'รีเฟรช YouTube Music',
                icon: const Icon(Icons.refresh, size: 16, color: Colors.white60),
                onPressed: _loadYouTubeMusicHome,
              ),
            ],
          ),
        ),

        // Sub-tabs: Home & Charts, Trending Playlists, My Library
        Container(
          color: const Color(0xFF10131C),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            children: [
              _buildTabPill(
                index: 0,
                activeTab: _ytmHomeSubTab,
                label: '🔥 หน้าแรก & ชาร์ตเพลง',
                onTap: () => setState(() => _ytmHomeSubTab = 0),
              ),
              const SizedBox(width: 6),
              _buildTabPill(
                index: 1,
                activeTab: _ytmHomeSubTab,
                label: '📁 เพลย์ลิสต์แนะนำ (Playlists)',
                onTap: () => setState(() => _ytmHomeSubTab = 1),
              ),
              const SizedBox(width: 6),
              _buildTabPill(
                index: 2,
                activeTab: _ytmHomeSubTab,
                label: '🎧 คลังเพลงของฉัน (My Library)',
                onTap: () {
                  setState(() => _ytmHomeSubTab = 2);
                  if (auth.isYTMusicConnected && _ytmHistory.isEmpty) {
                    _loadYTMusicLibrary();
                  }
                },
              ),
            ],
          ),
        ),

        // Sub-content
        Expanded(
          child: _isLoadingYtmHome
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF0033)))
              : _buildYtmHomeSubContent(auth),
        ),
      ],
    );
  }

  Widget _buildTabPill({
    required int index,
    required int activeTab,
    required String label,
    required VoidCallback onTap,
  }) {
    final isSel = activeTab == index;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSel ? const Color(0xFFFF0033).withAlpha(40) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSel ? const Color(0xFFFF0033) : Colors.transparent),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSel ? Colors.white : Colors.white70,
            fontSize: 11,
            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildYtmHomeSubContent(AuthService auth) {
    if (_ytmHomeSubTab == 2) {
      // My Library (Connected YT Music)
      return _buildYTMusicPrivateLibraryView(auth);
    }

    if (_ytmHomeSubTab == 1) {
      // Trending Playlists Grid
      if (_ytmTrendingPlaylists.isEmpty) {
        return const Center(child: Text('ไม่มีเพลย์ลิสต์', style: TextStyle(color: Colors.white54, fontSize: 11)));
      }

      return GridView.builder(
        padding: const EdgeInsets.all(10),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 260,
          childAspectRatio: 2.2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: _ytmTrendingPlaylists.length,
        itemBuilder: (context, index) {
          final p = _ytmTrendingPlaylists[index];
          return _buildPlaylistCard(p);
        },
      );
    }

    // Default: Home & Charts
    final listenAgainTracks = _parseTracks(_ytmUserSections['listen_again']);
    final userName = (_ytmUserSections['user_name'] as String?) ??
        ((auth.currentUser?.ytmusicUserName.isNotEmpty == true) ? auth.currentUser!.ytmusicUserName : null) ??
        auth.currentUser?.username ??
        'บุนมี คำทา - ENGINEER BM GROUP';

    return CustomScrollView(
      slivers: [
        // 1. "ฟังอีกครั้ง" (Listen Again) Section - Like Chrome!
        if (listenAgainTracks.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: const Color(0xFFFF0033),
                    child: Text(
                      userName.isNotEmpty ? userName[0].toUpperCase() : 'B',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userName,
                          style: const TextStyle(color: Colors.white60, fontSize: 9.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Text(
                          'ฟังอีกครั้ง',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _ytmHomeSubTab = 2),
                    child: const Text('เพิ่มเติม >', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 190,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                itemCount: listenAgainTracks.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) => SizedBox(
                  width: 175,
                  child: _buildYouDjTrackCard(listenAgainTracks[index]),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 10)),
        ] else ...[
          // Clean Quick Search & Nonstop DJ Highlights Banner
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFFF0033).withAlpha(35),
                    const Color(0xFF141824),
                  ],
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFF0033).withAlpha(60)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF0033).withAlpha(40),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.music_note, color: Color(0xFFFF0033), size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ค้นหาเพลง, DJ Remix หรือวางลิงก์ YouTube Music ได้ทันที',
                          style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'พิมพ์ชื่อเพลง เช่น "อมพระมาพูด dj" หรือชื่อศิลปินในช่องค้นหาด้านบนเพื่อเปิดมิกซ์ได้ทันที',
                          style: TextStyle(color: Colors.grey[400], fontSize: 9.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      _searchController.text = 'อมพระมาพูด dj';
                      _performSearch('อมพระมาพูด dj');
                    },
                    icon: const Icon(Icons.search, size: 12),
                    label: const Text('ลองค้นหา', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF0033),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      minimumSize: const Size(0, 30),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        // 2. Horizontal Playlists Row
        if (_ytmTrendingPlaylists.isNotEmpty) ...[
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Text(
                'เพลย์ลิสต์แนะนำจาก YouTube Music • คลิกเพื่อเปิดเพลงทั้งหมด',
                style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                itemCount: _ytmTrendingPlaylists.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) => _buildPlaylistCardHorizontal(_ytmTrendingPlaylists[index]),
              ),
            ),
          ),
        ],

        // 3. Top Chart Tracks
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Text(
              'ชาร์ตเพลงและเพลงแนะนำ YouTube Music',
              style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
            ),
          ),
        ),

        SliverPadding(
          padding: const EdgeInsets.all(8),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              childAspectRatio: 1.15,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildYouDjTrackCard(_ytmChartTracks[index]),
              childCount: _ytmChartTracks.length,
            ),
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // VIEW 3: OPENED PLAYLIST FULL TRACKS VIEW
  // =========================================================================
  Widget _buildOpenedPlaylistView() {
    if (_isLoadingPlaylist) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF00F2FE)),
            SizedBox(height: 10),
            Text('กำลังโหลดเพลงทั้งหมดในเพลย์ลิสต์...', style: TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Playlist Action Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: const Color(0xFF161A24),
          child: Row(
            children: [
              IconButton(
                tooltip: 'ย้อนกลับ',
                icon: const Icon(Icons.arrow_back, color: Color(0xFF00F2FE), size: 18),
                onPressed: () => setState(() => _openedPlaylistTitle = null),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '📁 ${_openedPlaylistTitle ?? "Playlist"}',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${_openedPlaylistTracks.length} เพลง ${_openedPlaylistAuthor != null ? "• โดย $_openedPlaylistAuthor" : ""}',
                      style: TextStyle(color: Colors.grey[400], fontSize: 10),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () {
                  widget.manager.addMultipleToQueue(_openedPlaylistTracks);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('เพิ่มทั้ง ${_openedPlaylistTracks.length} เพลงเข้าคิว DJ แล้ว!')),
                  );
                },
                icon: const Icon(Icons.playlist_add, size: 14),
                label: const Text('เพิ่มทั้งเพลย์ลิสต์เข้าคิว DJ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0072FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 30),
                ),
              ),
            ],
          ),
        ),

        // Playlist Tracks
        Expanded(
          child: _openedPlaylistTracks.isEmpty
              ? const Center(
                  child: Text('ไม่มีเพลงในเพลย์ลิสต์นี้หรือเพลย์ลิสต์เป็นส่วนตัว', style: TextStyle(color: Colors.white54, fontSize: 12)),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final colCount = (constraints.maxWidth / 200).floor().clamp(2, 6);
                    return GridView.builder(
                      padding: const EdgeInsets.all(8),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: colCount,
                        childAspectRatio: 1.15,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: _openedPlaylistTracks.length,
                      itemBuilder: (context, index) => _buildYouDjTrackCard(_openedPlaylistTracks[index]),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // =========================================================================
  // VIEW 4: SEARCH RESULTS GRID
  // =========================================================================
  Widget _buildSearchResultsGrid() {
    if (_isSearching) {
      final sourceName = _searchSource == 'ytmusic' ? 'YouTube Music' : 'YouTube';
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: _searchSource == 'ytmusic' ? const Color(0xFFFF0033) : const Color(0xFF00F2FE),
            ),
            const SizedBox(height: 10),
            Text('กำลังค้นหา $sourceName...', style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.orangeAccent, size: 36),
            const SizedBox(height: 6),
            Text(_errorMessage!, style: const TextStyle(color: Colors.white70, fontSize: 11)),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => _performSearch(_searchController.text),
              child: const Text('ลองค้นหาใหม่', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty && _matchingPlaylists.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search, color: Colors.white24, size: 40),
            const SizedBox(height: 6),
            const Text('พิมพ์ค้นหาเพลงหรือวางลิงก์ YouTube Playlist ด้านบน', style: TextStyle(color: Colors.white54, fontSize: 11)),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () => _performSearch('dj remix 2026'),
              child: const Text('โหลดเพลง DJ ยอดฮิต', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        // 1. Top Result Card (Authentic YouTube Music Style) FIRST!
        if (_searchResults.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _buildTopResultCard(_searchResults.first),
          ),

          // Remaining Tracks Header
          if (_searchResults.length > 1) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: Text(
                  'เพลงและวิดีโออื่นๆ (${_searchResults.length - 1} รายการ)',
                  style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ),

            if (_isGridView)
              SliverPadding(
                padding: const EdgeInsets.all(8),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    childAspectRatio: 1.15,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildYouDjTrackCard(_searchResults[index + 1]),
                    childCount: _searchResults.length - 1,
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildTrackListItem(_searchResults[index + 1]),
                  childCount: _searchResults.length - 1,
                ),
              ),
          ],
        ],

        // 2. Playlists (if any) placed below songs
        if (_matchingPlaylists.isNotEmpty) ...[
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, 16, 12, 6),
              child: Text(
                'เพลย์ลิสต์ที่ตรงกับการค้นหา • คลิกเพื่อเปิดเพลงทั้งหมด',
                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                itemCount: _matchingPlaylists.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) => _buildPlaylistCardHorizontal(_matchingPlaylists[index]),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Top Result Card (Authentic YouTube Music Highlight)
  Widget _buildTopResultCard(Track track) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B26),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFF0033).withAlpha(120), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF0033).withAlpha(25),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 16:9 Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 130,
              height: 80,
              color: const Color(0xFF202636),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (track.thumbnailUrl != null)
                    Image.network(
                      track.thumbnailUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.music_note, color: Colors.white24),
                    )
                  else
                    const Icon(Icons.music_note, color: Colors.white24),
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(3)),
                      child: Text(track.formattedDuration, style: const TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Details & Action Buttons
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF0033),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('ผลการค้นหาเด่น (TOP RESULT)', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      track.isYtMusic ? 'วิดีโอ • YouTube Music' : 'วิดีโอ • YouTube',
                      style: const TextStyle(color: Colors.white54, fontSize: 9),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  track.title,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          track.artist,
                          style: const TextStyle(color: Color(0xFF00F2FE), fontSize: 10, decoration: TextDecoration.underline),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 3),
                      const Icon(Icons.open_in_new, size: 8, color: Color(0xFF00F2FE)),
                    ],
                  ),
                ),
                const SizedBox(height: 6),

                // Load buttons
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        widget.manager.loadTrackToDeck(ActiveDeck.deckA, track);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('โหลดเข้า DECK A สำเร็จ (Standby รอเปิด/ข้ามเพลง)'), backgroundColor: Color(0xFF0072FF), duration: Duration(seconds: 1)));
                      },
                      icon: const Icon(Icons.play_arrow, size: 13),
                      label: const Text('DECK A', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00F2FE),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 0),
                        minimumSize: const Size(0, 26),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        widget.manager.loadTrackToDeck(ActiveDeck.deckB, track);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('โหลดเข้า DECK B สำเร็จ (Standby รอเปิด/ข้ามเพลง)'), backgroundColor: Color(0xFFFF2A85), duration: Duration(seconds: 1)));
                      },
                      icon: const Icon(Icons.play_arrow, size: 13),
                      label: const Text('DECK B', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF2A85),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 0),
                        minimumSize: const Size(0, 26),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        widget.manager.addToQueue(track);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เพิ่ม "${track.title}" เข้าคิวแล้ว'), duration: const Duration(seconds: 1)));
                      },
                      icon: const Icon(Icons.add, size: 12),
                      label: const Text('เข้าคิว', style: TextStyle(fontSize: 9.5)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                        minimumSize: const Size(0, 26),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        RelatedTracksDialog.show(context, seedTrack: track, manager: widget.manager, source: track.source);
                      },
                      icon: const Icon(Icons.auto_awesome, size: 11, color: Color(0xFF00F2FE)),
                      label: const Text('วิดีโอที่เกี่ยวข้อง', style: TextStyle(fontSize: 9.5, color: Color(0xFF00F2FE))),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF00F2FE),
                        side: BorderSide(color: const Color(0xFF00F2FE).withAlpha(100)),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                        minimumSize: const Size(0, 26),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Compact List View for Tracks (YouTube Music Style List)
  Widget _buildTrackListItem(Track track) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF131722),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          // Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: 50,
              height: 36,
              child: track.thumbnailUrl != null
                  ? Image.network(track.thumbnailUrl!, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => const Icon(Icons.music_note, color: Colors.white24))
                  : const Icon(Icons.music_note, color: Colors.white24),
            ),
          ),
          const SizedBox(width: 10),

          // Title & Artist
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(track.title, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 1),
                InkWell(
                  onTap: () => ChannelViewDialog.show(context, channelId: track.channelId, name: track.artist, source: track.source, manager: widget.manager),
                  child: Text(track.artist, style: const TextStyle(color: Colors.white60, fontSize: 9), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Duration
          Text(track.formattedDuration, style: const TextStyle(color: Colors.white38, fontSize: 9)),
          const SizedBox(width: 8),

          // Like Button
          ListenableBuilder(
            listenable: AuthService.instance,
            builder: (context, _) {
              final auth = AuthService.instance;
              final isLiked = auth.isTrackLiked(track.videoId);
              return Tooltip(
                message: isLiked ? 'ลบออกจากเพลงที่ชอบ' : 'กดถูกใจ (Like)',
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
                            duration: const Duration(seconds: 1),
                            backgroundColor: isLikedNow ? const Color(0xFFFF2A85) : Colors.grey[900],
                          ),
                        );
                      }
                    }
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Icon(
                      isLiked ? Icons.favorite : Icons.favorite_border,
                      color: isLiked ? const Color(0xFFFF2A85) : Colors.white60,
                      size: 15,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 6),

          // Deck A
          InkWell(
            onTap: () {
              widget.manager.loadTrackToDeck(ActiveDeck.deckA, track);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('โหลดเข้า DECK A สำเร็จ'), backgroundColor: Color(0xFF0072FF), duration: Duration(seconds: 1)));
            },
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(color: const Color(0xFF00F2FE), borderRadius: BorderRadius.circular(4)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.play_arrow, size: 11, color: Colors.black), Text('1', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 9.5))]),
            ),
          ),
          const SizedBox(width: 4),

          // Deck B
          InkWell(
            onTap: () {
              widget.manager.loadTrackToDeck(ActiveDeck.deckB, track);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('โหลดเข้า DECK B สำเร็จ'), backgroundColor: Color(0xFFFF2A85), duration: Duration(seconds: 1)));
            },
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(color: const Color(0xFFFF2A85), borderRadius: BorderRadius.circular(4)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.play_arrow, size: 11, color: Colors.white), Text('2', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 9.5))]),
            ),
          ),
          const SizedBox(width: 4),

          // Related
          IconButton(
            tooltip: 'วิดีโอที่เกี่ยวข้อง',
            icon: const Icon(Icons.auto_awesome, size: 13, color: Color(0xFF00F2FE)),
            onPressed: () => RelatedTracksDialog.show(context, seedTrack: track, manager: widget.manager, source: track.source),
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(4),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelCardHorizontal(Map<String, dynamic> channel) {
    final title = channel['title'] ?? 'Channel';
    final subscribers = channel['subscribers'] ?? '';
    final thumbnail = channel['thumbnail'];
    final channelId = channel['channel_id'] ?? channel['browseId'];

    return InkWell(
      onTap: () {
        ChannelViewDialog.show(
          context,
          channelId: channelId,
          name: title,
          source: _searchSource,
          manager: widget.manager,
        );
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF161B26),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: const Color(0xFF202636),
              backgroundImage: thumbnail != null && thumbnail.isNotEmpty ? NetworkImage(thumbnail) : null,
              child: thumbnail == null || thumbnail.isEmpty
                  ? const Icon(Icons.account_circle, size: 30, color: Colors.white60)
                  : null,
            ),
            const SizedBox(height: 5),
            Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            if (subscribers.isNotEmpty)
              Text(
                subscribers,
                style: const TextStyle(color: Colors.white54, fontSize: 8),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF00F2FE).withAlpha(30),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('ดูช่อง / ศิลปิน', style: TextStyle(color: Color(0xFF00F2FE), fontSize: 8, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // VIEW 5: CONNECTED USER PRIVATE YT MUSIC LIBRARY
  // =========================================================================
  Widget _buildYTMusicPrivateLibraryView(AuthService auth) {
    if (!auth.isLoggedIn) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_circle, color: Color(0xFF00F2FE), size: 48),
            const SizedBox(height: 10),
            const Text(
              'กรุณาเข้าสู่ระบบ BM DJ ก่อนเชื่อมต่อ YouTube Music',
              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'การเชื่อมต่อจะผูกกับบัญชีของคุณเพื่อให้สามารถดึงเพลย์ลิสต์และประวัติเพลงได้ตลอดเวลา',
              style: TextStyle(color: Colors.white54, fontSize: 11),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: () => showDialog(context: context, builder: (_) => const AuthDialog()),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00F2FE), foregroundColor: Colors.black),
              child: const Text('เข้าสู่ระบบ BM DJ (Login)'),
            ),
          ],
        ),
      );
    }

    if (!auth.isYTMusicConnected) {
      return Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF141824),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFF0033).withAlpha(120)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFF0033).withAlpha(30),
                ),
                child: const Icon(Icons.play_circle_fill, color: Color(0xFFFF0033), size: 42),
              ),
              const SizedBox(height: 12),
              const Text(
                'เชื่อมต่อบัญชี YouTube Music',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'ดึงเพลงที่คุณเพิ่งฟัง (History), เพลงที่กดถูกใจ (Liked Songs), และเพลย์ลิสต์ส่วนตัวใน YouTube Music มามิกซ์บน BM DJ ได้ทันที!',
                style: TextStyle(color: Colors.grey[400], fontSize: 11, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: () => showDialog(context: context, builder: (_) => const YTMusicConnectDialog()),
                icon: const Icon(Icons.link, size: 16),
                label: const Text('คลิกเพื่อเชื่อมต่อ YouTube Music'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF0033),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Sub-bar for private library: History, Liked, User Playlists
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          color: const Color(0xFF131722),
          child: Row(
            children: [
              _buildLibSubTabBtn(index: 0, label: 'ประวัติการฟัง (History)', icon: Icons.history),
              const SizedBox(width: 6),
              _buildLibSubTabBtn(index: 1, label: 'เพลงที่ชอบ (Liked)', icon: Icons.favorite),
              const SizedBox(width: 6),
              _buildLibSubTabBtn(index: 2, label: 'เพลย์ลิสต์ของฉัน (Playlists)', icon: Icons.playlist_play),
              const Spacer(),
              IconButton(
                tooltip: 'รีเฟรชข้อมูลคลังเพลง',
                icon: const Icon(Icons.refresh, color: Colors.white70, size: 18),
                onPressed: _loadYTMusicLibrary,
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoadingYtmLib
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF0033)))
              : _buildPrivateLibContent(),
        ),
      ],
    );
  }

  Widget _buildLibSubTabBtn({required int index, required String label, required IconData icon}) {
    final isSelected = _ytmLibSubTab == index;
    return InkWell(
      onTap: () {
        setState(() => _ytmLibSubTab = index);
        if (_ytmHistory.isEmpty && _ytmLiked.isEmpty) {
          _loadYTMusicLibrary();
        }
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFF0033).withAlpha(40) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? const Color(0xFFFF0033) : Colors.transparent),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: isSelected ? const Color(0xFFFF0033) : Colors.white60),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrivateLibContent() {
    if (_ytmLibSubTab == 0) {
      if (_ytmHistory.isEmpty) return _buildEmptyTab('ไม่มีประวัติการฟังล่าสุด หรือกดรีเฟรชเพื่อดึงข้อมูลใหม่');
      return _buildTracksGrid(_ytmHistory);
    } else if (_ytmLibSubTab == 1) {
      if (_ytmLiked.isEmpty) return _buildEmptyTab('ยังไม่มีเพลงที่ถูกใจใน YouTube Music');
      return _buildTracksGrid(_ytmLiked);
    } else {
      if (_ytmUserPlaylists.isEmpty) return _buildEmptyTab('ยังไม่มีเพลย์ลิสต์ใน YouTube Music ของคุณ');
      return GridView.builder(
        padding: const EdgeInsets.all(10),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 260,
          childAspectRatio: 2.2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: _ytmUserPlaylists.length,
        itemBuilder: (context, index) => _buildPlaylistCard(_ytmUserPlaylists[index]),
      );
    }
  }

  Widget _buildTracksGrid(List<Track> list) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final colCount = (constraints.maxWidth / 200).floor().clamp(2, 6);
        return GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: colCount,
            childAspectRatio: 1.15,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: list.length,
          itemBuilder: (context, index) => _buildYouDjTrackCard(list[index]),
        );
      },
    );
  }

  Widget _buildEmptyTab(String msg) {
    if (_ytmWarning == 'api_not_enabled') {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 560),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF161A26),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withAlpha(120)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.amber.withAlpha(30),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
                    ),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: Text(
                        'ยังไม่ได้เปิดใช้งาน YouTube Data API ใน Google Cloud',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'โปรเจกต์ Google Cloud (103650475879) ยังไม่ได้เปิดใช้งาน "YouTube Data API v3" ทำให้ Google ปฏิเสธการดึงเพลงที่ถูกใจ\nวิธีแก้: คุณสามารถกดเปิดใช้งานใน Google Console หรือเชื่อมต่อด้วย YouTube Music Cookie ได้ทันที',
                  style: TextStyle(color: Colors.grey[400], fontSize: 11, height: 1.4),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: [
                    if (_ytmEnableUrl != null)
                      ElevatedButton.icon(
                        onPressed: () async {
                          final uri = Uri.parse(_ytmEnableUrl!);
                          try {
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            }
                          } catch (e) {
                            debugPrint('Error launching url: $e');
                          }
                        },
                        icon: const Icon(Icons.open_in_new, size: 13),
                        label: const Text('กดเปิดใช้งานใน Google Console'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber[700],
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ),
                    ElevatedButton.icon(
                      onPressed: () => showDialog(context: context, builder: (_) => const YTMusicConnectDialog()),
                      icon: const Icon(Icons.cookie, size: 13),
                      label: const Text('เชื่อมต่อด้วย Cookie แทน'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF0033),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loadYTMusicLibrary,
                      icon: const Icon(Icons.refresh, size: 13),
                      label: const Text('โหลดใหม่'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        side: const BorderSide(color: Colors.white24),
                        textStyle: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline, color: Colors.white24, size: 32),
            const SizedBox(height: 6),
            Text(msg, style: const TextStyle(color: Colors.white54, fontSize: 11), textAlign: TextAlign.center),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _loadYTMusicLibrary,
              icon: const Icon(Icons.refresh, size: 14),
              label: const Text('โหลดข้อมูลใหม่'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A2234),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // VIEW 6: DECK QUEUE VIEW
  // =========================================================================
  Widget _buildQueueView() {
    if (widget.manager.queue.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.queue_music, color: Colors.white24, size: 40),
            const SizedBox(height: 6),
            const Text('คิวเพลงว่างอยู่', style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _loadDemoPresets,
              child: const Text('โหลดเพลง DJ ตัวอย่างเข้าคิว', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: const Color(0xFF131722),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'รายการคิวเล่นเพลง (${widget.manager.queue.length} Tracks)',
                style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                onPressed: () => widget.manager.clearQueue(),
                icon: const Icon(Icons.clear_all, size: 14, color: Colors.redAccent),
                label: const Text('ล้างคิวทั้งหมด', style: TextStyle(color: Colors.redAccent, fontSize: 10)),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(8),
            itemCount: widget.manager.queue.length,
            separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 1),
            itemBuilder: (context, index) {
              final track = widget.manager.queue[index];

              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: track.thumbnailUrl != null
                      ? Image.network(
                          track.thumbnailUrl!,
                          width: 44,
                          height: 32,
                          fit: BoxFit.cover,
                          cacheWidth: 80,
                          cacheHeight: 60,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(Icons.music_note, color: Colors.grey),
                        )
                      : const Icon(Icons.music_note, color: Colors.grey),
                ),
                title: Text(
                  track.title,
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: track.isYtMusic
                            ? const Color(0xFFFF0033).withAlpha(50)
                            : const Color(0xFFFF0000).withAlpha(50),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: track.isYtMusic ? const Color(0xFFFF0033) : const Color(0xFFFF0000),
                          width: 0.6,
                        ),
                      ),
                      child: Text(
                        track.isYtMusic ? 'YT Music' : 'YouTube',
                        style: TextStyle(
                          color: track.isYtMusic ? const Color(0xFFFF6688) : const Color(0xFFFF6666),
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${track.artist} • ${track.formattedDuration}',
                        style: TextStyle(color: Colors.grey[400], fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      onPressed: () => widget.manager.loadTrackToDeck(ActiveDeck.deckA, track),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00F2FE),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 26),
                      ),
                      child: const Text('▶ 1', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 4),
                    ElevatedButton(
                      onPressed: () => widget.manager.loadTrackToDeck(ActiveDeck.deckB, track),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF2A85),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 26),
                      ),
                      child: const Text('▶ 2', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white38, size: 16),
                      onPressed: () => widget.manager.removeFromQueue(index),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // VIEW 7: LIKED SONGS VIEW
  // =========================================================================
  Widget _buildLikedSongsView(AuthService auth) {
    if (!auth.isLoggedIn) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.favorite_border, color: Color(0xFFFF2A85), size: 48),
            const SizedBox(height: 10),
            const Text(
              'เข้าสู่ระบบเพื่อบันทึกเพลงที่ชอบของคุณ',
              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'เมื่อเข้าสู่ระบบ เพลงที่คุณกดถูกใจจะถูกจำไว้ในบัญชีของคุณข้ามทุกอุปกรณ์',
              style: TextStyle(color: Colors.white54, fontSize: 11),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: () => showDialog(context: context, builder: (_) => const AuthDialog()),
              icon: const Icon(Icons.login, size: 16),
              label: const Text('เข้าสู่ระบบ / สมัครสมาชิก (Login)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF2A85),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    final liked = auth.likedTracks;
    if (liked.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_border, color: Colors.white24, size: 40),
            SizedBox(height: 8),
            Text('ยังไม่มีเพลงที่ชอบ', style: TextStyle(color: Colors.white54, fontSize: 12)),
            SizedBox(height: 4),
            Text('กดไอคอนหัวใจบนเพลงเพื่อบันทึกไว้ในบัญชีของคุณได้ทันที', style: TextStyle(color: Colors.white38, fontSize: 10)),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final colCount = (constraints.maxWidth / 200).floor().clamp(2, 6);

        return GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: colCount,
            childAspectRatio: 1.15,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: liked.length,
          itemBuilder: (context, index) => _buildYouDjTrackCard(liked[index]),
        );
      },
    );
  }

  // =========================================================================
  // HELPER CARD WIDGETS
  // =========================================================================

  /// Horizontal Playlist Card (Carousel style)
  Widget _buildPlaylistCardHorizontal(Map<String, dynamic> p) {
    final title = p['title']?.toString() ?? 'Playlist';
    final count = p['count']?.toString() ?? '';
    final thumb = p['thumbnail']?.toString();
    final pId = p['playlist_id']?.toString() ?? '';
    final author = p['author']?.toString();

    return InkWell(
      onTap: () => _loadPlaylist(pId, title, author: author),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 175,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: const Color(0xFF161A26),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: thumb != null && thumb.isNotEmpty
                  ? Image.network(
                      thumb,
                      width: 55,
                      height: 55,
                      fit: BoxFit.cover,
                      cacheWidth: 100,
                      cacheHeight: 100,
                      errorBuilder: (_, _, _) => Container(
                        width: 55,
                        height: 55,
                        color: Colors.white10,
                        child: const Icon(Icons.playlist_play, color: Colors.white38),
                      ),
                    )
                  : Container(
                      width: 55,
                      height: 55,
                      color: Colors.white10,
                      child: const Icon(Icons.playlist_play, color: Colors.white38),
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  if (count.isNotEmpty)
                    Text(
                      '$count เพลง',
                      style: const TextStyle(color: Color(0xFF00F2FE), fontSize: 9.5),
                    ),
                  if (author != null && author.isNotEmpty)
                    Text(
                      author,
                      style: TextStyle(color: Colors.grey[500], fontSize: 8.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Grid Playlist Card
  Widget _buildPlaylistCard(Map<String, dynamic> p) {
    final title = p['title']?.toString() ?? 'Playlist';
    final count = p['count']?.toString() ?? '0';
    final thumb = p['thumbnail']?.toString();
    final pId = p['playlist_id']?.toString() ?? '';
    final author = p['author']?.toString();

    return InkWell(
      onTap: () => _loadPlaylist(pId, title, author: author),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF141824),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: thumb != null && thumb.isNotEmpty
                  ? Image.network(
                      thumb,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      cacheWidth: 90,
                      cacheHeight: 90,
                      errorBuilder: (_, _, _) => Container(
                        width: 50,
                        height: 50,
                        color: Colors.white10,
                        child: const Icon(Icons.playlist_play, color: Colors.white54),
                      ),
                    )
                  : Container(
                      width: 50,
                      height: 50,
                      color: Colors.white10,
                      child: const Icon(Icons.playlist_play, color: Colors.white54),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$count เพลง ${author != null ? "• $author" : ""}',
                    style: TextStyle(color: Colors.grey[400], fontSize: 9.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38, size: 18),
          ],
        ),
      ),
    );
  }

  /// Individual Track Card with YouDJ Style [▶ 1] and [▶ 2] load buttons
  Widget _buildYouDjTrackCard(Track track) {
    final auth = AuthService.instance;
    final isLiked = auth.isTrackLiked(track.videoId);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141824),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 16:9 Thumbnail with Duration Badge and YouDJ [▶ 1] [▶ 2] overlays
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Thumbnail image
                if (track.thumbnailUrl != null)
                  Image.network(
                    track.thumbnailUrl!,
                    fit: BoxFit.cover,
                    cacheWidth: 180,
                    cacheHeight: 100,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: const Color(0xFF1D2230),
                      child: const Icon(Icons.music_note, color: Colors.white24),
                    ),
                  )
                else
                  Container(
                    color: const Color(0xFF1D2230),
                    child: const Icon(Icons.music_note, color: Colors.white24),
                  ),

                // Like/Heart button top-left
                Positioned(
                  left: 4,
                  top: 4,
                  child: GestureDetector(
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
                              duration: const Duration(seconds: 1),
                              backgroundColor: isLikedNow ? const Color(0xFFFF2A85) : Colors.grey[900],
                            ),
                          );
                        }
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(180),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isLiked ? const Color(0xFFFF2A85).withAlpha(120) : Colors.white24,
                          width: 0.8,
                        ),
                      ),
                      child: Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border,
                        color: isLiked ? const Color(0xFFFF2A85) : Colors.white70,
                        size: 15,
                      ),
                    ),
                  ),
                ),

                // Source Badge (YouTube vs YT Music) top-right
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(210),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: track.isYtMusic ? const Color(0xFFFF0033) : const Color(0xFFFF0000),
                        width: 0.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (track.isYtMusic ? const Color(0xFFFF0033) : const Color(0xFFFF0000)).withAlpha(80),
                          blurRadius: 3,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          track.isYtMusic ? Icons.music_note : Icons.play_arrow,
                          size: 9,
                          color: track.isYtMusic ? const Color(0xFFFF0033) : const Color(0xFFFF0000),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          track.isYtMusic ? 'YT Music' : 'YouTube',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 7.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Duration badge bottom right
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(200),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      track.formattedDuration,
                      style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),

                // Center/Bottom Action Overlay (YouDJ exact [▶ 1] and [▶ 2] load buttons!)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.transparent, Colors.black.withAlpha(220)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                    child: Row(
                      children: [
                        // [▶ 1] Load to Deck A
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              widget.manager.loadTrackToDeck(ActiveDeck.deckA, track);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('โหลดเข้า DECK A เรียบร้อย (Standby รอเปิด/ข้ามเพลง)'),
                                  duration: Duration(seconds: 1),
                                  backgroundColor: Color(0xFF0072FF),
                                ),
                              );
                            },
                            child: Container(
                              height: 24,
                              decoration: BoxDecoration(
                                color: const Color(0xFF00F2FE),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.play_arrow, size: 14, color: Colors.black),
                                  Text(
                                    '1',
                                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),

                        // [▶ 2] Load to Deck B
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              widget.manager.loadTrackToDeck(ActiveDeck.deckB, track);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('โหลดเข้า DECK B เรียบร้อย (Standby รอเปิด/ข้ามเพลง)'),
                                  duration: Duration(seconds: 1),
                                  backgroundColor: Color(0xFFFF2A85),
                                ),
                              );
                            },
                            child: Container(
                              height: 24,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF2A85),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.play_arrow, size: 14, color: Colors.white),
                                  Text(
                                    '2',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 3),

                        // [+ Queue]
                        GestureDetector(
                          onTap: () {
                            widget.manager.addToQueue(track);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('เพิ่ม "${track.title}" เข้าคิวแล้ว'),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          },
                          child: Container(
                            height: 24,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              color: Colors.white12,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: const Icon(Icons.add, size: 14, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Title & Artist below thumbnail + Channel & Related tracks action
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
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
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                track.artist,
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 8.5,
                                  decoration: TextDecoration.underline,
                                  decorationColor: Colors.grey[600],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(Icons.open_in_new, size: 7.5, color: Colors.grey[500]),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Tooltip(
                  message: 'วิดีโอที่เกี่ยวข้อง / เล่นถัดไป (Up Next)',
                  child: InkWell(
                    onTap: () {
                      RelatedTracksDialog.show(
                        context,
                        seedTrack: track,
                        manager: widget.manager,
                        source: track.source,
                      );
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.all(3.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00F2FE).withAlpha(25),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF00F2FE).withAlpha(70)),
                      ),
                      child: const Icon(
                        Icons.auto_awesome,
                        size: 12,
                        color: Color(0xFF00F2FE),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
