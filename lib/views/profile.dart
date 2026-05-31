import 'package:collection/collection.dart';
import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/controller.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/services/api_client.dart';
import 'package:fl_clash/services/auth_service.dart';
import 'package:fl_clash/services/shop_service.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/invite.dart';
import 'package:fl_clash/views/orders.dart';
import 'package:fl_clash/views/tools.dart';
import 'package:fl_clash/views/wallet.dart';
import 'package:flutter/material.dart';

class ProfileView extends StatefulWidget {
  const ProfileView({super.key});
  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  UserInfo? _userInfo;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() { super.initState(); _loadUserInfo(); }

  Future<void> _loadUserInfo() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      UserInfo info = await authService.getUserInfo();

      // 从 /user/getSubscribe 获取套餐名称 + 流量数据（最可靠来源）
      try {
        final subRes = await apiClient.get('/user/getSubscribe');
        final subData = subRes['data'] as Map<String, dynamic>? ?? subRes;

        // 套餐名称: subscribe.plan.name (支持已下架套餐)
        String? subPlanName;
        try {
          final planObj = subData['plan'] as Map<String, dynamic>?;
          if (planObj != null) subPlanName = planObj['name'] as String?;
        } catch (_) {}
        subPlanName ??= subData['plan_name'] as String?;

        // 流量数据（字段名为 u / d，跟 /user/info 一致）
        final upload = (subData['u'] ?? 0) as int;
        final download = (subData['d'] ?? 0) as int;
        final total = (subData['transfer_enable'] ?? subData['total']) as int?;

        if (total != null && total > 0) {
          info = UserInfo(
            email: info.email, balance: info.balance, expireAt: info.expireAt,
            trafficUsed: upload + download, trafficTotal: total,
            planName: subPlanName ?? info.planName, planId: info.planId,
            commissionBalance: info.commissionBalance,
            inviteCount: info.inviteCount, inviteRate: info.inviteRate,
          );
        }
      } catch (_) {
        // /user/getSubscribe 不可用，尝试其他来源

        // 套餐名称：从套餐列表匹配
        if (info.planName == null && info.planId != null) {
          String? name;
          try {
            final plans = await shopService.fetchPlans();
            name = plans.where((p) => p.id == info.planId).firstOrNull?.name;
            if (name == null) {
              final plan = await shopService.fetchPlanById(info.planId!);
              name = plan?.name;
            }
          } catch (_) {}
          if (name != null) {
            info = UserInfo(
              email: info.email, balance: info.balance, expireAt: info.expireAt,
              trafficUsed: info.trafficUsed, trafficTotal: info.trafficTotal,
              planName: name, planId: info.planId,
              commissionBalance: info.commissionBalance,
              inviteCount: info.inviteCount, inviteRate: info.inviteRate,
            );
          }
        }

        // 流量：从已同步的订阅信息获取
        if (info.trafficUsed == null || info.trafficUsed == 0) {
          final subInfo = appController.currentProfile?.subscriptionInfo;
          if (subInfo != null && subInfo.total > 0) {
            info = UserInfo(
              email: info.email, balance: info.balance, expireAt: info.expireAt,
              trafficUsed: subInfo.upload + subInfo.download, trafficTotal: subInfo.total,
              planName: info.planName, planId: info.planId,
              commissionBalance: info.commissionBalance,
              inviteCount: info.inviteCount, inviteRate: info.inviteRate,
            );
          }
        }
      }

      if (mounted) setState(() { _userInfo = info; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _syncSubscription() async {
    try {
      await appController.syncSubscriptionNow();
      _showMsg('同步成功');
      _loadUserInfo();
    } catch (e) {
      _showMsg('同步失败，请检查订阅链接是否有效');
    }
  }

  Future<void> _handleLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'), content: const Text('确定要退出登录吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('退出', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      await appController.updateStatus(false);
      appController.toPage(PageLabel.dashboard);
      await authService.logout();
      if (mounted) globalState.navigatorKey.currentState?.pushNamedAndRemoveUntil('/login', (_) => false);
    }
  }

  Future<void> _handleCheckUpdate() async {
    _showMsg('正在检查更新...');
    final data = await request.checkForUpdate();
    await appController.checkUpdateResultHandle(data: data, isUser: true);
  }

  Future<void> _handleResetTraffic() async {
    final planId = _userInfo?.planId;
    if (planId == null) { _showMsg('无可用套餐'); return; }

    // 获取套餐详情（含重置价格）
    final plan = await shopService.fetchPlanById(planId);
    final resetPrice = plan?.resetPrice ?? 0;
    final totalTraffic = _userInfo?.trafficTotal;
    final totalGB = totalTraffic != null ? totalTraffic / (1024*1024*1024) : 0.0;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.refresh_rounded, color: Colors.orange.shade600),
          const SizedBox(width: 8),
          const Text('流量重置'),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('确认重置流量?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          if (totalGB > 0)
            _dialogRow(Icons.cloud_rounded, '重置后流量恢复至', '${totalGB.toStringAsFixed(2)} GB'),
          if (resetPrice > 0)
            _dialogRow(Icons.payment_rounded, '需支付', '¥${resetPrice.toStringAsFixed(2)}'),
          _dialogRow(Icons.event_rounded, '套餐到期时间不变', ''),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final result = await shopService.submitOrder(
        planId: planId,
        period: 'reset_price',
      );
      if (!mounted) return;
      final tradeNo = result['trade_no'] as String? ?? '';
      if (tradeNo.isNotEmpty) {
        final order = OrderItem(
          tradeNo: tradeNo,
          planId: planId,
          planName: plan?.name ?? '',
          totalAmount: (result['total_amount'] as num?)?.toDouble() ?? 0,
          status: 0,
          period: 'reset_price',
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => OrderDetailPage(order: order, formatTime: _fmtDateTime)),
        );
      } else {
        _showMsg('重置成功');
        _loadUserInfo();
      }
    } catch (e) {
      _showMsg('操作失败: $e');
    }
  }

  Widget _dialogRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        if (value.isNotEmpty) ...[
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ]),
    );
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _formatTimestamp(int t) {
    final dt = DateTime.fromMillisecondsSinceEpoch(t * 1000);
    return "${dt.year}-${dt.month.toString().padLeft(2, "0")}-${dt.day.toString().padLeft(2, "0")}";
  }

  String _fmtDateTime(int ts) {
    if (ts <= 0) return '--';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('用户'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadUserInfo,
          ),
        ],
      ),
      body: _buildBody(theme, cs),
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme cs) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.cloud_off, size: 48, color: cs.error.withValues(alpha: 0.7)),
            const SizedBox(height: 16), Text('加载失败', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('请检查网络连接或账号状态', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
            const SizedBox(height: 24),
            FilledButton.tonalIcon(onPressed: _loadUserInfo, icon: const Icon(Icons.refresh), label: const Text('重试')),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                authService.logout();
                globalState.navigatorKey.currentState
                    ?.pushNamedAndRemoveUntil('/login', (_) => false);
              },
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('退出登录'),
            ),
          ],
        ),
      );
    }

    final info = _userInfo!;
    final totalGB = info.trafficTotal != null ? info.trafficTotal! / (1024*1024*1024) : 0.0;
    final usedGB = info.trafficUsed != null ? info.trafficUsed! / (1024*1024*1024) : 0.0;
    final ratio = totalGB > 0 ? (usedGB / totalGB).clamp(0.0, 1.0) : 0.0;
    final ratioPct = (ratio * 100).toInt();
    final barColor = ratio > 0.8 ? cs.error : ratio > 0.5 ? cs.tertiary : cs.primary;

    // 到期状态
    bool isExpired = info.expireAt != null && info.expireAt! < DateTime.now().millisecondsSinceEpoch / 1000;
    bool isExpiring = info.expireAt != null && !isExpired &&
        info.expireAt! < DateTime.now().millisecondsSinceEpoch / 1000 + 7 * 86400;
    String expireText;
    String? expireRemaining;
    if (info.expireAt == null) {
      expireText = '-';
    } else if (isExpired) {
      expireText = '已过期';
    } else {
      expireText = _formatTimestamp(info.expireAt!);
      final remainDays = ((info.expireAt! - DateTime.now().millisecondsSinceEpoch / 1000) / 86400).ceil();
      if (remainDays > 0) expireRemaining = '剩余 $remainDays 天';
    }
    // 流量预警
    bool isLowTraffic = ratio > 0.8;
    bool isTrafficDepleted = ratio >= 0.99;

    return RefreshIndicator(
      onRefresh: _loadUserInfo,
      child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── 用户信息卡片（EZ 主题风格）──
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 头像 + 邮箱 + 套餐标签
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: cs.primaryContainer,
                      child: Icon(Icons.person, size: 24, color: cs.onPrimaryContainer),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(info.email ?? '未登录',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              if (info.planName != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isExpired
                                        ? cs.error.withValues(alpha: 0.12)
                                        : isExpiring
                                            ? Colors.orange.withValues(alpha: 0.12)
                                            : cs.primaryContainer,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(info.planName!,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isExpired
                                            ? cs.error
                                            : isExpiring
                                                ? Colors.orange.shade700
                                                : cs.onPrimaryContainer,
                                        fontWeight: FontWeight.w500)),
                                ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isExpired
                                      ? cs.error.withValues(alpha: 0.12)
                                      : isExpiring
                                          ? Colors.orange.withValues(alpha: 0.12)
                                          : cs.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  expireText + (expireRemaining != null ? ' ($expireRemaining)' : ''),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isExpired
                                        ? cs.error
                                        : isExpiring
                                            ? Colors.orange.shade700
                                            : cs.onSurfaceVariant,
                                    fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ── 信息行（EZ 主题 info-item 风格）──
                Row(
                  children: [
                    Expanded(child: _infoLabelValue(cs, '账户余额', '¥${info.balance != null ? (info.balance! / 100).toStringAsFixed(2) : "0.00"}')),
                    if (info.commissionBalance != null)
                      Expanded(child: _infoLabelValue(cs, '佣金', '¥${(info.commissionBalance! / 100).toStringAsFixed(2)}')),                   
                    if (info.inviteCount != null)
                      Expanded(child: _infoLabelValue(cs, '邀请', '${info.inviteCount} 人')),
                  ],
                ),
                const SizedBox(height: 12),

                // ── 流量使用（水波进度条风格）──
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('已用流量', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                        Text('${usedGB.toStringAsFixed(1)} GB / ${totalGB.toStringAsFixed(1)} GB',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: cs.onSurface)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 6,
                        backgroundColor: cs.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation(barColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ── 快捷操作移到页面底部 ──
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // ── 全部菜单项 ──
        Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _menuItem(cs, Icons.refresh_rounded, '重置流量', '重置已用流量', () => _handleResetTraffic(),
                  fg: isTrafficDepleted ? cs.error : Colors.orange.shade600),
              Divider(height: 1, indent: 50, color: cs.outlineVariant.withValues(alpha: 0.3)),
              _menuItem(cs, Icons.sync_rounded, '同步订阅', '手动同步订阅信息', _syncSubscription),
              Divider(height: 1, indent: 50, color: cs.outlineVariant.withValues(alpha: 0.3)),
              _menuItem(cs, Icons.account_balance_wallet_outlined, '我的钱包', '为账户余额充值', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WalletView()))),
              Divider(height: 1, indent: 50, color: cs.outlineVariant.withValues(alpha: 0.3)),
              _menuItem(cs, Icons.person_add_outlined, '我的邀请', '邀请朋友获取奖励', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InviteView()))),
              Divider(height: 1, indent: 50, color: cs.outlineVariant.withValues(alpha: 0.3)),
              _menuItem(cs, Icons.construction_outlined, '高级工具', '网络诊断与高级设置', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ToolsView()))),
              Divider(height: 1, indent: 50, color: cs.outlineVariant.withValues(alpha: 0.3)),
              _menuItem(cs, Icons.system_update_outlined, '检查更新', '检查新版本', _handleCheckUpdate),
              Divider(height: 1, indent: 50, color: cs.outlineVariant.withValues(alpha: 0.3)),
              _menuItem(cs, Icons.logout, '退出登录', '切换账户', _handleLogout, danger: true),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    ),
    );
  }

  Widget _infoLabelValue(ColorScheme cs, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: cs.onSurface)),
        ],
      ),
    );
  }

  Widget _actionChip(ColorScheme cs, IconData icon, String label, VoidCallback onTap, {Color? fg}) {
    final c = fg ?? cs.onSurface;
    return ActionChip(
      avatar: Icon(icon, size: 16, color: c),
      label: Text(label, style: TextStyle(fontSize: 12, color: c)),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: c.withValues(alpha: 0.3)),
    );
  }


  Widget _menuItem(ColorScheme cs, IconData icon, String title, String subtitle, VoidCallback onTap, {bool danger = false, Color? fg}) {
    final c = fg ?? (danger ? cs.error : cs.primary);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: danger ? cs.error.withValues(alpha: 0.1) : cs.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: c),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: danger ? cs.error : cs.onSurface)),
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
