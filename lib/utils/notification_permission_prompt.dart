import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';
import 'package:permission_handler/permission_handler.dart';

const String _primedStorageKey = 'notif_permissions_primed';

/// Shown once, right after the user lands on their home/dashboard screen —
/// walks them through the two Android permissions that make ride-call
/// notifications ring reliably in the background, the same way a WhatsApp
/// call does: notification access, and an exemption from battery
/// optimization (without it, Android can silently kill the app before an
/// incoming ride call ever reaches the screen).
///
/// Safe to call from every entry screen — it no-ops after the first time,
/// and does nothing at all on non-Android platforms.
Future<void> primeNotificationPermissions(BuildContext context) async {
  if (!Platform.isAndroid) return;

  final storage = GetStorage();
  if (storage.read(_primedStorageKey) == true) return;

  final notificationGranted = await Permission.notification.isGranted;
  final batteryExempt = await Permission.ignoreBatteryOptimizations.isGranted;
  if (notificationGranted && batteryExempt) {
    // Already set up (e.g. granted via an OS-level prompt earlier) — nothing to ask.
    await storage.write(_primedStorageKey, true);
    return;
  }

  if (!context.mounted) return;

  final proceed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: const [
          Icon(Icons.notifications_active, color: Color(0xFF10713C)),
          SizedBox(width: 10),
          Expanded(child: Text('Never Miss a Ride Call')),
        ],
      ),
      content: const Text(
        'GoRide needs two quick permissions to ring you for ride requests '
        'reliably — just like a WhatsApp call — even when the app is in '
        'the background or your screen is off.\n\n'
        '1. Allow notifications\n'
        '2. Allow GoRide to run in the background (disable battery optimization)',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Not Now', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10713C),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Allow', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );

  if (proceed == true) {
    await Permission.notification.request();
    // Separate system dialog — Android requires this one to be requested
    // on its own, it can't be bundled with a generic permission request.
    if (!(await Permission.ignoreBatteryOptimizations.isGranted)) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  // Mark as handled either way — if they said "Not Now" or denied a system
  // prompt, don't nag on every app open; they can still enable these
  // manually from the phone's own Settings app later.
  await storage.write(_primedStorageKey, true);
}
