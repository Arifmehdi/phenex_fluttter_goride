import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:goride/pages/chat_conversation_list_screen.dart';
import 'package:goride/pages/live_tracking_screen.dart';
import 'package:goride/services/api_service.dart';

class DeepLinkService extends GetxService {
  final _appLinks = AppLinks();

  @override
  void onInit() {
    super.onInit();
    _handleInitialLink();
    _listenForLinks();
  }

  Future<void> _handleInitialLink() async {
    try {
      final uri = await _appLinks.getInitialLink();
      if (uri != null) _route(uri);
    } catch (e) {
      debugPrint('Deep link initial error: $e');
    }
  }

  void _listenForLinks() {
    _appLinks.uriLinkStream.listen(
      (uri) => _route(uri),
      onError: (e) => debugPrint('Deep link stream error: $e'),
    );
  }

  Future<void> _route(Uri uri) async {
    debugPrint('Deep link received: $uri');
    // goride://chat  →  open conversation list
    if (uri.host == 'chat') {
      Get.to(() => const ChatConversationListScreen());
      return;
    }
    // goride://track/RIDE_ID  →  open live tracking for that ride
    if (uri.host == 'track') {
      final rideId = int.tryParse(
        uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '',
      );
      if (rideId == null) {
        Get.offAllNamed('/home');
        return;
      }
      await _openTracking(rideId);
      return;
    }
  }

  /// Fetch the ride's details, then open the live-tracking map for it. Used by
  /// the `goride://track/{id}` deep link (e.g. tapped from a shared trip link
  /// or a notification) so the recipient lands straight on the live map.
  Future<void> _openTracking(int rideId) async {
    final api = Get.find<ApiService>();

    // Must be signed in — the detail endpoint is auth-protected.
    if (!api.isLoggedInState) {
      Get.offAllNamed('/login');
      return;
    }

    try {
      final res = await api.getRideDetail(rideId);
      final data = res.data is Map ? res.data['data'] : null;
      if (res.statusCode != 200 || data == null) {
        Get.snackbar('Ride not found',
            'This trip link is no longer valid or you do not have access.',
            backgroundColor: Colors.red, colorText: Colors.white);
        return;
      }

      double d(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0.0;

      // Rider vs driver changes which controls the tracking screen shows.
      final storedRole = GetStorage().read('role')?.toString();
      final role = storedRole == 'driver' ? 'driver' : 'rider';

      Get.to(() => LiveTrackingScreen(
            role: role,
            rideType: data['ride_type']?.toString() ?? 'car',
            pickupAddress: data['pickup_address']?.toString() ?? '',
            destinationAddress: data['destination_address']?.toString() ?? '',
            price: d(data['fare']),
            pickupLat: d(data['pickup_latitude']),
            pickupLng: d(data['pickup_longitude']),
            destLat: d(data['destination_latitude']),
            destLng: d(data['destination_longitude']),
            tripId: data['firebase_trip_id']?.toString(),
          ));
    } catch (e) {
      debugPrint('Deep link track error: $e');
      Get.snackbar('Error', 'Could not open trip tracking. Please try again.',
          backgroundColor: Colors.red, colorText: Colors.white);
    }
  }
}
