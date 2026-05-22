import 'package:get_storage/get_storage.dart';

/// A location saved by the user (from map tap or popular places).
class RecentLocation {
  final String title;
  final String area;
  final double lat;
  final double lng;
  final String iconName;
  final int timestamp;

  const RecentLocation({
    required this.title,
    required this.area,
    required this.lat,
    required this.lng,
    this.iconName = 'history',
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'area': area,
        'lat': lat,
        'lng': lng,
        'iconName': iconName,
        'timestamp': timestamp,
      };

  factory RecentLocation.fromJson(Map<String, dynamic> json) =>
      RecentLocation(
        title: json['title'] as String? ?? 'Unknown',
        area: json['area'] as String? ?? '',
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        iconName: json['iconName'] as String? ?? 'history',
        timestamp: json['timestamp'] as int? ?? 0,
      );
}

/// Persists and retrieves recently used locations via GetStorage.
class RecentLocationsService {
  static const String _key = 'recent_locations';
  static const int _maxItems = 10;
  final GetStorage _storage;

  RecentLocationsService() : _storage = GetStorage();

  /// Load stored locations ordered by most recent first.
  List<RecentLocation> getLocations() {
    final raw = _storage.read<List<dynamic>>(_key);
    if (raw == null || raw.isEmpty) return [];
    return raw
        .cast<Map<String, dynamic>>()
        .map((e) => RecentLocation.fromJson(e))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  /// Add (or update) a location. Duplicates are moved to the top.
  void saveLocation(RecentLocation location) {
    final list = getLocations();

    // Remove duplicate if exists (same lat/lng)
    list.removeWhere(
        (e) => e.lat.toStringAsFixed(4) == location.lat.toStringAsFixed(4) &&
            e.lng.toStringAsFixed(4) == location.lng.toStringAsFixed(4));

    // Insert at front
    list.insert(
        0,
        RecentLocation(
          title: location.title,
          area: location.area,
          lat: location.lat,
          lng: location.lng,
          iconName: location.iconName,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ));

    // Cap to max items
    if (list.length > _maxItems) list.removeRange(_maxItems, list.length);

    _storage.write(_key, list.map((e) => e.toJson()).toList());
  }

  /// Completely wipe saved locations.
  void clearAll() => _storage.remove(_key);
}
