import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/ride_service.dart';
import '../pages/live_tracking_screen.dart';

/// Reopen the Live Tracking screen for the currently active ride using the
/// details cached in RideService. Works for both customer and driver.
void openActiveRideTracking() {
  final rs = Get.find<RideService>();
  if (!rs.hasActiveRide) return;
  Get.to(() => LiveTrackingScreen(
        role: rs.currentRole.value,
        rideType: rs.currentRideType.value,
        pickupAddress: rs.currentPickupAddress.value,
        destinationAddress: rs.currentDestAddress.value,
        price: rs.currentFare.value,
        pickupLat: rs.currentPickupLat.value,
        pickupLng: rs.currentPickupLng.value,
        destLat: rs.currentDestLat.value,
        destLng: rs.currentDestLng.value,
        tripId: rs.currentTripId.value,
      ));
}

/// A tap-to-reopen bar shown on the dashboard/home while a ride is live —
/// exactly like the "ongoing trip" bar in Pathao / Uber / InDrive.
class OngoingRideBanner extends StatelessWidget {
  const OngoingRideBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final rs = Get.find<RideService>();

    return Obx(() {
      if (!rs.hasActiveRide) return const SizedBox.shrink();

      final status = rs.tripStatus.value;
      final label = switch (status) {
        'accepted' => 'Driver is on the way',
        'arriving' => 'Driver is arriving',
        'in_progress' => 'On the way to destination',
        _ => 'Ongoing ride',
      };
      final isDriver = rs.currentRole.value == 'driver';
      final otherName = isDriver
          ? (rs.assignedRiderName.value.isNotEmpty ? rs.assignedRiderName.value : 'Passenger')
          : (rs.assignedDriverName.value.isNotEmpty ? rs.assignedDriverName.value : 'Driver');

      return GestureDetector(
        onTap: openActiveRideTracking,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF10713C),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF10713C).withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Pulsing live dot
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.navigation, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 7, height: 7,
                          decoration: const BoxDecoration(color: Colors.lightGreenAccent, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        const Text('ONGOING RIDE',
                            style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(label,
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(isDriver ? 'Passenger: $otherName' : 'Driver: $otherName',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const Text('View', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      );
    });
  }
}
