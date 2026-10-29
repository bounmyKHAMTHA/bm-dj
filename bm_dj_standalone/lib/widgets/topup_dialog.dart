import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/auth_service.dart';

class TopUpDialog extends StatefulWidget {
  final double? suggestedAmount;

  const TopUpDialog({super.key, this.suggestedAmount});

  @override
  State<TopUpDialog> createState() => _TopUpDialogState();
}

class _TopUpDialogState extends State<TopUpDialog> {
  final TextEditingController _amountController = TextEditingController();
  File? _selectedSlipFile;
  String? _slipBase64;
  bool _isUploading = false;
  bool _isLoadingHistory = false;
  List<Map<String, dynamic>> _transactions = [];
  Map<String, dynamic>? _paymentInfo;

  final List<double> _presetAmounts = [50, 100, 200, 350, 500, 1000];

  @override
  void initState() {
    super.initState();
    if (widget.suggestedAmount != null && widget.suggestedAmount! > 0) {
      _amountController.text = widget.suggestedAmount!.toStringAsFixed(0);
    } else {
      _amountController.text = '100';
    }
    _loadStatus();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    setState(() => _isLoadingHistory = true);
    final data = await AuthService.instance.fetchWalletStatus();
    if (mounted && data != null) {
      setState(() {
        if (data['payment_info'] is Map<String, dynamic>) {
          _paymentInfo = data['payment_info'] as Map<String, dynamic>;
        }
        if (data['transactions'] is List) {
          _transactions = (data['transactions'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
        _isLoadingHistory = false;
      });
    } else if (mounted) {
      setState(() => _isLoadingHistory = false);
    }
  }

  Future<void> _pickSlipImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      );

      if (result != null && result.files.isNotEmpty) {
        final path = result.files.first.path;
        if (path != null) {
          final file = File(path);
          final bytes = await file.readAsBytes();
          final ext = path.split('.').last.toLowerCase();
          final mime = (ext == 'png') ? 'image/png' : 'image/jpeg';
          final base64Str = 'data:$mime;base64,${base64Encode(bytes)}';

          setState(() {
            _selectedSlipFile = file;
            _slipBase64 = base64Str;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการเลือกรูปภาพ: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _submitTopUp() async {
    final amountText = _amountController.text.trim();
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกจำนวนเงินที่ต้องการเติม (มากกว่า 0 บาท)'), backgroundColor: Colors.orange),
      );
      return;
    }

    if (_slipBase64 == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาแนบรูปสลิปการโอนเงินเพื่อตรวจสอบ'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isUploading = true);
    final res = await AuthService.instance.topUpWallet(
      amount: amount,
      slipBase64: _slipBase64,
    );

    if (!mounted) return;
    setState(() => _isUploading = false);

    if (res['success'] == true) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF161A24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Color(0xFF10B981), size: 28),
              SizedBox(width: 10),
              Text('ส่งสลิปเติมเงินสำเร็จ!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(
            'ระบบได้รับข้อมูลสลิปการโอนเงินจำนวน ${amount.toStringAsFixed(2)} บาท เรียบร้อยแล้ว\n\n'
            'แอดมินจะตรวจสอบและกดอนุมัติยอดเงินเข้ากระเป๋าของคุณในระบบหลังบ้าน (Django Admin) โดยเร็วที่สุดครับ',
            style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, height: 1.5),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ตกลง', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      setState(() {
        _selectedSlipFile = null;
        _slipBase64 = null;
      });
      _loadStatus();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['error'] ?? 'เกิดข้อผิดพลาดในการส่งสลิป'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;

    return Dialog(
      backgroundColor: const Color(0xFF0F1219),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF252D3D), width: 1.2),
      ),
      child: Container(
        width: 760,
        height: 640,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.account_balance_wallet, color: Color(0xFF10B981), size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'เติมเงินเข้ากระเป๋า BM DJ Wallet',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'โอนผ่านพร้อมเพย์/บัญชีธนาคาร แล้วแนบสลิปเพื่ออนุมัติยอดเงิน',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A202E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Text('ยอดเงินในกระเป๋า: ', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      Text(
                        user?.walletBalanceFormatted ?? '0.00 ฿',
                        style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'ปิด',
                ),
              ],
            ),
            const Divider(color: Color(0xFF1E2536), height: 24),

            // Content Area (Two Columns)
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Column: Bank QR & Payment details
                  Expanded(
                    flex: 5,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141823),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF222B3D)),
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.qr_code_2, color: Color(0xFF00F2FE), size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'สแกน QR Code พร้อมเพย์',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // PromptPay QR Container
                            Container(
                              width: 170,
                              height: 170,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white, width: 4),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  'https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=0987654321',
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) => const Center(
                                    child: Icon(Icons.qr_code, size: 80, color: Colors.black87),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            // Bank Info Card
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0D1017),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFF1E2538)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildBankInfoRow(
                                    Icons.account_balance,
                                    'ธนาคาร:',
                                    _paymentInfo?['bank_name']?.toString() ?? 'พร้อมเพย์ / กสิกรไทย (K-Bank)',
                                  ),
                                  const SizedBox(height: 6),
                                  _buildBankInfoRow(
                                    Icons.person,
                                    'ชื่อบัญชี:',
                                    _paymentInfo?['account_name']?.toString() ?? 'BM DJ / นายบุนมี คำทา',
                                  ),
                                  const SizedBox(height: 6),
                                  _buildBankInfoRow(
                                    Icons.phone_android,
                                    'พร้อมเพย์:',
                                    _paymentInfo?['promptpay_number']?.toString() ?? '098-XXX-XXXX',
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00F2FE).withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF00F2FE).withValues(alpha: 0.2)),
                              ),
                              child: const Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.info_outline, color: Color(0xFF00F2FE), size: 16),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'หลังโอนเงินเสร็จแล้ว ให้แคปรูปสลิปจากแอพธนาคาร แล้วแนบในช่องด้านขวามือเพื่อส่งให้แอดมินอนุมัติครับ',
                                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, height: 1.4),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 16),

                  // Right Column: Upload Slip & Amount selection
                  Expanded(
                    flex: 6,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '1. เลือกหรือกรอกจำนวนเงินที่โอน (บาท)',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(height: 8),
                          // Preset Buttons
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _presetAmounts.map((amt) {
                              final isSelected = _amountController.text == amt.toStringAsFixed(0);
                              return InkWell(
                                onTap: () {
                                  setState(() {
                                    _amountController.text = amt.toStringAsFixed(0);
                                  });
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isSelected ? const Color(0xFF10B981) : const Color(0xFF1A2130),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSelected ? const Color(0xFF10B981) : const Color(0xFF2A364C),
                                    ),
                                  ),
                                  child: Text(
                                    '${amt.toStringAsFixed(0)} ฿',
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _amountController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                            decoration: InputDecoration(
                              labelText: 'จำนวนเงิน (บาท)',
                              labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                              prefixIcon: const Icon(Icons.monetization_on_outlined, color: Color(0xFF10B981)),
                              suffixText: 'THB',
                              suffixStyle: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                              filled: true,
                              fillColor: const Color(0xFF141823),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.5),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            ),
                          ),

                          const SizedBox(height: 18),

                          const Text(
                            '2. แนบรูปภาพสลิปการโอนเงิน (Slip)',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(height: 8),

                          // Slip picker area
                          InkWell(
                            onTap: _pickSlipImage,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF141823),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _selectedSlipFile != null ? const Color(0xFF10B981) : const Color(0xFF252E40),
                                  width: 1.5,
                                  style: BorderStyle.solid,
                                ),
                              ),
                              child: _selectedSlipFile != null
                                  ? Row(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.file(
                                            _selectedSlipFile!,
                                            width: 70,
                                            height: 70,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 16),
                                                  const SizedBox(width: 6),
                                                  const Text(
                                                    'เลือกรูปภาพสลิปแล้ว',
                                                    style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 13),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                _selectedSlipFile!.path.split(Platform.pathSeparator).last,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                                              ),
                                              const SizedBox(height: 4),
                                              const Text(
                                                'คลิกเพื่อเปลี่ยนรูปสลิป',
                                                style: TextStyle(color: Color(0xFF00F2FE), fontSize: 11),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    )
                                  : Column(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF10B981).withValues(alpha: 0.1),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.add_photo_alternate, color: Color(0xFF10B981), size: 30),
                                        ),
                                        const SizedBox(height: 10),
                                        const Text(
                                          'คลิกเพื่อเลือกไฟล์รูปภาพสลิป',
                                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'รองรับไฟล์ JPG, PNG, WEBP',
                                          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
                                        ),
                                      ],
                                    ),
                            ),
                          ),

                          const SizedBox(height: 18),

                          // Submit Button
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                elevation: 4,
                              ),
                              onPressed: _isUploading ? null : _submitTopUp,
                              icon: _isUploading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.send_rounded),
                              label: Text(
                                _isUploading ? 'กำลังอัปโหลดสลิป...' : 'ส่งสลิปเพื่อตรวจสอบและเติมเงิน',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Recent Transactions Accordion
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'ประวัติการเติมเงินล่าสุด',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              if (_isLoadingHistory)
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF00F2FE)),
                                )
                              else
                                InkWell(
                                  onTap: _loadStatus,
                                  child: const Text('รีเฟรช', style: TextStyle(color: Color(0xFF00F2FE), fontSize: 11)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_transactions.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF141823),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Center(
                                child: Text('ยังไม่มีรายการเติมเงิน', style: TextStyle(color: Colors.white54, fontSize: 11)),
                              ),
                            )
                          else
                            Column(
                              children: _transactions.take(4).map((tx) {
                                final status = tx['status']?.toString() ?? 'PENDING';
                                final isApproved = status == 'APPROVED';
                                final isPending = status == 'PENDING';
                                final statusColor = isApproved
                                    ? const Color(0xFF10B981)
                                    : (isPending ? const Color(0xFFF59E0B) : const Color(0xFFEF4444));
                                final statusText = tx['status_display']?.toString() ?? status;

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF141823),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFF202738)),
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        '+ ${(tx['amount'] as num?)?.toStringAsFixed(2) ?? '0.00'} ฿',
                                        style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          tx['created_at']?.toString() ?? '',
                                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: statusColor.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                                        ),
                                        child: Text(
                                          statusText,
                                          style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 10),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBankInfoRow(IconData icon, String title, String val) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: const Color(0xFF00F2FE)),
        const SizedBox(width: 6),
        Text(title, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            val,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
          ),
        ),
      ],
    );
  }
}
