import 'package:fl_clash/controller.dart';
import 'package:fl_clash/services/api_client.dart';
import 'package:fl_clash/services/auth_service.dart';
import 'package:fl_clash/services/shop_service.dart';
import 'package:fl_clash/views/orders.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class WalletView extends StatefulWidget {
  const WalletView({super.key});
  @override
  State<WalletView> createState() => _WalletViewState();
}

class _WalletViewState extends State<WalletView> {
  final _amountCtrl = TextEditingController();
  bool _isLoading = false;
  int? _balance;
  bool _autoRenew = false;
  bool _renewLoading = false;
  final _presetAmounts = [6, 30, 68, 128, 256, 328, 648, 1280];

  @override
  void initState() {
    super.initState();
    _loadBalance();
  }

  @override
  void dispose() { _amountCtrl.dispose(); super.dispose(); }

  Future<void> _loadBalance() async {
    try {
      final info = await authService.getUserInfo();
      if (mounted) {
        setState(() {
          _balance = info.balance;
          _autoRenew = info.autoRenewal ?? false;
        });
      }
    } catch (_) {}
  }

  Future<void> _deposit() async {
    final amtText = _amountCtrl.text.trim();
    if (amtText.isEmpty) return;
    final amt = double.tryParse(amtText);
    if (amt == null || amt <= 0) return;
    setState(() => _isLoading = true);
    try {
      final amountInCents = (amt * 100).round().toString();
      final result = await shopService.createDeposit(amountInCents);
      if (mounted) {
        final tradeNo = result['trade_no'] as String? ?? '';
        if (tradeNo.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('充值订单已创建: $tradeNo'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
          // 获取订单详情后直接跳转到支付页面
          final detail = await shopService.getOrderDetail(tradeNo);
          if (mounted && detail.isNotEmpty) {
            final orderItem = OrderItem(
              tradeNo: tradeNo,
              planId: 0,
              totalAmount: (detail['total_amount'] as num?)?.toDouble() ?? 0,
              status: detail['status'] as int? ?? 0,
              period: detail['period'] as String?,
              createdAt: detail['created_at'] as int? ?? 0,
            );
            if (mounted) {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => OrderDetailPage(
                  order: orderItem,
                  formatTime: (ts) {
                    if (ts <= 0) return '';
                    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
                    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                  },
                ),
              ));
            }
          } else {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const OrdersView(),
            ));
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('充值订单创建成功')));
        }
      }
    } catch (e) {
      final msg = e.toString();
      if (mounted) {
        if (msg.contains('500')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('可能存在未支付的充值订单，请到订单列表查看')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('充值失败: $e')));
        }
      }
    } finally { if (mounted) setState(() => _isLoading = false); }
  }

  Widget _amountItem(int a) {
    final sel = _amountCtrl.text == a.toString();
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(left: 4, right: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _amountCtrl.text = a.toString()),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: sel ? cs.primary : cs.outlineVariant,
                width: sel ? 1.5 : 1,
              ),
              color: sel ? cs.primaryContainer : null,
            ),
            child: Center(
              child: Text('¥$a', style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: sel ? cs.onPrimaryContainer : cs.onSurface,
              )),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final balanceStr = _balance != null ? (_balance! / 100).toStringAsFixed(2) : '--';

    return Scaffold(
      appBar: AppBar(title: const Text('我的钱包')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // 余额卡片
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(children: [
              Text('账户余额', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
              const SizedBox(height: 6),
              Text('¥$balanceStr',
                  style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: cs.onSurface)),
              const SizedBox(height: 6),
              Text('充值后的余额仅限消费',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ]),
          ),
        ),
        const SizedBox(height: 12),

        // 自动续费
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.repeat_rounded, color: cs.onTertiaryContainer, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('自动续费', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                Text('到期时自动续费套餐', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ])),
              _renewLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Switch(
                      value: _autoRenew,
                      onChanged: (v) async {
                        setState(() => _renewLoading = true);
                        final previous = _autoRenew;
                        setState(() => _autoRenew = v);
                        try {
                          await apiClient.post('/user/update', data: {
                            'auto_renewal': v ? 1 : 0,
                          });
                        } catch (e) {
                          setState(() => _autoRenew = previous);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('操作失败')),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _renewLoading = false);
                        }
                      },
                    ),
            ]),
          ),
        ),
        const SizedBox(height: 12),

        // 充值金额
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.sell_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 6),
                Text('充值余额', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              ]),
              const SizedBox(height: 6),
              Text('充值后的余额仅限消费，无法提现',
                  style: TextStyle(fontSize: 12, color: cs.error.withValues(alpha: 0.8))),
              const SizedBox(height: 12),
              // 预设金额：两行四列
              Column(
                children: [
                  Row(
                    children: _presetAmounts.sublist(0, 4).map((a) => _amountItem(a)).toList(),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: _presetAmounts.sublist(4, 8).map((a) => _amountItem(a)).toList(),
                  ),
                ],
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),

        // 自定义金额
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.edit_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 6),
                Text('自定义金额', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              ]),
              const SizedBox(height: 14),
              TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: '¥ 请输入充值金额',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isLoading ? null : _deposit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    backgroundColor: cs.error,
                  ),
                  child: _isLoading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('立即充值', style: TextStyle(fontSize: 15)),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _PaymentRedirect extends StatelessWidget {
  final String tradeNo;
  const _PaymentRedirect({required this.tradeNo});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('充值')),
      body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.check_circle_rounded, size: 64, color: Colors.green.shade400),
          const SizedBox(height: 16),
          const Text('充值订单已创建', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('订单号: $tradeNo', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => _DepositPaymentPage(tradeNo: tradeNo)),
              );
            },
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromWidth(200),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('去支付'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
            child: const Text('稍后支付'),
          ),
        ]),
      ),
    );
  }
}

/// 充值支付页（EZ 风格）
class _DepositPaymentPage extends StatefulWidget {
  final String tradeNo;
  const _DepositPaymentPage({required this.tradeNo});
  @override
  State<_DepositPaymentPage> createState() => _DepositPaymentPageState();
}

class _DepositPaymentPageState extends State<_DepositPaymentPage> {
  List<PaymentMethod> _methods = [];
  bool _isLoading = true;
  bool _loadError = false;
  bool _isPaying = false;

  @override
  void initState() { super.initState(); _loadMethods(); }

  Future<void> _loadMethods() async {
    try {
      final m = await shopService.getPaymentMethods();
      if (mounted) setState(() { _methods = m; _isLoading = false; });
    } catch (_) { if (mounted) setState(() { _isLoading = false; _loadError = true; }); }
  }

  Future<void> _pay(String methodId) async {
    setState(() { _selectedMethodId = methodId; _isPaying = true; });
    try {
      final c = await shopService.checkoutOrder(widget.tradeNo, methodId);
      if (mounted && c.type == 1 && c.data.isNotEmpty) {
        final uri = Uri.tryParse(c.data);
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          appController.syncSubscriptionNow();
        }
      }
    } catch (_) {}
    finally { if (mounted) setState(() => _isPaying = false); }
  }

  String? _selectedMethodId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('支付')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_off_rounded, size: 48, color: cs.error.withValues(alpha: 0.7)),
                      const SizedBox(height: 12),
                      Text('加载失败', style: TextStyle(color: cs.onSurfaceVariant)),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () {
                          setState(() { _isLoading = true; _loadError = false; });
                          _loadMethods();
                        },
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : _methods.isEmpty
              ? const Center(child: Text('暂无可用的支付方式'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: _methods.map((m) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    elevation: 0,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _isPaying ? null : () => _pay(m.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(children: [
                          Icon(
                            m.handler?.contains('alipay') == true ? Icons.account_balance_wallet_rounded :
                            m.handler?.contains('wx') == true || m.handler?.contains('wechat') == true ? Icons.chat_rounded :
                            Icons.payment_rounded,
                            color: cs.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(m.name.isNotEmpty ? m.name : (m.handler ?? '支付方式'),
                              style: TextStyle(fontWeight: FontWeight.w500))),
                          if (_isPaying && _selectedMethodId == m.id)
                            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          else
                            Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                        ]),
                      ),
                    ),
                  )).toList(),
                ),
    );
  }
}
