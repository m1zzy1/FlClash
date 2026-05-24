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
    String? url = await authService.fetchSubscribeUrl();
    url ??= authService.subscribeUrl;
    if (url == null) { _showMsg('无法获取订阅链接'); return; }
    try {
      final currentProfile = appController.currentProfile;
      if (currentProfile != null) {
        // 更新当前订阅配置，不新增
        await appController.updateProfile(currentProfile.copyWith(url: url));
      } else {
        await appController.addProfileFormURL(url);
      }
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

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _formatTimestamp(int t) {
    final dt = DateTime.fromMillisecondsSinceEpoch(t * 1000);
    return "${dt.year}-${dt.month.toString().padLeft(2, "0")}-${dt.day.toString().padLeft(2, "0")}";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
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
            Icon(Icons.error_outline, size: 48, color: cs.error),
            const SizedBox(height: 16), Text('加载失败', style: theme.textTheme.titleMedium),
            const SizedBox(height: 24),
            FilledButton.tonalIcon(onPressed: _loadUserInfo, icon: const Icon(Icons.refresh), label: const Text('重试')),
          ],
        ),
      );
    }

    final info = _userInfo!;
    final totalGB = info.trafficTotal != null ? info.trafficTotal! / (1024*1024*1024) : 0.0;
    final usedGB = info.trafficUsed != null ? info.trafficUsed! / (1024*1024*1024) : 0.0;
    final ratio = totalGB > 0 ? (usedGB / totalGB).clamp(0.0, 1.0) : 0.0;
    final barColor = ratio > 0.8 ? cs.error : ratio > 0.5 ? cs.tertiary : cs.primary;
    final expireText = info.expireAt != null ? _formatTimestamp(info.expireAt!) : '-';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ---- 用户卡片 ----
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // 头像行
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: cs.primaryContainer,
                      child: Icon(Icons.person, size: 28, color: cs.onPrimaryContainer),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(info.email ?? '未登录', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(4)),
                                child: Text(info.planName ?? '无套餐', style: TextStyle(fontSize: 11, color: cs.onPrimaryContainer)),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(4)),
                                child: Text('到期: $expireText', style: TextStyle(fontSize: 11, color: cs.onTertiaryContainer)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // 余额行
                Row(
                  children: [
                    _infoTile(cs, '账户余额', "¥${info.balance != null ? (info.balance! / 100).toStringAsFixed(2) : "0.00"}"),
                    if (info.commissionBalance != null)
                      _infoTile(cs, '佣金', '¥${(info.commissionBalance! / 100).toStringAsFixed(2)}'),
                  ],
                ),
                const SizedBox(height: 16),
                // 流量使用
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('流量使用情况', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant)),
                      Text('${usedGB.toStringAsFixed(1)} GB / ${totalGB.toStringAsFixed(1)} GB', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ]),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: ratio, minHeight: 8,
                          backgroundColor: cs.surfaceContainerHighest, valueColor: AlwaysStoppedAnimation(barColor)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ---- 功能菜单 ----
        _menuItem(cs, Icons.account_balance_wallet_outlined, '钱包充值', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WalletView()))),
        _menuItem(cs, Icons.person_add_outlined, '邀请与佣金', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InviteView()))),
        _menuItem(cs, Icons.receipt_long_outlined, '订单历史', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OrdersView()))),
        _menuItem(cs, Icons.construction_outlined, '工具', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ToolsView()))),
        _menuItem(cs, Icons.sync, '同步订阅', _syncSubscription),
        _menuItem(cs, Icons.system_update_alt, '检查更新', _handleCheckUpdate),
        _menuItem(cs, Icons.logout, '退出登录', _handleLogout, danger: true),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _infoTile(ColorScheme cs, String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cs.primary)),
        ],
      ),
    );
  }

  Widget _menuItem(ColorScheme cs, IconData icon, String title, VoidCallback onTap, {bool danger = false}) {
    final c = danger ? cs.error : cs.onSurface;
    return Card(
      margin: const EdgeInsets.only(bottom: 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
      child: ListTile(
        leading: Icon(icon, color: c),
        title: Text(title, style: TextStyle(color: c)),
        trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
        onTap: onTap,
      ),
    );
  }
}
