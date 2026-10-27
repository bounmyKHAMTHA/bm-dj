import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'controllers/dj_deck_manager.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'widgets/auth_dialog.dart';
import 'widgets/ytmusic_connect_dialog.dart';
import 'widgets/deck_panel.dart';
import 'widgets/crossfader_center_panel.dart';
import 'widgets/queue_and_search_panel.dart';
import 'widgets/dual_waveform_bar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService.init();
  await AuthService.instance.init();
  runApp(
    ChangeNotifierProvider(
      create: (_) => DJDeckManager(),
      child: const BMDJApp(),
    ),
  );
}

class BMDJApp extends StatelessWidget {
  const BMDJApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BM DJ - YouTube Music Dual-Deck DJ Console',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0C10),
        primaryColor: const Color(0xFF00F2FE),
        fontFamily: 'Segoe UI',
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00F2FE),
          secondary: Color(0xFFFF2A85),
          surface: Color(0xFF13161F),
        ),
      ),
      home: const DJConsoleScreen(),
    );
  }
}

class DJConsoleScreen extends StatefulWidget {
  const DJConsoleScreen({super.key});

  @override
  State<DJConsoleScreen> createState() => _DJConsoleScreenState();
}

class _DJConsoleScreenState extends State<DJConsoleScreen> {
  final FocusNode _focusNode = FocusNode();
  bool _isBackendConnected = true;
  int _mobileTabIndex = 0; // 0: Dual Deck, 1: Deck A, 2: Deck B, 3: Search & Queue

  @override
  void initState() {
    super.initState();
    _checkBackendStatus();
  }

  Future<void> _checkBackendStatus() async {
    try {
      final res = await ApiService.searchTracks('test', limit: 1);
      if (mounted) {
        setState(() {
          _isBackendConnected = res.isNotEmpty || true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isBackendConnected = false;
        });
      }
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final manager = Provider.of<DJDeckManager>(context, listen: false);

    if (event.logicalKey == LogicalKeyboardKey.space) {
      manager.toggleMasterPlay();
    } else if (event.logicalKey == LogicalKeyboardKey.tab ||
               event.logicalKey == LogicalKeyboardKey.keyS) {
      manager.executeSmoothSkip();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      manager.setManualCrossfader(manager.crossfadePosition - 0.05);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      manager.setManualCrossfader(manager.crossfadePosition + 0.05);
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _showSettingsDialog() {
    final controller = TextEditingController(text: ApiService.baseUrl);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161A24),
        title: const Text('Backend Configuration', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Set Stream Resolver API URL:',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF1A1F2C),
                hintText: 'http://139.180.216.110:8888',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '• Remote VPS: http://139.180.216.110:8888\n• Local Desktop: http://127.0.0.1:8888',
              style: TextStyle(color: Colors.grey[500], fontSize: 11),
            ),
            const SizedBox(height: 14),
            const Divider(color: Colors.white12),
            StatefulBuilder(
              builder: (context, setDialogState) {
                final manager = Provider.of<DJDeckManager>(context, listen: false);
                return SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('โหมดน้ำหนักเบา (Low-Spec Mode)', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  subtitle: const Text('ปิดอนิเมชั่นหนัก ประหยัด CPU/GPU และ RAM สำหรับคอม/มือถือสเปคต่ำ', style: TextStyle(color: Colors.white54, fontSize: 11)),
                  value: manager.lowSpecMode,
                  activeThumbColor: const Color(0xFFFFD700),
                  onChanged: (val) {
                    manager.toggleLowSpecMode();
                    setDialogState(() {});
                  },
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              ApiService.baseUrl = controller.text.trim();
              Navigator.pop(ctx);
              _checkBackendStatus();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00F2FE)),
            child: const Text('Save', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final manager = Provider.of<DJDeckManager>(context);

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF0D0F14),
          elevation: 0,
          toolbarHeight: 44,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00F2FE), Color(0xFFFF2A85)],
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.album, color: Colors.black, size: 16),
              ),
              const SizedBox(width: 8),
              const Text(
                'BM DJ',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: 1.5,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '“ຄຸນນະທຳຄ້ຳຈູນໂລກ ສັດໂລກເປັນໄປຕາມກຳ”',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha((255 * 0.08).round()),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'DUAL ENGINE',
                  style: TextStyle(fontSize: 8, letterSpacing: 0.8, color: Colors.white70),
                ),
              ),
            ],
          ),
          actions: [
            // Live REC Button & Session Tracking
            InkWell(
              onTap: () {
                final wasRecording = manager.isRecording;
                final duration = manager.recordingDuration;
                final tracklist = List<String>.from(manager.recordedTracklist);
                manager.toggleRecording();

                if (wasRecording) {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xFF131620),
                      title: const Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
                          SizedBox(width: 8),
                          Text('DJ Mix Session Summary', style: TextStyle(color: Colors.white, fontSize: 16)),
                        ],
                      ),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Session Time: ${_formatDuration(duration)}',
                            style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(height: 10),
                          const Text('Tracks Played:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 6),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 180),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black38,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: ListView(
                              shrinkWrap: true,
                              children: tracklist.isEmpty
                                  ? [const Text('No tracks logged in this session', style: TextStyle(color: Colors.grey, fontSize: 11))]
                                  : tracklist.map((t) => Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 2),
                                      child: Text('• $t', style: const TextStyle(color: Colors.white, fontSize: 11)),
                                    )).toList(),
                            ),
                          ),
                        ],
                      ),
                      actions: [
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00F2FE)),
                          child: const Text('Close', style: TextStyle(color: Colors.black)),
                        ),
                      ],
                    ),
                  );
                }
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 9),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: manager.isRecording ? Colors.red.withAlpha(80) : Colors.red.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: manager.isRecording ? Colors.redAccent : Colors.redAccent.withAlpha(120),
                    width: manager.isRecording ? 1.5 : 0.8,
                  ),
                  boxShadow: manager.isRecording
                      ? [const BoxShadow(color: Colors.redAccent, blurRadius: 6)]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.fiber_manual_record,
                      color: manager.isRecording ? Colors.redAccent : Colors.redAccent.withAlpha(180),
                      size: 10,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      manager.isRecording
                          ? 'REC ${_formatDuration(manager.recordingDuration)}'
                          : 'REC',
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Low-Spec & Eco Mode Switcher Button
            IconButton(
              tooltip: manager.lowSpecMode
                  ? '⚡ โหมดน้ำหนักเบา (Low-Spec): เปิดอยู่ (ประหยัด CPU/GPU/RAM)'
                  : '⚡ เปิดโหมดน้ำหนักเบา (Low-Spec Mode สำหรับเครื่องสเปคต่ำ)',
              icon: Icon(
                Icons.bolt,
                color: manager.lowSpecMode ? const Color(0xFFFFD700) : Colors.white38,
                size: 20,
              ),
              onPressed: () {
                manager.toggleLowSpecMode();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      manager.lowSpecMode
                          ? '⚡ เปิดโหมดน้ำหนักเบา (Low-Spec): ปิดอนิเมชั่นหนัก ประหยัด CPU/RAM สำหรับคอม/มือถือสเปคต่ำ'
                          : '✨ โหมดมาตรฐาน: เปิดกราฟิกและเอฟเฟกต์เต็มรูปแบบ',
                    ),
                    backgroundColor: manager.lowSpecMode ? const Color(0xFF1F2815) : const Color(0xFF202738),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
            IconButton(
              tooltip: 'Shortcuts: Space, Tab/S, Arrow Keys',
              icon: const Icon(Icons.keyboard, color: Colors.white70, size: 18),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Shortcuts: [Space] Master Play/Pause | [Tab/S] Smooth Skip | [◀ / ▶] Shift Crossfader',
                    ),
                    duration: Duration(seconds: 4),
                  ),
                );
              },
            ),
            // User Account Button
            ListenableBuilder(
              listenable: AuthService.instance,
              builder: (context, _) {
                final auth = AuthService.instance;
                final isLoggedIn = auth.isLoggedIn;
                final username = auth.currentUser?.username ?? '';

                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 7, horizontal: 3),
                  child: OutlinedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => const AuthDialog(),
                      );
                    },
                    icon: Icon(
                      isLoggedIn ? Icons.account_circle : Icons.person_outline,
                      color: isLoggedIn ? const Color(0xFF00F2FE) : Colors.white70,
                      size: 15,
                    ),
                    label: Text(
                      isLoggedIn ? username : 'เข้าสู่ระบบ',
                      style: TextStyle(
                        color: isLoggedIn ? const Color(0xFF00F2FE) : Colors.white70,
                        fontSize: 10,
                        fontWeight: isLoggedIn ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: isLoggedIn ? const Color(0xFF00F2FE).withAlpha(140) : Colors.white24,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 0),
                      minimumSize: const Size(0, 28),
                      backgroundColor: isLoggedIn ? const Color(0xFF00F2FE).withAlpha(25) : Colors.transparent,
                    ),
                  ),
                );
              },
            ),

            // YouTube Music Connect Button
            ListenableBuilder(
              listenable: AuthService.instance,
              builder: (context, _) {
                final auth = AuthService.instance;
                final isConnected = auth.isYTMusicConnected;

                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 7, horizontal: 3),
                  child: OutlinedButton.icon(
                    onPressed: () {
                      if (!auth.isLoggedIn) {
                        showDialog(context: context, builder: (_) => const AuthDialog());
                      } else {
                        showDialog(context: context, builder: (_) => const YTMusicConnectDialog());
                      }
                    },
                    icon: const Icon(
                      Icons.play_circle_fill,
                      color: Color(0xFFFF0033),
                      size: 14,
                    ),
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'YT Music',
                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isConnected ? const Color(0xFF00F2FE) : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: isConnected ? const Color(0xFFFF0033).withAlpha(160) : Colors.white12,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 0),
                      minimumSize: const Size(0, 28),
                      backgroundColor: isConnected ? const Color(0xFFFF0033).withAlpha(30) : Colors.transparent,
                    ),
                  ),
                );
              },
            ),

            IconButton(
              tooltip: 'Backend Settings',
              icon: const Icon(Icons.settings, color: Colors.white70, size: 18),
              onPressed: _showSettingsDialog,
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: Column(
          children: [
            // Full-Width Continuous Dual Waveform Bar (like YouDJ Desktop top strip)
            DualWaveformBar(manager: manager),

            // Main Body Area
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isDesktop = constraints.maxWidth >= 950;

                  if (isDesktop) {
                    return _buildDesktopLayout(manager);
                  } else {
                    return _buildMobileLayout(manager);
                  }
                },
              ),
            ),
          ],
        ),
        bottomNavigationBar: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 950;
            if (isDesktop) return const SizedBox.shrink();

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Persistent Sticky Mini-Crossfader Dock on Mobile (when in single deck or search tab)
                if (_mobileTabIndex != 0) _buildMobileMiniCrossfaderDock(manager),

                // Bottom Navigation Tabs
                Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFF0F121A),
                    border: Border(top: BorderSide(color: Colors.white12)),
                  ),
                  child: BottomNavigationBar(
                    currentIndex: _mobileTabIndex,
                    onTap: (index) => setState(() => _mobileTabIndex = index),
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    selectedItemColor: const Color(0xFF00F2FE),
                    unselectedItemColor: Colors.grey[500],
                    selectedFontSize: 11,
                    unselectedFontSize: 10,
                    type: BottomNavigationBarType.fixed,
                    items: const [
                      BottomNavigationBarItem(
                        icon: Icon(Icons.dashboard_customize),
                        label: 'Dual Deck',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.album, color: Color(0xFF00F2FE)),
                        label: 'Deck A',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.album, color: Color(0xFFFF2A85)),
                        label: 'Deck B',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.queue_music),
                        label: 'Search/Queue',
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // Desktop Layout (YouDJ Style: Compact Upper DJ Decks + Master Mixer, Lower YouTube Music Library)
  Widget _buildDesktopLayout(DJDeckManager manager) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBackendWarning(),
        // Upper DJ Decks & Center Mixer (compact and space-saving)
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 3, 10, 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Deck A (16:9 Video Screen with Red Play Button + Controls)
              Expanded(
                flex: 5,
                child: DeckPanel(
                  deck: ActiveDeck.deckA,
                  manager: manager,
                  accentColor: const Color(0xFF00F2FE),
                  deckName: 'DECK A',
                  isCompact: true,
                  onLoadTrackPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('เลือกเพลงด้านล่าง แล้วกดปุ่ม "▶ 1" เพื่อใส่ใน Deck A ได้ทันทีครับ'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),

              // Center Mixer (BPM, Dual Vertical Volume Faders, Crossfader)
              Expanded(
                flex: 4,
                child: CrossfaderCenterPanel(manager: manager),
              ),
              const SizedBox(width: 8),

              // Deck B (16:9 Video Screen with Red Play Button + Controls)
              Expanded(
                flex: 5,
                child: DeckPanel(
                  deck: ActiveDeck.deckB,
                  manager: manager,
                  accentColor: const Color(0xFFFF2A85),
                  deckName: 'DECK B',
                  isCompact: true,
                  onLoadTrackPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('เลือกเพลงด้านล่าง แล้วกดปุ่ม "▶ 2" เพื่อใส่ใน Deck B ได้ทันทีครับ'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // Lower YouTube Music Search, History & Queue Panel (Fills remainder, internal scroll)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: QueueAndSearchPanel(manager: manager),
          ),
        ),
      ],
    );
  }

  // Mobile Layout with Tab Switching
  Widget _buildMobileLayout(DJDeckManager manager) {
    return Column(
      children: [
        _buildBackendWarning(),

        // Tab Content
        Expanded(
          child: IndexedStack(
            index: _mobileTabIndex,
            children: [
              // Tab 0: Dual Deck Mode (Compact Turntables + Crossfader in one mobile view)
              SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Column(
                  children: [
                    // Deck A (Compact)
                    DeckPanel(
                      deck: ActiveDeck.deckA,
                      manager: manager,
                      accentColor: const Color(0xFF00F2FE),
                      deckName: 'DECK A',
                      isCompact: true,
                      onLoadTrackPressed: () => setState(() => _mobileTabIndex = 3),
                    ),
                    const SizedBox(height: 10),

                    // Center Crossfader & Smooth Skip
                    CrossfaderCenterPanel(manager: manager),
                    const SizedBox(height: 10),

                    // Deck B (Compact)
                    DeckPanel(
                      deck: ActiveDeck.deckB,
                      manager: manager,
                      accentColor: const Color(0xFFFF2A85),
                      deckName: 'DECK B',
                      isCompact: true,
                      onLoadTrackPressed: () => setState(() => _mobileTabIndex = 3),
                    ),
                    const SizedBox(height: 14),
                  ],
                ),
              ),

              // Tab 1: Full Deck A
              SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: DeckPanel(
                  deck: ActiveDeck.deckA,
                  manager: manager,
                  accentColor: const Color(0xFF00F2FE),
                  deckName: 'DECK A',
                  isCompact: false,
                  onLoadTrackPressed: () => setState(() => _mobileTabIndex = 3),
                ),
              ),

              // Tab 2: Full Deck B
              SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: DeckPanel(
                  deck: ActiveDeck.deckB,
                  manager: manager,
                  accentColor: const Color(0xFFFF2A85),
                  deckName: 'DECK B',
                  isCompact: false,
                  onLoadTrackPressed: () => setState(() => _mobileTabIndex = 3),
                ),
              ),

              // Tab 3: Search & Queue (Bounded height with internal scrolling)
              Padding(
                padding: const EdgeInsets.all(8),
                child: QueueAndSearchPanel(manager: manager),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Sticky Mini-Crossfader Dock on Mobile
  Widget _buildMobileMiniCrossfaderDock(DJDeckManager manager) {
    const colorA = Color(0xFF00F2FE);
    const colorB = Color(0xFFFF2A85);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: const BoxDecoration(
        color: Color(0xFF151922),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          // Master Play/Pause
          IconButton(
            onPressed: () => manager.toggleMasterPlay(),
            icon: Icon(manager.activePlayer.playing ? Icons.pause_circle_filled : Icons.play_circle_fill),
            color: Colors.white,
            iconSize: 30,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),

          // Deck A Indicator
          Text(
            'A',
            style: TextStyle(
              color: colorA,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),

          // Crossfader Slider
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 6,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: colorA,
                inactiveTrackColor: colorB,
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: manager.crossfadePosition,
                min: 0.0,
                max: 1.0,
                onChanged: manager.isTransitioning
                    ? null
                    : (val) => manager.setManualCrossfader(val),
              ),
            ),
          ),

          // Deck B Indicator
          Text(
            'B',
            style: TextStyle(
              color: colorB,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 8),

          // Mini Smooth Skip Button
          ElevatedButton(
            onPressed: manager.isTransitioning ? null : () => manager.executeSmoothSkip(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0072FF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size(0, 30),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              manager.isTransitioning ? 'FADING' : 'SKIP',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackendWarning() {
    if (_isBackendConnected) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.all(10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orange.withAlpha((255 * 0.15).round()),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orangeAccent),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning, color: Colors.orangeAccent, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Backend not detected. Run run_backend.bat or configure in settings.',
              style: TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
          TextButton(
            onPressed: _checkBackendStatus,
            child: const Text('Retry', style: TextStyle(color: Colors.orangeAccent, fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
