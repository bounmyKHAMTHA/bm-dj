import 'package:flutter/material.dart';
import '../models/time_package.dart';
import '../services/auth_service.dart';
import 'topup_dialog.dart';

class PackageStoreDialog extends StatefulWidget {
  const PackageStoreDialog({super.key});

  @override
  State<PackageStoreDialog> createState() => _PackageStoreDialogState();
}

class _PackageStoreDialogState extends State<PackageStoreDialog> {
  bool _isLoading = true;
  List<TimePackageModel> _packages = [];
  int? _buyingPackageId;

  @override
  void initState() {
    super.initState();
    _loadPackages();
  }

  Future<void> _loadPackages() async {
    setState(() => _isLoading = true);
    final list = await AuthService.instance.fetchPackages();
    if (mounted) {
      setState(() {
        _packages = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleBuy(TimePackageModel pkg) async {
    final user = AuthService.instance.currentUser;
    if (user == null) return;

    if (user.walletBalance < pkg.currentPrice) {
      final needed = pkg.currentPrice - user.walletBalance;
      final shouldTopUp = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF161A24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B), size: 28),
              SizedBox(width: 10),
              Text('ยอดเงินในกระเป๋าไม่เพียงพอ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: Text(
            'คุณต้องการซื้อ ${pkg.name} (${pkg.currentPrice.toStringAsFixed(2)} ฿)\n'
            'แต่ในกระเป๋ามี ${user.walletBalanceFormatted} (ยังขาดอีก ${needed.toStringAsFixed(2)} ฿)\n\n'
            'คุณต้องการไปหน้าเติมเงินเข้ากระเป๋าตอนนี้เลยหรือไม่?',
            style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ยกเลิก', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.account_balance_wallet, size: 16, color: Colors.white),
              label: const Text('ไปหน้าเติมเงิน', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (shouldTopUp == true && mounted) {
        await showDialog(
          context: context,
          builder: (_) => TopUpDialog(suggestedAmount: needed),
        );
        if (mounted) {
          setState(() {}); // refresh wallet balance
        }
      }
      return;
    }

    // Confirm purchase
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161A24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('ยืนยันการซื้อแพ็คเกจ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'คุณต้องการซื้อ "${pkg.name}" ในราคา ${pkg.currentPrice.toStringAsFixed(2)} ฿ ใช่หรือไม่?\n'
          'ระบบจะหักยอดเงินจากกระเป๋าของคุณทันที',
          style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00F2FE)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ยืนยันซื้อ', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _buyingPackageId = pkg.id);
    final res = await AuthService.instance.buyPackage(pkg.id);
    if (!mounted) return;
    setState(() => _buyingPackageId = null);

    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.black, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(res['message'] ?? 'ซื้อแพ็คเกจสำเร็จ!')),
            ],
          ),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['error'] ?? 'ซื้อไม่สำเร็จ'),
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
        width: 860,
        height: 650,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Bar
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F2FE).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.shopping_bag_outlined, color: Color(0xFF00F2FE), size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Text(
                            'ร้านค้าแพ็คเกจเวลา BM DJ',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(width: 8),
                          Icon(Icons.verified, color: Color(0xFF00F2FE), size: 16),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'เติมเวลาใช้งานคุ้มค่า • นับเฉพาะเวลาเปิดแอปเท่านั้น (ปิดแอปเวลาไม่ลด)',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                // Remaining Time Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161B26),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF00F2FE).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.timer_outlined, color: Color(0xFF00F2FE), size: 16),
                      const SizedBox(width: 6),
                      Text(
                        user?.remainingFormatted ?? '0 ชม.',
                        style: const TextStyle(color: Color(0xFF00F2FE), fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Wallet Balance Badge & Top-up Button
                InkWell(
                  onTap: () async {
                    await showDialog(context: context, builder: (_) => const TopUpDialog());
                    if (mounted) setState(() {});
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.account_balance_wallet, color: Color(0xFF10B981), size: 16),
                        const SizedBox(width: 6),
                        Text(
                          user?.walletBalanceFormatted ?? '0.00 ฿',
                          style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.add_circle, color: Color(0xFF10B981), size: 14),
                      ],
                    ),
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

            // Packages Content
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Color(0xFF00F2FE)),
                          SizedBox(height: 14),
                          Text('กำลังโหลดรายการแพ็คเกจ...', style: TextStyle(color: Colors.white70)),
                        ],
                      ),
                    )
                  : _packages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.inventory_2_outlined, color: Colors.white38, size: 50),
                              const SizedBox(height: 12),
                              const Text('ยังไม่มีแพ็คเกจที่เปิดจำหน่ายในขณะนี้', style: TextStyle(color: Colors.white60)),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: _loadPackages,
                                child: const Text('โหลดใหม่'),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _packages.length,
                          itemBuilder: (context, index) {
                            final pkg = _packages[index];
                            final isHot = pkg.isHot;
                            final isUnlimited = pkg.isUnlimited;
                            final isOnSale = pkg.isOnSale;
                            final isBuying = _buyingPackageId == pkg.id;
                            final hasEnoughMoney = (user?.walletBalance ?? 0) >= pkg.currentPrice;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isHot
                                    ? const Color(0xFF191E2C)
                                    : (isUnlimited ? const Color(0xFF1E172E) : const Color(0xFF131722)),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isHot
                                      ? const Color(0xFFF59E0B)
                                      : (isUnlimited
                                          ? const Color(0xFF8B5CF6)
                                          : const Color(0xFF222B3D)),
                                  width: isHot || isUnlimited ? 1.6 : 1.0,
                                ),
                                boxShadow: isHot
                                    ? [
                                        BoxShadow(
                                          color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                                          blurRadius: 10,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  // Icon Badge
                                  Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      color: isUnlimited
                                          ? const Color(0xFF8B5CF6).withValues(alpha: 0.2)
                                          : (isHot
                                              ? const Color(0xFFF59E0B).withValues(alpha: 0.2)
                                              : const Color(0xFF00F2FE).withValues(alpha: 0.15)),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      isUnlimited
                                          ? Icons.workspace_premium
                                          : (isHot ? Icons.local_fire_department : Icons.access_time_filled),
                                      color: isUnlimited
                                          ? const Color(0xFF8B5CF6)
                                          : (isHot ? const Color(0xFFF59E0B) : const Color(0xFF00F2FE)),
                                      size: 28,
                                    ),
                                  ),
                                  const SizedBox(width: 16),

                                  // Details
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              pkg.name,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                              ),
                                            ),
                                            if (isHot) ...[
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFEF4444),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: const Text(
                                                  'HOT ขายดี',
                                                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                            ],
                                            if (isUnlimited) ...[
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF8B5CF6),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: const Text(
                                                  'VIP ตลอดชีพ',
                                                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                            ],
                                            if (isOnSale) ...[
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: const Color(0xFFF59E0B)),
                                                ),
                                                child: const Text(
                                                  'ลดพิเศษ',
                                                  style: TextStyle(color: Color(0xFFF59E0B), fontSize: 10, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          pkg.description,
                                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            const Icon(Icons.timelapse, color: Color(0xFF00F2FE), size: 14),
                                            const SizedBox(width: 4),
                                            Text(
                                              'เวลาที่ได้รับ: ${pkg.hoursDisplay}',
                                              style: const TextStyle(
                                                color: Color(0xFF00F2FE),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(width: 16),

                                  // Price & Buy Button
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      if (isOnSale) ...[
                                        Text(
                                          '${pkg.originalPrice.toStringAsFixed(2)} ฿',
                                          style: const TextStyle(
                                            color: Colors.white54,
                                            decoration: TextDecoration.lineThrough,
                                            fontSize: 12,
                                          ),
                                        ),
                                        Text(
                                          '${pkg.currentPrice.toStringAsFixed(2)} ฿',
                                          style: const TextStyle(
                                            color: Color(0xFFEF4444),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 20,
                                          ),
                                        ),
                                      ] else ...[
                                        Text(
                                          '${pkg.originalPrice.toStringAsFixed(2)} ฿',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 20,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 8),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: hasEnoughMoney
                                              ? const Color(0xFF00F2FE)
                                              : const Color(0xFF263147),
                                          foregroundColor: hasEnoughMoney ? Colors.black : Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                        ),
                                        onPressed: isBuying ? null : () => _handleBuy(pkg),
                                        icon: isBuying
                                            ? const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                              )
                                            : Icon(
                                                hasEnoughMoney
                                                    ? Icons.shopping_cart_checkout
                                                    : Icons.account_balance_wallet,
                                                size: 16,
                                              ),
                                        label: Text(
                                          isBuying
                                              ? 'กำลังซื้อ...'
                                              : (hasEnoughMoney ? 'ซื้อแพ็คเกจนี้' : 'เติมเงินซื้อ'),
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),

            // Footer note
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF141823),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF1E2638)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.shield_outlined, color: Color(0xFF10B981), size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ระบบ Anti-Cheat: เวลาคงเหลือจะถูกนับเฉพาะขณะเปิดใช้งานโปรแกรมและคำนวณผ่านระบบเซิร์ฟเวอร์แบบเรียลไทม์ ปิดแอปเวลาไม่ลด',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
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
}

