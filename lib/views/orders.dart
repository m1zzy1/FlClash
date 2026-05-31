import 'package:fl_clash/controller.dart';
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
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('确定要取消此订单吗？'),
          const SizedBox(height: 8),
          Text(tradeNo, style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认')),
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

  Future<void> _payOrder(String tradeNo) async {
    OrderItem? order;
    for (final o in _orders) {
      if (o.tradeNo == tradeNo) { order = o; break; }
    }
    if (order == null) return;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => OrderDetailPage(order: order!, formatTime: _formatTime)),
    );
    if (result == true) _loadOrders();
  }

  String _formatTime(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的订单'),
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
                      Icon(Icons.receipt_long_outlined, size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                      const SizedBox(height: 16),
                      Text('暂无订单', style: theme.textTheme.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
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

// ──────────────────────────────────────────────
//  Order Card  — EZ 主题风格
// ──────────────────────────────────────────────
class _OrderCard extends StatelessWidget {
  final OrderItem order;
  final VoidCallback? onPay;
  final VoidCallback? onCancel;
  final String Function(int) formatTime;

  const _OrderCard({required this.order, this.onPay, this.onCancel, required this.formatTime});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // Status config: matching EZ theme colors
    Color statusFg, statusBg;
    IconData statusIcon;
    switch (order.status) {
      case 0:
        statusFg = Colors.orange;
        statusBg = isDark ? Colors.orange.withValues(alpha: 0.15) : Colors.orange.withValues(alpha: 0.1);
        statusIcon = Icons.pending_outlined;
      case 1:
        statusFg = Colors.blue;
        statusBg = isDark ? Colors.blue.withValues(alpha: 0.15) : Colors.blue.withValues(alpha: 0.1);
        statusIcon = Icons.sync_rounded;
      case 2:
        statusFg = Colors.grey;
        statusBg = isDark ? Colors.grey.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.1);
        statusIcon = Icons.cancel_outlined;
      case 3:
        statusFg = Colors.green;
        statusBg = isDark ? Colors.green.withValues(alpha: 0.15) : Colors.green.withValues(alpha: 0.1);
        statusIcon = Icons.check_circle_outlined;
      case 4:
        statusFg = Colors.purple;
        statusBg = isDark ? Colors.purple.withValues(alpha: 0.15) : Colors.purple.withValues(alpha: 0.1);
        statusIcon = Icons.sell_outlined;
      default:
        statusFg = Colors.grey;
        statusBg = isDark ? Colors.grey.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.1);
        statusIcon = Icons.help_outline;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => OrderDetailPage(order: order, formatTime: formatTime)),
          );
        },
        child: Column(
          children: [
            // ── Header: plan name + status badge ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: isDark ? 0.06 : 0.03),
                border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(order.planName ?? '套餐 #${order.planId}',
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(order.tradeNo,
                            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(6)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 14, color: statusFg),
                        const SizedBox(width: 4),
                        Text(order.statusText,
                            style: TextStyle(fontSize: 12, color: statusFg, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ── Body: info rows ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                children: [
                  _infoRow(cs, '创建时间', _formatTime(order.createdAt)),
                  if (order.period != null && order.periodText.isNotEmpty)
                    _infoRow(cs, '周期', order.periodText),
                  _infoRow(cs, '金额', '¥${(order.totalAmount / 100).toStringAsFixed(2)}',
                      isAmount: true),
                ],
              ),
            ),
            // ── Footer: action buttons ──
            if (order.status == 0)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow.withValues(alpha: 0.3),
                  border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Cancel button (light)
                    _actionButton(
                      label: '取消订单',
                      icon: Icons.close_rounded,
                      fg: cs.onSurfaceVariant,
                      bg: cs.surfaceContainerHighest,
                      onTap: onCancel,
                    ),
                    const SizedBox(width: 8),
                    // Pay button (red style)
                    _actionButton(
                      label: '继续支付',
                      icon: Icons.payment_rounded,
                      fg: Colors.red.shade400,
                      bg: isDark ? Colors.red.withValues(alpha: 0.15) : Colors.red.withValues(alpha: 0.08),
                      onTap: onPay,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTime(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Widget _infoRow(ColorScheme cs, String label, String value, {bool isAmount = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
          Text(value, style: TextStyle(
            fontSize: 14,
            fontWeight: isAmount ? FontWeight.w600 : FontWeight.normal,
            color: isAmount ? Colors.red.shade400 : cs.onSurface,
          )),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    IconData? icon,
    required Color fg,
    required Color bg,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 4),
              ],
              Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 订单详情页（含产品信息 + 订单信息 + 支付）
class OrderDetailPage extends StatefulWidget {
  final OrderItem order;
  final String Function(int) formatTime;

  const OrderDetailPage({super.key, required this.order, required this.formatTime});

  @override
  State<OrderDetailPage> createState() => OrderDetailPageState();
}

class OrderDetailPageState extends State<OrderDetailPage> {
  List<PaymentMethod> _methods = [];
  bool _methodsLoading = true;
  bool _methodsError = false;
  bool _isPaying = false;
  bool _isPolling = false;
  bool _pollCancelled = false;
  int _pollCount = 0;
  String? _pollingStatus;
  String? _selectedMethodId;
  Map<String, dynamic>? _orderDetail;

  @override
  void initState() {
    super.initState();
    _loadOrderDetail();
    _loadMethods();
  }

  @override
  void dispose() {
    _pollCancelled = true;
    super.dispose();
  }

  Future<void> _loadOrderDetail() async {
    try {
      final detail = await shopService.getOrderDetail(widget.order.tradeNo);
      if (mounted) setState(() => _orderDetail = detail);
    } catch (_) {}
  }

  Future<void> _loadMethods() async {
    try {
      final m = await shopService.getPaymentMethods();
      if (mounted) {
        setState(() {
          _methods = m;
          _methodsLoading = false;
          if (_selectedMethodId == null && m.isNotEmpty) {
            _selectedMethodId = m.first.id;
          }
        });
      }
    } catch (_) { if (mounted) setState(() { _methodsLoading = false; _methodsError = true; }); }
  }

  Future<void> _cancelOrder() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('取消订单'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('确定要取消此订单吗？'),
          const SizedBox(height: 8),
          Text(widget.order.tradeNo, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认')),
        ],
      ),
    );
    if (ok == true) {
      final success = await shopService.cancelOrder(widget.order.tradeNo);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(success ? '订单已取消' : '取消失败')),
        );
        if (success) Navigator.of(context).pop(true);
      }
    }
  }

  void _startPolling() {
    _pollCancelled = false;
    _pollCount = 0;
    _isPolling = true;
    _pollingStatus = '正在检测支付状态...';
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
          const SizedBox(width: 12),
          const Text('正在检测支付状态...'),
        ]),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
    }
    _doPoll();
  }

  Future<void> _checkPaymentStatus() async {
    try {
      final s = await shopService.checkOrderStatus(widget.order.tradeNo);
      if (!mounted) return;
      if (s == 1) {
        _startPolling();
        return;
      }
      if (s >= 3) {
        await _handlePaymentSuccess();
        return;
      }
      if (s == 2) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('订单已取消'), duration: Duration(seconds: 2)));
        }
        return;
      }
      _startPolling();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('检测失败，请重试'), duration: Duration(seconds: 2)));
      }
    }
  }

  Future<void> _doPoll() async {
    // 首次立即检测，之后每 5 秒检测一次（最多 30 次 ≈ 2.5 分钟）
    if (_pollCount > 0) {
      await Future.delayed(const Duration(seconds: 5));
    }
    if (!mounted || _pollCancelled) return;
    _pollingStatus = '正在检测支付状态${List.filled((_pollCount % 3) + 1, '.').join()}';
    setState(() {});
    try {
      final s = await shopService.checkOrderStatus(widget.order.tradeNo);
      if (!mounted || _pollCancelled) return;
      // status=1 处理中，延迟后过渡到成功
      if (s == 1) {
        _pollingStatus = '订单处理中...';
        setState(() {});
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted || _pollCancelled) return;
        await _handlePaymentSuccess();
        return;
      }
      if (s >= 3) {
        await _handlePaymentSuccess();
        return;
      }
      if (s == 2) {
        _pollCancelled = true;
        setState(() {
          _isPolling = false;
          _pollingStatus = null;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('订单已取消')));
        }
        return;
      }
    } catch (_) {}
    _pollCount++;
    if (_pollCount < 30) { _doPoll(); }
    else {
      setState(() {
        _isPolling = false;
        _pollingStatus = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('检测超时，可点击「检测支付状态」手动确认'),
        ));
      }
    }
  }

  Future<void> _handlePaymentSuccess() async {
    _pollCancelled = true;
    setState(() {
      _isPolling = false;
      _pollingStatus = null;
    });
    // 支付成功后 15 秒内每 5 秒重试同步订阅
    for (int i = 0; i < 3; i++) {
      if (!mounted) return;
      try {
        await appController.syncSubscriptionNow();
        final profile = appController.currentProfile;
        if (profile != null) break;
      } catch (_) {}
      if (i < 2) await Future.delayed(const Duration(seconds: 5));
    }
    if (mounted) {
      final navigator = Navigator.of(context);
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.check_circle_rounded, size: 56, color: Colors.green),
            const SizedBox(height: 12),
            const Text('支付成功！', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('即将返回...', style: TextStyle(fontSize: 13)),
          ]),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) {
        navigator.pop(); // 关闭对话框
        navigator.pop(true); // 返回订单列表
      }
    }
  }

  void _showQrDialog(String data) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.payment_rounded, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          const Text('支付', style: TextStyle(fontSize: 18)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('请使用支付应用扫描或打开以下链接：'),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(data, style: const TextStyle(fontSize: 13)),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
          FilledButton(onPressed: () {
            final uri = Uri.tryParse(data);
            if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
            Navigator.pop(ctx);
          }, child: const Text('打开链接')),
        ],
      ),
    );
  }

  Future<void> _pay(String methodId) async {
    setState(() => _isPaying = true);
    try {
      final c = await shopService.checkoutOrder(widget.order.tradeNo, methodId);
      if (!mounted) return;

      if (c.type == 1 && c.data.isNotEmpty) {
        final uri = Uri.tryParse(c.data);
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } else if (c.type == 0 && c.data.isNotEmpty) {
        // 二维码支付：显示对话框
        if (mounted) _showQrDialog(c.data);
      }
      // 无论 type 0 还是 1，都开始轮询
      _startPolling();
    } catch (_) {}
    finally { if (mounted) setState(() => _isPaying = false); }
  }

  String _fmtTime(dynamic ts) {
    if (ts is! int) return widget.formatTime(widget.order.createdAt);
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    return '${dt.year}/${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final o = widget.order;

    Color sf, sb;
    switch (o.status) {
      case 0: sf = Colors.orange; sb = isDark ? Colors.orange.withValues(alpha: 0.15) : Colors.orange.withValues(alpha: 0.1);
      case 1: sf = Colors.blue; sb = isDark ? Colors.blue.withValues(alpha: 0.15) : Colors.blue.withValues(alpha: 0.1);
      case 2: sf = Colors.grey; sb = isDark ? Colors.grey.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.1);
      case 3: sf = Colors.green; sb = isDark ? Colors.green.withValues(alpha: 0.15) : Colors.green.withValues(alpha: 0.1);
      case 4: sf = Colors.purple; sb = isDark ? Colors.purple.withValues(alpha: 0.15) : Colors.purple.withValues(alpha: 0.1);
      default: sf = Colors.grey; sb = isDark ? Colors.grey.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.1);
    }

    final totalAmount = _orderDetail != null
        ? ((_orderDetail!['total_amount'] as num?)?.toDouble() ?? 0) / 100
        : (o.totalAmount / 100);

    // 从 orderDetail 获取流量（V2Board API 返回的 transfer_enable 单位为 GB）
    String? trafficText;
    if (_orderDetail != null) {
      final plan = _orderDetail!['plan'] as Map<String, dynamic>?;
      if (plan != null) {
        final gb = plan['transfer_enable'] as int?;
        if (gb != null && gb > 0) {
          if (gb >= 1024) {
            trafficText = '${(gb / 1024).toStringAsFixed(1)} TB';
          } else {
            trafficText = '$gb GB';
          }
        }
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('支付订单')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // 产品信息
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('商品信息', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const Divider(height: 20),
              if (trafficText != null) ...[
                const SizedBox(height: 8),
                _detailRow(cs, '流量', trafficText),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 12),

        // 订单信息
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('订单信息', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const Divider(height: 20),
              _detailRow(cs, '订单号', o.tradeNo),
              const SizedBox(height: 8),
              _detailRow(cs, '创建时间', _fmtTime(_orderDetail?['created_at'])),
              const SizedBox(height: 8),
              _detailRow(cs, '套餐金额', '¥${totalAmount.toStringAsFixed(2)}'),
              const SizedBox(height: 8),
              _detailRow(cs, '订单总额', '¥${totalAmount.toStringAsFixed(2)}', isAmount: true),
            ]),
          ),
        ),
        const SizedBox(height: 12),

        // 订单状态
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: sb, borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                o.status == 0 ? Icons.pending_outlined :
                o.status == 3 ? Icons.check_circle_outlined :
                o.status == 2 ? Icons.cancel_outlined : Icons.info_outlined,
                size: 16, color: sf,
              ),
              const SizedBox(width: 6),
              Text('${o.statusText}  请选择您的支付方式完成订单',
                  style: TextStyle(fontSize: 12, color: sf, fontWeight: FontWeight.w500)),
            ]),
          ),
        ]),
        const SizedBox(height: 16),

        // 支付方式
        if (o.status == 0) ...[
          Text('支付方式', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 10),
          if (_methodsLoading)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else if (_methodsError)
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: cs.error.withValues(alpha: 0.3)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.cloud_off_rounded, size: 32, color: cs.error.withValues(alpha: 0.7)),
                    const SizedBox(height: 8),
                    Text('加载失败', style: TextStyle(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        setState(() { _methodsLoading = true; _methodsError = false; });
                        _loadMethods();
                      },
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              ),
            )
          else if (_methods.isEmpty)
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text('暂无可用的支付方式', style: TextStyle(color: cs.onSurfaceVariant))),
              ),
            )
          else
            ..._methods.map((m) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: _selectedMethodId == m.id ? cs.primary : cs.outlineVariant, width: _selectedMethodId == m.id ? 1.5 : 1),
              ),
              elevation: 0,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _selectedMethodId = m.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [
                    Icon(m.handler?.contains('alipay') == true ? Icons.account_balance_wallet_rounded :
                         m.handler?.contains('wx') == true ? Icons.chat_rounded : Icons.payment_rounded,
                        color: cs.primary),
                    const SizedBox(width: 12),
                    Expanded(child: Text(m.name, style: TextStyle(fontWeight: FontWeight.w500))),
                    // ignore: deprecated_member_use
                    Radio<String>(value: m.id, groupValue: _selectedMethodId, onChanged: (_) => setState(() => _selectedMethodId = m.id)),
                  ]),
                ),
              ),
            )),
          const SizedBox(height: 10),

          // 立即支付
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: (_selectedMethodId == null || _isPaying) ? null : () => _pay(_selectedMethodId!),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                backgroundColor: cs.error,
              ),
              child: _isPaying
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('立即支付', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 12),

          // 底部操作
          Row(children: [
            _bottomBtn(cs, Icons.close_rounded, '取消订单', Colors.red.shade400, _cancelOrder),
            const SizedBox(width: 12),
            _bottomBtn(cs, Icons.refresh_rounded, '检测支付状态', cs.primary, _checkPaymentStatus),
          ]),
        ],
      ]),
    );
  }

  Widget _detailRow(ColorScheme cs, String label, String value, {bool isAmount = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
        Text(value, style: TextStyle(
          fontSize: 14,
          fontWeight: isAmount ? FontWeight.bold : FontWeight.normal,
          color: isAmount ? cs.error : cs.onSurface,
        )),
      ],
    );
  }

  Widget _bottomBtn(ColorScheme cs, IconData icon, String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label, style: TextStyle(fontSize: 13)),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          minimumSize: const Size.fromHeight(46),
          side: BorderSide(color: color.withValues(alpha: 0.3)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        ),
      ),
    );
  }
}
