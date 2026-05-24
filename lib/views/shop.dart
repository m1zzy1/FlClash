import 'package:collection/collection.dart';
import 'package:fl_clash/services/shop_service.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class ShopView extends StatefulWidget {
  const ShopView({super.key});

  @override
  State<ShopView> createState() => _ShopViewState();
}

class _ShopViewState extends State<ShopView> {
  List<Plan> _plans = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final plans = await shopService.fetchPlans();
      if (mounted) {
        setState(() {
          _plans = plans;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _buyPlan(Plan plan) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _OrderPage(plan: plan),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('商店'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPlans,
          ),
        ],
      ),
      body: _buildBody(theme, colorScheme),
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme colorScheme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 16),
            Text('加载失败', style: theme.textTheme.titleMedium),
            const SizedBox(height: 24),
          OutlinedButton.icon(
              onPressed: _loadPlans,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_plans.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_cart_outlined, size: 64, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('暂无可用套餐', style: theme.textTheme.titleMedium),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _plans.length,
      itemBuilder: (_, index) => _PlanCard(
        plan: _plans[index],
        onBuy: () => _buyPlan(_plans[index]),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final Plan plan;
  final VoidCallback onBuy;

  const _PlanCard({required this.plan, required this.onBuy});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final options = plan.priceOptions;
    final displayPrice = options.isEmpty ? 0.0 : options.first.price;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    plan.name,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                if (displayPrice > 0)
                  Text(
                    '¥${displayPrice.toStringAsFixed(2)}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
            if (plan.contentList.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...plan.contentList.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: Icon(
                        item.support ? Icons.check_circle : Icons.cancel,
                        size: 18,
                        color: item.support ? Colors.green.shade400 : Colors.red.shade300,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(item.text, style: TextStyle(
                        color: item.support ? colorScheme.onSurfaceVariant : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                        fontSize: 13,
                      )),
                    ),
                  ],
                ),
              )),
            ],
            if (options.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: options.take(4).map((opt) => Chip(
                  label: Text('${opt.label} ¥${opt.price.toStringAsFixed(2)}'),
                  visualDensity: VisualDensity.compact,
                )).toList(),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onBuy,
                child: const Text('立即购买'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderPage extends StatefulWidget {
  final Plan plan;
  const _OrderPage({required this.plan});
  @override
  State<_OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<_OrderPage> {
  String? _selectedPeriod;
  final _couponCtrl = TextEditingController();
  bool _isSubmitting = false;
  String? _error;
  CouponResult? _couponResult;
  bool _isCheckingCoupon = false;

  @override
  void dispose() { _couponCtrl.dispose(); super.dispose(); }

  Future<void> _checkCoupon() async {
    final code = _couponCtrl.text.trim();
    if (code.isEmpty || _selectedPeriod == null) return;
    setState(() { _isCheckingCoupon = true; _couponResult = null; });
    try {
      final result = await shopService.verifyCoupon(code, widget.plan.id);
      if (mounted) setState(() { _couponResult = result; _isCheckingCoupon = false; });
    } catch (_) {
      if (mounted) setState(() { _couponResult = null; _isCheckingCoupon = false; });
    }
  }

  Future<void> _submit() async {
    if (_selectedPeriod == null) return;
    setState(() { _isSubmitting = true; _error = null; });
    try {
      final result = await shopService.submitOrder(
        planId: widget.plan.id,
        period: _selectedPeriod!,
        couponCode: _couponCtrl.text.trim().isEmpty ? null : _couponCtrl.text.trim(),
      );
      final tradeNo = result['trade_no'] as String? ?? '';
      if (mounted && tradeNo.isNotEmpty) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => _OrderPaymentPage(tradeNo: tradeNo)),
        );
      }
    } catch (e) {
      String msg = e.toString();
      if (msg.contains('500')) {
        msg = '可能存在未支付的订单，请到订单列表查看或联系客服';
      }
      if (mounted) setState(() { _error = msg; _isSubmitting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final options = widget.plan.priceOptions;

    return Scaffold(
      appBar: AppBar(title: Text('购买 ${widget.plan.name}')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('选择周期', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...options.map((opt) => RadioListTile<String>(
            title: Text('${opt.label} — ¥${opt.price.toStringAsFixed(2)}'),
            value: opt.key,
            groupValue: _selectedPeriod,
            onChanged: (v) => setState(() { _selectedPeriod = v; _couponResult = null; }),
            dense: true,
          )),
        ]))),
        const SizedBox(height: 12),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
          Row(children: [
            Expanded(child: TextField(
              controller: _couponCtrl,
              decoration: const InputDecoration(labelText: '优惠券码', border: OutlineInputBorder(), isDense: true),
            )),
            const SizedBox(width: 8),
            FilledButton.tonal(onPressed: _isCheckingCoupon ? null : _checkCoupon, child: const Text('验证')),
          ]),
          if (_isCheckingCoupon) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
          if (_couponResult != null) ...[
            const SizedBox(height: 8),
            Text(_couponResult!.valid ? '优惠券有效，折扣: ${_couponResult!.discountAmount} 元' : '优惠券无效',
                style: TextStyle(color: _couponResult!.valid ? Colors.green : Colors.red, fontSize: 13)),
          ],
        ]))),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: cs.error, fontSize: 13))),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _selectedPeriod == null || _isSubmitting ? null : _submit,
          style: ButtonStyle(minimumSize: const WidgetStatePropertyAll(Size(double.infinity, 48))),
          child: _isSubmitting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('提交订单'),
        ),
      ]),
    );
  }
}

class _OrderPaymentPage extends StatefulWidget {
  final String tradeNo;
  const _OrderPaymentPage({required this.tradeNo});
  @override
  State<_OrderPaymentPage> createState() => _OrderPaymentPageState();
}

class _OrderPaymentPageState extends State<_OrderPaymentPage> {
  List<PaymentMethod> _methods = [];
  bool _isLoading = true;
  bool _isPaying = false;

  @override
  void initState() { super.initState(); _loadMethods(); }

  Future<void> _loadMethods() async {
    try {
      final m = await shopService.getPaymentMethods();
      if (mounted) setState(() { _methods = m; _isLoading = false; });
    } catch (_) { if (mounted) setState(() => _isLoading = false); }
  }

  Future<void> _pay(String methodId) async {
    setState(() => _isPaying = true);
    try {
      final c = await shopService.checkoutOrder(widget.tradeNo, methodId);
      if (mounted && c.type == 1 && c.data.isNotEmpty) {
        final uri = Uri.tryParse(c.data);
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('支付链接已获取')));
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
              trailing: const Icon(Icons.chevron_right),
              onTap: _isPaying ? null : () => _pay(m.id),
            ),
          )).toList()),
    );
  }
}
