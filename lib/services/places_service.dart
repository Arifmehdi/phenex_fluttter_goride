import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../map_key.dart';

class PlaceSuggestion {
  final String placeId;
  final String description;
  final String mainText;
  final String secondaryText;

  PlaceSuggestion({
    required this.placeId,
    required this.description,
    required this.mainText,
    required this.secondaryText,
  });
}

class PlaceDetails {
  final double latitude;
  final double longitude;
  final String address;

  PlaceDetails({
    required this.latitude,
    required this.longitude,
    required this.address,
  });
}

class PlacesService {
  static const String _autocompleteUrl =
      'https://maps.googleapis.com/maps/api/place/autocomplete/json';
  static const String _detailsUrl =
      'https://maps.googleapis.com/maps/api/place/details/json';

  Future<List<PlaceSuggestion>> getSuggestions(String input) async {
    if (input.isEmpty) return [];

    try {
      final url = Uri.parse(
        '$_autocompleteUrl?input=${Uri.encodeComponent(input)}'
        '&key=$googleMapKey'
        '&components=country:bd' // Limit to Bangladesh
        '&location=23.8103,90.4125&radius=50000' // Bias towards Dhaka (50km radius)
        '&language=en',
      );

      final response = await http.get(url);
      debugPrint('Places API Request: $url');
      debugPrint('Places API Response: ${response.statusCode} - ${response.body}');

      if (response.statusCode != 200) {
        debugPrint('Google Places Autocomplete error: ${response.statusCode}');
        return [];
      }

      final data = jsonDecode(response.body);
      if (data['status'] != 'OK') {
        if (data['status'] == 'ZERO_RESULTS') {
          debugPrint('Google Places: No results found for "$input"');
          return [];
        }
        debugPrint('Google Places Autocomplete error status: ${data['status']}');
        if (data['error_message'] != null) {
          debugPrint('Error Message: ${data['error_message']}');
        }
        return [];
      }

      final predictions = data['predictions'] as List;
      return predictions.map((p) {
        return PlaceSuggestion(
          placeId: p['place_id'],
          description: p['description'],
          mainText: p['structured_formatting']['main_text'] ?? '',
          secondaryText: p['structured_formatting']['secondary_text'] ?? '',
        );
      }).toList();
    } catch (e) {
      debugPrint('Google Places error: $e');
      return [];
    }
  }

  Future<PlaceDetails?> getPlaceDetails(String placeId) async {
    try {
      final url = Uri.parse(
        '$_detailsUrl?place_id=$placeId'
        '&fields=geometry,formatted_address'
        '&key=$googleMapKey',
      );

      final response = await http.get(url);

      if (response.statusCode != 200) {
        debugPrint('Google Place Details error: ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body);
      if (data['status'] != 'OK') {
        debugPrint('Google Place Details error status: ${data['status']}');
        return null;
      }

      final result = data['result'];
      final location = result['geometry']['location'];
      
      return PlaceDetails(
        latitude: location['lat'],
        longitude: location['lng'],
        address: result['formatted_address'],
      );
    } catch (e) {
      debugPrint('Google Place Details error: $e');
      return null;
    }
  }

  Future<String?> getAddressFromLatLng(double lat, double lng) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=$googleMapKey',
      );

      final response = await http.get(url);

      if (response.statusCode != 200) {
        debugPrint('Google Reverse Geocode error: ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body);
      if (data['status'] != 'OK') {
        debugPrint('Google Reverse Geocode error status: ${data['status']}');
        return null;
      }

      if ((data['results'] as List).isNotEmpty) {
        return data['results'][0]['formatted_address'];
      }
      return null;
    } catch (e) {
      debugPrint('Google Reverse Geocode error: $e');
      return null;
    }
  }
}
