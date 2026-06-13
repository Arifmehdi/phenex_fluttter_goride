import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

class FirebaseService extends GetxService {
  FirebaseFirestore? _firestore;
  bool _initialized = false;

  FirebaseFirestore? get firestore {
    if (!_initialized || _firestore == null) {
      debugPrint('WARNING: Firebase not initialized. Firestore access ignored.');
      return null;
    }
    return _firestore!;
  }

  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;

    try {
      // Basic check for Firebase configuration if on mobile
      if (!kIsWeb) {
        // This is a soft check, actual init will throw if missing
      }

      await Firebase.initializeApp();
      _firestore = FirebaseFirestore.instance;
      
      // Enable offline persistence for better reliability
      _firestore!.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: 100_000_000, // 100MB
      );
      
      _initialized = true;
      debugPrint('Firebase initialized successfully');
    } catch (e) {
      _initialized = false;
      _firestore = null;
      debugPrint('Firebase initialization error: $e');
      // Don't rethrow here to allow app to run in "offline/limited" mode
    }
  }

  // Driver locations collection
  CollectionReference? get driverLocations =>
      firestore?.collection('driver_locations');

  // Active trips collection
  CollectionReference? get activeTrips =>
      firestore?.collection('active_trips');

  // Ride requests collection
  CollectionReference? get rideRequests =>
      firestore?.collection('ride_requests');

  /// Update driver's current location in Firestore
  Future<void> updateDriverLocation({
    required String driverId,
    required double latitude,
    required double longitude,
    required double heading,
    required double speed,
    required bool isOnline,
    String? currentTripId,
  }) async {
    final coll = driverLocations;
    if (coll == null) return;
    
    await coll.doc(driverId).set({
      'latitude': latitude,
      'longitude': longitude,
      'heading': heading,
      'speed': speed,
      'isOnline': isOnline,
      'currentTripId': currentTripId ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Stream driver location updates
  Stream<DocumentSnapshot> streamDriverLocation(String driverId) {
    final coll = driverLocations;
    if (coll == null) return const Stream.empty();
    return coll.doc(driverId).snapshots();
  }

  /// Create a new trip in Firestore
  Future<String?> createTrip({
    required String riderId,
    required String riderName,
    required String rideType,
    required double pickupLat,
    required double pickupLng,
    required String pickupAddress,
    required double destLat,
    required double destLng,
    required String destAddress,
    required double fare,
  }) async {
    final coll = activeTrips;
    if (coll == null) return null;

    final docRef = await coll.add({
      'riderId': riderId,
      'driverId': '',
      'riderName': riderName,
      'rideType': rideType,
      'pickupLatitude': pickupLat,
      'pickupLongitude': pickupLng,
      'pickupAddress': pickupAddress,
      'destLatitude': destLat,
      'destLongitude': destLng,
      'destAddress': destAddress,
      'status': 'requesting', // requesting -> accepted -> arriving -> in_progress -> completed
      'fare': fare,
      'createdAt': FieldValue.serverTimestamp(),
      'acceptedAt': null,
    });
    return docRef.id;
  }

  /// Stream trip status
  Stream<DocumentSnapshot> streamTrip(String tripId) {
    final coll = activeTrips;
    if (coll == null) return const Stream.empty();
    return coll.doc(tripId).snapshots();
  }

  /// Update trip status
  Future<void> updateTripStatus(String tripId, String status) async {
    final coll = activeTrips;
    if (coll == null) return;

    await coll.doc(tripId).update({
      'status': status,
      if (status == 'accepted') 'acceptedAt': FieldValue.serverTimestamp(),
      if (status == 'in_progress') 'startedAt': FieldValue.serverTimestamp(),
      if (status == 'completed') 'completedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Assign driver to trip
  Future<void> assignDriverToTrip(String tripId, String driverId) async {
    final coll = activeTrips;
    if (coll == null) return;

    await coll.doc(tripId).update({
      'driverId': driverId,
      'status': 'accepted',
      'acceptedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Create a ride request (for drivers to find)
  Future<String?> createRideRequest({
    required String riderId,
    required String riderName,
    required double pickupLat,
    required double pickupLng,
    required String pickupAddress,
    required double destLat,
    required double destLng,
    required String destAddress,
    required String tripId,
  }) async {
    final coll = rideRequests;
    if (coll == null) return null;

    final docRef = await coll.add({
      'riderId': riderId,
      'riderName': riderName,
      'pickupLatitude': pickupLat,
      'pickupLongitude': pickupLng,
      'pickupAddress': pickupAddress,
      'destLatitude': destLat,
      'destLongitude': destLng,
      'destAddress': destAddress,
      'tripId': tripId,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  /// Stream nearby ride requests (for drivers)
  Stream<QuerySnapshot> streamPendingRequests() {
    final coll = rideRequests;
    if (coll == null) return const Stream.empty();

    return coll
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Accept a ride request (driver)
  Future<void> acceptRideRequest(String requestId, String driverId) async {
    final coll = rideRequests;
    if (coll == null) return;

    await coll.doc(requestId).update({
      'status': 'accepted',
      'driverId': driverId,
      'acceptedAt': FieldValue.serverTimestamp(),
    });
  }
}
