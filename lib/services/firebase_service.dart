import 'package:firebase_auth/firebase_auth.dart';
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

      // Mark Firestore as ready BEFORE attempting auth
      // so a failed auth never breaks the ride request stream.
      _initialized = true;
      debugPrint('Firebase initialized successfully');

      // Try anonymous sign-in so Firestore rules (request.auth != null) pass.
      // This is optional — if Anonymous Auth is not enabled in Firebase Console
      // the sign-in fails silently and Firestore still works with open rules.
      _signInAnonymouslySafe();
    } catch (e) {
      _initialized = false;
      _firestore = null;
      debugPrint('Firebase initialization error: $e');
      // Don't rethrow here to allow app to run in "offline/limited" mode
    }
  }

  /// Sign in anonymously so Firestore security rules that check
  /// `request.auth != null` pass. Fails silently if Anonymous Auth
  /// is not enabled in the Firebase Console — Firestore still works.
  Future<void> _signInAnonymouslySafe() async {
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
        debugPrint('Firebase anonymous auth OK: ${FirebaseAuth.instance.currentUser?.uid}');
      }
    } catch (e) {
      // Anonymous Auth not enabled in Firebase Console — that's fine.
      // Set Firestore rules to "allow read, write: if true" for dev,
      // or enable Anonymous Auth in Firebase Console → Authentication.
      debugPrint('Firebase anonymous auth skipped: $e');
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
    String? vehicleType,
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
      'vehicleType': vehicleType ?? 'car',
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
    String? riderPhone,
  }) async {
    final coll = activeTrips;
    if (coll == null) return null;

    final docRef = await coll.add({
      'riderId': riderId,
      'driverId': '',
      'riderName': riderName,
      'riderPhone': riderPhone ?? '',
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
  Future<void> assignDriverToTrip(
    String tripId,
    String driverId, {
    String? driverName,
    String? driverPhone,
    double? driverRating,
  }) async {
    final coll = activeTrips;
    if (coll == null) return;

    await coll.doc(tripId).update({
      'driverId': driverId,
      'driverName': driverName ?? 'Driver',
      'driverPhone': driverPhone ?? '',
      'driverRating': driverRating ?? 4.8,
      'status': 'accepted',
      'acceptedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Create a ride request (for drivers to find)
  Future<String?> createRideRequest({
    required String riderId,
    required String riderName,
    required String rideType,
    required double pickupLat,
    required double pickupLng,
    required String pickupAddress,
    required double destLat,
    required double destLng,
    required String destAddress,
    required String tripId,
    required double fare,
    String? riderPhone,
  }) async {
    final coll = rideRequests;
    if (coll == null) return null;

    final docRef = await coll.add({
      'riderId': riderId,
      'riderName': riderName,
      'riderPhone': riderPhone ?? '',
      'rideType': rideType,
      'pickupLatitude': pickupLat,
      'pickupLongitude': pickupLng,
      'pickupAddress': pickupAddress,
      'destLatitude': destLat,
      'destLongitude': destLng,
      'destAddress': destAddress,
      'tripId': tripId,
      'fare': fare,
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
