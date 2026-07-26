import 'dart:io';
import 'package:flutter/material.dart';
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

/// Requests the extra permission a DRIVER needs so ride calls ring reliably
/// while the app is backgrounded / the phone is locked — background location,
/// so matching keeps working when the app isn't foreground.
///
/// We deliberately DON'T show a battery-optimization popup: the ride call is
/// delivered as a `priority: high` FCM data message, which Android wakes up and
/// delivers even under Doze / battery optimization. So the call rings without
/// asking the user to "let the app always run" — one fewer popup, same result.
///
/// Full-screen-intent access is declared in the manifest and granted at install
/// on the vast majority of devices, so we don't prompt for it either.
///
/// Called when a driver toggles ONLINE. Runs once, then remembers it.
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
  } catch (e) {
    debugPrint('Driver permission request error: $e');
  }

  await storage.write(_driverPrimedStorageKey, true);
}
