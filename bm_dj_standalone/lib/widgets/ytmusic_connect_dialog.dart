import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';

class YTMusicConnectDialog extends StatefulWidget {
  const YTMusicConnectDialog({super.key});

  @override
  State<YTMusicConnectDialog> createState() => _YTMusicConnectDialogState();
}

class _YTMusicConnectDialogState extends State<YTMusicConnectDialog> {
  final TextEditingController _cookieController = TextEditingController();
  bool _isConnecting = false;

  @override
  void dispose() {
    _cookieController.dispose();
    super.dispose();
  }

  Future<void> _openYouTubeMusicWeb() async {
    final uri = Uri.parse('https://music.youtube.com');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Could not launch URL: $e');
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    if (data != null && data.text != null) {
      setState(() {
        _cookieController.text = data.text!;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('วางข้อมูลจากคลิปบอร์ดแล้ว'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _connect() async {
    final text = _cookieController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาวาง Cookie หรือ Request Headers ของ YouTube Music ก่อนครับ')),
      );
      return;
    }

    setState(() => _isConnecting = true);
    final success = await AuthService.instance.connectYouTubeMusic(text);
    if (!mounted) return;
    setState(() => _isConnecting = false);

    if (success) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 เชื่อมต่อ YouTube Music สำเร็จ! เพลงและเพลย์ลิสต์ของคุณพร้อมให้ดีเจมิกซ์แล้ว'),
          backgroundColor: Color(0xFF00F2FE),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AuthService.instance.errorMessage ?? 'การเชื่อมต่อไม่สำเร็จ กรุณาตรวจสอบ Cookie อีกครั้ง'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _disconnect() async {
    final success = await AuthService.instance.disconnectYouTubeMusic();
    if (!mounted) return;
    if (success) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ยกเลิกการเชื่อมต่อ YouTube Music แล้ว')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AuthService.instance,
      builder: (context, _) {
        final auth = AuthService.instance;
        final isConnected = auth.isYTMusicConnected;

        return Dialog(
          backgroundColor: const Color(0xFF141824),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.white12),
          ),
          child: Container(
            width: 520,
            padding: const EdgeInsets.all(22),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF0033).withAlpha(30),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.play_circle_fill, color: Color(0xFFFF0033), size: 28),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'เชื่อมต่อ YouTube Music',
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            Row(
                              children: [
                                Icon(
                                  Icons.circle,
                                  size: 8,
                                  color: isConnected ? const Color(0xFF00F2FE) : Colors.orangeAccent,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isConnected ? 'สถานะ: เชื่อมต่อแล้ว (Connected)' : 'สถานะ: ยังไม่ได้เชื่อมต่อ',
                                  style: TextStyle(
                                    color: isConnected ? const Color(0xFF00F2FE) : Colors.orangeAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
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

                  if (isConnected) ...[
                    // Already connected view
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F121A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF00F2FE).withAlpha(100)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.check_circle, color: Color(0xFF00F2FE), size: 18),
                              SizedBox(width: 8),
                              Text(
                                'บัญชี YouTube Music เชื่อมต่ออยู่กับ BM DJ',
                                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'คุณสามารถเข้าถึง "ประวัติการฟัง (History)", "เพลงที่ชอบ (Liked Songs)", และ "เพลย์ลิสต์ของฉัน" ได้ที่แถบ YouTube Music ด้านซ้ายทันที',
                            style: TextStyle(color: Colors.grey[400], fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _disconnect,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                              side: const BorderSide(color: Colors.redAccent),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            child: const Text('ตัดการเชื่อมต่อ (Disconnect)', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00F2FE),
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            child: const Text('ปิดหน้าต่าง', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    // Step 1: Open Browser
                    const Text(
                      'ขั้นตอนที่ 1: เข้าสู่ระบบใน YouTube Music',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      onPressed: _openYouTubeMusicWeb,
                      icon: const Icon(Icons.open_in_new, size: 16, color: Color(0xFFFF0033)),
                      label: const Text('คลิกเปิด music.youtube.com ในเบราว์เซอร์', style: TextStyle(color: Colors.white, fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Step 2: Copy Cookie
                    const Text(
                      'ขั้นตอนที่ 2: คัดลอก Cookie หรือ Request Headers',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D1017),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Text(
                        '1. ในหน้าเว็บ music.youtube.com กด F12 (Developer Tools)\n'
                        '2. ไปที่แท็บ Network > เลือกคำขอใดก็ได้ (เช่น /browse หรือ /player)\n'
                        '3. คลิกขวาที่ Request Headers > Copy > Copy request headers\n'
                        '   (หรือคัดลอกเฉพาะค่าของ "Cookie:" มาวางได้เลย)',
                        style: TextStyle(color: Colors.grey[400], fontSize: 11, height: 1.4),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Step 3: Paste and connect
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'ขั้นตอนที่ 3: วาง Cookie หรือ Request Headers',
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        TextButton.icon(
                          onPressed: _pasteFromClipboard,
                          icon: const Icon(Icons.paste, size: 14, color: Color(0xFF00F2FE)),
                          label: const Text('วาง (Paste)', style: TextStyle(color: Color(0xFF00F2FE), fontSize: 11)),
                          style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _cookieController,
                      maxLines: 4,
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace'),
                      decoration: InputDecoration(
                        hintText: 'วาง Cookie (เช่น SAPISID=...; __Secure-3PAPISID=...) หรือ Request Headers ที่นี่...',
                        hintStyle: TextStyle(color: Colors.grey[600], fontSize: 11),
                        filled: true,
                        fillColor: const Color(0xFF0A0C10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.white12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFF00F2FE)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Connect button
                    ElevatedButton(
                      onPressed: _isConnecting ? null : _connect,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF0033),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: _isConnecting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text(
                              'เชื่อมต่อ YOUTUBE MUSIC (CONNECT)',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                            ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
