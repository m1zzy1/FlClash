import 'package:fl_clash/services/api_client.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef OnForceLogout = void Function();

class AuthService {
  static AuthService? _instance;
  static OnForceLogout? onForceLogout;

  AuthService._internal();

  factory AuthService() {
    _instance ??= AuthService._internal();
    return _instance!;
  }

  Future<LoginResult> login({
    required String baseUrl,
    required String email,
    required String password,
    String apiPath = '/api/v1',
  }) async {
    apiClient.configure(baseUrl: baseUrl, apiPath: apiPath);

    final response = await apiClient.post(
      '/passport/auth/login',
      data: {
        'email': email,
        'password': password,
      },
    );

    final data = response['data'] as Map<String, dynamic>? ?? response;

    if (data case {'token': String token, 'auth_data': String authData}) {
      apiClient.setAuth(authData: authData, token: token);
      await _persistAuth(
        token: token,
        authData: authData,
        baseUrl: baseUrl,
        apiPath: apiPath,
        isAdmin: data['is_admin'],
      );
      return LoginResult(
        token: token,
        authData: authData,
        isAdmin: data['is_admin'] == 1,
      );
    }

    throw Exception('登录数据不完整');
  }

  Future<UserInfo> getUserInfo() async {
    final response = await apiClient.get('/user/info');
    final data = response['data'] as Map<String, dynamic>? ?? response;
    // 调试：输出 API 返回的原始数据字段名
    debugPrint("V2Board /user/info keys: ${data.keys.join(', ')}");
    return UserInfo.fromJson(data);
  }

  Future<void> logout() async {
    apiClient.clear();
    await _clearPersistedAuth();
  }

  Future<bool> tryRestoreSession() async {
    final sp = await SharedPreferences.getInstance();
    final authData = sp.getString('api_auth_data');
    final token = sp.getString('api_token');
    final baseUrl = sp.getString('api_base_url');
    final apiPath = sp.getString('api_path') ?? '/api/v1';
    if (authData != null && baseUrl != null) {
      apiClient.configure(baseUrl: baseUrl, token: token, apiPath: apiPath);
      apiClient.setAuth(authData: authData, token: token);
      return true;
    }
    return false;
  }

  String? get token => apiClient.token;

  /// 获取 V2Board 订阅链接
  Future<String?> fetchSubscribeUrl() async {
    final base = apiClient.baseUrl;
    final token = apiClient.token;
    if (base != null && token != null) {
      return '$base/api/v1/client/subscribe?token=$token';
    }
    return null;
  }

  /// 构建 V2Board 订阅链接（备用方案）
  String? get subscribeUrl {
    final base = apiClient.baseUrl;
    final auth = apiClient.authData;
    if (base == null || auth == null) return null;
    return '$base/api/v1/client/subscribe?token=$auth';
  }

  Future<void> _persistAuth({
    required String token,
    required String authData,
    required String baseUrl,
    String apiPath = '/api/v1',
    dynamic isAdmin,
  }) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('api_token', token);
    await sp.setString('api_auth_data', authData);
    await sp.setString('api_base_url', baseUrl);
    await sp.setString('api_path', apiPath);
    if (isAdmin == 1) {
      await sp.setString('api_is_admin', '1');
    }
  }

  Future<void> _clearPersistedAuth() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove('api_token');
    await sp.remove('api_auth_data');
    await sp.remove('api_is_admin');
    // 保留 api_base_url 和 api_path，供登录页自动填充
  }

  Future<void> clearAuth() async {
    apiClient.clear();
    await _clearPersistedAuth();
    // 触发强制退出登录回调，通知 UI 跳转到登录页
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onForceLogout?.call();
    });
  }
}

class LoginResult {
  final String token;
  final String authData;
  final bool isAdmin;

  LoginResult({
    required this.token,
    required this.authData,
    required this.isAdmin,
  });

  factory LoginResult.success({
    required String token,
    required String authData,
    required bool isAdmin,
  }) {
    return LoginResult(
      token: token,
      authData: authData,
      isAdmin: isAdmin,
    );
  }
}

class UserInfo {
  final String? email;
  final int? balance;
  final int? expireAt;
  final int? trafficUsed;
  final int? trafficTotal;
  final String? planName;
  final int? planId;
  final int? commissionBalance;
  final int? inviteCount;
  final int? inviteRate;
  final bool? autoRenewal;

  UserInfo({
    this.email,
    this.balance,
    this.expireAt,
    this.trafficUsed,
    this.trafficTotal,
    this.planName,
    this.planId,
    this.commissionBalance,
    this.inviteCount,
    this.inviteRate,
    this.autoRenewal,
  });

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    // 兼容 int/String 类型
    int? toInt(dynamic v) {
      if (v is int) return v;
      if (v is double) return v.round();
      if (v is String) return int.tryParse(v);
      return null;
    }

    // V2Board 此面板 /user/info 不返回 u/d，流量数据需从订阅同步获取
    final transfer = toInt(json['transfer_enable']);

    return UserInfo(
      email: json['email'] as String?,
      balance: toInt(json['balance']),
      expireAt: toInt(json['expired_at']),
      trafficUsed: 0,
      trafficTotal: transfer,
      planName: null, // 此面板不返回套餐名称，需从 plan_id 匹配
      planId: toInt(json['plan_id']),
      commissionBalance: toInt(json['commission_balance']),
      inviteCount: toInt(json['invite_count']),
      inviteRate: toInt(json['invite_rate']),
      autoRenewal: json['auto_renewal'] == 1,
    );
  }
}

final authService = AuthService();
