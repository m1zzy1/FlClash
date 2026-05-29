import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fl_clash/common/app_config.dart';
import 'package:fl_clash/common/feature_flags.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/controller.dart';
import 'package:fl_clash/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';



class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _serverUrlController = TextEditingController();
  final _apiPathController = TextEditingController(text: '/api/v1');
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = true;
  bool _isRegisterMode = false;
  bool _isForgotPasswordMode = false;
  final _inviteCodeController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _codeController = TextEditingController();
  final _resetPasswordController = TextEditingController();
  final _confirmResetPasswordController = TextEditingController();
  bool _agreeTerms = true;
  bool _codeSent = false;
  bool _isResetting = false;
  bool _obscureConfirmPassword = true;
  bool _obscureResetPassword = true;
  bool _obscureConfirmResetPassword = true;
  final _emailPrefixController = TextEditingController();
  String _selectedSuffix = '';
  bool _showSuffixDropdown = false;
  String _siteDescription = '登录到您的账户';
  String _appUrl = '';
  String _tosUrl = '';
  List<String> _emailWhitelist = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSavedInfo();
  }

  Future<void> _loadSavedInfo() async {
    final sp = await SharedPreferences.getInstance();
    final savedUrl = sp.getString('api_base_url');
    final savedEmail = sp.getString('login_email');
    final savedPassword = sp.getString('login_password');
    final savedRemember = sp.getBool('login_remember');

    if (savedRemember != false) {
      _rememberMe = true;
      if (savedEmail != null) _emailController.text = savedEmail;
      if (savedPassword != null) _passwordController.text = savedPassword;
    } else {
      _rememberMe = false;
    }
    if (savedUrl != null) _serverUrlController.text = savedUrl;
    await _fetchOssUrl();
    _loadSiteConfig();
  }

  Future<void> _fetchOssUrl() async {
    if (!FeatureFlags.enableAppConfig) return;
    // 1. 从 OSS 获取服务器地址列表
    List<String> urls = [];
    for (final ossUrl in AppConfig.oss) {
      try {
        final dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          headers: {'User-Agent': browserUa},
        ));
        if (ossUrl.startsWith('https')) {
          dio.httpClientAdapter = IOHttpClientAdapter(
            createHttpClient: () {
              final client = HttpClient();
              client.badCertificateCallback = (_, _, _) => true;
              return client;
            },
          );
        }
        final response = await dio.get<String>(ossUrl);
        if (response.statusCode != 200 || response.data == null) continue;
        final decoded = utf8.decode(base64Decode(response.data!.trim()));
        final jsonData = json.decode(decoded);
        if (jsonData is Map && jsonData['urls'] is List) {
          urls = (jsonData['urls'] as List).cast<String>();
          break;
        }
      } catch (_) {
        continue;
      }
    }
    if (urls.isEmpty) return;

    // 2. 逐个测试连通性，用第一个通的地址
    for (final url in urls) {
      try {
        final testUrl = '${url.endsWith('/') ? url.substring(0, url.length - 1) : url}/api/v1/guest/comm/config';
        final dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          headers: {'User-Agent': browserUa},
        ));
        if (testUrl.startsWith('https')) {
          dio.httpClientAdapter = IOHttpClientAdapter(
            createHttpClient: () {
              final client = HttpClient();
              client.badCertificateCallback = (_, _, _) => true;
              return client;
            },
          );
        }
        final res = await dio.get(testUrl);
        if (res.statusCode == 200) {
          if (mounted) setState(() => _serverUrlController.text = url);
          return;
        }
      } catch (_) {
        continue;
      }
    }
  }

  Future<void> _loadSiteConfig() async {
    final baseUrl = _serverUrlController.text.trim();
    final apiPath = _apiPathController.text.trim();
    if (baseUrl.isEmpty) return;
    try {
      final cleanPath = apiPath.startsWith('/') ? apiPath.substring(1) : apiPath;
      final sep = baseUrl.endsWith('/') ? '' : '/';
      final url = '$baseUrl$sep$cleanPath/guest/comm/config';
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        headers: {'Content-Type': 'application/json', 'User-Agent': browserUa},
      ));
      if (url.startsWith('https')) {
        dio.httpClientAdapter = IOHttpClientAdapter(
          createHttpClient: () {
            final client = HttpClient();
            client.badCertificateCallback = (_, _, _) => true;
            client.findProxy = (uri) => 'DIRECT';
            return client;
          },
        );
      }
      final response = await dio.get(url);
      final body = response.data is Map ? response.data as Map<String, dynamic> : <String, dynamic>{};
      final data = (body['data'] ?? body) as Map<String, dynamic>;
      if (mounted) {
        final desc = data['app_description'] as String?;
        if (desc != null && desc.isNotEmpty) _siteDescription = desc;
        final appUrl = data['app_url'] as String?;
        if (appUrl != null && appUrl.isNotEmpty) _appUrl = appUrl;
        final tosUrl = data['tos_url'] as String?;
        if (tosUrl != null && tosUrl.isNotEmpty) _tosUrl = tosUrl;
        final whitelist = data['email_whitelist_suffix'];
        if (whitelist is List) {
          _emailWhitelist = whitelist.cast<String>();
        } else if (whitelist is String && whitelist.isNotEmpty) {
          _emailWhitelist = whitelist.split(',').map((e) => e.trim()).toList();
        }
        if (_emailWhitelist.isNotEmpty && _selectedSuffix.isEmpty) {
          _selectedSuffix = _emailWhitelist.first;
        }
        setState(() {});
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _inviteCodeController.dispose();
    _confirmPasswordController.dispose();
    _confirmResetPasswordController.dispose();
    _codeController.dispose();
    _resetPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await authService.login(
        baseUrl: _serverUrlController.text.trim(),
        apiPath: _apiPathController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      // 保存登录信息
      await _saveCredentials();

      // 登录后自动同步订阅配置
      if (mounted) _autoSyncSubscribe();

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } catch (e) {
      setState(() {
        _errorMessage = _formatError(e);
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;
    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() => _errorMessage = '两次输入的密码不一致');
      return;
    }
    if (!_agreeTerms) {
      setState(() => _errorMessage = '请先同意服务条款');
      return;
    }
    // 邮箱后缀白名单校验
    if (_emailWhitelist.isNotEmpty) {
      final email = _emailController.text.trim();
      final suffix = email.substring(email.indexOf('@') + 1);
      if (!_emailWhitelist.contains(suffix)) {
        setState(() => _errorMessage = '暂不支持 $suffix 邮箱，请使用: ${_emailWhitelist.join(", ")}');
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = <String, dynamic>{
        'email': _emailController.text.trim(),
        'password': _passwordController.text,
      };
      final code = _inviteCodeController.text.trim();
      if (code.isNotEmpty) data['invite_code'] = code;

      final response = await _apiPost('/passport/auth/register', data);
      final body = response.data is Map ? response.data as Map<String, dynamic> : <String, dynamic>{};
      final msg = body['message'] as String? ?? '注册成功，请登录';

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        setState(() => _isRegisterMode = false);
      }
    } catch (e) {
      setState(() {
        final msg = e.toString();
        if (msg.contains('invite') || msg.contains('invitation')) {
          _errorMessage = '需要邀请码才能注册';
        } else if (msg.contains('register') || msg.contains('closed')) {
          _errorMessage = '注册功能已关闭';
        } else {
          _errorMessage = _formatError(e);
        }
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<Response> _apiPost(String path, Map<String, dynamic> data) async {
    final base = _serverUrlController.text.trim();
    final apiPath = _apiPathController.text.trim();
    final cleanPath = apiPath.startsWith('/') ? apiPath.substring(1) : apiPath;
    final sep = base.endsWith('/') ? '' : '/';
    final url = '$base$sep$cleanPath$path';
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json', 'User-Agent': browserUa},
    ));
    if (url.startsWith('https')) {
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.badCertificateCallback = (_, _, _) => true;
          client.findProxy = (uri) => 'DIRECT';
          return client;
        },
      );
    }
    return dio.post(url, data: data);
  }

  Future<void> _saveCredentials() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('api_base_url', _serverUrlController.text.trim());
    await sp.setString('api_path', _apiPathController.text.trim());
    await sp.setBool('login_remember', _rememberMe);
    if (_rememberMe) {
      await sp.setString('login_email', _emailController.text.trim());
      await sp.setString('login_password', _passwordController.text);
    } else {
      await sp.remove('login_email');
      await sp.remove('login_password');
    }
  }

  Future<void> _handleSendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _errorMessage = '请输入有效的邮箱');
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      await _apiPost('/passport/comm/sendEmailVerify', {'email': email, 'isForgetPassword': true});
      if (mounted) {
        setState(() { _codeSent = true; });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('验证码已发送，请检查您的邮箱')),
        );
      }
    } catch (_) {
      setState(() => _errorMessage = '验证码发送失败');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleReset() async {
    if (_isResetting) return;
    _isResetting = true;
    final code = _codeController.text.trim();
    if (code.isEmpty) { _isResetting = false; setState(() => _errorMessage = '请输入验证码'); return; }
    if (_resetPasswordController.text.length < 6) { _isResetting = false; setState(() => _errorMessage = '密码长度不能少于 6 位'); return; }
    if (_resetPasswordController.text != _confirmResetPasswordController.text) { _isResetting = false; setState(() => _errorMessage = '两次密码不一致'); return; }

    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      await _apiPost('/passport/auth/forget', {
        'email': _emailController.text.trim(),
        'password': _resetPasswordController.text,
        'email_code': code,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('密码重置成功，请使用新密码登录')),
        );
        setState(() => _isForgotPasswordMode = false);
      }
    } catch (e) {
      String msg = '重置失败，请重试';
      if (e is DioException) {
        final body = e.response?.data;
        if (body is Map) {
          msg = (body['message'] as String?) ?? msg;
          if (e.response?.statusCode == 422) {
            final errors = body['errors'] as Map?;
            if (errors != null) {
              final firstError = errors.values.firstWhere(
                (v) => v is List && v.isNotEmpty, orElse: () => [],
              );
              if (firstError is List && firstError.isNotEmpty) msg = firstError.first.toString();
            }
          }
        }
      }
      setState(() => _errorMessage = msg);
    } finally {
      _isResetting = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _autoSyncSubscribe() async {
    try {
      await appController.syncSubscriptionNow();
    } catch (_) {}
  }

  void _updateEmailFromPrefix() {
    final prefix = _emailPrefixController.text.trim();
    if (prefix.isNotEmpty && _selectedSuffix.isNotEmpty) {
      _emailController.text = '$prefix@$_selectedSuffix';
    }
  }

  Widget _buildEmailWithSuffix() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: _emailPrefixController,
                decoration: InputDecoration(
                  labelText: '邮箱',
                  hintText: '请输入邮箱前缀',
                  hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onChanged: (_) => _updateEmailFromPrefix(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text('@', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            Expanded(
              flex: 2,
              child: GestureDetector(
                onTap: () => setState(() => _showSuffixDropdown = !_showSuffixDropdown),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).colorScheme.outline),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text(_selectedSuffix.isNotEmpty ? _selectedSuffix : '选择域名')),
                      Icon(Icons.arrow_drop_down, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_showSuffixDropdown)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.outline),
              borderRadius: BorderRadius.circular(12),
              color: Theme.of(context).colorScheme.surface,
            ),
            child: Column(
              children: _emailWhitelist.map((suffix) {
                final isSelected = suffix == _selectedSuffix;
                return ListTile(
                  dense: true,
                  title: Text('@$suffix', style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  )),
                  trailing: isSelected ? Icon(Icons.check, size: 18) : null,
                  onTap: () {
                    setState(() {
                      _selectedSuffix = suffix;
                      _showSuffixDropdown = false;
                    });
                    _updateEmailFromPrefix();
                  },
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Future<void> _handleForgotPassword() async {
    setState(() {
      _isForgotPasswordMode = true;
      _isRegisterMode = false;
      _errorMessage = null;
    });
  }

  String _formatError(Object error) {
    // 优先从 DioException 的响应数据中提取 V2Board 返回的 message
    if (error is DioException) {
      final response = error.response;
      // V2Board 返回的 message 可能在 response.data 或 response.data['message']
      if (response?.data != null) {
        if (response!.data is Map) {
          final data = response.data as Map;
          final apiMessage = data['message'] as String? ?? data['error'] as String?;
          if (apiMessage != null && apiMessage.isNotEmpty) {
            return apiMessage;
          }
        }
      }
      // 按 HTTP 状态码映射友好提示
      final statusCode = response?.statusCode;
      if (statusCode != null) {
        switch (statusCode) {
          case 400: return '请求参数错误';
          case 401: return '邮箱或密码错误';
          case 403: return '拒绝访问';
          case 404: return '请求的资源不存在';
          case 500: return '服务器内部错误，请稍后重试';
          case 502: return '服务器网关错误';
          case 503: return '服务器暂时不可用';
        }
      }
      // 网络层错误
      final type = error.type;
      switch (type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
          return '连接超时，请检查网络';
        case DioExceptionType.connectionError:
          final msg = error.message ?? '';
          if (msg.contains('Connection refused') || msg.contains('SocketException')) {
            return '无法连接到服务器，请检查服务器地址和网络';
          }
          return '网络连接失败，请检查网络';
        default:
          break;
      }
    }
    // 非 DioException 的兜底
    final msg = error.toString();
    if (msg.contains('HttpConnection closed') ||
        msg.contains('HandshakeException') ||
        msg.contains('TLS')) {
      return 'SSL/TLS 连接失败，请检查服务器地址或尝试使用 http://';
    }
    if (msg.contains('Connection reset')) {
      return '连接被重置，服务器可能不支持当前请求';
    }
    return error.toString().replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadSiteConfig();
              _fetchOssUrl();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已刷新'), duration: Duration(seconds: 1)),
              );
            },
          ),
        ],
      ),
      body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo / Title
                  Icon(
                    Icons.vpn_lock_rounded,
                    size: 72,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    appName,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isForgotPasswordMode ? '重置密码' : (_isRegisterMode ? '创建账户' : _siteDescription),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Server URL
                  if (FeatureFlags.showServerUrlInput)
                  TextFormField(
                    controller: _serverUrlController,
                    decoration: InputDecoration(
                      labelText: '服务器地址',
                      hintText: 'https://your-panel.com',
                      prefixIcon: const Icon(Icons.dns_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    keyboardType: TextInputType.url,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return '请输入服务器地址';
                      }
                      final trimmed = value.trim();
                      if (!trimmed.startsWith('http')) {
                        return '请输入有效的 URL（以 http:// 或 https:// 开头）';
                      }
                      return null;
                    },
                  ),
                  if (FeatureFlags.showServerUrlInput) const SizedBox(height: 12),

                  // API Path
                  if (FeatureFlags.showServerUrlInput)
                  TextFormField(
                    controller: _apiPathController,
                    decoration: InputDecoration(
                      labelText: 'API 接口路径',
                      hintText: '/api/v1',
                      prefixIcon: const Icon(Icons.api_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    keyboardType: TextInputType.text,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return '请输入 API 路径';
                      }
                      if (!value.trim().startsWith('/')) {
                        return 'API 路径必须以 / 开头';
                      }
                      return null;
                    },
                  ),
                  if (FeatureFlags.showServerUrlInput) const SizedBox(height: 12),

                  // Email
                  _isRegisterMode && _emailWhitelist.isNotEmpty
                  ? _buildEmailWithSuffix()
                  : TextFormField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        labelText: '邮箱',
                        hintText: '请输入邮件地址',
                        hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                        prefixIcon: const Icon(Icons.email_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return '请输入邮箱';
                        if (!value.contains('@')) return '请输入有效的邮箱地址';
                        return null;
                      },
                    ),
                  const SizedBox(height: 12),

                  // 忘记密码模式：验证码 + 新密码
                  if (_isForgotPasswordMode) ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _codeController,
                            decoration: InputDecoration(
                              labelText: '验证码',
                              prefixIcon: const Icon(Icons.pin_outlined),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          onPressed: _isLoading ? null : _handleSendCode,
                          style: ButtonStyle(
                            minimumSize: WidgetStateProperty.all(const Size(120, 56)),
                            shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          ),
                          child: Text(_codeSent ? '重新发送' : '发送验证码'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _resetPasswordController,
                      obscureText: _obscureResetPassword,
                      decoration: InputDecoration(
                        labelText: '新密码',
                        prefixIcon: const Icon(Icons.lock_outlined),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureResetPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                          onPressed: () => setState(() => _obscureResetPassword = !_obscureResetPassword),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _confirmResetPasswordController,
                      obscureText: _obscureConfirmResetPassword,
                      decoration: InputDecoration(
                        labelText: '确认密码',
                        prefixIcon: const Icon(Icons.lock_outlined),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureConfirmResetPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                          onPressed: () => setState(() => _obscureConfirmResetPassword = !_obscureConfirmResetPassword),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) return '请确认密码';
                        if (value != _resetPasswordController.text) return '两次密码不一致';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                  ] else
                  // Password
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: '密码',
                      hintText: '请输入密码',
                      hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                      prefixIcon: const Icon(Icons.lock_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () {
                          setState(() => _obscurePassword = !_obscurePassword);
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) return '请输入密码';
                      if (_isRegisterMode && value.length < 6) return '密码长度不能少于 6 位';
                      return null;
                    },
                    onFieldSubmitted: (_) => _isForgotPasswordMode ? _handleReset() : (_isRegisterMode ? _handleRegister() : _handleLogin()),
                  ),
                  const SizedBox(height: 12),

                  // 注册模式：确认密码 + 邀请码 + 服务条款
                  if (_isRegisterMode) ...[
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirmPassword,
                      decoration: InputDecoration(
                        labelText: '确认密码',
                        prefixIcon: const Icon(Icons.lock_outlined),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                          onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) return '请确认密码';
                        if (value != _passwordController.text) return '两次密码不一致';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _inviteCodeController,
                      decoration: InputDecoration(
                        labelText: '邀请码（选填）',
                        hintText: '如有邀请码请填写',
                        prefixIcon: const Icon(Icons.card_giftcard_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        SizedBox(
                          height: 48,
                          child: Checkbox(
                            value: _agreeTerms,
                            onChanged: (v) => setState(() => _agreeTerms = v ?? false),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _agreeTerms = !_agreeTerms),
                            child: RichText(
                              text: TextSpan(
                                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                                children: [
                                  const TextSpan(text: '我已阅读并同意 '),
                                  TextSpan(
                                    text: '服务条款',
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = () {
                                        final uri = Uri.tryParse(_tosUrl);
                                        if (uri != null) {
                                          launchUrl(uri, mode: LaunchMode.externalApplication);
                                        }
                                      },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  // Error message
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: colorScheme.error, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  const SizedBox(height: 4),

                  // Remember me (仅登录模式)
                  if (!_isRegisterMode && !_isForgotPasswordMode)
                    Row(
                      children: [
                        SizedBox(
                          height: 48,
                          child: Checkbox(
                            value: _rememberMe,
                            onChanged: (v) => setState(() => _rememberMe = v ?? true),
                          ),
                      ),
                      const Text('记住我（保存登录信息）'),
                    ],
                  ),

                  // Login / Register / Reset button
                  FilledButton(
                    onPressed: _isLoading
                        ? null
                        : (_isForgotPasswordMode
                            ? _handleReset
                            : (_isRegisterMode ? _handleRegister : _handleLogin)),
                    style: ButtonStyle(
                      minimumSize: WidgetStateProperty.all(const Size(double.infinity, 52)),
                      shape: WidgetStateProperty.all(
                        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _isForgotPasswordMode ? '重置密码' : (_isRegisterMode ? '创建账户' : '登录'),
                            style: const TextStyle(fontSize: 16),
                          ),
                  ),
                  const SizedBox(height: 8),

                  // 底部链接行
                  if (_isForgotPasswordMode)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _isForgotPasswordMode = false;
                              _errorMessage = null;
                            });
                          },
                          child: const Text('返回登录'),
                        ),
                      ],
                    )
                  else if (_isRegisterMode)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _isRegisterMode = false;
                              _errorMessage = null;
                            });
                          },
                          child: const Text('返回登录'),
                        ),
                      ],
                    )
                  else
                    Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextButton(
                              onPressed: () { setState(() { _isRegisterMode = true; _errorMessage = null; }); },
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.person_add_outlined, size: 16),
                                const SizedBox(width: 4),
                                const Text('创建账户'),
                              ]),
                            ),
                            TextButton(
                              onPressed: _handleForgotPassword,
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.lock_outline, size: 16),
                                const SizedBox(width: 4),
                                const Text('忘记密码'),
                              ]),
                            ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Divider(height: 1, thickness: 0.5),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton(
                              onPressed: () async {
                                final crispId = FeatureFlags.enableAppConfig ? AppConfig.crispId : null;
                                if (crispId == null || crispId.isEmpty) return;
                                final uri = Uri.parse(
                                  'https://go.crisp.chat/chat/embed/?website_id=$crispId',
                                );
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                                }
                              },
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.headphones_outlined, size: 14),
                                const SizedBox(width: 2),
                                const Text('联系客服', style: TextStyle(fontSize: 13)),
                              ]),
                            ),
                            SizedBox(height: 16, child: const VerticalDivider(width: 12, thickness: 1)),
                            TextButton(
                              onPressed: () async {
                                final url = _appUrl.isNotEmpty ? _appUrl : _serverUrlController.text.trim();
                                if (url.isNotEmpty) {
                                  final uri = Uri.parse(url);
                                  if (await canLaunchUrl(uri)) {
                                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                                  }
                                }
                              },
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.language_outlined, size: 14),
                                const SizedBox(width: 2),
                                const Text('访问官网', style: TextStyle(fontSize: 13)),
                              ]),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }
}
