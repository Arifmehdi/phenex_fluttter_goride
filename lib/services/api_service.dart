import 'package:dio/dio.dart';
import 'package:get_storage/get_storage.dart';
import 'package:get/get.dart' as g;

class ApiService extends g.GetxController {
  static const String baseUrl = 'https://goride.musafirinternational.com/public/api/';
  
  final Dio _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
    followRedirects: false,
    validateStatus: (status) {
      return status != null && status < 500;
    },
  ));

  final GetStorage _storage = GetStorage();
  
  final _isLoggedIn = false.obs;
  bool get isLoggedInState => _isLoggedIn.value;

  ApiService() {
    _isLoggedIn.value = _storage.hasData('token');
    
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = _storage.read('token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (DioException e, handler) {
        if (e.response?.statusCode == 401) {
          // Token expired or invalid
          logout();
        }
        return handler.next(e);
      },
    ));
  }

  Future<Response> login(String login, String password) async {
    try {
      final response = await _dio.post('/login', data: {
        'login': login,
        'password': password,
      });
      
      if (response.statusCode == 200) {
        await _storage.write('token', response.data['token']);
        await _storage.write('user', response.data['user']);
        _isLoggedIn.value = true;
      }
      
      return response;
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500, statusMessage: 'Unknown Error');
    }
  }

  Future<Response> register(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('/register', data: data);

      // Handle successful registration
      // The API may return HTML redirect (302 followed) or JSON
      if (response.statusCode == 200 || response.statusCode == 201) {
        // If response is JSON with token (API login after registration)
        if (response.data is Map && response.data['token'] != null) {
          await _storage.write('token', response.data['token']);
          await _storage.write('user', response.data['user']);
          _isLoggedIn.value = true;
        }
        // If API returns user data without token, save user info
        else if (response.data is Map && response.data['user'] != null) {
          await _storage.write('user', response.data['user']);
        }
        // If response is HTML (redirect), registration was successful
        // The server redirects on success, so treat as success
        else if (response.data is String) {
          // Registration likely succeeded (server redirected)
          // We can try to login with the provided credentials
          _isLoggedIn.value = false;
        }
      }

      return response;
    } on DioException catch (e) {
      // If registration actually succeeded but server returned non-JSON response
      if (e.response != null &&
          (e.response!.statusCode == 200 || e.response!.statusCode == 302)) {
        // Treat as success - registration likely completed
        return e.response!;
      }
      return e.response ??
          Response(
              requestOptions: RequestOptions(path: ''),
              statusCode: 500,
              statusMessage: 'Unknown Error');
    }
  }

  Future<void> logout() async {
    try {
      if (isLoggedIn()) {
        await _dio.post('/logout');
      }
    } catch (e) {
      // Ignore errors on logout
    } finally {
      await _storage.remove('token');
      await _storage.remove('user');
      _isLoggedIn.value = false;
    }
  }

  bool isLoggedIn() {
    return _storage.hasData('token');
  }

  Map<String, dynamic>? getUser() {
    return _storage.read('user');
  }

  String? getToken() {
    return _storage.read('token');
  }
}
