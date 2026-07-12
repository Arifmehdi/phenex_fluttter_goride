import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show FlutterLocalNotificationsPlugin, AndroidFlutterLocalNotificationsPlugin;
import 'package:get_storage/get_storage.dart';
import 'package:permission_handler/permission_handler.dart';

const String _primedStorageKey = 'notif_permissions_primed';
const String _driverPrimedStorageKey = 'driver_permissions_primed';

/// Requests ONLY the notification permission, once, with no custom "Allow?"
/// dialog in front of it. Every user needs this so alerts can appear.
///
/// IMPORTANT (Android platform rule, not a bug): a normally-installed app
/// CANNOT silently grant itself notification or location access. Android shows
/// its own system permission sheet the first time and only the user can accept
/// it — there is no code that bypasses this. What we can control is showing the
/// FEWEST possible sheets, once. Heavier permissions (background location,
/// battery-optimization exemption, full-screen lock-screen calls) are NOT asked
/// here — they're deferred to [primeDriverPermissions], requested only when a
/// driver goes online, so a rider install sees at most this single sheet
/// (and none at all on Android 12 and below, where notifications are on by
/// default).
///
/// Safe to call from every entry screen — no-ops after the first run and does
/// nothing on non-Android platforms.
Future<void> primeNotificationPermissions(BuildContext context) async {
  if (!Platform.isAndroid) return;

  final storage = GetStorage();
  if (storage.read(_primedStorageKey) == true) return;

  try {
    if (!await Permission.notification.isGranted) {
      await Permission.notification.request();
    }
  } catch (e) {
    debugPrint('Notification permission request error: $e');
  }

  await storage.write(_primedStorageKey, true);
}

/// Requests the extra permissions a DRIVER needs so ride calls ring reliably
/// while the app is backgrounded / the phone is locked:
///   • background location (to keep matching while the app isn't foreground)
///   • full-screen-intent access (Android 14+, to show the call over the lock
///     screen)
///
/// NOTE: we deliberately do NOT ask for the battery-optimization exemption
/// ("Let app always run in the background?"). Ride calls are delivered as
/// high-priority FCM data messages, which Android delivers even under Doze /
/// battery optimization — so that popup added friction without being needed.
///
/// Called only when a driver toggles ONLINE — riders never see these. Runs its
/// requests once, then remembers it's done so going online later is silent.
Future<void> primeDriverPermissions() async {
  if (!Platform.isAndroid) return;

  final storage = GetStorage();
  if (storage.read(_driverPrimedStorageKey) == true) return;

  try {
    // Background location — Android requires the foreground grant first, so
    // only ask for "always" once when-in-use is already granted.
    if (await Permission.locationWhenInUse.isGranted &&
        !await Permission.locationAlways.isGranted) {
      await Permission.locationAlways.request();
    }

    // Android 14+ revokes full-screen-intent access by default for non-calling
    // apps; the incoming ride call needs it to appear over the lock screen.
    final androidPlugin = FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestFullScreenIntentPermission();
  } catch (e) {
    debugPrint('Driver permission request error: $e');
  }

  await storage.write(_driverPrimedStorageKey, true);
}
