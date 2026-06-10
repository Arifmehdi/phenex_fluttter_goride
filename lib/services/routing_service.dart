import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import '../map_key.dart';

/// Google Route Response
class GoogleRoute {
  final List<LatLng> points;
  final double distance; // in km
  final double duration; // in minutes

  GoogleRoute({
    required this.points,
    required this.distance,
    required this.duration,
  });
}

class GoogleRouteResponse {
  final GoogleRoute? route;
  final String? errorMessage;
  final String status;

  GoogleRouteResponse({this.route, this.errorMessage, required this.status});
}

class RoutingService {
  static const String _baseUrl = 'https://maps.googleapis.com/maps/api/directions/json';

  /// Fetch a driving route between two points using Google Directions API
  Future<GoogleRouteResponse> getRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    try {
      final url = Uri.parse(
        '$_baseUrl?origin=${origin.latitude},${origin.longitude}'
        '&destination=${destination.latitude},${destination.longitude}'
        '&key=$googleMapKey'
        '&mode=driving'
      );

      final response = await http.get(url);
      debugPrint('Directions API Request: $url');
      debugPrint('Directions API Response: ${response.statusCode} - ${response.body}');

      if (response.statusCode != 200) {
        return GoogleRouteResponse(
          status: 'HTTP_${response.statusCode}',
          errorMessage: 'Server returned ${response.statusCode}',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final String status = data['status'] ?? 'UNKNOWN';
      
      if (status != 'OK') {
        final String? msg = data['error_message'];
        debugPrint('Google Directions API error status: $status - $msg');
        return GoogleRouteResponse(
          status: status,
          errorMessage: msg,
        );
      }

      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) {
        return GoogleRouteResponse(status: 'ZERO_RESULTS', errorMessage: 'No route found');
      }

      final route = routes[0] as Map<String, dynamic>;
      final legs = route['legs'] as List;
      final leg = legs[0] as Map<String, dynamic>;

      final distance = (leg['distance']['value'] as num).toDouble() / 1000.0; // meters to km
      final duration = (leg['duration']['value'] as num).toDouble() / 60.0;   // seconds to min

      final overviewPolyline = route['overview_polyline']['points'] as String;
      final points = _decodePolyline(overviewPolyline);

      return GoogleRouteResponse(
        status: 'OK',
        route: GoogleRoute(
          points: points,
          distance: distance,
          duration: duration,
        ),
      );
    } catch (e) {
      debugPrint('Google routing error: $e');
      return GoogleRouteResponse(status: 'EXCEPTION', errorMessage: e.toString());
    }
  }

  /// Decodes Google's encoded polyline string into a list of LatLng
  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> poly = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      poly.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return poly;
  }
}
