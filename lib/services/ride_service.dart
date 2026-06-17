import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'firebase_service.dart';
import 'location_service.dart';
import 'api_service.dart';

class RideService extends GetxService {
  final FirebaseService _firebaseService = Get.find<FirebaseService>();

  final ApiService _apiService = Get.find<ApiService>();

  // Current trip state
  final RxString currentTripId = ''.obs;
  final RxString tripStatus = 'idle'.obs; // idle, requesting, accepted, arriving, in_progress, completed, cancelled
  final RxString assignedDriverId = ''.obs;
  final RxString assignedDriverName = ''.obs;
  final RxString assignedDriverPhone = ''.obs;
  final RxDouble assignedDriverRating = 4.8.obs;
  final RxString assignedRiderName = 'Passenger'.obs;
  final RxString assignedRiderPhone = ''.obs;
  final RxDouble driverLatitude = 0.0.obs;
  final RxDouble driverLongitude = 0.0.obs;
  final RxDouble driverHeading = 0.0.obs;
  final RxDouble driverSpeed = 0.0.obs;
  final RxDouble driverDistance = 0.0.obs; // km away from pickup
  final RxInt driverETA = 0.obs; // minutes
  final RxDouble tripProgress = 0.0.obs; // 0.0 to 1.0
  final RxBool isDriverOnline = false.obs;

  StreamSubscription<DocumentSnapshot>? _tripStream;
  StreamSubscription<DocumentSnapshot>? _driverLocationStream;

  @override
  void onClose() {
    _tripStream?.cancel();
    _driverLocationStream?.cancel();
    super.onClose();
  }

  /// Request a ride (rider side)
  Future<String?> requestRide({
    required String rideType,
    required double pickupLat,
    required double pickupLng,
    required String pickupAddress,
    required double destLat,
    required double destLng,
    required String destAddress,
    required double fare,
  }) async {
    final user = _apiService.getUser();
    final riderId = user?['id']?.toString() ?? 'unknown';
    final riderName = user?['name']?.toString() ?? 'Rider';
    final riderPhone = user?['mobile']?.toString() ?? '';

    try {
      // Save rider phone locally so driver can access it
      assignedRiderPhone.value = riderPhone;

      // Create the trip in Firestore
      final tripId = await _firebaseService.createTrip(
        riderId: riderId,
        riderName: riderName,
        riderPhone: riderPhone,
        rideType: rideType,
        pickupLat: pickupLat,
        pickupLng: pickupLng,
        pickupAddress: pickupAddress,
        destLat: destLat,
        destLng: destLng,
        destAddress: destAddress,
        fare: fare,
      );

      // Create the trip in Laravel API
      await _apiService.createRideRequest({
        'ride_type': rideType,
        'pickup_latitude': pickupLat,
        'pickup_longitude': pickupLng,
        'pickup_address': pickupAddress,
        'destination_latitude': destLat,
        'destination_longitude': destLng,
        'destination_address': destAddress,
        'fare': fare,
        'firebase_trip_id': tripId ?? '',
      });

      // Create a ride request for drivers to see in Firestore
      await _firebaseService.createRideRequest(
        riderId: riderId,
        riderName: riderName,
        riderPhone: riderPhone,
        rideType: rideType,
        pickupLat: pickupLat,
        pickupLng: pickupLng,
        pickupAddress: pickupAddress,
        destLat: destLat,
        destLng: destLng,
        destAddress: destAddress,
        tripId: tripId ?? '',
        fare: fare,
      );

      currentTripId.value = tripId ?? '';
      tripStatus.value = 'requesting';

      // Start listening for trip updates
      if (tripId != null) {
        _listenToTrip(tripId);
      }

      return tripId;
    } catch (e) {
      debugPrint('Error requesting ride: $e');
      return null;
    }
  }

  /// Listen to trip status changes from Firestore
  void _listenToTrip(String tripId) {
    _tripStream?.cancel();
    _tripStream = _firebaseService.streamTrip(tripId).listen((snapshot) {
      if (!snapshot.exists) return;

      final data = snapshot.data() as Map<String, dynamic>?;
      if (data == null) return;

      final status = data['status'] as String? ?? 'requesting';
      final driverId = data['driverId'] as String? ?? '';

      // Set driver info BEFORE tripStatus so GetX ever() listeners
      // see the complete state when they fire synchronously
      if (driverId.isNotEmpty) {
        assignedDriverId.value = driverId;
        assignedDriverName.value = data['driverName'] as String? ?? 'Driver';
        // Try multiple possible field names for phone
        assignedDriverPhone.value = (data['driverPhone'] as String? ??
                                    data['phone'] as String? ??
                                    '');
        assignedDriverRating.value = (data['driverRating'] as num?)?.toDouble() ?? 4.8;
        // Start tracking the driver's location
        _listenToDriverLocation(driverId);
      }

      // Now set tripStatus (this triggers ever() listeners which may call setState)
      tripStatus.value = status;
      assignedRiderName.value = data['riderName'] as String? ?? 'Passenger';
      assignedRiderPhone.value = data['riderPhone'] as String? ?? '';

      if (status == 'completed' || status == 'cancelled') {
        _tripStream?.cancel();
        _driverLocationStream?.cancel();
      }
    });
  }

  /// Listen to driver's live location from Firestore
  void _listenToDriverLocation(String driverId) {
    _driverLocationStream?.cancel();
    _driverLocationStream = _firebaseService
        .streamDriverLocation(driverId)
        .listen((snapshot) {
      if (!snapshot.exists) return;

      final data = snapshot.data() as Map<String, dynamic>?;
      if (data == null) return;

      driverLatitude.value = (data['latitude'] as num?)?.toDouble() ?? 0.0;
      driverLongitude.value = (data['longitude'] as num?)?.toDouble() ?? 0.0;
      driverHeading.value = (data['heading'] as num?)?.toDouble() ?? 0.0;
      driverSpeed.value = (data['speed'] as num?)?.toDouble() ?? 0.0;
      isDriverOnline.value = (data['isOnline'] as bool?) ?? false;

      // Calculate distance from driver to pickup
      final rideData = _getRidePickupLocation();
      if (rideData != null) {
        driverDistance.value = LocationService.calculateDistance(
          driverLatitude.value,
          driverLongitude.value,
          rideData.$1,
          rideData.$2,
        );

        // Estimate ETA based on speed (default 30 km/h if unknown)
        final avgSpeed = driverSpeed.value > 0 ? driverSpeed.value * 3.6 : 30.0;
        driverETA.value = LocationService.calculateETA(
          driverDistance.value,
          avgSpeedKmh: avgSpeed,
        );
      }
    });
  }

  /// Get pickup location from current trip data in Firestore
  (double, double)? _getRidePickupLocation() {
    // We store this temporarily - in production, we'd get it from the trip doc
    // For now, we access from FirebaseService trips collection
    return null; // Will be populated from the trip document
  }

  /// Accept a ride request (driver side)
  Future<bool> acceptRideRequest(String requestId, {int? laravelRideId, String? tripId, String? riderName, String? riderPhone}) async {
    final user = _apiService.getUser();
    final driverId = user?['id']?.toString() ?? _apiService.getToken() ?? 'driver';
    final driverName = user?['name']?.toString() ?? 'Driver';
    // Try multiple possible keys for driver phone across different API response formats
    final driverPhone = 
        user?['mobile']?.toString() ??
        user?['phone']?.toString() ??
        user?['phone_number']?.toString() ??
        user?['contact']?.toString() ??
        user?['mobile_number']?.toString() ??
        '';
    debugPrint('Driver phone extracted: "$driverPhone" from user keys: ${user?.keys}');
    final driverRating = (user?['rating'] as num?)?.toDouble() ?? 4.8;

    // Set the rider's info directly from the ride request data
    if (riderName != null && riderName.isNotEmpty) {
      assignedRiderName.value = riderName;
    }
    if (riderPhone != null && riderPhone.isNotEmpty) {
      assignedRiderPhone.value = riderPhone;
    }

    try {
      // 1. Update the ride request status
      await _firebaseService.acceptRideRequest(requestId, driverId);

      // 2. Update the active trip (assign driver)
      String finalTripId = tripId ?? '';
      
      // If tripId is not provided, we should ideally fetch it from the requestId doc
      // For now, if we assume they might be different, we need tripId.
      // If we don't have it, we use requestId as a fallback (some old logic might rely on this)
      if (finalTripId.isEmpty) {
        finalTripId = requestId; 
      }

      await _firebaseService.assignDriverToTrip(
        finalTripId, 
        driverId,
        driverName: driverName,
        driverPhone: driverPhone,
        driverRating: driverRating,
      );

      if (laravelRideId != null) {
        await _apiService.updateRideStatus(laravelRideId, 'accepted');
      }

      currentTripId.value = finalTripId;
      assignedDriverId.value = driverId;
      assignedDriverName.value = driverName;
      assignedDriverPhone.value = driverPhone;
      assignedDriverRating.value = driverRating;
      tripStatus.value = 'accepted';

      // Start listening to the trip we just accepted
      _listenToTrip(finalTripId);

      return true;
    } catch (e) {
      debugPrint('Error accepting ride: $e');
      return false;
    }
  }

  /// Update trip status (driver)
  Future<void> updateStatus(String status, {int? laravelRideId}) async {
    if (currentTripId.value.isEmpty) return;
    await _firebaseService.updateTripStatus(currentTripId.value, status);
    
    if (laravelRideId != null) {
      await _apiService.updateRideStatus(laravelRideId, status);
    }
    
    tripStatus.value = status;
  }

  /// Cancel the current trip
  Future<void> cancelTrip() async {
    await updateStatus('cancelled');
    resetTrip();
  }

  /// Reset trip state
  void resetTrip() {
    _tripStream?.cancel();
    _driverLocationStream?.cancel();
    currentTripId.value = '';
    tripStatus.value = 'idle';
    assignedDriverId.value = '';
    assignedDriverName.value = '';
    assignedDriverPhone.value = '';
    assignedRiderName.value = 'Passenger';
    assignedRiderPhone.value = '';
    driverLatitude.value = 0;
    driverLongitude.value = 0;
    driverHeading.value = 0;
    driverSpeed.value = 0;
    driverDistance.value = 0;
    driverETA.value = 0;
    tripProgress.value = 0;
    isDriverOnline.value = false;
  }
}
