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

      // CRITICAL: sign in anonymously and WAIT for it BEFORE marking Firestore
      // ready. Our security rules require `request.auth != null`, so any write
      // that happens before auth is established would be DENIED (empty data).
      await _signInAnonymouslySafe();

      _initialized = true;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        debugPrint('⚠️ Firebase ready BUT NOT signed in. '
            'Enable Anonymous Auth in Firebase Console — Firestore writes will be denied.');
      } else {
        debugPrint('Firebase initialized + signed in (uid: $uid)');
      }
    } catch (e) {
      _initialized = false;
      _firestore = null;
      debugPrint('Firebase initialization error: $e');
      // Don't rethrow here to allow app to run in "offline/limited" mode
    }
  }

  /// Ensure there is a signed-in Firebase user so security rules that check
  /// `request.auth != null` pass. Retries briefly; logs clearly if Anonymous
  /// Auth is not enabled in the Firebase Console.
  Future<void> _signInAnonymouslySafe() async {
    try {
      if (FirebaseAuth.instance.currentUser != null) return;
      final cred = await FirebaseAuth.instance.signInAnonymously();
      debugPrint('Firebase anonymous auth OK: ${cred.user?.uid}');
    } catch (e) {
      // Most common cause: Anonymous Auth is DISABLED in the Firebase Console.
      // Console → Build → Authentication → Sign-in method → Anonymous → Enable.
      debugPrint('❌ Firebase anonymous sign-in FAILED: $e');
    }
  }

  /// Public guard: make sure we are signed in before a Firestore write.
  /// Call this defensively from write paths so a dropped session re-auths.
  Future<bool> ensureSignedIn() async {
    if (FirebaseAuth.instance.currentUser != null) return true;
    await _signInAnonymouslySafe();
    return FirebaseAuth.instance.currentUser != null;
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
    await ensureSignedIn(); // rules require an auth'd session
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
    await ensureSignedIn(); // rules require an auth'd session
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

  /// Mark the trip's payment as settled — this is the signal the driver's
  /// app watches for to know the rider has paid and it's safe to show the
  /// "rate the passenger" prompt (real-time, since driver and rider are on
  /// separate devices with no other shared channel once the trip ends).
  Future<void> updateTripPaymentStatus(String tripId, String paymentStatus, String paymentMethod) async {
    final coll = activeTrips;
    if (coll == null) return;

    await coll.doc(tripId).update({
      'paymentStatus': paymentStatus,
      'paymentMethod': paymentMethod,
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
    await ensureSignedIn(); // rules require an auth'd session
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

  /// Listen to a single ride request document (used by the incoming-call
  /// screen so it can auto-dismiss the moment another driver takes the ride).
  Stream<DocumentSnapshot>? streamRideRequestDoc(String requestId) {
    final coll = rideRequests;
    if (coll == null) return null;
    return coll.doc(requestId).snapshots();
  }

  /// Atomically claim a ride request. Only the FIRST driver to claim wins —
  /// the transaction only succeeds if the ride is still 'pending'.
  /// Returns true if this driver got it, false if someone else already did.
  Future<bool> claimRideRequest(String requestId, String driverId) async {
    final db = firestore;
    final coll = rideRequests;
    if (db == null || coll == null) return false;

    final docRef = coll.doc(requestId);
    try {
      final claimed = await db.runTransaction<bool>((txn) async {
        final snap = await txn.get(docRef);
        if (!snap.exists) return false;
        final data = snap.data() as Map<String, dynamic>?;
        final status = data?['status'] as String?;
        // Already taken / cancelled → cannot claim
        if (status != 'pending') return false;

        txn.update(docRef, {
          'status': 'accepted',
          'driverId': driverId,
          'acceptedAt': FieldValue.serverTimestamp(),
        });
        return true;
      });
      return claimed;
    } catch (e) {
      debugPrint('claimRideRequest error: $e');
      return false;
    }
  }

  /// Accept a ride request (driver) — non-atomic legacy path.
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
