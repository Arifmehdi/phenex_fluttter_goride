import 'package:dio/dio.dart';
import 'package:get_storage/get_storage.dart';
import 'package:get/get.dart' as g;

class ApiService extends g.GetxController {
  static const String baseUrl = 'https://gorides.musafirinternational.com/api/';
  
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

  Future<Response> login(String login, String password, {String? role}) async {
    try {
      final data = {
        'login': login,
        'password': password,
      };
      if (role != null) {
        data['role'] = role;
      }
      
      final response = await _dio.post('/login', data: data);
      
      if (response.statusCode == 200) {
        await _storage.write('token', response.data['token']);
        await _storage.write('user', response.data['user']);
        // Store the role if returned by API
        if (response.data['role'] != null) {
          await _storage.write('role', response.data['role']);
        }
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
      if (response.statusCode == 200 || response.statusCode == 201) {
        if (response.data is Map) {
          if (response.data['token'] != null) {
            await _storage.write('token', response.data['token']);
            _isLoggedIn.value = true;
          }
          if (response.data['user'] != null) {
            await _storage.write('user', response.data['user']);
            // If role is inside user object
            if (response.data['user']['role'] != null) {
              await _storage.write('role', response.data['user']['role']);
            }
          }
          // If role is at top level (like in login.txt)
          if (response.data['role'] != null) {
            await _storage.write('role', response.data['role']);
          }
        }
      }

      return response;
    } on DioException catch (e) {
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
