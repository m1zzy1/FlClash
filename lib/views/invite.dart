import 'package:fl_clash/services/shop_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class InviteView extends StatefulWidget {
  const InviteView({super.key});
  @override
  State<InviteView> createState() => _InviteViewState();
}

class _InviteViewState extends State<InviteView> {
  Map<String, dynamic>? _data;
  List<dynamic> _codes = [];
  String? _inviteCode;
  String? _appUrl;
  bool _isLoading = true;
  List<Map<String, dynamic>> _records = [];
  bool _recordsLoading = false;
  List<Map<String, dynamic>> _withdrawMethods = [];
  double _minWithdrawAmount = 0;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { super.dispose(); }

  String _inviteLink(String code) {
    final base = _appUrl?.replaceAll(RegExp(r'/+$'), '') ?? '';
    if (base.isEmpty) return code;
    return '$base/#/register?code=$code';
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        shopService.fetchInviteData(),
        shopService.fetchAppUrl(),
        shopService.fetchCommissionConfig(),
      ]);
      if (mounted) {
        final data = results[0] as Map<String, dynamic>;
        final codes = (data['codes'] as List<dynamic>?) ?? [];
        final appUrl = results[1] as String?;
        final config = results[2] as Map<String, dynamic>;
        final methods = (config['withdraw_methods'] as List<dynamic>?) ?? [];
        final minAmt = ((config['min_withdraw_amount'] as num?)?.toDouble() ?? 0) / 100;
        setState(() {
          _data = data;
          _codes = codes;
          _appUrl = appUrl;
          _withdrawMethods = methods.map((e) {
            if (e is Map) return Map<String, dynamic>.from(e);
            return <String, dynamic>{'id': e.toString(), 'name': e.toString()};
          }).toList();
          _minWithdrawAmount = minAmt;
          _inviteCode = codes.isNotEmpty
              ? (codes.first is Map ? (codes.first as Map)['code']?.toString() ?? codes.first.toString() : codes.first.toString())
              : null;
          _isLoading = false;
        });
        _loadRecords();
      }
    } catch (_) { if (mounted) setState(() => _isLoading = false); }
  }

  Future<void> _genCode() async {
    try {
      await shopService.generateInviteCode();
      await _load();
      if (mounted && _inviteCode != null) {
        final link = _inviteLink(_inviteCode!);
        Clipboard.setData(ClipboardData(text: link));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('链接已复制')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('生成失败')));
      }
    }
  }

  Future<void> _loadRecords() async {
    setState(() => _recordsLoading = true);
    try {
      final records = await shopService.fetchCommissionRecords();
      if (mounted) setState(() => _records = records);
    } catch (_) {}
    if (mounted) setState(() => _recordsLoading = false);
  }

  String _fmtTime(dynamic ts) {
    if (ts is! int || ts <= 0) return '--';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final stat = (_data?['stat'] as List<dynamic>?) ?? [];
    final regCount = stat.isNotEmpty ? stat[0] ?? 0 : 0;
    final pendingCommission = stat.length > 2 ? (stat[2] ?? 0) : 0;
    final rate = stat.length > 3 ? stat[3] ?? 0 : 0;
    final availableCommission = stat.length > 4 ? (stat[4] ?? 0) : 0;
    final totalCommission = availableCommission + pendingCommission;
    final totalStr = '¥${(totalCommission is num ? (totalCommission / 100) : 0).toStringAsFixed(2)}';
    final pendingStr = '¥${(pendingCommission is num ? pendingCommission / 100 : 0).toStringAsFixed(2)}';
    final availableStr = (availableCommission is num ? availableCommission / 100 : 0).toStringAsFixed(2);

    return Scaffold(
      appBar: AppBar(title: const Text('我的邀请')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              // ── 当前剩余佣金 + 操作 ──
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$availableStr CNY', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: cs.onSurface)),
                  const SizedBox(height: 2),
                  Text('当前剩余佣金', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                  const SizedBox(height: 14),
                  Row(children: [
                    SizedBox(
                      height: 36,
                      child: FilledButton(
                        onPressed: () => _showTransferDialog(),
                        style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
                        child: const Text('划转', style: TextStyle(fontSize: 13)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 36,
                      child: OutlinedButton(
                        onPressed: () => _showWithdrawDialog(),
                        style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
                        child: const Text('推广佣金提现', style: TextStyle(fontSize: 13)),
                      ),
                    ),
                  ]),
                ]),
              ),
              const SizedBox(height: 12),

              // ── 4 项统计 ──
              Container(
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: Column(children: [
                  _statRow(cs, Icons.people_rounded, '注册用户', '$regCount'),
                  Divider(height: 1, indent: 48, color: cs.outlineVariant.withValues(alpha: 0.3)),
                  _statRow(cs, Icons.trending_up_rounded, '佣金比例', '$rate%'),
                  Divider(height: 1, indent: 48, color: cs.outlineVariant.withValues(alpha: 0.3)),
                  _statRow(cs, Icons.pending_actions_rounded, '待结算', pendingStr),
                  Divider(height: 1, indent: 48, color: cs.outlineVariant.withValues(alpha: 0.3)),
                  _statRow(cs, Icons.account_balance_wallet_rounded, '累计', totalStr),
                ]),
              ),
              const SizedBox(height: 16),

              // ── 邀请码管理（表格风格） ──
              Container(
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: Column(children: [
                  // 表头
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(children: [
                      Text('邀请码管理', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      const Spacer(),
                      FilledButton(
                        onPressed: _genCode,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('生成邀请码', style: TextStyle(fontSize: 13)),
                      ),
                    ]),
                  ),
                  // 列标题
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: cs.surfaceContainerHighest),
                    child: Row(children: [
                      Expanded(flex: 3, child: Text('邀请码', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant))),
                      Expanded(flex: 2, child: Text('创建时间', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant))),
                    ]),
                  ),
                  // 数据行
                  if (_codes.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(child: Text('暂无邀请码', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant))),
                    )
                  else
                    ..._codes.asMap().entries.map((entry) {
                      final item = entry.value;
                      final code = item is Map ? item['code']?.toString() ?? '' : item.toString();
                      final createdAt = item is Map ? item['created_at'] : null;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          border: entry.key < _codes.length - 1
                              ? Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)))
                              : null,
                        ),
                        child: Row(children: [
                          Expanded(
                            flex: 3,
                            child: Row(children: [
                              Text(code, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface)),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () {
                                  final link = _inviteLink(code);
                                  Clipboard.setData(ClipboardData(text: link));
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('链接已复制')));
                                },
                                child: Text('复制链接', style: TextStyle(fontSize: 12, color: cs.primary)),
                              ),
                            ]),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              createdAt != null ? _fmtTime(createdAt) : '--',
                              textAlign: TextAlign.right,
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                            ),
                          ),
                        ]),
                      );
                    }),
                ]),
              ),
              const SizedBox(height: 12),

              // ── 佣金发放记录 ──
              Container(
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                    child: Row(children: [
                      Icon(Icons.receipt_long_outlined, size: 16, color: cs.primary),
                      const SizedBox(width: 6),
                      Text('佣金发放记录', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    ]),
                  ),
                  // 列标题
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: cs.surfaceContainerHighest),
                    child: Row(children: [
                      Expanded(child: Text('发放时间', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant))),
                      Expanded(child: Text('佣金', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant))),
                    ]),
                  ),
                  // 数据
                  if (_recordsLoading)
                    const Padding(padding: EdgeInsets.all(24), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
                  else if (_records.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Column(children: [
                          Icon(Icons.inbox_rounded, size: 32, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                          const SizedBox(height: 8),
                          Text('暂无发放记录', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                        ]),
                      ),
                    )
                  else
                    ..._records.asMap().entries.map((entry) {
                      final r = entry.value;
                      final commission = ((r['get_amount'] as num?)?.toDouble() ?? 0) / 100;
                      final createdAt = r['created_at'] as int?;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          border: entry.key < _records.length - 1
                              ? Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)))
                              : null,
                        ),
                        child: Row(children: [
                          Expanded(child: Text(createdAt != null ? _fmtTime(createdAt) : '--',
                              style: TextStyle(fontSize: 12, color: cs.onSurface))),
                          Expanded(child: Text('¥${commission.toStringAsFixed(2)}',
                              textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary))),
                        ]),
                      );
                    }),
                ]),
              ),
            ]),
    );
  }

  Widget _section({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: child,
    );
  }

  void _showTransferDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('划转佣金', style: TextStyle(fontSize: 17)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(children: [
              Icon(Icons.info_outline_rounded, size: 14, color: Colors.orange),
              const SizedBox(width: 6),
              Expanded(child: Text('划转后的余额仅用于消费使用，无法提现',
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade800))),
            ]),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: '输入金额',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              prefixText: '¥ ',
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final amt = double.tryParse(ctrl.text.trim());
              if (amt == null || amt <= 0) return;
              final ok = await shopService.transferCommission(amt);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? '划转成功' : '划转失败')));
                if (ok) _load();
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showWithdrawDialog() {
    if (_withdrawMethods.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('暂无可用提现方式')));
      return;
    }
    final accountCtrl = TextEditingController();
    String selectedMethod = _withdrawMethods.first['id']?.toString() ?? '';
    bool loading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text('申请提现', style: TextStyle(fontSize: 17)),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 提现方式
            Text('提现方式', style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            if (_withdrawMethods.length == 1)
              Text(_withdrawMethods.first['name'] as String? ?? '',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: _withdrawMethods.map((m) {
                  final id = m['id']?.toString() ?? '';
                  final name = m['name'] as String? ?? id;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(name, style: const TextStyle(fontSize: 12)),
                      selected: selectedMethod == id,
                      selectedColor: Theme.of(context).colorScheme.primaryContainer,
                      onSelected: (_) => setDlgState(() => selectedMethod = id),
                    ),
                  );
                }).toList()),
              ),
            const SizedBox(height: 16),
            Text('提现账号', style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            TextField(
              controller: accountCtrl,
              decoration: InputDecoration(
                hintText: '请输入提现账号',
                hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: loading ? null : () async {
                final account = accountCtrl.text.trim();
                if (account.isEmpty) return;
                setDlgState(() => loading = true);
                final stat = (_data?['stat'] as List<dynamic>?) ?? [];
                final available = stat.length > 4 ? (stat[4] ?? 0) : 0;
                final amount = (available is num ? available / 100 : 0.0).toDouble();
                if (amount <= 0) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无可提现金额')));
                  return;
                }
                final ok = await shopService.withdrawCommission(
                  amount: amount, account: account, method: selectedMethod,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(ok ? '提现申请已提交' : '提现失败')),
                  );
                  if (ok) _load();
                }
              },
              child: loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('确认'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statRow(ColorScheme cs, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(children: [
        Icon(icon, size: 16, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: cs.onSurface))),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface)),
      ]),
    );
  }

  Widget _ruleItem(ColorScheme cs, String step, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Text(step, style: TextStyle(fontSize: 12, color: cs.primary)),
        const SizedBox(width: 6),
        Text(desc, style: TextStyle(fontSize: 13, color: cs.onSurface)),
      ]),
    );
  }
}
