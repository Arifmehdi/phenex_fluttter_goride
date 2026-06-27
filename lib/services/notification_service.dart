import 'dart:typed_data';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:goride/services/api_service.dart';

/// Background FCM handler — must be a top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('FCM background: ${message.notification?.title}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  bool _initialized = false;

  static const int _rideRequestNotificationId = 1001;
  static const int _rideStatusNotificationId = 1002;

  final Set<String> _activeRequestIds = {};

  Future<void> init() async {
    if (_initialized) return;

    // 1. Register background handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 2. Request permission
    await _fcm.requestPermission(alert: true, badge: true, sound: true);

    // 3. Init local notifications
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // 4. Create channels
    const AndroidNotificationChannel rideChannel = AndroidNotificationChannel(
      'ride_requests_channel', 'Ride Requests',
      description: 'New ride request alerts',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    const AndroidNotificationChannel statusChannel = AndroidNotificationChannel(
      'ride_status_channel', 'Ride Status',
      description: 'Ride status updates',
      importance: Importance.high,
    );
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(rideChannel);
    await androidPlugin?.createNotificationChannel(statusChannel);
    await androidPlugin?.requestNotificationsPermission();

    // 5. Foreground FCM → show local notification
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // 6. App opened from notification tap
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    _initialized = true;

    // 7. Upload FCM token to backend
    await _uploadFcmToken();
    _fcm.onTokenRefresh.listen((_) => _uploadFcmToken());
  }

  Future<void> _uploadFcmToken() async {
    try {
      final token = await _fcm.getToken();
      if (token != null) {
        final api = Get.find<ApiService>();
        if (api.isLoggedInState) {
          await api.updateFcmToken(token);
          debugPrint('FCM token uploaded: ${token.substring(0, 20)}...');
        }
      }
    } catch (e) {
      debugPrint('FCM token upload error: $e');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final data = message.data;
    final type = data['type'] ?? '';

    if (type == 'ride_request') {
      showRideRequestNotification(
        requestId: data['request_id'] ?? '',
        riderName: data['rider_name'] ?? 'Passenger',
        pickupAddress: data['pickup'] ?? '',
        destinationAddress: data['destination'] ?? '',
        fare: data['fare'] ?? '0',
      );
    } else {
      // Generic status notification
      _showStatusNotification(
        title: message.notification?.title ?? 'GoRide',
        body: message.notification?.body ?? '',
      );
    }
  }

  void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint('Notification tapped: ${message.data}');
    // Navigate based on type — extend as needed
  }

  void _onNotificationTap(NotificationResponse response) {
    debugPrint('Local notification tapped: ${response.payload}');
  }

  Future<void> showRideRequestNotification({
    required String requestId,
    required String riderName,
    required String pickupAddress,
    required String destinationAddress,
    required String fare,
  }) async {
    if (_activeRequestIds.contains(requestId)) return;
    _activeRequestIds.add(requestId);

    final vibrationPattern = Int64List.fromList([500, 500, 500, 500, 500, 1000, 500, 500]);

    final androidDetails = AndroidNotificationDetails(
      'ride_requests_channel', 'Ride Requests',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: vibrationPattern,
      category: AndroidNotificationCategory.call,
      visibility: NotificationVisibility.public,
      fullScreenIntent: true,
      autoCancel: false,
    );

    await _plugin.show(
      id: _rideRequestNotificationId,
      title: '🚗 New Ride Request!',
      body: '$riderName • $pickupAddress → $destinationAddress • ৳$fare',
      notificationDetails: NotificationDetails(android: androidDetails),
      payload: 'ride_request:$requestId',
    );
  }

  Future<void> _showStatusNotification({required String title, required String body}) async {
    const androidDetails = AndroidNotificationDetails(
      'ride_status_channel', 'Ride Status',
      importance: Importance.high,
      priority: Priority.high,
    );
    await _plugin.show(
      id: _rideStatusNotificationId,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(android: androidDetails),
    );
  }

  Future<void> cancelRideRequestNotification() async {
    await _plugin.cancel(id: _rideRequestNotificationId);
  }

  Future<void> dismissRequest(String requestId) async {
    _activeRequestIds.remove(requestId);
    if (_activeRequestIds.isEmpty) await cancelRideRequestNotification();
  }

  bool isRequestActive(String requestId) => _activeRequestIds.contains(requestId);

  /// No-op: permissions are requested inside init() via FCM.
  /// Kept for backwards compatibility with main.dart.
  Future<void> requestPermission() async {}

  Future<void> cancelAll() async {
    _activeRequestIds.clear();
    await _plugin.cancelAll();
  }
}
