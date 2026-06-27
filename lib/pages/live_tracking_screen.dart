import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../services/ride_service.dart';
import '../services/routing_service.dart';
import '../services/voice_guidance_service.dart';
import '../services/sslcommerz_service.dart';
import '../services/api_service.dart';
import '../utils/marker_utils.dart';
import '../widgets/sos_helper.dart';
import 'package:goride/pages/chat_conversation_list_screen.dart';
import 'post_trip_rating_sheet.dart';

class LiveTrackingScreen extends StatefulWidget {
  final String rideType;
  final String pickupAddress;
  final String destinationAddress;
  final double price;
  final double pickupLat;
  final double pickupLng;
  final double destLat;
  final double destLng;
  /// 'driver' or 'rider' — controls which actions/buttons are shown
  final String role;
  final String? tripId;

  const LiveTrackingScreen({
    super.key,
    required this.rideType,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.price,
    required this.pickupLat,
    required this.pickupLng,
    required this.destLat,
    required this.destLng,
    this.role = 'rider',
    this.tripId,
  });

  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen> {
  final RideService _rideService = Get.find<RideService>();
  final RoutingService _routingService = RoutingService();
  final VoiceGuidanceService _voiceService = Get.find<VoiceGuidanceService>();

  GoogleMapController? _mapController;
  StreamSubscription<Position>? _positionSub;
  Position? _myPosition;

  Set<Polyline> _polylines = {};
  BitmapDescriptor? _driverIcon;
  BitmapDescriptor? _pickupIcon;
  BitmapDescriptor? _destIcon;

  List<NavigationStep> _navSteps = [];
  int _currentStepIndex = 0;
  bool _routeLoaded = false;
  bool _isCompleting = false;

  // Announced distance thresholds (metres)
  final Set<int> _announcedThresholds = {};
  String _lastKnownStatus = '';

  @override
  void initState() {
    super.initState();
    _loadIcons();
    _fetchRoute();
    _startPositionTracking();
    // Re-fetch route whenever trip status changes phase
    ever(_rideService.tripStatus, (String status) {
      if (status != _lastKnownStatus) {
        _lastKnownStatus = status;
        _onStatusChanged(status);
      }
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _mapController?.dispose();
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
      default:
        assetPath = 'assets/car.png';
    }
    _driverIcon = await MarkerUtils.getBytesFromAsset(assetPath, 52);
    _pickupIcon = await MarkerUtils.getBytesFromAsset('assets/pickup_pin.png', 48)
        .catchError((_) => BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen));
    _destIcon = await MarkerUtils.getBytesFromAsset('assets/dest_pin.png', 48)
        .catchError((_) => BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed));
    if (mounted) setState(() {});
  }

  /// Fetch route based on current trip phase.
  /// - arriving/accepted: driver → pickup (dashed blue)
  /// - in_progress:       pickup → destination (solid green)
  Future<void> _fetchRoute() async {
    final status = _rideService.tripStatus.value;
    final dLat = _rideService.driverLatitude.value;
    final dLng = _rideService.driverLongitude.value;

    final bool isPickupPhase =
        status == 'accepted' || status == 'arriving' || status == 'idle';

    final origin = (dLat > 0 && dLng > 0)
        ? LatLng(dLat, dLng)
        : LatLng(widget.pickupLat, widget.pickupLng);

    final destination = isPickupPhase
        ? LatLng(widget.pickupLat, widget.pickupLng)
        : LatLng(widget.destLat, widget.destLng);

    final result = await _routingService.getRoute(
      origin: origin,
      destination: destination,
    );

    if (result.route != null && mounted) {
      final Set<Polyline> newPolylines = {};

      if (isPickupPhase) {
        // Dashed blue: driver heading to pickup
        newPolylines.add(Polyline(
          polylineId: const PolylineId('pickup_route'),
          points: result.route!.points,
          color: const Color(0xFF1565C0),
          width: 4,
          patterns: [PatternItem.dash(20), PatternItem.gap(8)],
        ));
      } else {
        // Solid green: pickup → destination
        newPolylines.add(Polyline(
          polylineId: const PolylineId('trip_route'),
          points: result.route!.points,
          color: const Color(0xFF10713C),
          width: 5,
        ));
      }

      setState(() {
        _polylines = newPolylines;
        _navSteps = result.route!.steps;
        _routeLoaded = true;
      });

      if (_navSteps.isNotEmpty) {
        _voiceService.announceInstruction(_navSteps[0].cleanInstruction);
      }
      _fitBounds(result.route!.points);
    }
  }

  /// Called when trip status changes to re-draw the correct route.
  void _onStatusChanged(String status) {
    _currentStepIndex = 0;
    _announcedThresholds.clear();
    _fetchRoute();
  }

  void _fitBounds(List<LatLng> points) {
    if (points.isEmpty || _mapController == null) return;
    double minLat = points[0].latitude, maxLat = points[0].latitude;
    double minLng = points[0].longitude, maxLng = points[0].longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat - 0.005, minLng - 0.005),
          northeast: LatLng(maxLat + 0.005, maxLng + 0.005),
        ),
        60,
      ),
    );
  }

  void _startPositionTracking() {
    const settings = LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10);
    _positionSub = Geolocator.getPositionStream(locationSettings: settings).listen((pos) {
      if (!mounted) return;
      setState(() => _myPosition = pos);
      _checkStepAdvancement(pos);
      _checkDistanceAlerts(pos);
    });
  }

  void _checkStepAdvancement(Position pos) {
    if (_navSteps.isEmpty || _currentStepIndex >= _navSteps.length - 1) return;
    final step = _navSteps[_currentStepIndex];
    final distToEnd = Geolocator.distanceBetween(
      pos.latitude, pos.longitude,
      step.endLocation.latitude, step.endLocation.longitude,
    );
    if (distToEnd < 25) {
      setState(() => _currentStepIndex++);
      if (_currentStepIndex < _navSteps.length) {
        _voiceService.announceInstruction(_navSteps[_currentStepIndex].cleanInstruction);
      }
    }
  }

  void _checkDistanceAlerts(Position pos) {
    final distToDest = Geolocator.distanceBetween(
      pos.latitude, pos.longitude,
      widget.destLat, widget.destLng,
    );
    for (final threshold in [500, 200, 100]) {
      if (distToDest <= threshold && !_announcedThresholds.contains(threshold)) {
        _announcedThresholds.add(threshold);
        _voiceService.announceDistanceUpdate(
          instruction: _currentStepIndex < _navSteps.length
              ? _navSteps[_currentStepIndex].cleanInstruction
              : 'Destination ahead',
          distanceText: '${threshold} metres',
        );
      }
    }
    if (distToDest < 30 && !_announcedThresholds.contains(0)) {
      _announcedThresholds.add(0);
      _voiceService.announceArrival();
    }
  }

  void _recenterCamera() {
    if (_mapController == null) return;
    final dLat = _rideService.driverLatitude.value;
    final dLng = _rideService.driverLongitude.value;
    if (dLat > 0 && dLng > 0) {
      _mapController!.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: LatLng(dLat, dLng), zoom: 16, tilt: 30),
      ));
    } else if (_myPosition != null) {
      _mapController!.animateCamera(CameraUpdate.newLatLngZoom(
        LatLng(_myPosition!.latitude, _myPosition!.longitude), 16,
      ));
    }
  }

  void _handleChat() {
    Get.to(() => const ChatConversationListScreen());
  }

  void _handleCall() async {
    // Driver calls the customer; passenger calls the driver.
    final phone = widget.role == 'driver'
        ? _rideService.assignedRiderPhone.value
        : _rideService.assignedDriverPhone.value;
    final uri = Uri(scheme: 'tel', path: phone.isNotEmpty ? phone : '+8801234567890');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  // Task 50 — Share live tracking link
  Future<void> _handleShare() async {
    final rideId = _rideService.laravelRideId.value;
    if (rideId > 0) {
      try {
        final res = await Get.find<ApiService>().generateTrackingToken(rideId);
        if (res.statusCode == 200 && res.data['success'] == true) {
          final url = res.data['tracking_url'] as String;
          SharePlus.instance.share(ShareParams(
            text: 'Track my GoRide trip live 🚗\n'
                  'From: ${widget.pickupAddress}\n'
                  'To: ${widget.destinationAddress}\n'
                  'Live map: $url',
          ));
          return;
        }
      } catch (_) {}
    }
    // Fallback — share text only
    SharePlus.instance.share(ShareParams(
      text: 'I\'m on a GoRide trip!\n'
            'From: ${widget.pickupAddress}\n'
            'To: ${widget.destinationAddress}\n'
            'Fare: ৳${widget.price.toStringAsFixed(0)}',
    ));
  }

  // Task 49 — SOS Emergency Button (shared helper)
  Future<void> _triggerSos() async {
    await triggerSosFlow(
      context,
      rideId: _rideService.laravelRideId.value,
      lat: _myPosition?.latitude,
      lng: _myPosition?.longitude,
    );
  }

  // ── Driver staged action: Arrived → Start Trip → Complete ──

  /// Label for the driver's primary button based on current trip status.
  String _driverButtonLabel() {
    switch (_rideService.tripStatus.value) {
      case 'accepted':
        return "I've Arrived";
      case 'arriving':
        return 'Start Trip';
      case 'in_progress':
        return 'Complete Trip';
      default:
        return 'Complete Trip';
    }
  }

  /// Button color per stage — blue for "arrived", green for go/complete.
  Color _driverButtonColor() {
    return _rideService.tripStatus.value == 'accepted'
        ? const Color(0xFF1565C0)
        : const Color(0xFF10713C);
  }

  /// Advance the trip one stage forward (driver only).
  Future<void> _driverAdvanceStatus() async {
    final status = _rideService.tripStatus.value;
    setState(() => _isCompleting = true);

    if (status == 'accepted') {
      // Driver reached the pickup point
      await _rideService.updateStatus('arriving');
    } else if (status == 'arriving') {
      // Passenger is in — start the trip
      await _rideService.updateStatus('in_progress');
    } else if (status == 'in_progress') {
      // Trip finished
      await _rideService.updateStatus('completed');
      if (mounted) await _showRatingSheet();
      if (mounted) Get.back();
      return;
    } else {
      await _rideService.updateStatus('completed');
      if (mounted) Get.back();
      return;
    }

    if (mounted) setState(() => _isCompleting = false);
  }

  Future<void> _completeTripAsCash() async {
    // If rider role, show payment method picker first
    if (widget.role == 'rider') {
      await _showPaymentPicker();
    } else {
      // Driver just marks complete
      setState(() => _isCompleting = true);
      await _rideService.updateStatus('completed');
      if (mounted) Get.back();
    }
  }

  Future<void> _showPaymentPicker() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            const Text('Choose Payment Method', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              'Total: ৳${widget.price.toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 15, color: Color(0xFF10713C), fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            _payOption(ctx, 'cash', Icons.money, 'Cash', 'Pay driver directly'),
            const SizedBox(height: 10),
            _payOption(ctx, 'sslcommerz', Icons.credit_card, 'Card / Mobile Banking', 'SSLCommerz secure payment'),
          ],
        ),
      ),
    );

    if (choice == null || !mounted) return;

    if (choice == 'cash') {
      setState(() => _isCompleting = true);
      await _rideService.updateStatus('completed');
      if (mounted) await _showRatingSheet();
      if (mounted) Get.back();
    } else if (choice == 'sslcommerz') {
      await _payWithSSLCommerz();
    }
  }

  Widget _payOption(BuildContext ctx, String value, IconData icon, String title, String subtitle) {
    return GestureDetector(
      onTap: () => Navigator.pop(ctx, value),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF10713C).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: const Color(0xFF10713C)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  Text(subtitle, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Future<void> _payWithSSLCommerz() async {
    setState(() => _isCompleting = true);
    final user = Get.find<ApiService>().getUser();
    final sslService = Get.find<SslCommerzService>();

    final url = await sslService.initiatePayment(
      amount: widget.price,
      transactionId: 'RIDE_${DateTime.now().millisecondsSinceEpoch}',
      passengerName: user?['name'] ?? 'Passenger',
      passengerEmail: user?['email'] ?? 'passenger@goride.app',
      passengerPhone: user?['mobile'] ?? '01700000000',
    );

    if (url != null && mounted) {
      final launched = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (launched) {
        await _rideService.updateStatus('completed');
        if (mounted) await _showRatingSheet();
        if (mounted) Get.back();
      } else {
        setState(() => _isCompleting = false);
        Get.snackbar('Error', 'Could not open payment page.', backgroundColor: Colors.red, colorText: Colors.white);
      }
    } else {
      setState(() => _isCompleting = false);
      Get.snackbar('Payment Failed', 'Could not connect to payment gateway.', backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  Future<void> _showRatingSheet() async {
    final isDriver = widget.role == 'driver';
    final rideId = _rideService.laravelRideId.value;
    if (rideId <= 0) return;

    await showPostTripRating(
      context: context,
      mode: isDriver ? 'rate_rider' : 'rate_driver',
      rideRequestId: rideId,
      targetUserId: isDriver
          ? 0 // rider id — extend when available from rideService
          : _rideService.assignedDriverId.value.isNotEmpty
              ? int.tryParse(_rideService.assignedDriverId.value) ?? 0
              : 0,
      targetName: isDriver
          ? _rideService.assignedRiderName.value
          : _rideService.assignedDriverName.value,
    );
  }

  static const List<String> _cancelReasons = [
    'Driver taking too long',
    'Found another ride',
    'Changed my plans',
    'Wrong pickup location',
    'Price is too high',
    'Other',
  ];

  Future<void> _showCancelDialog() async {
    final status = _rideService.tripStatus.value;
    final isChargeable = status == 'accepted' || status == 'arriving' || status == 'in_progress';
    String? selectedReason;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            top: 8, left: 20, right: 20,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 16),
              const Text('Cancel Ride', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              if (isChargeable) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.red.shade600, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'A ৳50 cancellation fee applies because your driver is already on the way.',
                          style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Why are you cancelling?', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              ),
              const SizedBox(height: 8),
              ..._cancelReasons.map((r) => RadioListTile<String>(
                value: r,
                groupValue: selectedReason,
                title: Text(r, style: const TextStyle(fontSize: 14)),
                activeColor: const Color(0xFF10713C),
                dense: true,
                onChanged: (v) => setS(() => selectedReason = v),
              )),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Keep Ride'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: selectedReason == null ? null : () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        disabledBackgroundColor: Colors.grey[300],
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Cancel Ride', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true && selectedReason != null && mounted) {
      setState(() => _isCompleting = true);
      final fee = await _rideService.cancelTrip(reason: selectedReason!);
      if (mounted) {
        if (fee > 0) {
          Get.snackbar(
            'Ride Cancelled',
            '৳${fee.toStringAsFixed(0)} cancellation fee has been applied.',
            backgroundColor: Colors.orange,
            colorText: Colors.white,
            duration: const Duration(seconds: 4),
          );
        }
        Get.back();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _buildMap(),
          _buildTopBar(),
          _buildNavBanner(),
          _buildBottomPanel(),
          _buildRecenterButton(),
        ],
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
          target: LatLng(widget.pickupLat, widget.pickupLng),
          zoom: 15,
        ),
        onMapCreated: (c) {
          _mapController = c;
          if (_routeLoaded && _polylines.isNotEmpty) {
            _fitBounds(_polylines.first.points);
          }
        },
        myLocationEnabled: true,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: false,
        mapToolbarEnabled: false,
        polylines: _polylines,
        markers: {
          if (dLat > 0)
            Marker(
              markerId: const MarkerId('driver'),
              position: LatLng(dLat, dLng),
              icon: _driverIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
              rotation: dHeading,
              anchor: const Offset(0.5, 0.5),
              infoWindow: InfoWindow(
                title: widget.role == 'driver'
                    ? 'You'
                    : (_rideService.assignedDriverName.value.isNotEmpty
                        ? _rideService.assignedDriverName.value
                        : 'Driver'),
              ),
            ),
          Marker(
            markerId: const MarkerId('pickup'),
            position: LatLng(widget.pickupLat, widget.pickupLng),
            icon: _pickupIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
            infoWindow: InfoWindow(title: 'Pickup', snippet: widget.pickupAddress),
          ),
          Marker(
            markerId: const MarkerId('dest'),
            position: LatLng(widget.destLat, widget.destLng),
            icon: _destIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: InfoWindow(title: 'Destination', snippet: widget.destinationAddress),
          ),
        },
      );
    });
  }

  Widget _buildTopBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.white,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black87),
                onPressed: () => Get.back(),
              ),
            ),
            const Spacer(),
            Obx(() => Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8)],
              ),
              child: Row(
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: _rideService.tripStatus.value == 'in_progress'
                          ? Colors.green
                          : Colors.orange,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _statusLabel(_rideService.tripStatus.value),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            )),
            const SizedBox(width: 8),
            // Voice navigation control — only shown when enabled in Settings.
            Obx(() => _voiceService.isVoiceEnabled.value
                ? CircleAvatar(
                    backgroundColor: Colors.white,
                    child: IconButton(
                      icon: const Icon(Icons.volume_up, color: Color(0xFF10713C)),
                      tooltip: 'Voice navigation on',
                      onPressed: () {
                        _voiceService.setVoiceEnabled(false);
                        Get.snackbar(
                          'Voice Off',
                          'Re-enable voice navigation in Settings.',
                          snackPosition: SnackPosition.BOTTOM,
                          backgroundColor: Colors.black87,
                          colorText: Colors.white,
                          duration: const Duration(seconds: 3),
                        );
                      },
                    ),
                  )
                : const SizedBox.shrink()),
          ],
        ),
      ),
    );
  }

  Widget _buildNavBanner() {
    if (_navSteps.isEmpty || _currentStepIndex >= _navSteps.length) return const SizedBox.shrink();
    final step = _navSteps[_currentStepIndex];
    return Positioned(
      top: 90,
      left: 12,
      right: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF10713C),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 12)],
        ),
        child: Row(
          children: [
            Icon(step.maneuverIcon, color: Colors.white, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.cleanInstruction,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${step.distance.toStringAsFixed(1)} km · ${step.duration.toStringAsFixed(0)} min',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(
              '${_currentStepIndex + 1}/${_navSteps.length}',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.only(left: 12, right: 12, bottom: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20)],
        ),
        child: Obx(() => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Driver info row
            Row(
              children: [
                const CircleAvatar(
                  radius: 26,
                  backgroundColor: Color(0xFFE8F5E9),
                  child: Icon(Icons.person, color: Color(0xFF10713C), size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Driver sees the CUSTOMER (passenger); passenger sees the driver.
                      Text(
                        widget.role == 'driver'
                            ? (_rideService.assignedRiderName.value.isNotEmpty
                                ? _rideService.assignedRiderName.value
                                : 'Passenger')
                            : (_rideService.assignedDriverName.value.isNotEmpty
                                ? _rideService.assignedDriverName.value
                                : 'Your Driver'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        widget.role == 'driver' ? 'Passenger • ${widget.rideType}' : widget.rideType,
                        style: TextStyle(color: Colors.grey[500], fontSize: 13),
                      ),
                    ],
                  ),
                ),
                // Show rating badge only to the passenger (driver's rating).
                if (widget.role != 'driver')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10713C).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 16),
                        Text(
                          ' ${_rideService.assignedDriverRating.value.toStringAsFixed(1)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Route summary
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _routeRow(Icons.trip_origin, const Color(0xFF10713C), widget.pickupAddress),
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Container(height: 16, width: 2, color: Colors.grey[300]),
                  ),
                  _routeRow(Icons.location_on, Colors.red, widget.destinationAddress),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Fare + action buttons
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10713C).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '৳ ${widget.price.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: Color(0xFF10713C),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                const Spacer(),
                _iconBtn(Icons.chat_bubble_outline, 'Chat', _handleChat),
                const SizedBox(width: 8),
                _iconBtn(Icons.call_outlined, 'Call', _handleCall),
                const SizedBox(width: 8),
                _iconBtn(Icons.share_outlined, 'Share', () => _handleShare()),
                const SizedBox(width: 8),
                // SOS — only for rider
                if (widget.role == 'rider')
                  GestureDetector(
                    onTap: _triggerSos,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.shade300),
                          ),
                          child: const Icon(Icons.sos, size: 20, color: Colors.red),
                        ),
                        const SizedBox(height: 3),
                        const Text('SOS', style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Primary action + Cancel buttons
            Builder(builder: (_) {
              final status = _rideService.tripStatus.value;
              final isDriver = widget.role == 'driver';
              // Cancel allowed before the trip starts (not once in_progress/completed)
              final canCancel = status == 'accepted' || status == 'arriving';

              final primaryLabel = isDriver
                  ? _driverButtonLabel()
                  : 'Complete Trip (Cash)';
              final primaryColor = isDriver
                  ? _driverButtonColor()
                  : const Color(0xFF10713C);
              final primaryAction =
                  isDriver ? _driverAdvanceStatus : _completeTripAsCash;

              return Row(
                children: [
                  if (canCancel) ...[
                    Expanded(
                      flex: 2,
                      child: OutlinedButton(
                        onPressed: _isCompleting ? null : _showCancelDialog,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Cancel', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    flex: 3,
                    child: ElevatedButton(
                      onPressed: _isCompleting ? null : primaryAction,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        disabledBackgroundColor: Colors.grey[300],
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _isCompleting
                          ? const SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              primaryLabel,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                    ),
                  ),
                ],
              );
            }),
          ],
        )),
      ),
    );
  }

  Widget _buildRecenterButton() {
    return Positioned(
      right: 16,
      bottom: 240,
      child: FloatingActionButton.small(
        heroTag: 'recenter',
        backgroundColor: Colors.white,
        onPressed: _recenterCamera,
        child: const Icon(Icons.my_location, color: Color(0xFF10713C)),
      ),
    );
  }

  Widget _routeRow(IconData icon, Color color, String label) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _iconBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: Colors.black87),
          ),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'accepted': return 'Driver Accepted';
      case 'arriving': return 'Driver Arriving';
      case 'in_progress': return 'On the Way';
      case 'completed': return 'Completed';
      default: return 'Live Tracking';
    }
  }
}
