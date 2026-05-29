import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fl_clash/common/app_config.dart';
import 'package:fl_clash/common/feature_flags.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/manager/hotkey_manager.dart';
import 'package:fl_clash/manager/manager.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/services/api_client.dart';
import 'package:fl_clash/services/auth_service.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'controller.dart';
import 'pages/pages.dart';

class Application extends ConsumerStatefulWidget {
  const Application({super.key});

  @override
  ConsumerState<Application> createState() => ApplicationState();
}

class ApplicationState extends ConsumerState<Application> {
  Timer? _autoUpdateProfilesTaskTimer;
  Timer? _subscribePollingTimer;
  String? _lastSubscribeHash;
  int? _lastExpireAt;
  bool _preHasVpn = false;
  bool _isAuthChecked = false;
  bool _isAuthenticated = false;

  final _pageTransitionsTheme = const PageTransitionsTheme(
    builders: <TargetPlatform, PageTransitionsBuilder>{
      TargetPlatform.android: commonSharedXPageTransitions,
      TargetPlatform.windows: commonSharedXPageTransitions,
      TargetPlatform.linux: commonSharedXPageTransitions,
      TargetPlatform.macOS: commonSharedXPageTransitions,
    },
  );

  ColorScheme _getAppColorScheme({
    required Brightness brightness,
    int? primaryColor,
  }) {
    return ref.read(genColorSchemeProvider(brightness));
  }

  @override
  void initState() {
    super.initState();
    _checkAuth();
    // 注册强制退出登录回调
    AuthService.onForceLogout = () {
      _forceLogout();
    };
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) async {
      final currentContext = globalState.navigatorKey.currentContext;
      if (currentContext != null) {
        await appController.attach(currentContext, ref);
      } else {
        exit(0);
      }
      _autoUpdateProfilesTask();
      _startSubscribePolling();
      appController.initLink();
      app?.initShortcuts();
    });
  }

  Future<void> _checkAuth() async {
    final isAuthed = await authService.tryRestoreSession();
    if (mounted) {
      setState(() {
        _isAuthChecked = true;
        _isAuthenticated = isAuthed;
      });
    }
    if (isAuthed) {
      // 检测当前服务器地址是否可用，不可用则从 OSS 拉取新地址
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _checkAndRefreshServerUrl();
      });
      _autoSyncSubscribeOnStart();
    }
  }

  /// 账号被封禁/删除/Token 失效时强制退出登录
  void _forceLogout() {
    _autoUpdateProfilesTaskTimer?.cancel();
    _subscribePollingTimer?.cancel();
    _lastSubscribeHash = null;
    _lastExpireAt = null;
    if (mounted) {
      setState(() {
        _isAuthenticated = false;
        _isAuthChecked = true;
      });
      globalState.navigatorKey.currentState
          ?.pushNamedAndRemoveUntil('/login', (_) => false);
    }
  }

  /// 检测当前服务器地址是否可用，不可用则从 OSS 刷新
  Future<void> _checkAndRefreshServerUrl() async {
    final baseUrl = apiClient.baseUrl;
    if (baseUrl == null) return;

    final isAvailable = await _testServerUrl(baseUrl);
    if (isAvailable) return;

    // 当前地址不可用，从 OSS 拉取新地址
    final newUrl = await _fetchOssUrl();
    if (newUrl != null) {
      apiClient.configure(baseUrl: newUrl, apiPath: '/api/v1');
      _autoSyncSubscribeOnStart();
    }
  }

  /// 测试服务器地址是否可用
  Future<bool> _testServerUrl(String url) async {
    try {
      final testUrl =
          '${url.endsWith('/') ? url.substring(0, url.length - 1) : url}/api/v1/guest/comm/config';
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
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 从 OSS 获取可用服务器地址
  Future<String?> _fetchOssUrl() async {
    if (!FeatureFlags.enableAppConfig) return null;
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
    if (urls.isEmpty) return null;

    for (final url in urls) {
      final isOk = await _testServerUrl(url);
      if (isOk) return url;
    }
    return null;
  }

  Future<void> _autoSyncSubscribeOnStart() async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await appController.syncSubscriptionNow();
      } catch (_) {}
    });
  }

  void _autoUpdateProfilesTask() {
    _autoUpdateProfilesTaskTimer = Timer(const Duration(minutes: 20), () async {
      await appController.autoUpdateProfiles();
      _autoUpdateProfilesTask();
    });
  }

  /// 每 30 秒检测订阅内容是否变化
  void _startSubscribePolling() {
    if (!_isAuthenticated) return;
    _subscribePollingTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkSubscribeChanges(),
    );
  }

  Future<void> _checkSubscribeChanges() async {
    try {
      final url = await authService.fetchSubscribeUrl();
      if (url == null) return;

      // 用 HEAD 请求检测订阅是否变化（只拿响应头，不下载正文）
      bool headFailed = false;
      String? currentId;
      try {
        final dio = Dio();
        if (url.startsWith('https')) {
          dio.httpClientAdapter = IOHttpClientAdapter(
            createHttpClient: () {
              final client = HttpClient();
              client.badCertificateCallback = (_, _, _) => true;
              return client;
            },
          );
        }
        final headRes = await dio.head(url,
            options: Options(
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 5),
              headers: {'User-Agent': browserUa, 'Cache-Control': 'no-cache'},
            ));
        final contentLength = headRes.headers.value('content-length');
        final etag = headRes.headers.value('etag');
        currentId = etag ?? contentLength;
      } catch (_) {
        headFailed = true;
      }

      // 没有 HEAD 标识时，通过 /user/info 检测套餐变化
      if (currentId == null) {
        try {
          final info = await apiClient.get('/user/info');
          final data = info['data'] as Map<String, dynamic>? ?? info;
          final planId = data['plan_id'];
          // 没有套餐 → 跳过
          if (planId == null || planId == 0) return;
          // 有套餐时生成临时标识，强制触发一次更新
          currentId = DateTime.now().millisecondsSinceEpoch.toString();
        } catch (_) {
          return;
        }
      }

      // 检测到期时间变化（覆盖续费后 Content-Length/ETag 不变的场景）
      try {
        final info = await apiClient.get('/user/info');
        final data = info['data'] as Map<String, dynamic>? ?? info;
        final expireAt = data['expired_at'] as int?;
        if (expireAt != null && _lastExpireAt != null && _lastExpireAt != expireAt) {
          _lastExpireAt = expireAt;
          _lastSubscribeHash = null;
        } else if (expireAt != null) {
          _lastExpireAt ??= expireAt;
        }
      } catch (_) {}
      if (_lastSubscribeHash != null && _lastSubscribeHash == currentId) return;
      _lastSubscribeHash = currentId;

      final currentProfile = appController.currentProfile;
      if (currentProfile != null) {
        await appController.updateProfile(currentProfile.copyWith(url: url));
      } else {
        await appController.addProfileFormURL(url);
      }
    } catch (_) {}
  }

  Widget _buildPlatformState({required Widget child}) {
    if (system.isDesktop) {
      return WindowManager(
        child: TrayManager(
          child: HotKeyManager(child: ProxyManager(child: child)),
        ),
      );
    }
    return AndroidManager(child: TileManager(child: child));
  }

  Widget _buildState({required Widget child}) {
    return AppStateManager(
      child: CoreManager(
        child: ConnectivityManager(
          onConnectivityChanged: (results) async {
            commonPrint.log('connectivityChanged ${results.toString()}');
            appController.updateLocalIp();
            final hasVpn = results.contains(ConnectivityResult.vpn);
            if (_preHasVpn == hasVpn) {
              appController.addCheckIp();
            }
            _preHasVpn = hasVpn;
          },
          child: child,
        ),
      ),
    );
  }

  Widget _buildPlatformApp({required Widget child}) {
    if (system.isDesktop) {
      return WindowHeaderContainer(child: child);
    }
    return VpnManager(child: child);
  }

  Widget _buildApp({required Widget child}) {
    return StatusManager(child: ThemeManager(child: child));
  }

  @override
  Widget build(context) {
    return Consumer(
      builder: (_, ref, child) {
        final locale = ref.watch(
          appSettingProvider.select((state) => state.locale),
        );
        final themeProps = ref.watch(themeSettingProvider);
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorKey: globalState.navigatorKey,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          builder: (_, child) {
            return AppEnvManager(
              child: _buildApp(
                child: _buildPlatformState(
                  child: _buildState(child: _buildPlatformApp(child: child!)),
                ),
              ),
            );
          },
          scrollBehavior: BaseScrollBehavior(),
          title: appName,
          locale: utils.getLocaleForString(locale),
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          themeMode: themeProps.themeMode,
          theme: ThemeData(
            useMaterial3: true,
            pageTransitionsTheme: _pageTransitionsTheme,
            colorScheme: _getAppColorScheme(
              brightness: Brightness.light,
              primaryColor: themeProps.primaryColor,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            pageTransitionsTheme: _pageTransitionsTheme,
            colorScheme: _getAppColorScheme(
              brightness: Brightness.dark,
              primaryColor: themeProps.primaryColor,
            ).toPureBlack(themeProps.pureBlack),
          ),
          home: _isAuthChecked && !_isAuthenticated
              ? const LoginPage()
              : child!,
          routes: {
            '/login': (_) => const LoginPage(),
            '/home': (_) => const HomePage(),
          },
        );
      },
      child: const HomePage(),
    );
  }

  @override
  Future<void> dispose() async {
    AuthService.onForceLogout = null;
    linkManager.destroy();
    _autoUpdateProfilesTaskTimer?.cancel();
    _subscribePollingTimer?.cancel();
    await coreController.destroy();
    await appController.handleExit();
    super.dispose();
  }
}
