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
  bool _isLoading = true;
  final _transferCtrl = TextEditingController();

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _transferCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final data = await shopService.fetchInviteData();
      if (mounted) {
        final codes = (data['codes'] as List<dynamic>?) ?? [];
        final stat = (data['stat'] as List<dynamic>?) ?? [];
        setState(() {
          _data = data;
          _codes = codes;
          // codes 可能是字符串数组或对象数组
          _inviteCode = codes.isNotEmpty
              ? (codes.first is Map ? (codes.first as Map)['code']?.toString() ?? codes.first.toString() : codes.first.toString())
              : null;
          _isLoading = false;
        });
      }
    } catch (_) { if (mounted) setState(() => _isLoading = false); }
  }

  Future<void> _genCode() async {
    final code = await shopService.generateInviteCode();
    if (code != null && mounted) {
      setState(() => _inviteCode = code);
      Clipboard.setData(ClipboardData(text: code));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('邀请码已复制')));
    }
  }

  Future<void> _transfer() async {
    final amt = double.tryParse(_transferCtrl.text.trim());
    if (amt == null || amt <= 0) return;
    final ok = await shopService.transferCommission(amt);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? '划转成功' : '划转失败')));
      if (ok) { _transferCtrl.clear(); _load(); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final stat = (_data?['stat'] as List<dynamic>?) ?? [];
    final regCount = stat.isNotEmpty ? stat[0] ?? 0 : 0;
    final validCommission = stat.length > 1 ? (stat[1] ?? 0) : 0;
    final pendingCommission = stat.length > 2 ? (stat[2] ?? 0) : 0;
    final rate = stat.length > 3 ? stat[3] ?? 0 : 0;
    final availableCommission = stat.length > 4 ? (stat[4] ?? 0) : 0;

    return Scaffold(
      appBar: AppBar(title: const Text('邀请与佣金')),
      body: _isLoading ? const Center(child: CircularProgressIndicator())
      : ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _stat(cs, '$regCount', '邀请人数'),
            _stat(cs, '$rate%', '佣金比例'),
            _stat(cs, '¥${(availableCommission is num ? availableCommission / 100 : 0).toStringAsFixed(2)}', '可用佣金'),
          ]),
        ]))),
        const SizedBox(height: 12),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
          Row(children: [
            Expanded(child: Text(_inviteCode ?? '点击下方按钮生成邀请码', style: TextStyle(color: cs.onSurfaceVariant))),
            if (_inviteCode != null) IconButton(icon: const Icon(Icons.copy), onPressed: () {
              Clipboard.setData(ClipboardData(text: _inviteCode!));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制')));
            }),
          ]),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _genCode, child: const Text('生成邀请码')),
        ]))),
        const SizedBox(height: 12),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
          const Text('划转佣金到余额', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(controller: _transferCtrl, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '划转金额', border: OutlineInputBorder(), prefixText: '¥ ')),
          const SizedBox(height: 12),
          FilledButton(onPressed: _transfer,
            style: ButtonStyle(minimumSize: const WidgetStatePropertyAll(Size(double.infinity, 48))),
            child: const Text('划转')),
        ]))),
      ]),
    );
  }

  Widget _stat(ColorScheme cs, String value, String label) {
    return Column(children: [
      Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cs.primary)),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
    ]);
  }
}
