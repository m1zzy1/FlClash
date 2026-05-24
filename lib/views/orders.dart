import 'package:fl_clash/services/shop_service.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class OrdersView extends StatefulWidget {
  const OrdersView({super.key});

  @override
  State<OrdersView> createState() => _OrdersViewState();
}

class _OrdersViewState extends State<OrdersView> {
  List<OrderItem> _orders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() => _isLoading = true);
    try {
      final orders = await shopService.fetchOrders();
      if (mounted) setState(() { _orders = orders; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _cancelOrder(String tradeNo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('取消订单'),
        content: const Text('确定要取消此订单吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('返回')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定取消')),
        ],
      ),
    );
    if (ok == true) {
      final success = await shopService.cancelOrder(tradeNo);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(success ? '订单已取消' : '取消失败')),
        );
        if (success) _loadOrders();
      }
    }
  }

  void _payOrder(String tradeNo) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _OrderPaymentPage(tradeNo: tradeNo)),
    );
  }

  String _formatTime(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('订单列表'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadOrders),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _orders.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.receipt_long_outlined, size: 64, color: colorScheme.onSurfaceVariant),
                      const SizedBox(height: 16),
                      Text('暂无订单', style: theme.textTheme.titleMedium),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadOrders,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _orders.length,
                    itemBuilder: (_, i) => _OrderCard(
                      order: _orders[i],
                      onPay: _orders[i].status == 0 ? () => _payOrder(_orders[i].tradeNo) : null,
                      onCancel: _orders[i].status == 0 ? () => _cancelOrder(_orders[i].tradeNo) : null,
                      formatTime: _formatTime,
                    ),
                  ),
                ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final OrderItem order;
  final VoidCallback? onPay;
  final VoidCallback? onCancel;
  final String Function(int) formatTime;

  const _OrderCard({required this.order, this.onPay, this.onCancel, required this.formatTime});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final statusColor = switch (order.status) {
      0 => Colors.orange,
      1 => Colors.green,
      2 => Colors.grey,
      _ => Colors.grey,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(order.planName ?? '套餐 #${order.planId}',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(order.statusText,
                      style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w500)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('订单号: ${order.tradeNo}', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(formatTime(order.createdAt),
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                Text('¥${(order.totalAmount / 100).toStringAsFixed(2)}',
                    style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary)),
              ],
            ),
            if (order.status == 0) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton.icon(
                  onPressed: onPay,
                  icon: const Icon(Icons.payment, size: 16),
                  label: const Text('去支付', style: TextStyle(fontSize: 13)),
                  style: TextButton.styleFrom(foregroundColor: colorScheme.primary, padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
                TextButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: const Text('取消订单', style: TextStyle(fontSize: 13)),
                  style: TextButton.styleFrom(foregroundColor: colorScheme.error, padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
              ]),
              ),
            ],
          ],
        ),
      ),
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
