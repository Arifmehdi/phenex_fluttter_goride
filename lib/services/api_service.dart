import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';
import 'package:get/get.dart' as g;

enum EnvType {
  production,
  localEmulator,
  localWifi,
  customNgrok,
}

class ApiService extends g.GetxController {
  // --- ENVIRONMENT CONFIGURATION ---
  // Change currentEnv to switch between local development and production.
  static const EnvType currentEnv = EnvType.production; 
  
  // Your computer's local network IP address (for testing on physical devices via Wi-Fi)
  static const String _localMachineIp = '192.168.68.102'; 
  
  // If sharing the API publicly with others via ngrok (e.g. 'https://xxx.ngrok-free.app')
  static const String _ngrokUrl = 'https://YOUR_NGROK_SUBDOMAIN.ngrok-free.app';

  static String get baseUrl {
    switch (currentEnv) {
      case EnvType.production:
        return 'https://qalamhr.islamibookbd.com/api/';
      case EnvType.localEmulator:
        // 10.0.2.2 maps to the computer's localhost inside Android Emulators.
        // Change path if running with php artisan serve (e.g. 'http://10.0.2.2:8000/api/')
        return 'http://10.0.2.2/goride/public/api/';
      case EnvType.localWifi:
        // Points to the computer's local IP on the network (for physical devices)
        return 'http://$_localMachineIp/goride/public/api/';
      case EnvType.customNgrok:
        return '$_ngrokUrl/api/';
    }
  }
  
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

  /// Expose the Dio instance for screens that need multipart requests.
  Dio get dio => _dio;

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
        // Store approval status
        await _storage.write('is_approved', response.data['is_approved'] ?? true);
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

  /// Persist updated user data locally after a profile save.
  Future<void> refreshUser(Map<String, dynamic> updated) async {
    final current = Map<String, dynamic>.from(_storage.read('user') ?? {});
    current.addAll(updated);
    await _storage.write('user', current);
  }

  String? getToken() {
    return _storage.read('token');
  }

  // Ride Related Methods
  Future<Response> createRideRequest(Map<String, dynamic> data) async {
    return await _dio.post('/ride-requests', data: data);
  }

  Future<Response> updateRideStatus(int id, String status) async {
    return await _dio.patch('/ride-requests/$id/status', data: {'status': status});
  }

  Future<void> updateFcmToken(String token) async {
    try {
      await _dio.post('/user/fcm-token', data: {'fcm_token': token});
    } catch (_) {}
  }

  Future<Response> cancelRide(int id, {required String reason, String cancelledBy = 'rider'}) async {
    try {
      return await _dio.patch('/ride-requests/$id/status', data: {
        'status': 'cancelled',
        'cancellation_reason': reason,
        'cancelled_by': cancelledBy,
      });
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500);
    }
  }

  Future<Response> updateLocation(double lat, double lng) async {
    try {
      debugPrint('Syncing location to Laravel: $lat, $lng');
      final response = await _dio.post('/update-location', data: {
        'latitude': lat,
        'longitude': lng,
      });
      debugPrint('Laravel sync response: ${response.statusCode} ${response.data}');
      return response;
    } catch (e) {
      debugPrint('Laravel sync error: $e');
      rethrow;
    }
  }

  Future<Response> getNearbyDrivers(double lat, double lng, {double radius = 5}) async {
    return await _dio.get('/nearby-drivers', queryParameters: {
      'latitude': lat,
      'longitude': lng,
      'radius': radius,
    });
  }

  Future<Response> getActiveRide() async {
    return await _dio.get('/active-ride');
  }

  // ── Profile Completion ──

  Future<Response> getProfileCompletion() async {
    try {
      final response = await _dio.get('/user/profile-completion');
      return response;
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500, statusMessage: 'Unknown Error');
    }
  }

  Future<Response> completeProfile(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('/user/complete-profile', data: data);
      // Update stored user data
      if (response.data is Map && response.data['user'] != null) {
        await _storage.write('user', response.data['user']);
      }
      return response;
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500, statusMessage: 'Unknown Error');
    }
  }

  // ── Password Reset ──

  Future<Response> forgotPassword(String email) async {
    try {
      final response = await _dio.post('/forgot-password', data: {
        'email': email,
      });
      return response;
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500, statusMessage: 'Unknown Error');
    }
  }

  Future<Response> resetPassword({
    required String email,
    required String token,
    required String password,
    required String passwordConfirmation,
  }) async {
    try {
      final response = await _dio.post('/reset-password', data: {
        'email': email,
        'token': token,
        'password': password,
        'password_confirmation': passwordConfirmation,
      });
      return response;
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500, statusMessage: 'Unknown Error');
    }
  }

  /// Change password for authenticated user
  Future<Response> changePassword({
    required String currentPassword,
    required String password,
    required String passwordConfirmation,
  }) async {
    try {
      final response = await _dio.patch('/user/password', data: {
        'current_password': currentPassword,
        'password': password,
        'password_confirmation': passwordConfirmation,
      });
      return response;
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500, statusMessage: 'Unknown Error');
    }
  }

  // ── Saved Addresses ──

  Future<Response> getSavedAddresses() async {
    try {
      final response = await _dio.get('/user/saved-addresses');
      return response;
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500, statusMessage: 'Unknown Error');
    }
  }

  Future<Response> createSavedAddress(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('/user/saved-addresses', data: data);
      return response;
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500, statusMessage: 'Unknown Error');
    }
  }

  Future<Response> updateSavedAddress(int id, Map<String, dynamic> data) async {
    try {
      final response = await _dio.put('/user/saved-addresses/$id', data: data);
      return response;
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500, statusMessage: 'Unknown Error');
    }
  }

  Future<Response> deleteSavedAddress(int id) async {
    try {
      final response = await _dio.delete('/user/saved-addresses/$id');
      return response;
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500, statusMessage: 'Unknown Error');
    }
  }

  /// Fetches website parameters including per_km_rate for fare calculation
  Future<Response> getWebsiteParameters() async {
    try {
      final response = await _dio.get('/website-parameters');
      return response;
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500, statusMessage: 'Unknown Error');
    }
  }

  // ── Driver Ratings ──

  /// Submit a rating for a driver after a completed trip
  Future<Response> rateDriver({
    required int rideRequestId,
    required int driverId,
    required int rating,
    String? review,
  }) async {
    try {
      final Map<String, dynamic> data = {
        'ride_request_id': rideRequestId,
        'driver_id': driverId,
        'rating': rating,
      };
      if (review != null && review.isNotEmpty) {
        data['review'] = review;
      }
      final response = await _dio.post('/driver-ratings', data: data);
      return response;
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500, statusMessage: 'Unknown Error');
    }
  }

  /// Check if user has already rated a specific ride
  Future<Response> checkDriverRating(int rideRequestId) async {
    try {
      final response = await _dio.get('/driver-ratings/check/$rideRequestId');
      return response;
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500, statusMessage: 'Unknown Error');
    }
  }

  // ── Ride Matching & History ──

  /// Match nearby drivers and create ride offers
  Future<Response> matchDrivers({required int rideRequestId}) async {
    try {
      final response = await _dio.post('/ride-requests/match', data: {
        'ride_request_id': rideRequestId,
      });
      return response;
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500, statusMessage: 'Unknown Error');
    }
  }

  /// Respond to a ride offer (accept or decline)
  Future<Response> respondToRideOffer({
    required int offerId,
    required String response,
    required int driverId,
  }) async {
    try {
      final data = {
        'response': response,
        'driver_id': driverId,
      };
      final apiResponse = await _dio.post('/ride-offers/$offerId/respond', data: data);
      return apiResponse;
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500, statusMessage: 'Unknown Error');
    }
  }

  /// Get ride history for the current user
  Future<Response> getRideHistory({String? status, int perPage = 20}) async {
    try {
      final queryParams = <String, dynamic>{'per_page': perPage};
      if (status != null && status.isNotEmpty) {
        queryParams['status'] = status;
      }
      final response = await _dio.get('/ride-history', queryParameters: queryParams);
      return response;
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500, statusMessage: 'Unknown Error');
    }
  }

  /// Get detailed info for a specific ride
  Future<Response> getRideDetail(int rideId) async {
    try {
      final response = await _dio.get('/ride-requests/$rideId/detail');
      return response;
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500, statusMessage: 'Unknown Error');
    }
  }

  /// Get all ride offers for a specific ride
  Future<Response> getRideOffers(int rideRequestId) async {
    try {
      final response = await _dio.get('/ride-requests/$rideRequestId/offers');
      return response;
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500, statusMessage: 'Unknown Error');
    }
  }

  /// Update ride payment info after trip completes
  Future<Response> updateRidePayment(int rideId, Map<String, dynamic> paymentData) async {
    try {
      final response = await _dio.post('/ride-requests/$rideId/payment', data: paymentData);
      return response;
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500, statusMessage: 'Unknown Error');
    }
  }

  /// Toggle driver online/offline status
  Future<Response> toggleDriverOnline(bool isOnline) async {
    try {
      final response = await _dio.post('/driver/toggle-online', data: {
        'is_online': isOnline,
      });
      return response;
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500, statusMessage: 'Unknown Error');
    }
  }

  // ── Chat API Methods ──

  Future<Response> getConversations({int perPage = 20}) async {
    try {
      final response = await _dio.get('/chat/conversations', queryParameters: {'per_page': perPage});
      return response;
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500, statusMessage: 'Unknown Error');
    }
  }

  Future<Response> createConversation({
    required String type,
    required List<int> participants,
    String? title,
  }) async {
    try {
      final response = await _dio.post('/chat/conversations', data: {
        'type': type,
        'participants': participants,
        if (title != null) 'title': title,
      });
      return response;
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500, statusMessage: 'Unknown Error');
    }
  }

  Future<Response> getConversation(int conversationId) async {
    try {
      final response = await _dio.get('/chat/conversations/$conversationId');
      return response;
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500, statusMessage: 'Unknown Error');
    }
  }

  Future<Response> getMessages(int conversationId, {int perPage = 50}) async {
    try {
      final response = await _dio.get('/chat/conversations/$conversationId/messages', queryParameters: {'per_page': perPage});
      return response;
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500, statusMessage: 'Unknown Error');
    }
  }

  Future<Response> sendMessage({
    required int conversationId,
    required String messageType,
    String? message,
    String? fileUrl,
    String? thumbnailUrl,
  }) async {
    try {
      final data = <String, dynamic>{
        'message_type': messageType,
      };
      if (message != null) data['message'] = message;
      if (fileUrl != null) data['file_url'] = fileUrl;
      if (thumbnailUrl != null) data['thumbnail_url'] = thumbnailUrl;
      final response = await _dio.post('/chat/send', data: {
        'conversation_id': conversationId,
        ...data,
      });
      return response;
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500, statusMessage: 'Unknown Error');
    }
  }

  Future<Response> sendMultipartMessage({
    required int conversationId,
    required String messageType,
    String? message,
    String? filePath,
  }) async {
    try {
      final formData = FormData.fromMap({
        'conversation_id': conversationId,
        'message_type': messageType,
        if (message != null) 'message': message,
        if (filePath != null) 'file': await MultipartFile.fromFile(filePath),
      });
      final response = await _dio.post('/chat/conversations/$conversationId/messages', data: formData);
      return response;
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500, statusMessage: 'Unknown Error');
    }
  }

  Future<Response> getNewMessages(int conversationId, {int? afterId}) async {
    try {
      final params = <String, dynamic>{'conversation_id': conversationId};
      if (afterId != null) params['after_id'] = afterId;
      final response = await _dio.get('/chat/messages', queryParameters: params);
      return response;
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500, statusMessage: 'Unknown Error');
    }
  }

  Future<Response> markMessagesRead(int conversationId) async {
    try {
      final response = await _dio.post('/chat/read', data: {'conversation_id': conversationId});
      return response;
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500, statusMessage: 'Unknown Error');
    }
  }

  Future<Response> searchChatUsers(String query) async {
    try {
      final response = await _dio.get('/chat/users/search', queryParameters: {'search': query});
      return response;
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500, statusMessage: 'Unknown Error');
    }
  }

  Future<Response> getOrCreatePrivateChat(int otherUserId) async {
    try {
      final response = await _dio.get('/chat/users/$otherUserId/conversation');
      return response;
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500, statusMessage: 'Unknown Error');
    }
  }

  Future<Response> deleteMessage(int messageId) async {
    try {
      final response = await _dio.delete('/chat/messages/$messageId');
      return response;
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500, statusMessage: 'Unknown Error');
    }
  }

  Future<Response> addParticipant(int conversationId, int userId) async {
    try {
      final response = await _dio.post('/chat/conversations/$conversationId/add-participant', data: {'user_id': userId});
      return response;
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500, statusMessage: 'Unknown Error');
    }
  }

  Future<Response> removeParticipant(int conversationId, int userId) async {
    try {
      final response = await _dio.delete('/chat/conversations/$conversationId/remove-participant/$userId');
      return response;
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500, statusMessage: 'Unknown Error');
    }
  }

  // ── Phase 2 API Methods ──

  Future<Response> getBanners() async {
    try { return await _dio.get('/banners'); }
    on DioException catch (e) { return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500); }
  }

  Future<Response> validatePromo(String code, double fare) async {
    try { return await _dio.post('/promo/validate', data: {'code': code, 'fare': fare}); }
    on DioException catch (e) { return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500); }
  }

  Future<Response> getWalletBalance() async {
    try { return await _dio.get('/wallet/balance'); }
    on DioException catch (e) { return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500); }
  }

  Future<Response> getWalletTransactions() async {
    try { return await _dio.get('/wallet/transactions'); }
    on DioException catch (e) { return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500); }
  }

  Future<Response> topUpWallet(double amount) async {
    try { return await _dio.post('/wallet/top-up', data: {'amount': amount}); }
    on DioException catch (e) { return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500); }
  }

  Future<Response> payRideWithWallet(int rideId, double amount) async {
    try { return await _dio.post('/ride-requests/$rideId/pay-wallet', data: {'amount': amount}); }
    on DioException catch (e) { return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500); }
  }

  Future<Response> getDriverEarnings(String period) async {
    try { return await _dio.get('/driver/earnings', queryParameters: {'period': period}); }
    on DioException catch (e) { return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500); }
  }

  Future<Response> submitRiderRating({
    required int rideRequestId,
    required int riderId,
    required int rating,
    List<String>? tags,
    String? review,
  }) async {
    try {
      return await _dio.post('/rider-ratings', data: {
        'ride_request_id': rideRequestId,
        'rider_id': riderId,
        'rating': rating,
        if (tags != null) 'tags': tags,
        if (review != null) 'review': review,
      });
    } on DioException catch (e) { return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500); }
  }

  // ── Phase 3 API Methods ──

  // ── Phase 6: Safety ──
  Future<Response> triggerSos({int? rideRequestId, double? lat, double? lng}) async {
    try {
      return await _dio.post('/sos/trigger', data: {
        if (rideRequestId != null) 'ride_request_id': rideRequestId,
        if (lat != null) 'latitude': lat,
        if (lng != null) 'longitude': lng,
      });
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500);
    }
  }

  Future<Response> generateTrackingToken(int rideId) async {
    try { return await _dio.post('/ride-requests/$rideId/tracking-token'); }
    on DioException catch (e) { return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500); }
  }

  Future<Response> uploadDriverDocument(String documentType, String filePath) async {
    try {
      final formData = FormData.fromMap({
        'document_type': documentType,
        'file': await MultipartFile.fromFile(filePath, filename: filePath.split('/').last),
      });
      return await _dio.post('/driver/upload-document', data: formData);
    } on DioException catch (e) {
      return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500);
    }
  }

  Future<Response> getMyDocuments() async {
    try { return await _dio.get('/driver/my-documents'); }
    on DioException catch (e) { return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500); }
  }

  Future<Response> getDriverStats() async {
    try { return await _dio.get('/driver/stats'); }
    on DioException catch (e) { return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500); }
  }

  Future<Response> sendOtp(String mobile, {String purpose = 'registration'}) async {
    try { return await _dio.post('/auth/send-otp', data: {'mobile': mobile, 'purpose': purpose}); }
    on DioException catch (e) { return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500); }
  }

  Future<Response> verifyOtp(String mobile, String otp, {String purpose = 'registration'}) async {
    try { return await _dio.post('/auth/verify-otp', data: {'mobile': mobile, 'otp': otp, 'purpose': purpose}); }
    on DioException catch (e) { return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500); }
  }

  Future<Response> getNotifications() async {
    try { return await _dio.get('/notifications'); }
    on DioException catch (e) { return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500); }
  }

  Future<Response> markNotificationRead(int id) async {
    try { return await _dio.post('/notifications/read/$id'); }
    on DioException catch (e) { return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500); }
  }

  Future<Response> markAllNotificationsRead() async {
    try { return await _dio.post('/notifications/read-all'); }
    on DioException catch (e) { return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500); }
  }

  Future<Response> submitDriverRatingWithTags({
    required int rideRequestId,
    required int driverId,
    required int rating,
    List<String>? tags,
    String? review,
  }) async {
    try {
      return await _dio.post('/driver-ratings', data: {
        'ride_request_id': rideRequestId,
        'driver_id': driverId,
        'rating': rating,
        if (tags != null) 'tags': tags,
        if (review != null) 'review': review,
      });
    } on DioException catch (e) { return e.response ?? Response(requestOptions: RequestOptions(path: ''), statusCode: 500); }
  }
}
