import 'package:collection/collection.dart';
import 'package:fl_clash/controller.dart';
import 'package:fl_clash/common/app_config.dart';
import 'package:fl_clash/common/feature_flags.dart';
import 'package:fl_clash/services/shop_service.dart';
import 'package:fl_clash/views/orders.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// 商店 Hub（二级目录）
class ShopView extends StatefulWidget {
  const ShopView({super.key});

  @override
  State<ShopView> createState() => _ShopViewState();
}

class _ShopViewState extends State<ShopView> {
  String? _appUrl;

  @override
  void initState() {
    super.initState();
    _loadAppUrl();
  }

  Future<void> _loadAppUrl() async {
    final url = await shopService.fetchAppUrl();
    if (mounted) setState(() => _appUrl = url);
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('商店')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _menuItem(cs, Icons.shopping_bag_outlined, '套餐购买', '浏览并购买套餐', () {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ShopPlansPage()));
        }),
        const Divider(height: 1, indent: 50, color: Color(0x4D8E8E93)),
        _menuItem(cs, Icons.receipt_long_outlined, '我的订单', '查看购买记录和订单状态', () {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OrdersView()));
        }),
        const Divider(height: 1, indent: 50, color: Color(0x4D8E8E93)),
        _menuItem(cs, Icons.language_outlined, '访问官网', '打开官方网站', () {
          if (_appUrl != null && _appUrl!.isNotEmpty) _openUrl(_appUrl!);
        }),
        const Divider(height: 1, indent: 50, color: Color(0x4D8E8E93)),
        _menuItem(cs, Icons.headphones_outlined, '联系客服', '与在线客服对话', _contactService),
      ]),
    );
  }

  void _contactService() {
    final crispId = FeatureFlags.enableAppConfig ? AppConfig.crispId : null;
    if (crispId == null || crispId.isEmpty) return;
    final uri = Uri.parse('https://go.crisp.chat/chat/embed/?website_id=$crispId');
    canLaunchUrl(uri).then((can) {
      if (can) launchUrl(uri, mode: LaunchMode.externalApplication);
    });
  }

  Widget _menuItem(ColorScheme cs, IconData icon, String title, String subtitle, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: cs.onSurface)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            ]),
          ),
          Icon(Icons.chevron_right, size: 18, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
        ]),
      ),
    );
  }
}

/// 套餐列表页（二级页面）
class ShopPlansPage extends StatefulWidget {
  const ShopPlansPage({super.key});

  @override
  State<ShopPlansPage> createState() => _ShopPlansPageState();
}

class _ShopPlansPageState extends State<ShopPlansPage> {
  List<Plan> _plans = [];
  List<Plan> get _filteredPlans {
    if (_selectedFilter == 0) return _plans;
    if (_selectedFilter == 1) return _plans.where((p) => p.isRecurring).toList();
    return _plans.where((p) => p.totalBandwidth != null && p.totalBandwidth! > 0).toList();
  }

  bool _isLoading = true;
  String? _error;
  int _selectedFilter = 0;
  static const _filterLabels = ['全部', '按周期', '按流量'];

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
      plans.sort((a, b) => (a.sort ?? 999).compareTo(b.sort ?? 999));
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

  void _buyPlan(Plan plan) {} // 弃用，卡片内直接导航

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('套餐购买'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadPlans),
        ],
      ),
      body: _buildBody(theme, cs),
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme cs) {
    if (_isLoading) return _buildSkeleton(cs);
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 56, color: cs.error.withValues(alpha: 0.7)),
            const SizedBox(height: 16),
            Text('加载失败', style: theme.textTheme.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(onPressed: _loadPlans, icon: const Icon(Icons.refresh, size: 18), label: const Text('重试')),
          ],
        ),
      );
    }
    if (_plans.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_cart_outlined, size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text('暂无可用套餐', style: theme.textTheme.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
      );
    }
    return Column(
      children: [
        // Filter pills
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: List.generate(_filterLabels.length, (i) {
              final sel = _selectedFilter == i;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedFilter = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? cs.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: sel ? cs.primary : cs.outlineVariant),
                    ),
                    child: Text(_filterLabels[i], style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: sel ? cs.onPrimary : cs.onSurfaceVariant,
                    )),
                  ),
                ),
              );
            }),
          ),
        ),
        Expanded(
          child: _filteredPlans.isEmpty
              ? Center(child: Text('没有匹配的套餐', style: TextStyle(color: cs.onSurfaceVariant)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: _filteredPlans.length,
                  itemBuilder: (_, i) => _PlanCard(plan: _filteredPlans[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildSkeleton(ColorScheme cs) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 3,
      itemBuilder: (_, __) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(5, (i) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                height: 12,
                width: [120.0, double.infinity, 200.0, 80.0, double.infinity][i],
                decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(4)),
              ),
            )),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
//  Plan Card  — EZ 主题风格套餐卡片
// ──────────────────────────────────────────────
class _PlanCard extends StatefulWidget {
  final Plan plan;

  const _PlanCard({required this.plan});

  @override
  State<_PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<_PlanCard> {
  String? _selectedPeriod;

  @override
  void initState() {
    super.initState();
    final options = widget.plan.priceOptions.where((o) => o.key != 'reset_price').toList();
    if (options.isNotEmpty) {
      // 默认选择周期最长的标签
      _selectedPeriod = options.reduce((a, b) =>
          _periodMonths(a.key) > _periodMonths(b.key) ? a : b).key;
    }
  }

  static double _calcDiscount(PriceOption opt, double monthPrice) {
    if (monthPrice <= 0 || opt.price <= 0) return 0;
    const periods = {
      'month_price': 1, 'quarter_price': 3, 'half_year_price': 6,
      'year_price': 12, 'two_year_price': 24, 'three_year_price': 36,
    };
    final months = periods[opt.key] ?? 1;
    final me = opt.price / months;
    if (me >= monthPrice) return 0;
    return ((monthPrice - me) / monthPrice * 100);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final options = widget.plan.priceOptions.where((o) => o.key != 'reset_price').toList();
    final selOpt = options.firstWhereOrNull((o) => o.key == _selectedPeriod);
    final monthPrice = widget.plan.monthPrice;

    // Stock
    bool soldOut = widget.plan.stock == 0;
    Color? stockBg, stockFg;
    String? stockText;
    if (widget.plan.stock != null) {
      if (widget.plan.stock! >= 50) {
        stockBg = isDark ? Colors.green.withValues(alpha: 0.2) : Colors.green.withValues(alpha: 0.12);
        stockFg = isDark ? Colors.green.shade300 : Colors.green.shade700;
        stockText = '充足';
      } else if (widget.plan.stock! > 0) {
        stockBg = isDark ? Colors.orange.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.12);
        stockFg = isDark ? Colors.orange.shade300 : Colors.orange.shade700;
        stockText = '仅剩 ${widget.plan.stock}';
      } else {
        stockBg = isDark ? Colors.red.withValues(alpha: 0.2) : Colors.red.withValues(alpha: 0.12);
        stockFg = isDark ? Colors.red.shade300 : Colors.red.shade700;
        stockText = '已售罄';
      }
    }

    // Price
    final displayPrice = selOpt?.price ?? (options.isEmpty ? 0.0 : options.first.price);
    final displayLabel = selOpt?.label ?? '';
    final discount = selOpt != null ? _calcDiscount(selOpt, monthPrice) : 0.0;
    final savings = monthPrice > 0 && discount > 0
        ? ((monthPrice * _periodMonths(selOpt!.key) - selOpt.price)).toStringAsFixed(2)
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header: name + stock badge ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(widget.plan.name,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                ),
                if (stockText != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: stockBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: stockFg!.withValues(alpha: 0.2)),
                    ),
                    child: Text(stockText, style: TextStyle(fontSize: 12, color: stockFg, fontWeight: FontWeight.w500)),
                  ),
              ],
            ),
          ),

          // ── Pricing section: 类似 v2_theme bg-gray-light ──
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('¥${displayPrice.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: cs.onSurface)),
              ],
            ),
          ),

          // ── Content: period tags + features + button ──
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Period tags
                if (options.isNotEmpty) ...[
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: options.map((opt) {
                        final sel = opt.key == _selectedPeriod;
                        final d = _calcDiscount(opt, monthPrice);
                        return GestureDetector(
                          onTap: () => setState(() => _selectedPeriod = opt.key),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: sel ? cs.primary : cs.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_rounded,
                                  size: 12,
                                  color: sel ? Colors.white : cs.primary.withValues(alpha: 0.4),
                                ),
                                const SizedBox(width: 4),
                                Text(opt.label,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: sel ? Colors.white : cs.onSurface,
                                    )),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Features ──
                if (widget.plan.contentList.isNotEmpty) ...[
                  ...widget.plan.contentList.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Icon(
                            item.support ? Icons.check_circle : Icons.cancel,
                            size: 16,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(item.text, style: TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: item.support ? cs.onSurface : cs.onSurface.withValues(alpha: 0.35),
                          )),
                        ),
                      ],
                    ),
                  )),
                  const SizedBox(height: 16),
                ],

                // ── Purchase button ──
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: soldOut ? null : () {
                      _navigateToOrder(context);
                    },
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(40),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      backgroundColor: soldOut ? null : cs.primary,
                    ),
                    child: Text(soldOut ? '已售罄' : '购买',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToOrder(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _OrderPage(plan: widget.plan, initialPeriod: _selectedPeriod),
      ),
    );
  }
}

int _periodMonths(String key) {
  const map = {
    'month_price': 1, 'quarter_price': 3, 'half_year_price': 6,
    'year_price': 12, 'two_year_price': 24, 'three_year_price': 36,
  };
  return map[key] ?? 1;
}

// ──────────────────────────────────────────────
//  Notices Page  — 公告列表（v2_theme 风格）
// ──────────────────────────────────────────────
class NoticesPage extends StatefulWidget {
  const NoticesPage({super.key});

  @override
  State<NoticesPage> createState() => _NoticesPageState();
}

class _NoticesPageState extends State<NoticesPage> {
  List<NoticeItem> _notices = [];
  bool _isLoading = true;
  bool _loadError = false;

  @override
  void initState() {
    super.initState();
    _loadNotices();
  }

  Future<void> _loadNotices() async {
    setState(() { _isLoading = true; _loadError = false; });
    final notices = await shopService.fetchNotices();
    if (mounted) {
      setState(() {
        _notices = notices;
        _isLoading = false;
        _loadError = notices.isEmpty;
      });
    }
  }

  void _showNoticeDetail(NoticeItem notice) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.notifications_active, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(notice.title, style: const TextStyle(fontSize: 16))),
        ]),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (notice.imgUrl != null && notice.imgUrl!.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      notice.imgUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      loadingBuilder: (_, child, loadingProgress) =>
                          loadingProgress == null
                              ? child
                              : const Center(child: CircularProgressIndicator()),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Text(notice.content, style: const TextStyle(fontSize: 14, height: 1.6)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('系统公告'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadNotices),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notices.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_off_outlined, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                      const SizedBox(height: 12),
                      Text('暂无公告', style: TextStyle(color: cs.onSurfaceVariant)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _notices.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final notice = _notices[i];
                    final date = notice.displayTime > 0
                        ? '${DateTime.fromMillisecondsSinceEpoch(notice.displayTime * 1000).year}/'
                          '${DateTime.fromMillisecondsSinceEpoch(notice.displayTime * 1000).month.toString().padLeft(2, '0')}/'
                          '${DateTime.fromMillisecondsSinceEpoch(notice.displayTime * 1000).day.toString().padLeft(2, '0')}'
                        : '';
                    final isPopup = notice.tags.any((t) => t.contains('弹窗'));
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      leading: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isPopup ? Icons.campaign_rounded : Icons.notifications_none_rounded,
                          size: 20, color: cs.primary,
                        ),
                      ),
                      title: Text(notice.title, style: const TextStyle(fontWeight: FontWeight.w500)),
                      subtitle: date.isNotEmpty ? Text(date, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)) : null,
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () => _showNoticeDetail(notice),
                    );
                  },
                ),
    );
  }
}

// ──────────────────────────────────────────────
//  Order Page  — 订单确认页（EZ 风格）
// ──────────────────────────────────────────────
class _OrderPage extends StatefulWidget {
  final Plan plan;
  final String? initialPeriod;
  const _OrderPage({required this.plan, this.initialPeriod});

  @override
  State<_OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<_OrderPage> {
  final _couponController = TextEditingController();
  bool _isSubmitting = false;
  bool _couponApplied = false;
  bool _couponVerifying = false;
  CouponResult? _couponResult;
  String? _selectedPeriod;

  @override
  void initState() {
    super.initState();
    _selectedPeriod = widget.initialPeriod;
    if (_selectedPeriod == null) {
      final options = widget.plan.priceOptions.where((o) => o.key != 'reset_price').toList();
      if (options.isNotEmpty) {
        // 默认选择周期最长的标签
        _selectedPeriod = options.reduce((a, b) =>
            _periodMonths(a.key) > _periodMonths(b.key) ? a : b).key;
      }
    }
  }

  @override
  void dispose() {
    _couponController.dispose();
    super.dispose();
  }

  double get _currentPrice {
    final opt = widget.plan.priceOptions.firstWhereOrNull((o) => o.key == _selectedPeriod);
    return opt?.price ?? 0;
  }

  double get _discountAmount {
    if (!_couponApplied || _couponResult == null) return 0;
    if (_couponResult!.type == 1) return _couponResult!.value / 100;
    if (_couponResult!.type == 2) return _currentPrice * (_couponResult!.value / 100);
    return _couponResult!.discountAmount;
  }

  Future<void> _verifyCoupon() async {
    final code = _couponController.text.trim();
    if (code.isEmpty || _couponVerifying) return;
    setState(() => _couponVerifying = true);
    try {
      final r = await shopService.verifyCoupon(code, widget.plan.id);
      if (r.valid) {
        setState(() { _couponResult = r; _couponApplied = true; });
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(r.type == 1
                ? '优惠码已应用，优惠 ¥${(r.value / 100).toStringAsFixed(2)}'
                : '优惠码已应用，优惠 ${r.value}%'),
            duration: const Duration(seconds: 2),
          ));
        }
      } else {
        _couponApplied = false; _couponResult = null;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无效的优惠码'), duration: Duration(seconds: 2)));
        }
      }
    } catch (_) {
      _couponApplied = false; _couponResult = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('验证失败'), duration: Duration(seconds: 2)));
      }
    } finally {
      if (mounted) setState(() => _couponVerifying = false);
    }
  }

  void _removeCoupon() {
    _couponController.clear();
    setState(() { _couponApplied = false; _couponResult = null; });
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('优惠码已移除'), duration: Duration(seconds: 2)));
  }

  String _formatTime(int ts) {
    if (ts <= 0) return '--';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _submitOrder() async {
    if (_selectedPeriod == null) return;
    setState(() => _isSubmitting = true);
    try {
      final result = await shopService.submitOrder(
        planId: widget.plan.id,
        period: _selectedPeriod!,
        couponCode: _couponApplied ? _couponController.text.trim() : null,
      );
      if (!mounted) return;
      final tradeNo = result['trade_no'] as String? ?? result['data'] as String? ?? '';
      if (tradeNo.isNotEmpty) {
        final order = OrderItem(
          tradeNo: tradeNo,
          planId: widget.plan.id,
          planName: widget.plan.name,
          totalAmount: _currentPrice - _discountAmount,
          status: 0,
          period: _selectedPeriod,
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => OrderDetailPage(order: order, formatTime: _formatTime)),
        );
      } else {
        appController.syncSubscriptionNow();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('购买成功')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下单失败: ${msg.length > 80 ? msg.substring(0, 80) : msg}'), duration: const Duration(seconds: 4)),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final options = widget.plan.priceOptions.where((o) => o.key != 'reset_price').toList();
    final discount = _discountAmount;
    final finalPrice = (_currentPrice - discount).clamp(0.0, _currentPrice);

    return Scaffold(
      appBar: AppBar(title: Text('确认订单')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // Plan summary
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.shopping_cart_rounded, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(widget.plan.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
            ]),
          ),
        ),
        const SizedBox(height: 12),

        // Period selection
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('选择周期', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              ...options.map((opt) {
                final sel = opt.key == _selectedPeriod;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() => _selectedPeriod = opt.key),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: sel ? cs.primary : cs.outlineVariant, width: sel ? 1.5 : 1),
                        color: sel ? cs.primaryContainer.withValues(alpha: 0.3) : null,
                      ),
                      child: Row(children: [
                        Icon(sel ? Icons.radio_button_checked : Icons.radio_button_off,
                            size: 20, color: sel ? cs.primary : cs.onSurfaceVariant),
                        const SizedBox(width: 10),
                        Expanded(child: Text(opt.label, style: TextStyle(fontWeight: sel ? FontWeight.w600 : null))),
                        Text('¥${opt.price.toStringAsFixed(2)}',
                            style: TextStyle(fontWeight: FontWeight.bold, color: sel ? cs.primary : cs.onSurface)),
                      ]),
                    ),
                  ),
                );
              }),
            ]),
          ),
        ),
        const SizedBox(height: 12),

        // Coupon（EZ 风格）
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
                Icon(Icons.discount_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 6),
                Text('优惠码', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _couponController,
                    enabled: !_couponApplied,
                    decoration: InputDecoration(
                      hintText: _couponApplied ? '已应用' : '输入优惠码',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (_couponApplied)
                  TextButton.icon(
                    onPressed: _removeCoupon,
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('移除', style: TextStyle(fontSize: 13)),
                    style: TextButton.styleFrom(foregroundColor: cs.error, padding: const EdgeInsets.symmetric(horizontal: 8)),
                  )
                else
                  FilledButton(
                    onPressed: _couponVerifying ? null : _verifyCoupon,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _couponVerifying
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('验证', style: TextStyle(fontSize: 13)),
                  ),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 12),

        // Order summary（EZ 风格）
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('套餐金额', style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
                Text('¥${_currentPrice.toStringAsFixed(2)}', style: TextStyle(fontSize: 14, color: cs.onSurface)),
              ]),
              if (discount > 0) ...[
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Row(children: [
                    Text('优惠', style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
                    if (_couponResult?.name != null) ...[
                      const SizedBox(width: 4),
                      Text('(${_couponResult!.name})', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ]),
                  Text('-¥${discount.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 14, color: Colors.green, fontWeight: FontWeight.w500)),
                ]),
              ],
              const Divider(height: 24),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('合计', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cs.onSurface)),
                Text('¥${finalPrice.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cs.error)),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 20),

        // Submit
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _isSubmitting ? null : _submitOrder,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isSubmitting
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('提交订单', style: TextStyle(fontSize: 16)),
          ),
        ),
      ]),
    );
  }
}


