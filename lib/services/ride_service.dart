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

  // Post-trip payment — the shared signal that lets the driver's app know
  // the rider has paid (they're on separate devices; this is the only
  // real-time channel between them once the trip ends).
  final RxString paymentStatus = 'pending'.obs; // pending, paid
  final RxString paymentMethod = ''.obs; // cash, wallet, sslcommerz

  // Active trip details caching to support perfect session resumption
  final RxString currentRideType = 'car'.obs;
  final RxString currentPickupAddress = ''.obs;
  final RxString currentDestAddress = ''.obs;
  final RxDouble currentFare = 0.0.obs;
  final RxDouble currentPickupLat = 0.0.obs;
  final RxDouble currentPickupLng = 0.0.obs;
  final RxDouble currentDestLat = 0.0.obs;
  final RxDouble currentDestLng = 0.0.obs;
  // 'rider' (customer) or 'driver' — who is viewing the active ride
  final RxString currentRole = 'rider'.obs;

  /// True while a ride is live (accepted → in_progress). Used by the
  /// dashboard "ongoing ride" banner to know whether to show.
  bool get hasActiveRide =>
      const ['accepted', 'arriving', 'in_progress'].contains(tripStatus.value);

  /// Cache the ride details so the trip can be reopened from the dashboard.
  void cacheActiveRide({
    required String role,
    required String rideType,
    required String pickupAddress,
    required String destAddress,
    required double fare,
    required double pickupLat,
    required double pickupLng,
    required double destLat,
    required double destLng,
  }) {
    currentRole.value = role;
    currentRideType.value = rideType;
    currentPickupAddress.value = pickupAddress;
    currentDestAddress.value = destAddress;
    currentFare.value = fare;
    currentPickupLat.value = pickupLat;
    currentPickupLng.value = pickupLng;
    currentDestLat.value = destLat;
    currentDestLng.value = destLng;
  }

  String _currentRideRequestId = '';
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

      if (tripId == null) {
        debugPrint('Failed to create trip in Firestore');
        return null;
      }

      // MUST set up the trip listener BEFORE any API calls that could fail.
      // The Laravel API might be unreachable, but the rider should still
      // receive Firestore updates when the driver accepts the ride.
      currentTripId.value = tripId;
      tripStatus.value = 'requesting';
      _listenToTrip(tripId);

      // Create the ride request for drivers to see in Firestore
      // (This is non-critical — rider can still receive trip updates)
      try {
        final requestId = await _firebaseService.createRideRequest(
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
          tripId: tripId,
          fare: fare,
        );
        // Save the ride request ID so we can cancel it later
        if (requestId != null) {
          _currentRideRequestId = requestId;
        }
      } catch (e) {
        debugPrint('Warning: could not create ride request in Firestore: $e');
      }

      // Create the trip in Laravel API (non-critical, rider can still receive updates)
      try {
        final laravelResponse = await _apiService.createRideRequest({
          'ride_type': rideType,
          'pickup_latitude': pickupLat,
          'pickup_longitude': pickupLng,
          'pickup_address': pickupAddress,
          'destination_latitude': destLat,
          'destination_longitude': destLng,
          'destination_address': destAddress,
          'fare': fare,
          'firebase_trip_id': tripId,
        });
        // Store the Laravel ride request ID for rating submission
        if (laravelResponse.statusCode == 201 && laravelResponse.data is Map) {
          final rideData = laravelResponse.data['data'];
          if (rideData != null && rideData['id'] != null) {
            laravelRideId.value = (rideData['id'] as num).toInt();
            if (rideData['driver_id'] != null) {
              laravelDriverId.value = (rideData['driver_id'] as num).toInt();
            }
            debugPrint('Stored Laravel ride ID: ${laravelRideId.value}');
            // Now match nearby drivers to this ride
            if (laravelRideId.value > 0) {
              try {
                final matchRes = await _apiService.matchDrivers(rideRequestId: laravelRideId.value);
                debugPrint('Driver matching response: ${matchRes.statusCode} - ${matchRes.data}');
              } catch (e) {
                debugPrint('Warning: could not match drivers: $e');
              }
              
              // Sync the Laravel MySQL ID to Firestore so driver can fetch it
              try {
                await _firebaseService.activeTrips?.doc(tripId).update({
                  'mysqlRideId': laravelRideId.value,
                });
                if (_currentRideRequestId.isNotEmpty) {
                  await _firebaseService.rideRequests?.doc(_currentRideRequestId).update({
                    'mysqlRideId': laravelRideId.value,
                  });
                }
                debugPrint('Updated Firestore with mysqlRideId: ${laravelRideId.value}');
              } catch (firebaseErr) {
                debugPrint('Warning: could not update Firestore with mysqlRideId: $firebaseErr');
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Warning: could not create ride request in Laravel API: $e');
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

      // Persist active trip parameters for resume functionality
      currentFare.value = (data['fare'] as num?)?.toDouble() ?? 0.0;
      currentRideType.value = data['rideType'] as String? ?? 'car';
      currentPickupAddress.value = data['pickupAddress'] as String? ?? 'Pickup';
      currentDestAddress.value = data['destAddress'] as String? ?? 'Destination';
      currentPickupLat.value = (data['pickupLatitude'] as num?)?.toDouble() ?? 0.0;
      currentPickupLng.value = (data['pickupLongitude'] as num?)?.toDouble() ?? 0.0;
      currentDestLat.value = (data['destLatitude'] as num?)?.toDouble() ?? 0.0;
      currentDestLng.value = (data['destLongitude'] as num?)?.toDouble() ?? 0.0;

      final newPaymentStatus = data['paymentStatus'] as String? ?? 'pending';
      paymentStatus.value = newPaymentStatus;
      paymentMethod.value = data['paymentMethod'] as String? ?? '';

      // Keep listening past 'completed' until payment is also confirmed —
      // that's the driver's only real-time signal that the rider has paid.
      if (status == 'cancelled' ||
          (status == 'completed' && newPaymentStatus == 'paid')) {
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

  /// Get pickup location from current trip data (stored in the service when trip is accepted)
  (double, double)? _getRidePickupLocation() {
    final pickupLat = currentPickupLat.value;
    final pickupLng = currentPickupLng.value;
    if (pickupLat == 0.0 || pickupLng == 0.0) return null;
    return (pickupLat, pickupLng);
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
      // 1. ATOMIC claim — only the first driver to accept wins.
      final claimed = await _firebaseService.claimRideRequest(requestId, driverId);
      if (!claimed) {
        // Another driver already took this ride.
        debugPrint('Ride $requestId already taken by another driver.');
        return false;
      }

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

      currentTripId.value = finalTripId;
      if (laravelRideId != null) this.laravelRideId.value = laravelRideId;
      // Resolve the ride id from the trip id if it wasn't passed, so the
      // 'accepted' status reliably reaches Laravel (not just Firestore).
      final acceptedRideId = await _ensureLaravelRideId();
      if (acceptedRideId > 0) {
        await _apiService.updateRideStatus(acceptedRideId, 'accepted');
      }

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

  /// Make sure we hold the Laravel ride id. If the real-time (Firestore)
  /// accept handshake never captured it, resolve it from the trip id so
  /// status/payment still reach Laravel (otherwise the ride stays 'pending'
  /// forever and the driver never earns).
  Future<int> _ensureLaravelRideId() async {
    if (laravelRideId.value > 0) return laravelRideId.value;
    if (currentTripId.value.isNotEmpty) {
      final id = await _apiService.resolveLaravelRideId(currentTripId.value);
      if (id != null && id > 0) laravelRideId.value = id;
    }
    return laravelRideId.value;
  }

  /// Public: resolve & return the Laravel ride id (needed for wallet payment).
  Future<int> resolveRideId() => _ensureLaravelRideId();

  /// Update trip status (driver)
  Future<void> updateStatus(String status, {int? laravelRideId}) async {
    if (currentTripId.value.isEmpty) return;
    await _firebaseService.updateTripStatus(currentTripId.value, status);

    final finalLaravelId = laravelRideId ?? await _ensureLaravelRideId();
    if (finalLaravelId > 0) {
      await _apiService.updateRideStatus(finalLaravelId, status);
    }

    tripStatus.value = status;
  }

  /// Rider marks the trip as paid (cash/wallet/card). Writes to Firestore
  /// only — the driver-authorized Laravel payment record is written
  /// separately, since the rider isn't allowed to call that endpoint.
  /// This is what unblocks the driver's "rate the passenger" prompt.
  Future<void> markPaymentPaid(String method) async {
    paymentStatus.value = 'paid';
    paymentMethod.value = method;

    // 1. Real-time signal to the driver's app (unblocks their rating prompt).
    if (currentTripId.value.isNotEmpty) {
      try {
        await _firebaseService.updateTripPaymentStatus(currentTripId.value, 'paid', method);
      } catch (e) {
        debugPrint('Warning: could not sync payment status to Firestore: $e');
      }
    }

    // 2. Persist to Laravel directly from the passenger so the ride is marked
    //    paid immediately — this is what triggers the driver's earnings, and
    //    it no longer depends on the driver's app being open to relay it.
    //    Resolve the ride id from the trip id first if we don't already have it.
    try {
      final rideId = await _ensureLaravelRideId();
      if (rideId > 0) {
        await _apiService.updateRidePayment(rideId, {
          'payment_status': 'paid',
          'payment_method': method,
        });
      }
    } catch (e) {
      debugPrint('Warning: could not persist payment to Laravel: $e');
    }
  }

  /// Driver-side: once the rider has confirmed a CASH payment (seen via the
  /// Firestore signal above), persist it to Laravel — only the assigned
  /// driver is authorized to record a cash payment as received.
  Future<void> persistCashPaymentAsDriver() async {
    if (laravelRideId.value <= 0) return;
    try {
      await _apiService.updateRidePayment(laravelRideId.value, {
        'payment_status': 'paid',
        'payment_method': 'cash',
      });
    } catch (e) {
      debugPrint('Warning: could not persist cash payment: $e');
    }
  }

  /// Cancel the current trip. Returns the cancellation fee (0 if free).
  Future<double> cancelTrip({String reason = 'Cancelled by rider'}) async {
    double fee = 0;
    // Rider pays a fixed ৳50 fee once a driver is already assigned; a driver
    // cancelling at the same stage pays no fee but takes a reliability hit
    // on the backend (cancelled_rides_count + acceptance_rate) instead.
    final chargeable = tripStatus.value == 'accepted' ||
        tripStatus.value == 'arriving' ||
        tripStatus.value == 'in_progress';
    if (chargeable && currentRole.value != 'driver') fee = 50;

    // Update Laravel with reason
    if (laravelRideId.value > 0) {
      try {
        await _apiService.cancelRide(
          laravelRideId.value,
          reason: reason,
          cancelledBy: currentRole.value == 'driver' ? 'driver' : 'rider',
        );
      } catch (e) {
        // Timed out or unreachable — still fall through to reset local state
        // below so the UI never gets stuck on a permanent loading spinner.
        debugPrint('Warning: could not update ride status on server: $e');
      }
    }

    // Update Firestore ride_requests doc (dismisses all ringing drivers)
    if (_currentRideRequestId.isNotEmpty) {
      try {
        final coll = _firebaseService.rideRequests;
        if (coll != null) {
          await coll.doc(_currentRideRequestId).update({
            'status': 'cancelled',
            'cancelReason': reason,
            'cancelledAt': FieldValue.serverTimestamp(),
          });
        }
      } catch (e) {
        debugPrint('Warning: could not cancel ride request: $e');
      }
    }

    // Also cancel the active_trips doc so an assigned driver stops tracking
    if (currentTripId.value.isNotEmpty) {
      try {
        await _firebaseService.updateTripStatus(currentTripId.value, 'cancelled');
      } catch (e) {
        debugPrint('Warning: could not cancel active trip: $e');
      }
    }

    resetTrip();
    return fee;
  }

  /// Reset trip state
  void resetTrip() {
    _tripStream?.cancel();
    _driverLocationStream?.cancel();
    _currentRideRequestId = '';
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
    paymentStatus.value = 'pending';
    paymentMethod.value = '';
  }

  // ── Laravel IDs for rating submission ──
  final RxInt laravelRideId = 0.obs;
  final RxInt laravelDriverId = 0.obs;
}
