import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Custom painter that renders a compact route overview mini-map.
/// Draws the route polyline, pickup/destination markers, and the current position.
class RouteMiniMapPainter extends CustomPainter {
  final List<LatLng> routePoints;
  final LatLng? currentPosition;
  final LatLng pickupPoint;
  final LatLng destPoint;

  RouteMiniMapPainter({
    required this.routePoints,
    this.currentPosition,
    required this.pickupPoint,
    required this.destPoint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (routePoints.isEmpty) return;

    // Compute bounding box with padding
    double minLat = double.infinity, maxLat = double.negativeInfinity;
    double minLng = double.infinity, maxLng = double.negativeInfinity;

    for (final pt in routePoints) {
      if (pt.latitude < minLat) minLat = pt.latitude;
      if (pt.latitude > maxLat) maxLat = pt.latitude;
      if (pt.longitude < minLng) minLng = pt.longitude;
      if (pt.longitude > maxLng) maxLng = pt.longitude;
    }
    // Include markers
    minLat = min(minLat, min(pickupPoint.latitude, destPoint.latitude));
    maxLat = max(maxLat, max(pickupPoint.latitude, destPoint.latitude));
    minLng = min(minLng, min(pickupPoint.longitude, destPoint.longitude));
    maxLng = max(maxLng, max(pickupPoint.longitude, destPoint.longitude));

    // Add 10% padding
    final latPad = (maxLat - minLat) * 0.1;
    final lngPad = (maxLng - minLng) * 0.1;
    minLat -= latPad;
    maxLat += latPad;
    minLng -= lngPad;
    maxLng += lngPad;

    // Handle degenerate bounding box (single point)
    if ((maxLat - minLat) < 1e-6) { minLat -= 0.001; maxLat += 0.001; }
    if ((maxLng - minLng) < 1e-6) { minLng -= 0.001; maxLng += 0.001; }

    // Transformation: geo → canvas (x = lng, y = lat, y inverted for canvas)
    double toCanvasX(double lng) => ((lng - minLng) / (maxLng - minLng)) * size.width;
    double toCanvasY(double lat) => size.height - ((lat - minLat) / (maxLat - minLat)) * size.height;

    // Determine stroke width based on route aspect ratio vs canvas
    final double aspectRatio = size.width / size.height;
    final double geoRatio = (maxLng - minLng) / (maxLat - minLat);
    final double strokeWidth = (geoRatio > aspectRatio) ? 2.5 : 3.0;

    // ---- Draw route polyline ----
    final routePaint = Paint()
      ..color = const Color(0xFF10713C).withValues(alpha: 0.5)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final routePath = Path();
    for (int i = 0; i < routePoints.length; i++) {
      final x = toCanvasX(routePoints[i].longitude);
      final y = toCanvasY(routePoints[i].latitude);
      if (i == 0) {
        routePath.moveTo(x, y);
      } else {
        routePath.lineTo(x, y);
      }
    }
    canvas.drawPath(routePath, routePaint);

    // ---- Draw progress highlight (portion already traveled) ----
    if (currentPosition != null) {
      // Find the closest point on the route to current position
      int closestIndex = 0;
      double minDist = double.infinity;
      for (int i = 0; i < routePoints.length; i++) {
        final dx = toCanvasX(routePoints[i].longitude) - toCanvasX(currentPosition!.longitude);
        final dy = toCanvasY(routePoints[i].latitude) - toCanvasY(currentPosition!.latitude);
        final d = dx * dx + dy * dy;
        if (d < minDist) {
          minDist = d;
          closestIndex = i;
        }
      }

      // Draw completed portion in solid green
      if (closestIndex > 0) {
        final completedPaint = Paint()
          ..color = const Color(0xFF10713C)
          ..strokeWidth = strokeWidth + 0.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

        final completedPath = Path();
        for (int i = 0; i <= closestIndex; i++) {
          final x = toCanvasX(routePoints[i].longitude);
          final y = toCanvasY(routePoints[i].latitude);
          if (i == 0) {
            completedPath.moveTo(x, y);
          } else {
            completedPath.lineTo(x, y);
          }
        }
        canvas.drawPath(completedPath, completedPaint);
      }
    }

    // ---- Draw pickup marker (green circle) ----
    final pickupX = toCanvasX(pickupPoint.longitude);
    final pickupY = toCanvasY(pickupPoint.latitude);

    canvas.drawCircle(
      Offset(pickupX, pickupY),
      6,
      Paint()..color = Colors.white..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset(pickupX, pickupY),
      6,
      Paint()
        ..color = const Color(0xFF34A853)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // ---- Draw destination marker (red pin shape) ----
    final destX = toCanvasX(destPoint.longitude);
    final destY = toCanvasY(destPoint.latitude);

    canvas.drawCircle(
      Offset(destX, destY),
      6,
      Paint()..color = Colors.white..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset(destX, destY),
      6,
      Paint()
        ..color = const Color(0xFFEA4335)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // ---- Draw current position (blue dot with ring) ----
    if (currentPosition != null) {
      final curX = toCanvasX(currentPosition!.longitude);
      final curY = toCanvasY(currentPosition!.latitude);

      // Outer ring
      canvas.drawCircle(
        Offset(curX, curY),
        8,
        Paint()
          ..color = const Color(0xFF4285F4).withValues(alpha: 0.25)
          ..style = PaintingStyle.fill,
      );
      // Inner dot
      canvas.drawCircle(
        Offset(curX, curY),
        4.5,
        Paint()
          ..color = const Color(0xFF4285F4)
          ..style = PaintingStyle.fill,
      );
      // White center
      canvas.drawCircle(
        Offset(curX, curY),
        2,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant RouteMiniMapPainter oldDelegate) {
    // Use value equality for LatLng
    final posChanged = (currentPosition == null && oldDelegate.currentPosition != null) ||
        (currentPosition != null && oldDelegate.currentPosition == null) ||
        (currentPosition != null && oldDelegate.currentPosition != null &&
            (currentPosition!.latitude != oldDelegate.currentPosition!.latitude ||
                currentPosition!.longitude != oldDelegate.currentPosition!.longitude));
    return posChanged ||
        oldDelegate.routePoints != routePoints ||
        oldDelegate.pickupPoint.latitude != pickupPoint.latitude ||
        oldDelegate.pickupPoint.longitude != pickupPoint.longitude ||
        oldDelegate.destPoint.latitude != destPoint.latitude ||
        oldDelegate.destPoint.longitude != destPoint.longitude;
  }
}
