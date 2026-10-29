import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'package_store_dialog.dart';

class AuthGateDialog extends StatefulWidget {
  final bool isExpired;

  const AuthGateDialog({super.key, this.isExpired = false});

  @override
  State<AuthGateDialog> createState() => _AuthGateDialogState();
}

class _AuthGateDialogState extends State<AuthGateDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _loginUsernameController = TextEditingController();
  final TextEditingController _loginPasswordController = TextEditingController();
  final TextEditingController _regUsernameController = TextEditingController();
  final TextEditingController _regPasswordController = TextEditingController();
  final TextEditingController _regEmailController = TextEditingController();

  bool _obscureLoginPassword = true;
  bool _obscureRegPassword = true;
  String? _googleStatusMessage;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginUsernameController.dispose();
    _loginPasswordController.dispose();
    _regUsernameController.dispose();
    _regPasswordController.dispose();
    _regEmailController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final username = _loginUsernameController.text.trim();
    final password = _loginPasswordController.text.trim();
    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกชื่อผู้ใช้และรหัสผ่านให้ครบถ้วน')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    final success = await AuthService.instance.login(username, password);
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (success) {
      final user = AuthService.instance.currentUser;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ยินดีต้อนรับกลับมา, $username! เวลาคงเหลือ: ${user?.remainingFormatted ?? ""}'),
          backgroundColor: const Color(0xFF10B981),
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
    final username = _regUsernameController.text.trim();
    final password = _regPasswordController.text.trim();
    final email = _regEmailController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกชื่อผู้ใช้และรหัสผ่าน')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    final success = await AuthService.instance.register(username, password, email: email);
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.card_giftcard, color: Colors.black),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'สมัครสมาชิกสำเร็จ! คุณได้รับสิทธิ์ใช้งานฟรี 48 ชั่วโมงเต็ม (นับเฉพาะเวลาเปิดแอป)',
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: Color(0xFF00F2FE),
          duration: Duration(seconds: 4),
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

  Future<void> _handleGoogleSignIn() async {
    setState(() => _googleStatusMessage = 'กำลังเปิดเบราว์เซอร์ Google...');
    final success = await AuthService.instance.startGoogleSignIn(
      onStatusUpdate: (msg) {
        if (mounted) setState(() => _googleStatusMessage = msg);
      },
    );

    if (!mounted) return;
    setState(() => _googleStatusMessage = null);

    if (success) {
      final user = AuthService.instance.currentUser;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เข้าสู่ระบบด้วย Google สำเร็จ! ยินดีต้อนรับ ${user?.username ?? ""}'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AuthService.instance.errorMessage ?? 'เข้าสู่ระบบด้วย Google ไม่สำเร็จ'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;
    final user = auth.currentUser;

    // Expired Screen (User is logged in but time is 0)
    if (widget.isExpired && user != null && !user.hasActiveSubscription) {
      return Container(
        color: Colors.black.withValues(alpha: 0.88),
        alignment: Alignment.center,
        child: Container(
          width: 580,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: const Color(0xFF121622),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.6), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFEF4444).withValues(alpha: 0.25),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.timer_off_outlined, color: Color(0xFFEF4444), size: 48),
              ),
              const SizedBox(height: 18),
              const Text(
                'เวลาการใช้งานของคุณหมดลงแล้ว',
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'สวัสดีคุณ ${user.username}\n'
                'สิทธิ์ทดลองใช้ฟรี 48 ชม. หรือแพ็คเกจเวลาของคุณหมดแล้วครับ\n'
                'คุณสามารถเติมเงินหรือซื้อแพ็คเกจเวลาเพื่อเปิดเพลงมิกซ์ต่อได้ทันที',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF19202E),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Text('ยอดเงินในกระเป๋า: ', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        Text(
                          user.walletBalanceFormatted,
                          style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00F2FE),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 5,
                  ),
                  onPressed: () {
                    showDialog(context: context, builder: (_) => const PackageStoreDialog());
                  },
                  icon: const Icon(Icons.shopping_cart, size: 20),
                  label: const Text(
                    'เปิดร้านค้าแพ็คเกจ / ซื้อเวลาใช้งาน',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => auth.logout(),
                child: const Text('สลับบัญชีผู้ใช้ (ออกจากระบบ)', style: TextStyle(color: Colors.white54, fontSize: 12)),
              ),
            ],
          ),
        ),
      );
    }

    // Login & Register Screen (Blocking Gate)
    return Container(
      color: Colors.black.withValues(alpha: 0.92),
      alignment: Alignment.center,
      child: Container(
        width: 620,
        constraints: const BoxConstraints(maxHeight: 700),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xFF11141E),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF00F2FE).withValues(alpha: 0.4), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00F2FE).withValues(alpha: 0.2),
              blurRadius: 35,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Branding & Trial Banner
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF00F2FE), Color(0xFFFF2A85)]),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.headphones, color: Colors.black, size: 24),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'BM DJ CONSOLE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Free Trial 48H Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF00F2FE).withValues(alpha: 0.15),
                      const Color(0xFF10B981).withValues(alpha: 0.15),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF00F2FE).withValues(alpha: 0.4)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.stars, color: Color(0xFF00F2FE), size: 24),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '🎁 สมาชิกใหม่รับสิทธิ์ใช้งานฟรี 48 ชั่วโมง!',
                            style: TextStyle(color: Color(0xFF00F2FE), fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'นับเฉพาะเวลาเปิดใช้งานโปรแกรมเท่านั้น ปิดแอปเวลาไม่ลดลง',
                            style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Tab Selector
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF171C28),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: const Color(0xFF00F2FE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  labelColor: Colors.black,
                  unselectedLabelColor: Colors.white70,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  tabs: const [
                    Tab(text: 'เข้าสู่ระบบ (Login)'),
                    Tab(text: 'สมัครสมาชิกใหม่ (Register)'),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Tab Views
              SizedBox(
                height: 260,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Login Tab
                    _buildLoginForm(),
                    // Register Tab
                    _buildRegisterForm(),
                  ],
                ),
              ),

              const SizedBox(height: 12),
              // Divider with 'or'
              Row(
                children: [
                  const Expanded(child: Divider(color: Color(0xFF232B3C))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text('หรือ', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
                  ),
                  const Expanded(child: Divider(color: Color(0xFF232B3C))),
                ],
              ),
              const SizedBox(height: 12),

              // Google Sign-In Button
              SizedBox(
                width: double.infinity,
                height: 42,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF2D374D)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    backgroundColor: const Color(0xFF151A26),
                  ),
                  onPressed: _googleStatusMessage != null ? null : _handleGoogleSignIn,
                  icon: const Icon(Icons.g_mobiledata, color: Colors.redAccent, size: 24),
                  label: Text(
                    _googleStatusMessage ?? 'เข้าสู่ระบบด้วยบัญชี Google',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),

              const SizedBox(height: 14),
              // Backend Server Indicator & Switcher
              InkWell(
                onTap: _showServerSwitcherDialog,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161B26),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF232D40)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.circle,
                        size: 8,
                        color: ApiService.baseUrl.contains('127.0.0.1') ? const Color(0xFF10B981) : const Color(0xFF00F2FE),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'เซิร์ฟเวอร์: ${ApiService.baseUrl}',
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        '(คลิกเพื่อสลับ/ตั้งค่า)',
                        style: TextStyle(color: Color(0xFF00F2FE), fontSize: 10, fontWeight: FontWeight.bold),
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

  Future<void> _showServerSwitcherDialog() async {
    final customUrlController = TextEditingController(text: ApiService.baseUrl);
    String? testResult;
    bool isTesting = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF131722),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.dns, color: Color(0xFF00F2FE), size: 22),
              SizedBox(width: 8),
              Text('ตั้งค่า Backend Server', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'เลือกหรือระบุ URL เซิร์ฟเวอร์ที่ต้องการให้โปรแกรมเชื่อมต่อ:',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: customUrlController.text.contains(':8888') ? const Color(0xFF00F2FE) : Colors.white24,
                        ),
                        backgroundColor: customUrlController.text.contains(':8888')
                            ? const Color(0xFF00F2FE).withValues(alpha: 0.15)
                            : Colors.transparent,
                      ),
                      onPressed: () {
                        setDialogState(() {
                          customUrlController.text = 'http://139.180.216.110:8888';
                          testResult = null;
                        });
                      },
                      child: const Text('☁️ VPS (139.180.216.110:8888)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: customUrlController.text.contains('127.0.0.1') ? const Color(0xFF10B981) : Colors.white24,
                        ),
                        backgroundColor: customUrlController.text.contains('127.0.0.1')
                            ? const Color(0xFF10B981).withValues(alpha: 0.15)
                            : Colors.transparent,
                      ),
                      onPressed: () {
                        setDialogState(() {
                          customUrlController.text = 'http://127.0.0.1:8000';
                          testResult = null;
                        });
                      },
                      child: const Text('🖥️ Localhost (ในเครื่อง)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: customUrlController.text.contains('bmdj.syterm8899.com') ? const Color(0xFFFFD700) : Colors.white24,
                        ),
                        backgroundColor: customUrlController.text.contains('bmdj.syterm8899.com')
                            ? const Color(0xFFFFD700).withValues(alpha: 0.15)
                            : Colors.transparent,
                      ),
                      onPressed: () {
                        setDialogState(() {
                          customUrlController.text = 'https://bmdj.syterm8899.com';
                          testResult = null;
                        });
                      },
                      child: const Text('🌐 bmdj.syterm8899.com', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: customUrlController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Server URL',
                    labelStyle: const TextStyle(color: Colors.white60, fontSize: 11),
                    filled: true,
                    fillColor: const Color(0xFF0D1017),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 10),
                if (testResult != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: testResult!.contains('สำเร็จ') ? const Color(0xFF10B981).withValues(alpha: 0.15) : Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      testResult!,
                      style: TextStyle(
                        color: testResult!.contains('สำเร็จ') ? const Color(0xFF10B981) : Colors.redAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isTesting
                  ? null
                  : () async {
                      setDialogState(() {
                        isTesting = true;
                        testResult = 'กำลังทดสอบเชื่อมต่อ...';
                      });
                      try {
                        final testUrl = '${customUrlController.text.trim()}/api/v1/packages/';
                        final res = await http.get(Uri.parse(testUrl)).timeout(const Duration(seconds: 4));
                        setDialogState(() {
                          isTesting = false;
                          if (res.statusCode == 200) {
                            testResult = '✅ เชื่อมต่อสำเร็จ! (HTTP 200 OK)';
                          } else {
                            testResult = '❌ ตอบกลับ HTTP ${res.statusCode} (ไม่ใช่ API ของ BM DJ)';
                          }
                        });
                      } catch (e) {
                        setDialogState(() {
                          isTesting = false;
                          testResult = '❌ ไม่สามารถเชื่อมต่อได้: $e';
                        });
                      }
                    },
              child: isTesting
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00F2FE)))
                  : const Text('ทดสอบเชื่อมต่อ', style: TextStyle(color: Color(0xFF00F2FE))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
              onPressed: () {
                final newUrl = customUrlController.text.trim();
                if (newUrl.isNotEmpty) {
                  ApiService.baseUrl = newUrl;
                  setState(() {});
                }
                Navigator.pop(ctx);
              },
              child: const Text('บันทึก', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _loginUsernameController,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            labelText: 'ชื่อผู้ใช้ (Username)',
            labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
            prefixIcon: const Icon(Icons.person, color: Color(0xFF00F2FE), size: 18),
            filled: true,
            fillColor: const Color(0xFF151924),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _loginPasswordController,
          obscureText: _obscureLoginPassword,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            labelText: 'รหัสผ่าน (Password)',
            labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
            prefixIcon: const Icon(Icons.lock, color: Color(0xFF00F2FE), size: 18),
            suffixIcon: IconButton(
              icon: Icon(_obscureLoginPassword ? Icons.visibility_off : Icons.visibility, color: Colors.white54, size: 18),
              onPressed: () => setState(() => _obscureLoginPassword = !_obscureLoginPassword),
            ),
            filled: true,
            fillColor: const Color(0xFF151924),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 44,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00F2FE),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 4,
            ),
            onPressed: _isSubmitting ? null : _handleLogin,
            child: _isSubmitting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Text('เข้าสู่ระบบ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ),
        ),
      ],
    );
  }

  Widget _buildRegisterForm() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _regUsernameController,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'ตั้งชื่อผู้ใช้ (Username)',
              labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
              prefixIcon: const Icon(Icons.person_add, color: Color(0xFF10B981), size: 18),
              filled: true,
              fillColor: const Color(0xFF151924),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _regPasswordController,
            obscureText: _obscureRegPassword,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'ตั้งรหัสผ่าน (Password)',
              labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
              prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF10B981), size: 18),
              suffixIcon: IconButton(
                icon: Icon(_obscureRegPassword ? Icons.visibility_off : Icons.visibility, color: Colors.white54, size: 18),
                onPressed: () => setState(() => _obscureRegPassword = !_obscureRegPassword),
              ),
              filled: true,
              fillColor: const Color(0xFF151924),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _regEmailController,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'อีเมล (ถ้ามี)',
              labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
              prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF10B981), size: 18),
              filled: true,
              fillColor: const Color(0xFF151924),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 4,
              ),
              onPressed: _isSubmitting ? null : _handleRegister,
              icon: _isSubmitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.card_giftcard, size: 18),
              label: const Text('สมัครสมาชิก (รับฟรี 48 ชม.)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}

