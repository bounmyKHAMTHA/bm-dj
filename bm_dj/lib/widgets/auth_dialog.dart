import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'ytmusic_connect_dialog.dart';

class AuthDialog extends StatefulWidget {
  const AuthDialog({super.key});

  @override
  State<AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends State<AuthDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  bool _obscurePassword = true;
  String? _googleStatusMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _googleStatusMessage = 'กำลังเปิดเบราว์เซอร์ Google Chrome...';
    });

    final success = await AuthService.instance.startGoogleSignIn(
      onStatusUpdate: (msg) {
        if (mounted) {
          setState(() {
            _googleStatusMessage = msg;
          });
        }
      },
    );

    if (!mounted) return;

    if (success) {
      Navigator.pop(context);
      final user = AuthService.instance.currentUser;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เข้าสู่ระบบด้วย Google สำเร็จ! ยินดีต้อนรับ ${user?.username ?? ""}'),
          backgroundColor: const Color(0xFF00F2FE),
        ),
      );
    } else {
      setState(() {
        _googleStatusMessage = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AuthService.instance.errorMessage ?? 'เข้าสู่ระบบด้วย Google ไม่สำเร็จ'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _handleLogin() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกชื่อผู้ใช้และรหัสผ่านให้ครบถ้วน')),
      );
      return;
    }

    final success = await AuthService.instance.login(username, password);
    if (!mounted) return;

    if (success) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ยินดีต้อนรับกลับมา, $username! ข้อมูลและเพลงของคุณถูกโหลดแล้ว'),
          backgroundColor: const Color(0xFF00F2FE),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AuthService.instance.errorMessage ?? 'เข้าสู่ระบบไม่สำเร็จ'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _handleRegister() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final email = _emailController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกชื่อผู้ใช้และรหัสผ่าน')),
      );
      return;
    }

    final success = await AuthService.instance.register(username, password, email: email);
    if (!mounted) return;

    if (success) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('สร้างบัญชีสำเร็จ! ยินดีต้อนรับสู่ BM DJ, $username'),
          backgroundColor: const Color(0xFF0072FF),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AuthService.instance.errorMessage ?? 'สมัครสมาชิกไม่สำเร็จ'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AuthService.instance,
      builder: (context, _) {
        final auth = AuthService.instance;
        final isLoggedIn = auth.isLoggedIn;
        final user = auth.currentUser;

        return Dialog(
          backgroundColor: const Color(0xFF141824),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.white12),
          ),
          child: Container(
            width: 440,
            padding: const EdgeInsets.all(20),
            child: isLoggedIn
                ? _buildLoggedInView(user!)
                : _buildAuthFormView(auth),
          ),
        );
      },
    );
  }

  /// Profile view when user is logged in
  Widget _buildLoggedInView(dynamic user) {
    final auth = AuthService.instance;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFF00F2FE), Color(0xFFFF2A85)],
                ),
              ),
              child: const Icon(Icons.person, color: Colors.black, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.username,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    user.email.isNotEmpty ? user.email : 'BM DJ Account Connected',
                    style: TextStyle(color: Colors.grey[400], fontSize: 11),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white54, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(color: Colors.white12),
        const SizedBox(height: 12),

        // Memory stats badges
        const Text(
          'ความทรงจำที่บันทึกไว้ในบัญชีของคุณ (Synced Memories):',
          style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildStatCard(
              title: 'ประวัติค้นหา',
              count: user.searchHistory.length.toString(),
              icon: Icons.history,
              color: const Color(0xFF00F2FE),
            ),
            const SizedBox(width: 8),
            _buildStatCard(
              title: 'เพลงที่ชอบ',
              count: user.likedTracks.length.toString(),
              icon: Icons.favorite,
              color: const Color(0xFFFF2A85),
            ),
            const SizedBox(width: 8),
            _buildStatCard(
              title: 'คิวเพลงล่าสุด',
              count: user.savedQueue.length.toString(),
              icon: Icons.queue_music,
              color: const Color(0xFFFFD700),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // YouTube Music Link Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F121A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: auth.isYTMusicConnected ? const Color(0xFF00F2FE) : Colors.redAccent.withAlpha(120),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.play_circle_fill, color: Color(0xFFFF0033), size: 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'YouTube Music',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    Row(
                      children: [
                        Icon(
                          Icons.circle,
                          size: 8,
                          color: auth.isYTMusicConnected ? const Color(0xFF00F2FE) : Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          auth.isYTMusicConnected ? 'เชื่อมต่อแล้ว (Connected)' : 'ยังไม่ได้เชื่อมต่อ (Not Connected)',
                          style: TextStyle(
                            color: auth.isYTMusicConnected ? const Color(0xFF00F2FE) : Colors.grey,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  showDialog(
                    context: context,
                    builder: (ctx) => const YTMusicConnectDialog(),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: auth.isYTMusicConnected ? const Color(0xFF1E2638) : const Color(0xFFFF0033),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  minimumSize: const Size(0, 32),
                ),
                child: Text(
                  auth.isYTMusicConnected ? 'ตั้งค่า / จัดการ' : 'เชื่อมต่อ',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Logout Button
        OutlinedButton.icon(
          onPressed: () async {
            await auth.logout();
            if (!mounted) return;
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('ออกจากระบบเรียบร้อย')),
            );
          },
          icon: const Icon(Icons.logout, size: 16, color: Colors.redAccent),
          label: const Text('ออกจากระบบ (Logout)', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.redAccent),
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String count,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0F121A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(height: 4),
            Text(
              count,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              title,
              style: TextStyle(color: Colors.grey[400], fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }

  /// Form view for Login / Register
  Widget _buildAuthFormView(AuthService auth) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Title & Close
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              children: [
                Icon(Icons.account_circle, color: Color(0xFF00F2FE), size: 22),
                SizedBox(width: 8),
                Text(
                  'BM DJ บัญชี & ความทรงจำ',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white54, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'เข้าสู่ระบบเพื่อบันทึกประวัติการค้นหา เพลงที่ชอบ คิวเพลง และเชื่อมต่อ YouTube Music ข้ามทุกอุปกรณ์',
          style: TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 14),

        // Google Sign-In Button
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: const LinearGradient(
              colors: [Color(0xFF242C3D), Color(0xFF181E2B)],
            ),
            border: Border.all(color: const Color(0xFF00F2FE).withAlpha(100)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(90),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: auth.isLoading ? null : _handleGoogleSignIn,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'G',
                        style: TextStyle(
                          color: Color(0xFF4285F4),
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          fontFamily: 'sans-serif',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'เข้าสู่ระบบด้วย Google (Sign in with Google)',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        if (_googleStatusMessage != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF00F2FE).withAlpha(20),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF00F2FE).withAlpha(80)),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(color: Color(0xFF00F2FE), strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _googleStatusMessage!,
                    style: const TextStyle(color: Color(0xFF00F2FE), fontSize: 11),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.cancel, color: Colors.white54, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    AuthService.instance.cancelGoogleSignIn();
                    setState(() => _googleStatusMessage = null);
                  },
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 14),
        Row(
          children: [
            const Expanded(child: Divider(color: Colors.white12)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'หรือเข้าสู่ระบบด้วยชื่อผู้ใช้ (OR)',
                style: TextStyle(color: Colors.grey[500], fontSize: 10),
              ),
            ),
            const Expanded(child: Divider(color: Colors.white12)),
          ],
        ),
        const SizedBox(height: 14),

        // Tabs
        Container(
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF0F121A),
            borderRadius: BorderRadius.circular(8),
          ),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              color: const Color(0xFF0072FF),
              borderRadius: BorderRadius.circular(8),
            ),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            tabs: const [
              Tab(text: 'เข้าสู่ระบบ (Login)'),
              Tab(text: 'สมัครใหม่ (Register)'),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Form fields
        TextField(
          controller: _usernameController,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            labelText: 'ชื่อผู้ใช้ (Username)',
            labelStyle: const TextStyle(color: Colors.grey, fontSize: 12),
            prefixIcon: const Icon(Icons.person, color: Color(0xFF00F2FE), size: 18),
            filled: true,
            fillColor: const Color(0xFF0D1017),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        const SizedBox(height: 10),

        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            labelText: 'รหัสผ่าน (Password)',
            labelStyle: const TextStyle(color: Colors.grey, fontSize: 12),
            prefixIcon: const Icon(Icons.lock, color: Color(0xFFFF2A85), size: 18),
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.grey, size: 18),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
            filled: true,
            fillColor: const Color(0xFF0D1017),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        const SizedBox(height: 16),

        // Submit Button
        ElevatedButton(
          onPressed: auth.isLoading
              ? null
              : () {
                  if (_tabController.index == 0) {
                    _handleLogin();
                  } else {
                    _handleRegister();
                  }
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00F2FE),
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: auth.isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                )
              : AnimatedBuilder(
                  animation: _tabController,
                  builder: (context, _) => Text(
                    _tabController.index == 0 ? 'เข้าสู่ระบบ (LOGIN)' : 'สมัครสมาชิก (REGISTER)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
        ),
      ],
    );
  }
}
