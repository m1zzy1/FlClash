import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fl_clash/services/api_client.dart';

class ShopService {
  static ShopService? _instance;

  ShopService._internal();

  factory ShopService() {
    _instance ??= ShopService._internal();
    return _instance!;
  }

  /// 获取所有套餐
  Future<List<Plan>> fetchPlans() async {
    final res = await apiClient.get('/user/plan/fetch');
    final list = (res['data'] as List<dynamic>?) ?? (res['plans'] as List<dynamic>?) ?? [];
    return list.map((e) => Plan.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 根据 ID 获取单个套餐（包括已下架的）
  Future<Plan?> fetchPlanById(int id) async {
    try {
      final res = await apiClient.get('/user/plan/fetch', queryParameters: {'id': id});
      final data = res['data'] as Map<String, dynamic>?;
      if (data != null) return Plan.fromJson(data);
      // 有时返回数组
      final list = res['data'] as List<dynamic>?;
      if (list != null && list.isNotEmpty) {
        return Plan.fromJson(list.first as Map<String, dynamic>);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 验证优惠券
  Future<CouponResult> verifyCoupon(String code, int planId) async {
    final res = await apiClient.post('/user/coupon/check', data: {
      'code': code,
      'plan_id': planId,
    });
    final data = res['data'];
    // V2Board: 成功时 data 为对象 {type, value, name}，失败时 data 为 false/null
    if (data is Map) {
      return CouponResult(
        valid: true,
        discount: (data['discount'] ?? 0) as num,
        discountAmount: ((data['discount_amount'] ?? data['amount'] ?? 0) as num).toDouble(),
        type: (data['type'] ?? 0) as int,
        name: data['name'] as String?,
        value: ((data['value'] ?? 0) as num).toDouble(),
      );
    }
    return CouponResult(valid: false, discount: 0, discountAmount: 0);
  }

  /// 提交订单
  Future<Map<String, dynamic>> submitOrder({
    required int planId,
    required String period,
    String? couponCode,
    String? paymentMethod,
  }) async {
    final data = <String, dynamic>{
      'plan_id': planId,
      'period': period,
    };
    if (couponCode != null && couponCode.isNotEmpty) {
      data['coupon_code'] = couponCode;
    }
    try {
      final res = await apiClient.post('/user/order/save', data: data);
      final result = res['data'];
      if (result is Map<String, dynamic>) return result;
      if (result is String) return {'trade_no': result, ...res};
      return res;
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response!.data as Map)['message'] ?? e.toString()
          : e.toString();
      throw Exception(msg.toString());
    }
  }

  /// 获取支付方式
  Future<List<PaymentMethod>> getPaymentMethods() async {
    final res = await apiClient.get('/user/order/getPaymentMethod');
    final list = (res['data'] as List<dynamic>?) ?? [];
    return list.map((e) => PaymentMethod.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取订单详情
  Future<Map<String, dynamic>> getOrderDetail(String tradeNo) async {
    final res = await apiClient.get('/user/order/detail', queryParameters: {'trade_no': tradeNo});
    final data = res['data'] as Map<String, dynamic>? ?? res;
    return data;
  }

  /// 检查订单支付状态（0=待支付 1=开通中 2=已取消 3=已完成 4=已折抵）
  Future<int> checkOrderStatus(String tradeNo) async {
    final res = await apiClient.get('/user/order/check', queryParameters: {'trade_no': tradeNo});
    final data = res['data'];
    if (data is int) return data;
    if (data is String) return int.tryParse(data) ?? 0;
    if (data is Map && data.containsKey('status')) return (data['status'] as num).toInt();
    return 0;
  }

  /// 发起支付（结账）
  Future<PaymentCheckout> checkoutOrder(String tradeNo, String methodId) async {
    final res = await apiClient.post('/user/order/checkout', data: {
      'trade_no': tradeNo,
      'method': methodId,
    });
    return PaymentCheckout(
      type: (res['type'] ?? 0) as int,
      data: (res['data'] ?? '') as String,
    );
  }

  /// 获取订单列表
  Future<List<OrderItem>> fetchOrders() async {
    final res = await apiClient.get('/user/order/fetch');
    final list = (res['data'] as List<dynamic>?) ?? [];
    return list.map((e) => OrderItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 取消订单
  Future<bool> cancelOrder(String tradeNo) async {
    try {
      await apiClient.post('/user/order/cancel', data: {'trade_no': tradeNo});
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 获取站点配置（获取 app_url 用于拼接邀请链接）
  Future<String?> fetchAppUrl() async {
    try {
      // 与 EZ 主题一致：通过 apiClient 请求 /guest/comm/config
      final res = await apiClient.get('/guest/comm/config');
      // V2Board 返回 {data: {app_url: "https://...", ...}}
      final data = res['data'];
      if (data is Map) {
        final appUrl = data['app_url'] as String?;
        if (appUrl != null && appUrl.isNotEmpty) return appUrl;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 获取佣金发放记录
  Future<List<Map<String, dynamic>>> fetchCommissionRecords({int page = 1, int pageSize = 10}) async {
    try {
      final res = await apiClient.get('/user/invite/details', queryParameters: {
        'current': page,
        'page_size': pageSize,
      });
      // 兼容两种返回结构：{data: [...]} 或 {data: {data: [...], total: N}}
      var list = res['data'];
      if (list is Map) list = list['data'];
      if (list is List) {
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// 获取公告列表
  Future<List<NoticeItem>> fetchNotices() async {
    try {
      final res = await apiClient.get('/user/notice/fetch');
      final list = res['data'] as List<dynamic>? ?? [];
      return list.map((e) => NoticeItem.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  /// 获取邀请数据
  Future<Map<String, dynamic>> fetchInviteData() async {
    final res = await apiClient.get('/user/invite/fetch');
    final data = res['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    return res;
  }

  /// 生成邀请码
  Future<String?> generateInviteCode() async {
    final res = await apiClient.get('/user/invite/save');
    // 兼容多种返回格式：{data: true}、{data: {code: "xxx"}}、{data: "xxx"}
    final data = res['data'];
    if (data is Map) {
      return data['code'] as String? ?? data['invite_code'] as String?;
    }
    if (data is String && data.isNotEmpty) {
      return data;
    }
    // {data: true} 表示生成成功，返回空 sentinel
    if (data == true) return '';
    return null;
  }

  /// 划转佣金到余额（金额单位：元，API 以分为单位）
  Future<bool> transferCommission(double amount) async {
    try {
      final amountInCents = (amount * 100).round();
      await apiClient.post('/user/transfer', data: {'transfer_amount': amountInCents});
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 获取佣金配置（提现方式、最低提现金额等）
  Future<Map<String, dynamic>> fetchCommissionConfig() async {
    try {
      final res = await apiClient.get('/user/comm/config');
      final data = res['data'];
      if (data is Map) return Map<String, dynamic>.from(data);
      return {};
    } catch (_) {
      return {};
    }
  }

  /// 提现佣金
  Future<bool> withdrawCommission({
    required double amount,
    required String account,
    required String method,
  }) async {
    try {
      final amountInCents = (amount * 100).round();
      await apiClient.post('/user/ticket/withdraw', data: {
        'withdraw_amount': amountInCents,
        'withdraw_account': account,
        'withdraw_method': method,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 创建充值订单
  Future<Map<String, dynamic>> createDeposit(String amount) async {
    final res = await apiClient.post('/user/order/save', data: {
      'period': 'deposit',
      'deposit_amount': amount,
      'plan_id': 0,
    });
    final data = res['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is String) return {'trade_no': data};
    return res;
  }
}

class Plan {
  final int id;
  final String name;
  final String? description;
  final double monthPrice;
  final double quarterPrice;
  final double halfYearPrice;
  final double yearPrice;
  final double twoYearPrice;
  final double threeYearPrice;
  final double onetimePrice;
  final double resetPrice;
  final int? totalBandwidth;
  final int? nodeSpeedLimit;
  final int? nodeConnector;
  final int? trafficLimit;
  final int? sort;
  final int? stock;
  final List<ContentItem> contentList;

  bool get isRecurring =>
      monthPrice > 0 || quarterPrice > 0 || halfYearPrice > 0 ||
      yearPrice > 0 || twoYearPrice > 0 || threeYearPrice > 0;
  bool get isOneTime => onetimePrice > 0;

  Plan({
    required this.id,
    required this.name,
    this.description,
    this.monthPrice = 0,
    this.quarterPrice = 0,
    this.halfYearPrice = 0,
    this.yearPrice = 0,
    this.twoYearPrice = 0,
    this.threeYearPrice = 0,
    this.onetimePrice = 0,
    this.resetPrice = 0,
    this.totalBandwidth,
    this.nodeSpeedLimit,
    this.nodeConnector,
    this.trafficLimit,
    this.sort,
    this.stock,
    this.contentList = const [],
  });

  /// 获取所有可选的价格类型及对应价格
  List<PriceOption> get priceOptions {
    final options = <PriceOption>[];
    final entries = [
      ('month_price', '月付', monthPrice),
      ('quarter_price', '季度', quarterPrice),
      ('half_year_price', '半年', halfYearPrice),
      ('year_price', '一年', yearPrice),
      ('two_year_price', '两年付', twoYearPrice),
      ('three_year_price', '三年付', threeYearPrice),
      ('onetime_price', '一次性', onetimePrice),
      ('reset_price', '重置', resetPrice),
    ];
    for (final entry in entries) {
      if (entry.$3 > 0) {
        options.add(PriceOption(key: entry.$1, label: entry.$2, price: entry.$3));
      }
    }
    return options;
  }

  factory Plan.fromJson(Map<String, dynamic> json) {
    // 解析描述（可能是 JSON 数组）
    List<ContentItem> contentList = [];
    final desc = json['content'] ?? json['description'];
    if (desc is List) {
      for (final item in desc) {
        if (item is Map) {
          final feature = item['feature'] ?? item['name'] ?? item['text'] ?? '';
          final support = item['support'] != false;
          contentList.add(ContentItem(text: feature.toString(), support: support));
        } else {
          contentList.add(ContentItem(text: item.toString()));
        }
      }
    } else if (desc is String) {
      contentList = _parseJsonDescription(desc);
    }

    return Plan(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? json['plan_name'] as String? ?? '',
      description: desc is String ? desc : null,
      monthPrice: _getPrice(json, 'month_price'),
      quarterPrice: _getPrice(json, 'quarter_price'),
      halfYearPrice: _getPrice(json, 'half_year_price'),
      yearPrice: _getPrice(json, 'year_price'),
      twoYearPrice: _getPrice(json, 'two_year_price'),
      threeYearPrice: _getPrice(json, 'three_year_price'),
      onetimePrice: _getPrice(json, 'onetime_price'),
      resetPrice: _getPrice(json, 'reset_price'),
      totalBandwidth: json['total_bandwidth'] as int?,
      nodeSpeedLimit: json['node_speed_limit'] as int?,
      nodeConnector: json['node_connector'] as int?,
      trafficLimit: json['traffic_limit'] as int?,
      sort: json['sort'] as int?,
      stock: json['stock'] as int?,
      contentList: contentList,
    );
  }

  static double _getPrice(Map<String, dynamic> json, String key) {
    final val = json[key];
    if (val is num) return val.toDouble() / 100;
    if (val is String) return (double.tryParse(val) ?? 0) / 100;
    return 0;
  }

  static List<ContentItem> _parseJsonDescription(String text) {
    final trimmed = text.trim();
    // JSON array of feature objects  [{"feature":"...","support":true}, ...]
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      try {
        final list = const JsonDecoder().convert(trimmed);
        if (list is List) {
          final result = <ContentItem>[];
          for (final item in list) {
            if (item is Map) {
              final feature = item['feature'] ?? item['name'] ?? item['text'] ?? item.toString();
              final support = item['support'] != false;
              result.add(ContentItem(text: _stripHtml(feature.toString()), support: support));
            } else {
              result.add(ContentItem(text: _stripHtml(item.toString())));
            }
          }
          if (result.isNotEmpty) return result;
        }
      } catch (_) {}
    }
    // JSON object  {"key": "value", ...}
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final decoded = const JsonDecoder().convert(trimmed);
        if (decoded is Map) {
          final result = <ContentItem>[];
          for (final val in decoded.values) {
            if (val is String && val.isNotEmpty) {
              result.add(ContentItem(text: _stripHtml(val)));
            } else if (val is List) {
              for (final e in val) {
                if (e is Map) {
                  final feature = e['feature'] ?? e['name'] ?? e.toString();
                  final support = e['support'] != false;
                  result.add(ContentItem(text: _stripHtml(feature.toString()), support: support));
                } else {
                  result.add(ContentItem(text: _stripHtml(e.toString())));
                }
              }
            } else if (val is Map) {
              final feature = val['feature'] ?? val['name'] ?? '';
              final support = val['support'] != false;
              result.add(ContentItem(text: _stripHtml(feature.toString()), support: support));
            }
          }
          if (result.isNotEmpty) return result;
        }
      } catch (_) {}
    }
    // HTML or plain text fallback
    final stripped = _stripHtml(text);
    if (stripped.contains('\n')) {
      return stripped
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .map((e) => ContentItem(text: e))
          .toList();
    }
    if (stripped.isNotEmpty) return [ContentItem(text: stripped)];
    return [];
  }

  /// 去除 HTML 标签并解码常见实体
  static String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .trim();
  }
}

class ContentItem {
  final String text;
  final bool support;

  ContentItem({required this.text, this.support = true});
}

class PriceOption {
  final String key;
  final String label;
  final double price;

  PriceOption({required this.key, required this.label, required this.price});
}

class CouponResult {
  final bool valid;
  final num discount;
  final double discountAmount;
  final int type; // 1=固定金额, 2=百分比
  final String? name;
  final double value; // 分(固定) 或 %(百分比)

  CouponResult({
    required this.valid,
    required this.discount,
    required this.discountAmount,
    this.type = 0,
    this.name,
    this.value = 0,
  });
}

class PaymentMethod {
  final String id;
  final String name;
  final String? icon;
  final String? handler;

  PaymentMethod({required this.id, required this.name, this.icon, this.handler});

  factory PaymentMethod.fromJson(Map<String, dynamic> json) {
    return PaymentMethod(
      id: (json['id'] ?? json['payment'] ?? '').toString(),
      name: json['name'] as String? ??
             json['payment_name'] as String? ??
             json['handler'] as String? ??
             '未知支付方式',
      icon: json['icon'] as String?,
      handler: json['handler'] as String?,
    );
  }
}

class PaymentCheckout {
  final int type; // 0=QR code, 1=URL
  final String data;

  PaymentCheckout({required this.type, required this.data});
}

class NoticeItem {
  final String title;
  final String content;
  final String? imgUrl;
  final int createdAt;
  final int updatedAt;
  final List<String> tags;

  /// 优先显示更新时间，没有则用创建时间
  int get displayTime => updatedAt > 0 ? updatedAt : createdAt;

  NoticeItem({
    required this.title,
    required this.content,
    this.imgUrl,
    this.createdAt = 0,
    this.updatedAt = 0,
    this.tags = const [],
  });

  factory NoticeItem.fromJson(Map<String, dynamic> json) {
    // tags 可能是逗号分隔字符串或 JSON 数组
    List<String> tags = [];
    final tagsRaw = json['tags'];
    if (tagsRaw is String) {
      tags = tagsRaw.isNotEmpty
          ? tagsRaw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
          : [];
    } else if (tagsRaw is List) {
      tags = tagsRaw.map((e) => e.toString()).toList();
    }
    return NoticeItem(
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      imgUrl: json['img_url'] as String?,
      createdAt: json['created_at'] as int? ?? 0,
      updatedAt: json['updated_at'] as int? ?? 0,
      tags: tags,
    );
  }
}

class OrderItem {
  final String tradeNo;
  final int planId;
  final String? planName;
  final double totalAmount;
  final int status; // 0=pending, 1=completed, 2=cancelled
  final String? period;
  final int createdAt;

  OrderItem({
    required this.tradeNo,
    required this.planId,
    this.planName,
    required this.totalAmount,
    required this.status,
    this.period,
    required this.createdAt,
  });

  String get statusText {
    switch (status) {
      case 0: return '待支付';
      case 1: return '开通中';
      case 2: return '已取消';
      case 3: return '已完成';
      case 4: return '已折抵';
      default: return '未知';
    }
  }

  String get periodText {
    if (period == null) return '';
    switch (period) {
      case 'month_price': return '月付';
      case 'quarter_price': return '季度';
      case 'half_year_price': return '半年';
      case 'year_price': return '一年';
      case 'two_year_price': return '两年';
      case 'three_year_price': return '三年';
      case 'onetime_price': return '一次性';
      case 'reset_price': return '重置';
      case 'deposit': return '充值';
      default: return period!;
    }
  }

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    final plan = json['plan'] as Map<String, dynamic>?;
    return OrderItem(
      tradeNo: json['trade_no'] as String? ?? '',
      planId: json['plan_id'] as int? ?? 0,
      planName: plan?['name'] as String? ?? json['plan_name'] as String?,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
      status: json['status'] as int? ?? 0,
      period: json['period'] as String?,
      createdAt: json['created_at'] as int? ?? 0,
    );
  }
}

final shopService = ShopService();
