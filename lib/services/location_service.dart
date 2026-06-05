import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'firebase_service.dart';
import 'api_service.dart';

class LocationService extends GetxService {
  FirebaseService? _firebaseService;
  final ApiService _apiService = Get.find<ApiService>();

  StreamSubscription<Position>? _positionStream;
  Position? _currentPosition;
  Timer? _locationSyncTimer;

  // Observable state
  final Rx<Position?> currentPosition = Rx<Position?>(null);
  final RxBool isTracking = false.obs;
  final RxDouble speed = 0.0.obs;
  final RxDouble heading = 0.0.obs;

  bool _isUpdatingFirestore = false;
  bool _isUpdatingApi = false;
  String? _driverId;
  String? _currentTripId;
  bool _isOnline = false;
  LatLng? _lastSyncedLocation;

  @override
  void onClose() {
    stopTracking();
    super.onClose();
  }

  /// Initialize with Firebase service
  void initFirebase(FirebaseService firebaseService) {
    _firebaseService = firebaseService;
  }

  /// Request location permissions
  Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('Location services are disabled');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('Location permission denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('Location permission permanently denied');
      return false;
    }

    return true;
  }

  /// Get current position once
  Future<Position?> getCurrentPosition() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _currentPosition = position;
      currentPosition.value = position;
      return position;
    } catch (e) {
      debugPrint('Error getting current position: $e');
      return null;
    }
  }

  /// Start continuous location tracking
  Future<void> startTracking({
    bool syncToFirestore = false,
    String? driverId,
    bool isOnline = false,
    String? tripId,
  }) async {
    if (isTracking.value) return;

    final hasPermission = await requestPermission();
    if (!hasPermission) return;

    _driverId = driverId;
    _isOnline = isOnline;
    _currentTripId = tripId;

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // Update every 10 meters
    );

    // Get initial position immediately
    await getCurrentPosition();

    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      debugPrint('Location Update: ${position.latitude}, ${position.longitude}');
      _currentPosition = position;
      currentPosition.value = position;
      speed.value = position.speed;
      heading.value = position.heading;

      // Update heading based on movement direction if heading is not available
      if (position.heading <= 0 && _lastSyncedLocation != null) {
        final double dx = position.longitude - _lastSyncedLocation!.longitude;
        final double dy = position.latitude - _lastSyncedLocation!.latitude;
        if (dx.abs() > 0.000001 || dy.abs() > 0.000001) {
          heading.value = atan2(dx, dy) * 180 / pi;
        }
      }

      _lastSyncedLocation = LatLng(position.latitude, position.longitude);
    });

    isTracking.value = true;

    // Sync to Firestore and API periodically (every 3 seconds)
    if (syncToFirestore && driverId != null) {
      debugPrint('Starting location sync timer for driver: $driverId');
      _locationSyncTimer = Timer.periodic(
        const Duration(seconds: 3),
        (_) {
          _syncLocationToFirestore();
          _syncLocationToApi();
        },
      );
    }
  }

  /// Stop location tracking
  Future<void> stopTracking() async {
    _positionStream?.cancel();
    _positionStream = null;
    _locationSyncTimer?.cancel();
    _locationSyncTimer = null;
    isTracking.value = false;

    // Mark driver as offline in Firestore
    if (_driverId != null && _firebaseService != null && _isOnline) {
      await _firebaseService!.updateDriverLocation(
        driverId: _driverId!,
        latitude: _currentPosition?.latitude ?? 0,
        longitude: _currentPosition?.longitude ?? 0,
        heading: heading.value,
        speed: speed.value,
        isOnline: false,
      );
    }

    _isOnline = false;
    _driverId = null;
    _currentTripId = null;
  }

  /// Sync current location to Firestore
  Future<void> _syncLocationToFirestore() async {
    if (_firebaseService == null || _currentPosition == null || _driverId == null) return;
    if (_isUpdatingFirestore) return;

    _isUpdatingFirestore = true;
    try {
      await _firebaseService!.updateDriverLocation(
        driverId: _driverId!,
        latitude: _currentPosition!.latitude,
        longitude: _currentPosition!.longitude,
        heading: heading.value,
        speed: speed.value,
        isOnline: _isOnline,
        currentTripId: _currentTripId,
      );
    } catch (e) {
      debugPrint('Firestore sync error: $e');
    } finally {
      _isUpdatingFirestore = false;
    }
  }

  /// Sync current location to Laravel API
  Future<void> _syncLocationToApi() async {
    if (_currentPosition == null || !_apiService.isLoggedIn()) return;
    if (_isUpdatingApi) return;

    _isUpdatingApi = true;
    try {
      await _apiService.updateLocation(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      );
    } catch (e) {
      debugPrint('API location sync error: $e');
    } finally {
      _isUpdatingApi = false;
    }
  }

  /// Set driver online/offline status for ride sharing
  Future<void> setDriverOnline(bool online) async {
    _isOnline = online;
    if (_firebaseService != null && _driverId != null && _currentPosition != null) {
      await _firebaseService!.updateDriverLocation(
        driverId: _driverId!,
        latitude: _currentPosition!.latitude,
        longitude: _currentPosition!.longitude,
        heading: heading.value,
        speed: speed.value,
        isOnline: online,
      );
    }
  }

  /// Update the current trip ID for tracking
  void setCurrentTripId(String? tripId) {
    _currentTripId = tripId;
  }

  /// Get address from coordinates using reverse geocoding
  Future<String> getAddressFromLatLng(double latitude, double longitude) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        latitude,
        longitude,
      );
      if (placemarks.isNotEmpty) {
        final place = placemarks[0];
        String address = '';
        if (place.name != null && place.name!.isNotEmpty) {
          address += place.name!;
        }
        if (place.subLocality != null && place.subLocality!.isNotEmpty) {
          address += '${address.isNotEmpty ? ', ' : ''}${place.subLocality}';
        }
        if (place.locality != null && place.locality!.isNotEmpty) {
          address += '${address.isNotEmpty ? ', ' : ''}${place.locality}';
        }
        return address.isNotEmpty ? address : '$latitude, $longitude';
      }
      return '$latitude, $longitude';
    } catch (e) {
      debugPrint('Geocoding error: $e');
      return '$latitude, $longitude';
    }
  }

  /// Calculate distance between two coordinates in km
  static double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2) / 1000;
  }

  /// Calculate estimated time of arrival in minutes
  static int calculateETA(double distanceKm, {double avgSpeedKmh = 30}) {
    if (distanceKm <= 0) return 1;
    return (distanceKm / avgSpeedKmh * 60).ceil();
  }
}
