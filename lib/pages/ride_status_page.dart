import 'package:flutter/material.dart';
import 'dart:async';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'live_tracking_screen.dart';
import '../services/ride_service.dart';
import '../utils/marker_utils.dart';
import '../widgets/sos_helper.dart';

class RideStatusScreen extends StatefulWidget {
  final String rideType;
  final String pickup;
  final String destination;
  final double price;
  final double pickupLat;
  final double pickupLng;
  final double destLat;
  final double destLng;
  final double discount;
  final String? promoCode;

  const RideStatusScreen({
    super.key,
    required this.rideType,
    required this.pickup,
    required this.destination,
    required this.price,
    required this.pickupLat,
    required this.pickupLng,
    required this.destLat,
    required this.destLng,
    this.discount = 0,
    this.promoCode,
  });

  @override
  State<RideStatusScreen> createState() => _RideStatusScreenState();
}

class _RideStatusScreenState extends State<RideStatusScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  GoogleMapController? _mapController;
  bool _isDriverFound = false;
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStreamSubscription;
  Worker? _statusWorker;
  Timer? _searchTimeout;
  bool _leaving = false;

  // How long to keep searching before giving up (like Pathao/InDrive)
  static const int _searchTimeoutSeconds = 60;

  final RideService _rideService = Get.find<RideService>();
  BitmapDescriptor? _vehicleIcon;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _loadIcons();
    _startPositionTracking();
    _submitRideRequest();
    _startSearchTimeout();

    // Listen to real tripStatus from RideService
    _statusWorker = ever(_rideService.tripStatus, (String status) {
      if (!mounted) return;
      if (status == 'accepted' || status == 'arriving' || status == 'in_progress') {
        if (!_isDriverFound) {
          _isDriverFound = true;
          _pulseController.stop();
          _searchTimeout?.cancel(); // driver found — stop the countdown
          _leaving = true;

          // Go straight into live tracking the moment a driver accepts —
          // no "Driver Found" popup step, matching Uber/Pathao/inDrive/Obhai.
          Get.until((route) => route.isFirst);
          Get.to(() => LiveTrackingScreen(
                role: 'rider',
                rideType: widget.rideType,
                pickupAddress: widget.pickup,
                destinationAddress: widget.destination,
                price: widget.price,
                pickupLat: widget.pickupLat,
                pickupLng: widget.pickupLng,
                destLat: widget.destLat,
                destLng: widget.destLng,
              ));
        }
      } else if (status == 'cancelled') {
        _searchTimeout?.cancel();
        if (!_leaving) {
          _leaving = true;
          Get.back();
          Get.snackbar('Cancelled', 'This ride was cancelled.',
              backgroundColor: Colors.red, colorText: Colors.white);
        }
      }
    });
  }

  /// Auto-cancel the search if no driver accepts within the timeout window.
  void _startSearchTimeout() {
    _searchTimeout = Timer(const Duration(seconds: _searchTimeoutSeconds), () async {
      if (!mounted || _isDriverFound || _leaving) return;
      _leaving = true;
      await _rideService.cancelTrip(reason: 'No driver found in time');
      if (mounted) {
        Get.back();
        Get.snackbar(
          'No Drivers Available',
          'We couldn\'t find a driver nearby. Please try again.',
          backgroundColor: Colors.orange,
          colorText: Colors.white,
          duration: const Duration(seconds: 4),
        );
      }
    });
  }

  @override
  void dispose() {
    _searchTimeout?.cancel();
    _positionStreamSubscription?.cancel();
    _mapController?.dispose();
    _pulseController.dispose();
    _statusWorker?.dispose();
    super.dispose();
  }

  Future<void> _loadIcons() async {
    final String assetPath;
    switch (widget.rideType.toLowerCase()) {
      case 'motor':
      case 'bike':
        assetPath = 'assets/motor.png';
        break;
      case 'ambulance':
        assetPath = 'assets/ambulance.png';
        break;
      case 'rent_car':
        assetPath = 'assets/rent_car.png';
        break;
      default:
        assetPath = 'assets/car.png';
    }
    _vehicleIcon = await MarkerUtils.getBytesFromAsset(assetPath, 50);
    if (mounted) setState(() {});
  }

  Future<void> _submitRideRequest() async {
    await _rideService.requestRide(
      rideType: widget.rideType,
      pickupLat: widget.pickupLat,
      pickupLng: widget.pickupLng,
      pickupAddress: widget.pickup,
      destLat: widget.destLat,
      destLng: widget.destLng,
      destAddress: widget.destination,
      fare: widget.price,
    );
  }

  void _startPositionTracking() {
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );
    _positionStreamSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (Position position) {
        if (mounted) {
          setState(() => _currentPosition = position);
          _mapController?.animateCamera(
            CameraUpdate.newLatLng(
                LatLng(position.latitude, position.longitude)),
          );
        }
      },
    );
  }

  Future<void> _cancelRide() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Ride?'),
        content: const Text('Are you sure you want to cancel this request?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Yes, Cancel', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      _leaving = true;
      _searchTimeout?.cancel();
      try {
        await _rideService.cancelTrip(reason: 'Rider cancelled while searching');
      } catch (e) {
        // Fall through and leave anyway — never leave the rider stuck on
        // this screen because the cancel request timed out.
        debugPrint('Warning: cancel request failed: $e');
      }
      if (mounted) Get.back();
    }
  }

  /// Intercept leaving the screen. While still searching, leaving must
  /// cancel the request so drivers stop ringing. After a driver is found,
  /// leaving is allowed (the trip continues in Live Tracking).
  Future<bool> _onWillLeave() async {
    if (_isDriverFound || _leaving) return true;
    await _cancelRide();
    return false; // _cancelRide handles navigation itself
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _isDriverFound,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        await _onWillLeave();
      },
      child: Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          _buildMap(),
          // Top bar: back button (left) + SOS (right)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.white,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.black),
                      onPressed: _onWillLeave,
                    ),
                  ),
                  SosPillButton(
                    onTap: () => triggerSosFlow(
                      context,
                      rideId: _rideService.laravelRideId.value,
                      lat: _currentPosition?.latitude,
                      lng: _currentPosition?.longitude,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Bottom panel — stays on the searching state; the moment a driver
          // accepts we navigate straight into Live Tracking (see initState).
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _buildSearchingPanel(),
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildMap() {
    return Obx(() {
      final dLat = _rideService.driverLatitude.value;
      final dLng = _rideService.driverLongitude.value;
      final dHeading = _rideService.driverHeading.value;

      return GoogleMap(
        initialCameraPosition: CameraPosition(
          target: _currentPosition != null
              ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
              : LatLng(widget.pickupLat, widget.pickupLng),
          zoom: 15,
        ),
        onMapCreated: (controller) => _mapController = controller,
        myLocationEnabled: true,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: false,
        mapToolbarEnabled: false,
        markers: {
          if (_isDriverFound && dLat > 0)
            Marker(
              markerId: const MarkerId('driver'),
              position: LatLng(dLat, dLng),
              icon: _vehicleIcon ??
                  BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueGreen),
              rotation: dHeading,
              anchor: const Offset(0.5, 0.5),
            ),
          Marker(
            markerId: const MarkerId('pickup'),
            position: LatLng(widget.pickupLat, widget.pickupLng),
            infoWindow: InfoWindow(title: 'Pickup', snippet: widget.pickup),
          ),
        },
      );
    });
  }

  Widget _buildSearchingPanel() {
    return Container(
      key: const ValueKey('searching'),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              spreadRadius: 5),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pulsing search animation
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Outer pulse ring
                  Container(
                    width: 90 + 20 * _pulseController.value,
                    height: 90 + 20 * _pulseController.value,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF10713C)
                          .withValues(alpha: 0.08 * (1 - _pulseController.value)),
                    ),
                  ),
                  // Inner pulse ring
                  Container(
                    width: 80 + 10 * _pulseController.value,
                    height: 80 + 10 * _pulseController.value,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF10713C)
                          .withValues(alpha: 0.12 * (1 - _pulseController.value)),
                    ),
                  ),
                  // Car icon center
                  Container(
                    width: 70,
                    height: 70,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF10713C),
                    ),
                    child: const Icon(Icons.directions_car,
                        color: Colors.white, size: 36),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          const Text(
            'Finding your driver...',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Looking for nearby ${widget.rideType}s',
            style: TextStyle(color: Colors.grey[500], fontSize: 14),
          ),
          const SizedBox(height: 8),
          // Ride summary chips
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _chip(Icons.location_on_outlined, widget.pickup, Colors.green),
              const Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
              _chip(Icons.flag_outlined, widget.destination, Colors.red),
            ],
          ),
          const SizedBox(height: 8),
          // Fare + applied coupon chip
          Column(
            children: [
              Text(
                '৳${widget.price.toStringAsFixed(0)}',
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF10713C)),
              ),
              if (widget.discount > 0 && widget.promoCode != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.local_offer, size: 14, color: Colors.green),
                      const SizedBox(width: 6),
                      Text(
                        '${widget.promoCode} applied · −৳${widget.discount.toStringAsFixed(0)}',
                        style: const TextStyle(
                            fontSize: 12,
                            color: Colors.green,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton(
              onPressed: _cancelRide,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Cancel Request',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 90),
            child: Text(
              label,
              style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

}
