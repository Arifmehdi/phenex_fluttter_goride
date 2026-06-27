import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';

/// Shared SOS emergency flow — confirmation dialog, backend trigger,
/// and "Call 999" follow-up. Used by RideStatusScreen and LiveTrackingScreen.
Future<void> triggerSosFlow(
  BuildContext context, {
  int? rideId,
  double? lat,
  double? lng,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(children: [
        Icon(Icons.warning_rounded, color: Colors.red, size: 28),
        SizedBox(width: 10),
        Text('SOS Emergency',
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('This will immediately:'),
          const SizedBox(height: 8),
          const Text('• Alert GoRide admin', style: TextStyle(fontSize: 13)),
          const Text('• SMS your emergency contact', style: TextStyle(fontSize: 13)),
          const Text('• Share your live location', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          Builder(builder: (_) {
            final user = Get.find<ApiService>().getUser();
            final ecName = user?['emergency_contact_name'] as String?;
            if (ecName == null || ecName.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: const Text(
                  '⚠️ No emergency contact set. Set one in your profile for SMS alerts.',
                  style: TextStyle(fontSize: 12, color: Colors.orange),
                ),
              );
            }
            return Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Text('Emergency contact: $ecName',
                  style: const TextStyle(fontSize: 12, color: Colors.green)),
            );
          }),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('SEND SOS',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;

  await Get.find<ApiService>().triggerSos(
    rideRequestId: rideId != null && rideId > 0 ? rideId : null,
    lat: lat,
    lng: lng,
  );

  if (!context.mounted) return;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(children: [
        Icon(Icons.check_circle, color: Color(0xFF10713C), size: 26),
        SizedBox(width: 8),
        Text('SOS Sent', style: TextStyle(fontWeight: FontWeight.bold)),
      ]),
      content: const Text(
          'Help has been alerted. Stay calm and stay where you are. '
          'You can also call the national emergency line.'),
      actions: [
        ElevatedButton.icon(
          onPressed: () async {
            Navigator.pop(ctx);
            final uri = Uri(scheme: 'tel', path: '999');
            if (await canLaunchUrl(uri)) launchUrl(uri);
          },
          icon: const Icon(Icons.call, color: Colors.white),
          label: const Text('Call 999', style: TextStyle(color: Colors.white)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

/// A reusable pill-shaped SOS button (red) for app bars / overlays.
class SosPillButton extends StatelessWidget {
  final VoidCallback onTap;
  const SosPillButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withValues(alpha: 0.4),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sos, color: Colors.white, size: 18),
              SizedBox(width: 6),
              Text('SOS',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      letterSpacing: 1)),
            ],
          ),
        ),
      ),
    );
  }
}
