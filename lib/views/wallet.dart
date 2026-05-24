import 'package:fl_clash/services/shop_service.dart';
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
  final _presetAmounts = [10, 30, 50, 100, 200, 500];

  @override
  void dispose() { _amountCtrl.dispose(); super.dispose(); }

  Future<void> _deposit() async {
    final amtText = _amountCtrl.text.trim();
    if (amtText.isEmpty) return;
    final amt = double.tryParse(amtText);
    if (amt == null || amt <= 0) return;
    setState(() => _isLoading = true);
    try {
      // API 以分为单位
      final amountInCents = (amt * 100).round().toString();
      final result = await shopService.createDeposit(amountInCents);
      if (mounted) {
        final tradeNo = result['trade_no'] as String? ?? '';
        if (tradeNo.isNotEmpty) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => _PaymentRedirect(tradeNo: tradeNo, type: 'deposit'),
          ));
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('钱包充值')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
          Text('账户余额', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
          const SizedBox(height: 4),
          Text('¥0.00', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: cs.primary)),
        ]))),
        const SizedBox(height: 16),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
          const Text('选择充值金额', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: _presetAmounts.map((a) => ChoiceChip(
            label: Text('¥$a'),
            selected: _amountCtrl.text == a.toString(),
            onSelected: (_) => setState(() => _amountCtrl.text = a.toString()),
          )).toList()),
          const SizedBox(height: 16),
          TextField(controller: _amountCtrl, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '或输入自定义金额', border: OutlineInputBorder(), prefixText: '¥ ')),
          const SizedBox(height: 16),
          FilledButton(onPressed: _isLoading ? null : _deposit,
            style: ButtonStyle(minimumSize: const WidgetStatePropertyAll(Size(double.infinity, 48))),
            child: _isLoading ? const CircularProgressIndicator(strokeWidth: 2) : const Text('确认充值')),
        ]))),
      ]),
    );
  }
}

class _PaymentRedirect extends StatelessWidget {
  final String tradeNo;
  final String type;
  const _PaymentRedirect({required this.tradeNo, this.type = ''});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('充值')),
      body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.check_circle, size: 64, color: Colors.green),
        const SizedBox(height: 16),
        const Text('充值订单已创建'),
        const SizedBox(height: 8),
        Text('订单号: $tradeNo', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 24),
        FilledButton(onPressed: () {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => _DepositPaymentPage(tradeNo: tradeNo)),
          );
        }, child: const Text('去支付')),
        const SizedBox(height: 8),
        TextButton(onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst), child: const Text('稍后支付')),
      ])),
    );
  }
}

class _DepositPaymentPage extends StatefulWidget {
  final String tradeNo;
  const _DepositPaymentPage({required this.tradeNo});
  @override
  State<_DepositPaymentPage> createState() => _DepositPaymentPageState();
}

class _DepositPaymentPageState extends State<_DepositPaymentPage> {
  List<PaymentMethod> _methods = [];
  bool _isLoading = true;
  bool _isPaying = false;
  String? _selectedMethodId;

  @override
  void initState() { super.initState(); _loadMethods(); }

  Future<void> _loadMethods() async {
    try {
      final m = await shopService.getPaymentMethods();
      if (mounted) setState(() { _methods = m; _isLoading = false; });
    } catch (_) { if (mounted) setState(() => _isLoading = false); }
  }

  Future<void> _pay(String methodId) async {
    setState(() { _selectedMethodId = methodId; _isPaying = true; });
    try {
      final c = await shopService.checkoutOrder(widget.tradeNo, methodId);
      if (mounted && c.type == 1 && c.data.isNotEmpty) {
        final uri = Uri.tryParse(c.data);
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (_) {}
    finally { if (mounted) setState(() => _isPaying = false); }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('选择支付方式')),
      body: _isLoading ? const Center(child: CircularProgressIndicator())
      : _methods.isEmpty
        ? const Center(child: Text('暂无可用的支付方式'))
        : ListView(padding: const EdgeInsets.all(16), children: _methods.map((m) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.payment),
              title: Text(m.name.isNotEmpty ? m.name : (m.handler ?? '支付方式')),
              trailing: _isPaying && _selectedMethodId == m.id
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.chevron_right),
              onTap: _isPaying ? null : () => _pay(m.id),
            ),
          )).toList()),
    );
  }
}
