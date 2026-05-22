import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// OSRM Route Response
class OSRMRoute {
  final List<LatLng> points;
  final double distance; // in km
  final double duration; // in minutes

  OSRMRoute({
    required this.points,
    required this.distance,
    required this.duration,
  });
}

class RoutingService {
  static const String _osrmBaseUrl = 'https://router.project-osrm.org';

  /// Fetch a driving route between two points using OSRM
  /// Returns the decoded polyline points, distance (km), and duration (min)
  Future<OSRMRoute?> getRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    try {
      final url = Uri.parse(
        '$_osrmBaseUrl/route/v1/driving/'
        '${origin.longitude},${origin.latitude};'
        '${destination.longitude},${destination.latitude}'
        '?geometries=geojson&overview=full&steps=false&alternatives=false',
      );

      final response = await http.get(
        url,
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode != 200) {
        debugPrint('OSRM API error: ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) {
        return null;
      }

      final route = routes[0] as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;

      // Parse GeoJSON coordinates [lon, lat] to LatLng
      final points = coordinates.map((coord) {
        final lon = (coord as List)[0] as num;
        final lat = coord[1] as num;
        return LatLng(lat.toDouble(), lon.toDouble());
      }).toList();

      final distance = (route['distance'] as num?)?.toDouble() ?? 0.0;
      final duration = (route['duration'] as num?)?.toDouble() ?? 0.0;

      return OSRMRoute(
        points: points,
        distance: distance / 1000, // Convert to km
        duration: duration / 60,   // Convert to minutes
      );
    } catch (e) {
      debugPrint('OSRM routing error: $e');
      return null;
    }
  }

  /// Simplify a route polyline by removing points that are too close together
  /// This can help with performance for very detailed routes
  static List<LatLng> simplifyRoute(List<LatLng> points, {double toleranceMeters = 5}) {
    if (points.length <= 2) return points;

    final result = <LatLng>[points.first];
    for (int i = 1; i < points.length - 1; i++) {
      final distance = _distanceBetweenPoints(points[i - 1], points[i]);
      if (distance > toleranceMeters) {
        result.add(points[i]);
      }
    }
    result.add(points.last);
    return result;
  }

  static double _distanceBetweenPoints(LatLng a, LatLng b) {
    const double earthRadius = 6371000; // meters
    final dLat = _degToRad(b.latitude - a.latitude);
    final dLon = _degToRad(b.longitude - a.longitude);
    final sinDLat = _sin(dLat / 2);
    final sinDLon = _sin(dLon / 2);
    final aVal = sinDLat * sinDLat +
        _cos(_degToRad(a.latitude)) * _cos(_degToRad(b.latitude)) * sinDLon * sinDLon;
    final c = 2 * _atan2(_sqrt(aVal), _sqrt(1 - aVal));
    return earthRadius * c;
  }

  static double _degToRad(double deg) => deg * (3.141592653589793 / 180);
  static double _sin(double val) => val - (val * val * val) / 6;
  static double _cos(double val) => 1 - (val * val) / 2;
  static double _sqrt(double val) => val < 0 ? 0 : val > 1 ? 1 : val; // Simplified
  static double _atan2(double y, double x) {
    if (x == 0) {
      return y > 0 ? 1.5707963267948966 : -1.5707963267948966;
    }
    final val = y / x;
    return val - (val * val * val) / 3;
  }
}


