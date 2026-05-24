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
  final _couponController = TextEditingController();
  bool _isSubmitting = false;
  String? _couponMessage;
  CouponResult? _couponResult;
  String? _selectedPeriod;

  @override
  void initState() {
    super.initState();
    final options = widget.plan.priceOptions;
    if (options.isNotEmpty) {
      _selectedPeriod = options.first.key;
    }
  }

  @override
  void dispose() {
    _couponController.dispose();
    super.dispose();
  }

  String? get _selectedLabel =>
      widget.plan.priceOptions.firstWhereOrNull((o) => o.key == _selectedPeriod)?.label ?? '';

  double get _currentPrice {
    final opt = widget.plan.priceOptions.firstWhereOrNull((o) => o.key == _selectedPeriod);
    return opt?.price ?? 0;
  }

  Future<void> _checkCoupon() async {
    final code = _couponController.text.trim();
    if (code.isEmpty) return;
    try {
      final result = await shopService.verifyCoupon(code, widget.plan.id);
      setState(() {
        _couponResult = result;
        _couponMessage = result.valid
            ? '优惠券有效，优惠 ¥${result.discountAmount.toStringAsFixed(2)}'
            : '优惠券无效';
      });
    } catch (e) {
      setState(() => _couponMessage = '验证失败');
    }
  }

  Future<void> _submitOrder() async {
    if (_selectedPeriod == null) return;
    setState(() => _isSubmitting = true);
    try {
      final result = await shopService.submitOrder(
        planId: widget.plan.id,
        period: _selectedPeriod!,
        couponCode: _couponController.text.trim(),
      );
      if (mounted) {
        final tradeNo = result['trade_no'] as String? ?? result['data'] as String? ?? '';
        if (tradeNo.isNotEmpty) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => _PaymentPage(tradeNo: tradeNo, planName: widget.plan.name),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('订单创建成功')),
          );
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      final msg = e.toString();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下单失败: ${msg.replaceFirst("Exception: ", "").length > 100 ? msg.substring(0, 100) : msg.replaceFirst("Exception: ", "")}'), duration: const Duration(seconds: 5)),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final options = widget.plan.priceOptions;
    final discount = _couponResult?.discountAmount ?? 0;
    final finalPrice = (_currentPrice - discount).clamp(0.0, _currentPrice);

    return Scaffold(
      appBar: AppBar(title: Text('购买 ${widget.plan.name}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Plan info
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.plan.name, style: theme.textTheme.titleLarge),
                  if (widget.plan.contentList.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...widget.plan.contentList.map((item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20, height: 20,
                            child: Icon(
                              item.support ? Icons.check_circle : Icons.cancel,
                              size: 18,
                              color: item.support ? Colors.green.shade400 : Colors.red.shade300,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(item.text, style: const TextStyle(fontSize: 13))),
                        ],
                      ),
                    )),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Period selection
          if (options.length > 1)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('选择周期', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ...options.map((opt) => RadioListTile<String>(
                      title: Text('${opt.label}  ¥${opt.price.toStringAsFixed(2)}'),
                      value: opt.key,
                      groupValue: _selectedPeriod,
                      onChanged: (v) => setState(() => _selectedPeriod = v),
                      dense: true,
                    )),
                  ],
                ),
              ),
            ),
          if (options.length == 1) ...[
            Card(
              child: ListTile(
                title: Text(options.first.label),
                trailing: Text('¥${options.first.price.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.primary)),
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Coupon
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('优惠码', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _couponController,
                          decoration: const InputDecoration(
                            hintText: '输入优惠码',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _checkCoupon,
                        child: const Text('验证'),
                      ),
                    ],
                  ),
                  if (_couponMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _couponMessage!,
                        style: TextStyle(
                          color: _couponResult?.valid == true ? Colors.green : colorScheme.error,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Total & Submit
          if (discount > 0)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('小计'),
                      Text('¥${_currentPrice.toStringAsFixed(2)}'),
                    ]),
                    const SizedBox(height: 4),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('优惠', style: TextStyle(color: colorScheme.error)),
                      Text('-¥${discount.toStringAsFixed(2)}', style: TextStyle(color: colorScheme.error)),
                    ]),
                    const Divider(height: 20),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('实付', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('¥${finalPrice.toStringAsFixed(2)}',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colorScheme.primary)),
                    ]),
                  ],
                ),
              ),
            ),
          FilledButton(
            onPressed: _isSubmitting ? null : _submitOrder,
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(Size(double.infinity, 48)),
            ),
            child: _isSubmitting
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('确认下单  ¥${finalPrice.toStringAsFixed(2)}'),
          ),
        ],
      ),
    );
  }
}

class _PaymentPage extends StatefulWidget {
  final String tradeNo;
  final String planName;
  const _PaymentPage({required this.tradeNo, required this.planName});

  @override
  State<_PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<_PaymentPage> {
  List<PaymentMethod> _methods = [];
  bool _isLoading = true;
  bool _isPaying = false;
  String? _selectedMethodId;

  @override
  void initState() {
    super.initState();
    _loadMethods();
  }

  Future<void> _loadMethods() async {
    try {
      final methods = await shopService.getPaymentMethods();
      if (mounted) setState(() { _methods = methods; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _processPayment(String methodId) async {
    setState(() {
      _selectedMethodId = methodId;
      _isPaying = true;
    });
    try {
      final checkout = await shopService.checkoutOrder(widget.tradeNo, methodId);
      if (mounted) {
        if (checkout.type == 1 && checkout.data.isNotEmpty) {
          final uri = Uri.tryParse(checkout.data);
          if (uri != null && await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } else {
            _showSnackBar('支付链接: ${checkout.data}', 10);
          }
        } else {
          _showSnackBar('支付信息已获取，请查看', 3);
        }
      }
    } catch (e) {
      if (mounted) _showSnackBar('支付发起失败: ${e.toString().replaceFirst("Exception: ", "").substring(0, (e.toString().length > 60 ? 60 : e.toString().length))}', 5);
    } finally {
      if (mounted) setState(() => _isPaying = false);
    }
  }

  void _showSnackBar(String msg, int seconds) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: Duration(seconds: seconds)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('支付 - ${widget.planName}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Icon(Icons.receipt_long, size: 48),
                  const SizedBox(height: 8),
                  Text('订单已创建', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('订单号: ${widget.tradeNo}',
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('选择支付方式', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_methods.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.credit_card_off_outlined, size: 48,
                        color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(height: 8),
                    const Text('暂无可用的支付方式'),
                  ],
                ),
              ),
            )
          else
            ..._methods.map((m) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(
                  m.handler?.contains('alipay') == true
                      ? Icons.account_balance_wallet
                      : Icons.payment,
                ),
                title: Text(m.name.isNotEmpty ? m.name : (m.handler ?? '支付方式')),
                trailing: _isPaying && _selectedMethodId == m.id
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.chevron_right),
                onTap: _isPaying ? null : () => _processPayment(m.id),
              ),
            )),
        ],
      ),
    );
  }
}
