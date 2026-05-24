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
    final data = res['data'] as Map<String, dynamic>? ?? res;
    return CouponResult(
      valid: data['valid'] == true,
      discount: (data['discount'] ?? 0) as num,
      discountAmount: ((data['discount_amount'] ?? data['amount'] ?? 0) as num).toDouble(),
    );
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

  /// 获取邀请数据
  Future<Map<String, dynamic>> fetchInviteData() async {
    final res = await apiClient.get('/user/invite/fetch');
    return res['data'] as Map<String, dynamic>? ?? res;
  }

  /// 生成邀请码
  Future<String?> generateInviteCode() async {
    final res = await apiClient.get('/user/invite/save');
    final data = res['data'] as Map<String, dynamic>? ?? res;
    return data['code'] as String? ?? data['invite_code'] as String?;
  }

  /// 划转佣金到余额
  Future<bool> transferCommission(double amount) async {
    try {
      await apiClient.post('/user/transfer', data: {'transfer_amount': amount});
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
  final List<ContentItem> contentList;

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
    this.contentList = const [],
  });

  /// 获取所有可选的价格类型及对应价格
  List<PriceOption> get priceOptions {
    final options = <PriceOption>[];
    final entries = [
      ('month_price', '月付', monthPrice),
      ('quarter_price', '季付', quarterPrice),
      ('half_year_price', '半年付', halfYearPrice),
      ('year_price', '年付', yearPrice),
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
      contentList = _parseJsonDescription(desc).map((e) => ContentItem(text: e)).toList();
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
      contentList: contentList,
    );
  }

  static double _getPrice(Map<String, dynamic> json, String key) {
    final val = json[key];
    if (val is num) return val.toDouble() / 100;
    if (val is String) return (double.tryParse(val) ?? 0) / 100;
    return 0;
  }

  static List<String> _parseJsonDescription(String text) {
    final trimmed = text.trim();
    // JSON array of feature objects
    if (trimmed.startsWith('[')) {
      try {
        final list = const JsonDecoder().convert(trimmed);
        if (list is List) {
          final result = <String>[];
          for (final item in list) {
            if (item is Map) {
              result.add((item['feature'] ?? item['name'] ?? item['text'] ?? item.toString()).toString());
            } else {
              result.add(item.toString());
            }
          }
          if (result.isNotEmpty) return result;
        }
      } catch (_) {}
    }
    // JSON object
    if (trimmed.startsWith('{')) {
      try {
        final decoded = const JsonDecoder().convert(trimmed);
        if (decoded is Map) {
          final result = <String>[];
          for (final val in decoded.values) {
            if (val is String && val.isNotEmpty) {
              result.add(val);
            } else if (val is List) {
              result.addAll(val.map((e) => e.toString()));
            } else if (val is Map) {
              result.add((val['feature'] ?? val['name'] ?? '').toString());
            }
          }
          if (result.isNotEmpty) return result;
        }
      } catch (_) {}
    }
    final htmlStripped = text
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    if (htmlStripped.contains('\n')) {
      return htmlStripped
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (htmlStripped.isNotEmpty && htmlStripped != text) {
      return [htmlStripped];
    }
    return [text];
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

  CouponResult({
    required this.valid,
    required this.discount,
    required this.discountAmount,
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
      case 1: return '已完成';
      case 2: return '已取消';
      default: return '未知';
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
