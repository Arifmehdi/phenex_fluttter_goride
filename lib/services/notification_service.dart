import 'dart:typed_data';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:goride/services/api_service.dart';
import 'package:goride/pages/ride_request_call_screen.dart';

/// Background / terminated FCM handler — MUST be a top-level function.
/// For a ride request it shows a full-screen "incoming call" notification
/// so the driver's phone rings even when the app is closed.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // This runs in a separate background isolate with no Firebase context, so
  // initialize it here (safe to call if already initialized) before doing
  // anything Firebase-related.
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Already initialized in this isolate — ignore.
  }

  final data = message.data;
  final type = data['type'] ?? '';

  // Another driver took the ride → cancel the ringing notification.
  if (type == 'ride_taken') {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.cancel(id: 1001);
    return;
  }

  if (type != 'ride_request') return;

  // Respect the driver's online/offline choice — never ring when offline.
  await GetStorage.init();
  if (GetStorage().read('driver_online') != true) return;

  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(settings: const InitializationSettings(android: androidInit));

  // Ensure the channel exists in this isolate too
  const channel = AndroidNotificationChannel(
    'ride_requests_channel', 'Ride Requests',
    description: 'New ride request alerts',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );
  await plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  final vibration = Int64List.fromList([0, 500, 500, 500, 500, 1000, 500, 500]);
  final details = AndroidNotificationDetails(
    'ride_requests_channel', 'Ride Requests',
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.call,
    fullScreenIntent: true, // shows on the lock screen like an incoming call
    visibility: NotificationVisibility.public,
    playSound: true,
    enableVibration: true,
    vibrationPattern: vibration,
    ongoing: true,
    autoCancel: false,
    timeoutAfter: 45000,
  );

  await plugin.show(
    id: 1001,
    title: '🚗 New Ride Request',
    body: '${data['rider_name'] ?? 'Passenger'} • ${data['pickup'] ?? ''} → ${data['destination'] ?? ''} • ৳${data['fare'] ?? '0'}',
    notificationDetails: NotificationDetails(android: details),
    payload: 'ride_request',
  );
}

/// Builds and opens the full-screen incoming call from an FCM data map.
/// Used for foreground messages and when the app is opened from the notification.
void openRideCallFromData(Map<String, dynamic> data) {
  if ((data['type'] ?? '') != 'ride_request') return;

  // Never ring/track when the driver is offline.
  if (GetStorage().read('driver_online') != true) return;

  final requestId = data['request_id']?.toString() ?? data['ride_request_id']?.toString() ?? '';
  if (requestId.isEmpty) return;

  // Dedup — don't open twice for the same request
  if (NotificationService.shownCallRequestIds.contains(requestId)) return;
  NotificationService.shownCallRequestIds.add(requestId);

  double d(String k) => double.tryParse(data[k]?.toString() ?? '') ?? 0.0;

  Get.to(() => RideRequestCallScreen(
        requestId: requestId,
        riderName: data['rider_name']?.toString() ?? 'Passenger',
        pickupAddress: data['pickup']?.toString() ?? '',
        destinationAddress: data['destination']?.toString() ?? '',
        rideType: data['ride_type']?.toString() ?? 'car',
        fare: d('fare'),
        pickupLat: d('pickup_lat'),
        pickupLng: d('pickup_lng'),
        destLat: d('dest_lat'),
        destLng: d('dest_lng'),
        tripId: data['trip_id']?.toString(),
        riderPhone: data['rider_phone']?.toString(),
        mysqlRideId: int.tryParse(data['mysqlRideId']?.toString() ?? ''),
      ));
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

  /// Request ids we've already opened a call screen for (cross-handler dedup).
  static final Set<String> shownCallRequestIds = {};

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
    // Notification permission is already requested once above via
    // _fcm.requestPermission() — don't ask again here (that caused repeat
    // popups). The Android 14+ full-screen-intent access is requested only
    // when a driver goes online (see primeDriverPermissions), since only
    // drivers need the lock-screen ride-call ring.

    // 5. Foreground FCM → show the incoming call screen directly
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // 6. App opened from a notification tap (was in background)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    // 6b. App launched from terminated by tapping the call notification
    final initial = await _fcm.getInitialMessage();
    if (initial != null && (initial.data['type'] ?? '') == 'ride_request') {
      // Slight delay so the app's first route is ready before navigating
      Future.delayed(const Duration(milliseconds: 800), () {
        openRideCallFromData(initial.data);
      });
    }

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

    if (type == 'ride_taken') {
      // Another driver got it — clear the notification (the open call screen
      // dismisses itself via its Firestore listener).
      cancelRideRequestNotification();
    } else if (type == 'ride_request') {
      // App is open → ring + open the full-screen call immediately
      openRideCallFromData(data);
    } else {
      // Generic status notification
      _showStatusNotification(
        title: message.notification?.title ?? 'GoRide',
        body: message.notification?.body ?? '',
      );
    }
  }

  void _handleMessageOpenedApp(RemoteMessage message) {
    final data = message.data;
    if ((data['type'] ?? '') == 'ride_request') {
      openRideCallFromData(data);
    }
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
