import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'route_mini_map_painter.dart';

/// Collapsible route overview panel showing a mini-map of the full route,
/// trip progress bar, and waypoint labels.
class RouteOverviewWidget extends StatelessWidget {
  final List<LatLng> routePoints;
  final LatLng? currentPosition;
  final LatLng pickupPoint;
  final LatLng destPoint;
  final String pickupAddress;
  final String destAddress;
  final double tripProgress;
  final double remainingDistance;
  final String role; // 'rider' or 'driver'
  final String tripStatus; // 'accepted', 'arriving', 'in_progress', etc.

  const RouteOverviewWidget({
    super.key,
    required this.routePoints,
    this.currentPosition,
    required this.pickupPoint,
    required this.destPoint,
    required this.pickupAddress,
    required this.destAddress,
    required this.tripProgress,
    required this.remainingDistance,
    required this.role,
    required this.tripStatus,
  });

  @override
  Widget build(BuildContext context) {
    // For driver heading to pickup, show "You are here" as start
    final bool isDriverToPickup = role == 'driver' && tripStatus != 'in_progress';
    final String startLabel = isDriverToPickup ? 'You' : 'Pickup';
    const String endLabel = 'Destination';
    final String startAddr = isDriverToPickup ? 'You are here' : pickupAddress;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Mini-map canvas
        Container(
          height: 110,
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CustomPaint(
              painter: RouteMiniMapPainter(
                routePoints: routePoints,
                currentPosition: currentPosition,
                pickupPoint: pickupPoint,
                destPoint: destPoint,
              ),
              size: const Size(double.infinity, 110),
            ),
          ),
        ),

        // Waypoint labels row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            children: [
              Icon(
                isDriverToPickup ? Icons.near_me : Icons.circle,
                size: 10,
                color: isDriverToPickup ? const Color(0xFF4285F4) : const Color(0xFF34A853),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  startAddr,
                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.flag, size: 10, color: Color(0xFFEA4335)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  destAddress,
                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Trip progress bar
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Trip progress',
                  style: TextStyle(fontSize: 10, color: Colors.grey[500], fontWeight: FontWeight.w500),
                ),
                Text(
                  '${(tripProgress * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF10713C),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: tripProgress,
                minHeight: 6,
                backgroundColor: Colors.grey[200],
                color: tripProgress >= 0.9
                    ? Colors.green
                    : tripProgress >= 0.5
                        ? const Color(0xFF10713C)
                        : Colors.amber[700],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  startLabel,
                  style: TextStyle(fontSize: 9, color: Colors.grey[400]),
                ),
                Text(
                  '${remainingDistance.toStringAsFixed(1)} km left',
                  style: TextStyle(fontSize: 9, color: Colors.grey[400]),
                ),
                Text(
                  endLabel,
                  style: TextStyle(fontSize: 9, color: Colors.grey[400]),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
