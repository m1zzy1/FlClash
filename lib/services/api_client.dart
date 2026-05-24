import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/services/auth_service.dart';

class ApiClient {
  static ApiClient? _instance;
  late final Dio _dio;
  String? _authData;
  String? _token;
  String? _baseUrl;
  String _apiPath = '';

  ApiClient._internal() {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': browserUa,
        },
      ),
    );
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.badCertificateCallback = (_, _, _) => true;
        client.findProxy = (uri) => 'DIRECT';
        return client;
      },
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_authData != null) {
            options.headers['Authorization'] = _authData;
          }
          if (options.data is Map) {
            options.data = Map<String, dynamic>.from(options.data as Map);
          }
          handler.next(options);
        },
        onError: (error, handler) {
          if (error.response?.statusCode == 401) {
            authService.clearAuth();
          }
          handler.next(error);
        },
      ),
    );
  }

  factory ApiClient() {
    _instance ??= ApiClient._internal();
    return _instance!;
  }

  void configure({required String baseUrl, String? token, String apiPath = ''}) {
    _baseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    _apiPath = apiPath;
    while (_apiPath.startsWith('/')) {
      _apiPath = _apiPath.substring(1);
    }
    while (_apiPath.endsWith('/')) {
      _apiPath = _apiPath.substring(0, _apiPath.length - 1);
    }
    if (token != null) {
      _token = token;
    }
  }

  void setAuth({required String authData, String? token}) {
    _authData = authData;
    if (token != null) {
      _token = token;
    }
  }

  String? get token => _token;
  String? get authData => _authData;
  String? get baseUrl => _baseUrl;
  String get apiPath => _apiPath;

  String _buildUrl(String path) {
    final base = _baseUrl ?? '';
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    if (_apiPath.isEmpty) {
      return '$base/$cleanPath';
    }
    return '$base/$_apiPath/$cleanPath';
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    final url = _buildUrl(path);
    final response = await _dio.post(url, data: data);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final url = _buildUrl(path);
    final response = await _dio.get(url, queryParameters: queryParameters);
    return response.data as Map<String, dynamic>;
  }

  /// 下载原始字节数据（用于订阅等场景）
  Future<List<int>> downloadBytes(String url) async {
    final response = await _dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    return response.data ?? [];
  }

  /// 以表单格式发送 POST 请求（V2Board 某些接口需要）
  Future<Map<String, dynamic>> postForm(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    final url = _buildUrl(path);
    final formData = FormData.fromMap(data ?? {});
    final response = await _dio.post(url, data: formData, options: Options(
      contentType: 'application/x-www-form-urlencoded',
    ));
    return response.data as Map<String, dynamic>;
  }

  void clear() {
    _authData = null;
    _token = null;
    _baseUrl = null;
    _apiPath = '';
  }
}

final apiClient = ApiClient();
