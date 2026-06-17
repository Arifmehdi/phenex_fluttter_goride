import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Service to handle ride request notifications with ringing and vibration.
/// Plays a persistent alert for 10 seconds when a new ride request arrives.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // Notification IDs
  static const int _rideRequestNotificationId = 1001;

  /// Track active request IDs to avoid duplicate alerts
  final Set<String> _activeRequestIds = {};

  /// Initialize the notification plugin
  Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(settings: initSettings);
    _initialized = true;
  }

  /// Request Android 13+ notification permission
  Future<void> requestPermission() async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
  }

  /// Show a ride request notification with ringing and vibration.
  /// Uses the default system notification sound for ringing + vibration.
  Future<void> showRideRequestNotification({
    required String requestId,
    required String riderName,
    required String pickupAddress,
    required String destinationAddress,
    required String fare,
  }) async {
    if (_activeRequestIds.contains(requestId)) return;
    _activeRequestIds.add(requestId);

    // Vibration pattern: vibrate pattern for phone-call-like behavior
    final vibrationPattern = Int64List.fromList([
      500, 500, 500, 500, 500, 1000, 500, 500,
    ]);

    // Android-specific high-priority notification for ringing like a phone call
    final androidDetails = AndroidNotificationDetails(
      'ride_requests_channel',
      'Ride Requests',
      channelDescription: 'Notifications for new ride requests',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: vibrationPattern,
      category: AndroidNotificationCategory.call,
      visibility: NotificationVisibility.public,
      fullScreenIntent: true,
      ongoing: false,
      autoCancel: false,
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'default',
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      id: _rideRequestNotificationId,
      title: '🚗 New Ride Request!',
      body: '$riderName wants to go from $pickupAddress to $destinationAddress • $fare',
      notificationDetails: notificationDetails,
    );
  }

  /// Cancel the current ride request notification
  Future<void> cancelRideRequestNotification() async {
    await _plugin.cancel(id: _rideRequestNotificationId);
  }

  /// Remove a request ID from the active set (called when request is accepted/timed out)
  Future<void> dismissRequest(String requestId) async {
    _activeRequestIds.remove(requestId);
    if (_activeRequestIds.isEmpty) {
      await cancelRideRequestNotification();
    }
  }

  /// Check if a request is already being alerted
  bool isRequestActive(String requestId) {
    return _activeRequestIds.contains(requestId);
  }

  /// Cancel all notifications
  Future<void> cancelAll() async {
    _activeRequestIds.clear();
    await _plugin.cancelAll();
  }
}
