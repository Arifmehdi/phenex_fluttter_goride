import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../services/ride_service.dart';
import '../services/routing_service.dart';
import '../services/sslcommerz_service.dart';
import '../services/api_service.dart';
import '../utils/marker_utils.dart';
import '../utils/num_utils.dart';
import '../widgets/sos_helper.dart';
import 'package:goride/pages/chat_conversation_list_screen.dart';
import 'trip_chat_screen.dart';
import 'post_trip_rating_sheet.dart';
import 'dashboard_page.dart';
import 'home_page.dart';

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

  /// Driver-only: while heading to pickup, the bottom panel starts collapsed
  /// (pickup address + status pill) and expands to full details on tap.
  bool _pickupPanelExpanded = false;

  // Live ETA + distance to the current target (pickup or destination)
  double _etaMinutes = 0;
  double _distanceKm = 0;
  DateTime _lastRouteFetch = DateTime.fromMillisecondsSinceEpoch(0);
  Worker? _statusWorker;
  Timer? _etaTimer;
  Worker? _paymentWorker;
  bool _ratingShownForPayment = false;

  String _lastKnownStatus = '';

  @override
  void initState() {
    super.initState();
    _loadIcons();
    _fetchRoute();
    _startPositionTracking();

    // Cache the ride AFTER the current frame — this mutates Rx values that the
    // dashboard's "ongoing ride" Obx watches, and doing it during build throws
    // "setState/markNeedsBuild called during build".
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _rideService.cacheActiveRide(
        role: widget.role,
        rideType: widget.rideType,
        pickupAddress: widget.pickupAddress,
        destAddress: widget.destinationAddress,
        fare: widget.price,
        pickupLat: widget.pickupLat,
        pickupLng: widget.pickupLng,
        destLat: widget.destLat,
        destLng: widget.destLng,
      );
    });

    // Re-fetch route whenever trip status changes phase
    _statusWorker = ever(_rideService.tripStatus, (String status) {
      if (status != _lastKnownStatus) {
        _lastKnownStatus = status;
        _onStatusChanged(status);
      }
    });

    // Live ETA: refresh the route on a timer (not a reactive ever, which could
    // fire mid-build). Keeps the pickup/destination ETA current as the driver moves.
    _etaTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && _rideService.tripStatus.value != 'completed') {
        _fetchRoute();
      }
    });

    // Driver only: the moment the rider confirms payment (signalled via
    // Firestore — see RideService.markPaymentPaid), persist a cash payment
    // to Laravel if that's how they paid, then show the "rate the
    // passenger" prompt and close the screen — matching Uber/Pathao/
    // Obhai/InDrive, where the driver only rates after payment settles.
    if (widget.role == 'driver') {
      _paymentWorker = ever(_rideService.paymentStatus, (String status) async {
        if (status == 'paid' && !_ratingShownForPayment && mounted) {
          _ratingShownForPayment = true;
          if (_rideService.paymentMethod.value == 'cash') {
            await _rideService.persistCashPaymentAsDriver();
          }
          if (mounted) await _showRatingSheet();
          // Clear the finished ride's cached state so the dashboard's
          // wallet/earnings refresh (and the next ride starts clean).
          _rideService.resetTrip();
          if (mounted) Get.back();
        }
      });
    }
  }

  /// Minimize the trip — return to the correct home for this role. The ride
  /// stays live (RideService), and the "ongoing ride" bar there reopens it.
  void _minimizeToDashboard() {
    if (widget.role == 'driver') {
      Get.offAll(() => const UnifiedDashboard(role: 'driver'));
    } else {
      Get.offAll(() => const HomePage());
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _statusWorker?.dispose();
    _paymentWorker?.dispose();
    _etaTimer?.cancel();
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
    // The pickup marker represents the waiting passenger — use the passenger icon.
    _pickupIcon = await MarkerUtils.getBytesFromAsset('assets/passenger.png', 56)
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
        _etaMinutes = result.route!.duration;   // minutes
        _distanceKm = result.route!.distance;    // km
      });
      _lastRouteFetch = DateTime.now();
      _fitBounds(result.route!.points);
    }
  }

  /// Called when trip status changes to re-draw the correct route.
  void _onStatusChanged(String status) {
    _currentStepIndex = 0;

    // The OTHER party cancelled (synced via the shared Firestore trip doc) —
    // end the trip on this side too: notify, clear state, return home.
    // _isCompleting is true when WE initiated the cancel; that flow already
    // handles its own navigation, so skip to avoid a double pop.
    if (status == 'cancelled') {
      if (!_isCompleting && mounted) {
        _rideService.resetTrip();
        _minimizeToDashboard();
        Get.snackbar(
          'Trip Cancelled',
          widget.role == 'driver'
              ? 'The passenger has cancelled this trip.'
              : 'Your driver has cancelled this trip.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
          duration: const Duration(seconds: 4),
        );
      }
      return;
    }

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
    final tripId = _rideService.currentTripId.value;
    if (tripId.isEmpty) {
      // No live trip context — fall back to the general inbox.
      Get.to(() => const ChatConversationListScreen());
      return;
    }

    final isDriver = widget.role == 'driver';
    final myName = Get.find<ApiService>().getUser()?['name']?.toString() ??
        (isDriver ? 'Driver' : 'Passenger');
    final otherName = isDriver
        ? (_rideService.assignedRiderName.value.isNotEmpty
            ? _rideService.assignedRiderName.value
            : 'Passenger')
        : (_rideService.assignedDriverName.value.isNotEmpty
            ? _rideService.assignedDriverName.value
            : 'Your Driver');
    final otherPhone = isDriver
        ? _rideService.assignedRiderPhone.value
        : _rideService.assignedDriverPhone.value;

    Get.to(() => TripChatScreen(
          tripId: tripId,
          myRole: isDriver ? 'driver' : 'rider',
          myName: myName,
          otherName: otherName,
          otherPhone: otherPhone,
        ));
  }

  /// "Customer Details" (for the driver) / "Driver Details" (for the rider) —
  /// same popup UI on both sides, just filled with whichever party is relevant.
  void _showPartyDetailsSheet() {
    final isDriver = widget.role == 'driver';
    final name = isDriver
        ? (_rideService.assignedRiderName.value.isNotEmpty
            ? _rideService.assignedRiderName.value
            : 'Passenger')
        : (_rideService.assignedDriverName.value.isNotEmpty
            ? _rideService.assignedDriverName.value
            : 'Your Driver');
    final phone = isDriver
        ? _rideService.assignedRiderPhone.value
        : _rideService.assignedDriverPhone.value;
    final rating = _rideService.assignedDriverRating.value;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(
          20, 10, 20, 24 + MediaQuery.of(ctx).padding.bottom,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: _sheetGrabHandle()),
            const SizedBox(height: 8),
            Text(isDriver ? 'Customer Details' : 'Driver Details',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 18),
            Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: const Color(0xFFE8F5E9),
                  backgroundImage:
                      isDriver ? const AssetImage('assets/passenger.png') : null,
                  child: isDriver
                      ? null
                      : const Icon(Icons.person, color: Color(0xFF10713C), size: 34),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      if (!isDriver)
                        Row(
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 16),
                            const SizedBox(width: 4),
                            Text(rating.toStringAsFixed(1),
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            const SizedBox(width: 10),
                            Text(widget.rideType,
                                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                          ],
                        )
                      else
                        Text(widget.rideType,
                            style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                      if (phone.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.phone, size: 14, color: Colors.grey[500]),
                            const SizedBox(width: 6),
                            Text(phone,
                                style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
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
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _handleChat();
                    },
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: const Text('Chat'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF10713C),
                      side: const BorderSide(color: Color(0xFF10713C)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _handleCall();
                    },
                    icon: const Icon(Icons.call, size: 18, color: Colors.white),
                    label: const Text('Call', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10713C),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
            // Cancel Trip — available to BOTH passenger and driver while the
            // trip hasn't started yet. Opens the same reason/confirm dialog
            // (rider sees the ৳50 fee warning, driver the reliability warning).
            if (_rideService.tripStatus.value == 'accepted' ||
                _rideService.tripStatus.value == 'arriving') ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showCancelDialog();
                  },
                  icon: const Icon(Icons.close_rounded, color: Colors.red, size: 20),
                  label: const Text(
                    'Cancel This Trip',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.red.shade50,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: Colors.red.shade200),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
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

  /// Opens the phone's Google Maps app (or web fallback) for turn-by-turn
  /// navigation to the current target — pickup while heading there, else destination.
  Future<void> _launchExternalNavigation() async {
    final isPickupPhase = _rideService.tripStatus.value == 'accepted' ||
        _rideService.tripStatus.value == 'arriving';
    final lat = isPickupPhase ? widget.pickupLat : widget.destLat;
    final lng = isPickupPhase ? widget.pickupLng : widget.destLng;

    final nativeUri = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    final webUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
    );

    if (await canLaunchUrl(nativeUri)) {
      await launchUrl(nativeUri);
    } else {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
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
      case 'completed':
        return 'Waiting for Payment';
      default:
        return 'Complete Trip';
    }
  }

  /// Button color per stage — blue for "arrived", grey while waiting for
  /// the rider to pay, green otherwise.
  Color _driverButtonColor() {
    final status = _rideService.tripStatus.value;
    if (status == 'accepted') return const Color(0xFF1565C0);
    if (status == 'completed') return Colors.grey.shade400;
    return const Color(0xFF10713C);
  }

  /// Driver taps the primary trip button — inserts a "Start the trip?"
  /// Yes/No confirmation only for the arriving → in_progress step; every
  /// other stage advances immediately as before.
  Future<void> _handleDriverPrimaryTap() async {
    if (_rideService.tripStatus.value == 'arriving') {
      final confirmed = await _showStartTripConfirmation();
      if (confirmed != true) return;
    }
    await _driverAdvanceStatus();
  }

  Future<bool?> _showStartTripConfirmation() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Start the trip?'),
        content: const Text('Make sure the passenger is in the vehicle before you begin.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10713C),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Yes, Start', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
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
      // Trip finished — the rider now sees a payment prompt, and this
      // screen waits (see the paymentStatus worker in initState) before
      // showing the driver's own rating prompt and closing.
      await _rideService.updateStatus('completed');
    } else {
      return;
    }

    if (mounted) setState(() => _isCompleting = false);
  }

  Future<void> _showPaymentPicker() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(
          20, 8, 20, 24 + MediaQuery.of(ctx).padding.bottom,
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
            const Text('Choose Payment Method', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              'Total: ৳${widget.price.toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 15, color: Color(0xFF10713C), fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            _payOption(ctx, 'cash', Icons.money, 'Cash', 'Pay driver directly'),
            const SizedBox(height: 10),
            _payOption(ctx, 'wallet', Icons.account_balance_wallet, 'Wallet', 'Pay from your GoRide balance'),
            const SizedBox(height: 10),
            _payOption(ctx, 'split', Icons.call_split, 'Split (Wallet + Cash)', 'Use your balance, pay the rest in cash'),
            const SizedBox(height: 10),
            _payOption(ctx, 'sslcommerz', Icons.credit_card, 'Card / Mobile Banking', 'SSLCommerz secure payment'),
          ],
        ),
      ),
    );

    if (choice == null || !mounted) return;

    if (choice == 'wallet') {
      await _payWithWallet();
      return;
    }

    if (choice == 'split') {
      await _paySplit();
      return;
    }

    if (choice == 'cash') {
      // Rider hands over cash directly — this signals the driver (who is
      // waiting on the previous screen) that payment is settled, so their
      // app can show the "rate the passenger" prompt. The driver's own app
      // persists the actual Laravel payment record, since only the
      // assigned driver is authorized to confirm cash was received.
      setState(() => _isCompleting = true);
      await _rideService.markPaymentPaid('cash');
      if (mounted) await _showRatingSheet();
      _rideService.resetTrip();
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

  Future<void> _payWithWallet() async {
    setState(() => _isCompleting = true);
    final api = Get.find<ApiService>();
    final rideId = await _rideService.resolveRideId();
    if (rideId <= 0) {
      if (mounted) {
        setState(() => _isCompleting = false);
        Get.snackbar('Error', 'Could not identify the ride. Please use Cash or Card.',
            backgroundColor: Colors.red, colorText: Colors.white);
      }
      return;
    }
    try {
      final res = await api.payRideWithWallet(rideId, widget.price);
      final ok = res.statusCode == 200 &&
          (res.data is Map && res.data['success'] == true);
      if (ok) {
        // payRideWithWallet already debited the wallet, marked the ride paid,
        // and credited the driver. Sync Firestore + reactive state, then close.
        await _rideService.markPaymentPaid('wallet');
        if (mounted) await _showRatingSheet();
        _rideService.resetTrip();
        if (mounted) Get.back();
      } else {
        final msg = (res.data is Map ? res.data['message'] : null) ??
            'Wallet payment failed';
        if (mounted) {
          setState(() => _isCompleting = false);
          Get.snackbar('Payment failed', msg.toString(),
              backgroundColor: Colors.red, colorText: Colors.white);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCompleting = false);
        Get.snackbar('Error', 'Wallet payment failed. Please try again.',
            backgroundColor: Colors.red, colorText: Colors.white);
      }
    }
  }

  /// Split payment: use whatever wallet balance is available, driver
  /// collects the remaining fare in cash. Common in Bangladesh apps where
  /// riders keep a small wallet balance and top up with cash.
  Future<void> _paySplit() async {
    final api = Get.find<ApiService>();

    // How much is in the wallet right now?
    double balance = 0;
    try {
      final res = await api.getWalletBalance();
      if (res.statusCode == 200 && res.data is Map) {
        balance = parseApiDouble(res.data['balance']);
      }
    } catch (_) {}

    if (balance <= 0) {
      Get.snackbar('Empty wallet', 'Nothing to split — pay by Cash or top up first.',
          backgroundColor: Colors.orange, colorText: Colors.white);
      return;
    }

    final walletPart = balance >= widget.price ? widget.price : balance;
    final cashPart = widget.price - walletPart;

    // Confirm the split before charging.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Split payment'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _splitRow('From wallet', walletPart),
          const SizedBox(height: 6),
          _splitRow('Cash to driver', cashPart),
          const Divider(height: 20),
          _splitRow('Total', widget.price, bold: true),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10713C)),
            child: const Text('Confirm', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _isCompleting = true);
    final rideId = await _rideService.resolveRideId();
    if (rideId <= 0) {
      if (mounted) {
        setState(() => _isCompleting = false);
        Get.snackbar('Error', 'Could not identify the ride. Please use Cash.',
            backgroundColor: Colors.red, colorText: Colors.white);
      }
      return;
    }

    try {
      // Debit only the wallet portion; the driver collects the cash remainder.
      if (walletPart > 0) {
        final res = await api.payRideWithWallet(rideId, walletPart);
        final ok = res.statusCode == 200 && res.data is Map && res.data['success'] == true;
        if (!ok) {
          if (mounted) {
            setState(() => _isCompleting = false);
            Get.snackbar('Payment failed',
                (res.data is Map ? res.data['message'] : null)?.toString() ?? 'Wallet debit failed',
                backgroundColor: Colors.red, colorText: Colors.white);
          }
          return;
        }
      }
      await _rideService.markPaymentPaid('split');
      if (mounted && cashPart > 0) {
        Get.snackbar('Collect cash',
            'Driver collects ৳${cashPart.toStringAsFixed(0)} in cash.',
            backgroundColor: const Color(0xFF10713C), colorText: Colors.white);
      }
      if (mounted) await _showRatingSheet();
      _rideService.resetTrip();
      if (mounted) Get.back();
    } catch (e) {
      if (mounted) {
        setState(() => _isCompleting = false);
        Get.snackbar('Error', 'Split payment failed. Please try again.',
            backgroundColor: Colors.red, colorText: Colors.white);
      }
    }
  }

  Widget _splitRow(String label, double amount, {bool bold = false}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          Text('৳${amount.toStringAsFixed(0)}',
              style: TextStyle(
                  fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                  color: const Color(0xFF10713C))),
        ],
      );

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
        // Card payment IPN settles the Laravel record server-to-server;
        // this signal is what unblocks the driver's rating prompt.
        await _rideService.markPaymentPaid('sslcommerz');
        if (mounted) await _showRatingSheet();
        _rideService.resetTrip();
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

  static const List<String> _riderCancelReasons = [
    'Driver taking too long',
    'Found another ride',
    'Changed my plans',
    'Wrong pickup location',
    'Price is too high',
    'Other',
  ];

  static const List<String> _driverCancelReasons = [
    'Passenger not responding',
    'Passenger not at pickup location',
    'Vehicle problem',
    'Personal emergency',
    'Unsafe or uncomfortable situation',
    'Other',
  ];

  Future<void> _showCancelDialog() async {
    final status = _rideService.tripStatus.value;
    final isDriver = widget.role == 'driver';
    final isChargeable = status == 'accepted' || status == 'arriving' || status == 'in_progress';
    final cancelReasons = isDriver ? _driverCancelReasons : _riderCancelReasons;
    String? selectedReason;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom +
                MediaQuery.of(ctx).padding.bottom + 16,
            top: 8, left: 20, right: 20,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 16),
              // Icon header
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.close_rounded, color: Colors.red.shade600, size: 30),
              ),
              const SizedBox(height: 10),
              const Text('Cancel this trip?',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                'The trip will end for both you and the ${isDriver ? 'passenger' : 'driver'}.',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              if (isChargeable) ...[
                const SizedBox(height: 12),
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
                          isDriver
                              ? 'Cancelling now will count against your reliability score and be visible on your driver profile.'
                              : 'A ৳50 cancellation fee applies because your driver is already on the way.',
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
              const SizedBox(height: 10),
              // Tappable reason tiles — nicer than dense radio rows
              ...cancelReasons.map((r) {
                final selected = selectedReason == r;
                return GestureDetector(
                  onTap: () => setS(() => selectedReason = r),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF10713C).withValues(alpha: 0.08)
                          : Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected ? const Color(0xFF10713C) : Colors.grey.shade200,
                        width: selected ? 1.6 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selected ? Icons.check_circle : Icons.circle_outlined,
                          size: 20,
                          color: selected ? const Color(0xFF10713C) : Colors.grey[400],
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            r,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Keep Ride', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: selectedReason == null ? null : () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        disabledBackgroundColor: Colors.grey[300],
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Cancel Trip',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
          ),
        ),
      ),
    );

    if (confirmed == true && selectedReason != null && mounted) {
      setState(() => _isCompleting = true);
      try {
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
          } else if (isDriver && isChargeable) {
            Get.snackbar(
              'Ride Cancelled',
              'This cancellation has been recorded on your driver profile.',
              backgroundColor: Colors.orange,
              colorText: Colors.white,
              duration: const Duration(seconds: 4),
            );
          }
          Get.back();
        }
      } catch (e) {
        // Never leave the button stuck on a spinner — surface the failure
        // and let the driver/rider try again.
        if (mounted) {
          setState(() => _isCompleting = false);
          Get.snackbar(
            'Could Not Cancel',
            'Please check your connection and try again.',
            backgroundColor: Colors.red,
            colorText: Colors.white,
          );
        }
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
        child: Obx(() {
          final status = _rideService.tripStatus.value;
          final isTripPhase = status == 'accepted' || status == 'arriving' ||
          status == 'in_progress' || status == 'completed';
          return isTripPhase ? _buildTripTopBar() : _buildDefaultTopBar();
        }),
      ),
    );
  }

  /// Vehicle icon matching the ride type — used as the rider's "your driver"
  /// avatar, same logic as the driver marker icon on the map.
  String _vehicleAssetPath() {
    switch (widget.rideType.toLowerCase()) {
      case 'motor':
      case 'bike':
        return 'assets/motor.png';
      case 'ambulance':
        return 'assets/ambulance.png';
      default:
        return 'assets/car.png';
    }
  }

  /// "Go to the passenger" → "Go to destination" bar + NAVIGATE button —
  /// shown to BOTH the driver and the rider through the whole trip (heading
  /// to pickup, waiting at pickup, and heading to destination), so both
  /// sides get the same look and feel throughout.
  Widget _buildTripTopBar() {
    final isDriver = widget.role == 'driver';
    final status = _rideService.tripStatus.value;
    final String label;
    if (status == 'completed') {
      label = isDriver ? 'Waiting for payment' : 'Trip completed';
    } else if (status == 'in_progress') {
      label = isDriver ? 'Go to destination' : 'Heading to destination';
    } else if (status == 'arriving') {
      label = isDriver ? 'Waiting for passenger' : 'Driver has arrived';
    } else {
      label = isDriver ? 'Go to the passenger' : 'Driver is on the way';
    }
    return Row(
      children: [
        GestureDetector(
          onTap: _minimizeToDashboard,
          child: Container(
            padding: const EdgeInsets.all(9),
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: const Icon(Icons.keyboard_arrow_down, color: Colors.black87, size: 20),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: _showPartyDetailsSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.white,
                    backgroundImage: AssetImage(
                        isDriver ? 'assets/passenger.png' : _vehicleAssetPath()),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.info_outline, color: Colors.white70, size: 15),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: _launchExternalNavigation,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.navigation, color: Colors.white, size: 16),
                SizedBox(width: 6),
                Text(
                  'NAVIGATE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDefaultTopBar() {
    return Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.white,
              child: IconButton(
                icon: const Icon(Icons.keyboard_arrow_down, color: Colors.black87),
                tooltip: 'Minimize',
                onPressed: _minimizeToDashboard,
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
          ],
        );
  }

  Widget _buildBottomPanel() {
    return Obx(() {
      final status = _rideService.tripStatus.value;
      final isTripPhase = status == 'accepted' || status == 'arriving' ||
          status == 'in_progress' || status == 'completed';

      if (isTripPhase && !_pickupPanelExpanded) {
        return _buildCollapsedTripPanel();
      }
      return _buildExpandedPanel(showCollapseHandle: isTripPhase);
    });
  }

  /// A small rounded "grab handle" bar shown at the top of the draggable
  /// pickup sheet — the modern bottom-sheet affordance for tap / swipe.
  Widget _sheetGrabHandle() {
    return Center(
      child: Container(
        width: 44,
        height: 5,
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }

  /// Interprets a vertical swipe on the pickup sheet: swipe up expands the
  /// full popup, swipe down collapses it back to the pickup-only view.
  void _handlePickupSheetDrag(DragEndDetails details) {
    final v = details.primaryVelocity ?? 0;
    if (v < -100) {
      setState(() => _pickupPanelExpanded = true);
    } else if (v > 100) {
      setState(() => _pickupPanelExpanded = false);
    }
  }

  /// Minimal "location + status button" panel matching the driver navigation
  /// reference design — shown to BOTH driver and rider for the whole trip
  /// (pickup phase AND the drive to destination). Tap the handle/card OR
  /// swipe up to open the full trip-details popup.
  Widget _buildCollapsedTripPanel() {
    final isDriver = widget.role == 'driver';
    final status = _rideService.tripStatus.value;
    final bool completed = status == 'completed';
    final bool tripStarted = status == 'in_progress';
    final bool arrived = status == 'arriving';

    final String locationLabel = completed
        ? 'TRIP FARE'
        : (tripStarted ? 'DESTINATION' : 'PICKUP LOCATION');
    final String address = completed
        ? '৳ ${widget.price.toStringAsFixed(0)}'
        : (tripStarted ? widget.destinationAddress : widget.pickupAddress);
    final IconData locationIcon =
        completed ? Icons.payments : (tripStarted ? Icons.flag : Icons.my_location);
    final Color locationAccent = completed
        ? const Color(0xFF10713C)
        : (tripStarted ? Colors.red : const Color(0xFF10713C));

    // Status button: the driver always gets an actionable progression
    // button (tapping "Start Trip" now asks for confirmation — see
    // _handleDriverPrimaryTap) until the trip is complete, at which point
    // they just wait for payment. The rider's button is informational
    // throughout — except once the trip is complete, when "Pay Now" becomes
    // their one and only action (only the driver can advance the trip itself).
    final Color statusColor = isDriver
        ? _driverButtonColor()
        : (completed
            ? const Color(0xFF10713C)
            : (tripStarted || arrived ? const Color(0xFF10713C) : const Color(0xFF1565C0)));
    final String statusLabel = isDriver
        ? _driverButtonLabel().toUpperCase()
        : (completed
            ? 'PAY NOW'
            : (tripStarted
                ? 'ON THE WAY TO DESTINATION'
                : (arrived ? 'DRIVER HAS ARRIVED' : 'DRIVER IS ON THE WAY')));
    final bool statusTappable = isDriver ? !completed : completed;
    final VoidCallback statusAction = isDriver ? _handleDriverPrimaryTap : _showPaymentPicker;
    // Cancel is available to both roles right up until the trip starts —
    // shown directly here so it's never hidden behind "expand for details".
    final bool canCancel = status == 'accepted' || status == 'arriving';

    return Align(
      alignment: Alignment.bottomCenter,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _pickupPanelExpanded = true),
        onVerticalDragEnd: _handlePickupSheetDrag,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          margin: EdgeInsets.only(
            left: 12, right: 12,
            bottom: 16 + MediaQuery.of(context).padding.bottom,
          ),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sheetGrabHandle(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: locationAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(locationIcon, color: locationAccent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          locationLabel,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                            letterSpacing: 0.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          address,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.keyboard_arrow_up_rounded, color: Colors.grey[400]),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (canCancel) ...[
                    Expanded(
                      flex: 2,
                      child: OutlinedButton(
                        onPressed: _isCompleting ? null : _showCancelDialog,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Cancel',
                            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    flex: 3,
                    child: ElevatedButton(
                      onPressed: statusTappable ? (_isCompleting ? null : statusAction) : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: statusColor,
                        disabledBackgroundColor: statusColor,
                        disabledForegroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _isCompleting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              statusLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Full trip-details panel (driver/passenger card, ETA, route, fare, actions).
  /// [showCollapseHandle] adds a down-arrow to collapse back to the pickup-only view.
  Widget _buildExpandedPanel({required bool showCollapseHandle}) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Only the driver-pickup sheet is collapsible; ignore drags otherwise.
        onVerticalDragEnd: showCollapseHandle ? _handlePickupSheetDrag : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          margin: EdgeInsets.only(
            left: 12, right: 12,
            bottom: 16 + MediaQuery.of(context).padding.bottom,
          ),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Obx(() => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showCollapseHandle)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _pickupPanelExpanded = false),
                child: _sheetGrabHandle(),
              ),
            // Driver/passenger info row — tap to open the full details popup.
            GestureDetector(
              onTap: _showPartyDetailsSheet,
              behavior: HitTestBehavior.opaque,
              child: Row(
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
                  const SizedBox(width: 6),
                  Icon(Icons.chevron_right, color: Colors.grey[400]),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── ETA + distance + status card (live) ──
            _buildEtaCard(),
            const SizedBox(height: 14),

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
              final completed = status == 'completed';
              // Cancel allowed before the trip starts (not once in_progress/completed)
              final canCancel = status == 'accepted' || status == 'arriving';

              final String primaryLabel;
              final Color primaryColor;
              final VoidCallback? primaryAction;

              if (isDriver) {
                // Only the driver advances the trip; once complete they just
                // wait for the rider to pay (see the paymentStatus worker).
                primaryLabel = _driverButtonLabel();
                primaryColor = _driverButtonColor();
                primaryAction = completed ? null : _handleDriverPrimaryTap;
              } else if (completed) {
                primaryLabel = 'Pay Now';
                primaryColor = const Color(0xFF10713C);
                primaryAction = _showPaymentPicker;
              } else {
                // The rider can't end the trip — only the driver can.
                primaryLabel = 'Trip in Progress';
                primaryColor = Colors.grey.shade400;
                primaryAction = null;
              }

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
                      onPressed: (_isCompleting || primaryAction == null) ? null : primaryAction,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        disabledBackgroundColor: primaryColor,
                        disabledForegroundColor: Colors.white,
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

  /// Live ETA + distance + status banner (like Pathao/Uber pickup card).
  Widget _buildEtaCard() {
    final status = _rideService.tripStatus.value;
    final arrived = status == 'arriving';
    final bg = arrived ? const Color(0xFFE8F5E9) : const Color(0xFF10713C).withValues(alpha: 0.06);
    final accent = arrived ? const Color(0xFF16A34A) : const Color(0xFF10713C);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(
              arrived ? Icons.check_circle : Icons.access_time_filled,
              color: accent, size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _statusLabel(status),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: accent),
                ),
                const SizedBox(height: 2),
                if (arrived)
                  Text(
                    widget.role == 'driver' ? 'Waiting for passenger' : 'Your driver is at the pickup point',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  )
                else if (_routeLoaded && _etaMinutes > 0)
                  Text(
                    '${_etaMinutes.ceil()} min · ${_distanceKm.toStringAsFixed(1)} km ${_etaTargetLabel()}',
                    style: TextStyle(fontSize: 13, color: Colors.grey[700], fontWeight: FontWeight.w500),
                  )
                else
                  Text('Calculating route…', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              ],
            ),
          ),
          // Big ETA number
          if (!arrived && _routeLoaded && _etaMinutes > 0)
            Column(
              children: [
                Text('${_etaMinutes.ceil()}',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: accent, height: 1)),
                Text('min', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              ],
            ),
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    final isDriver = widget.role == 'driver';
    switch (status) {
      case 'accepted':
        return isDriver ? 'Head to pickup' : 'Driver is on the way';
      case 'arriving':
        return isDriver ? 'You have arrived' : 'Driver has arrived';
      case 'in_progress':
        return 'On the way to destination';
      case 'completed':
        return 'Trip completed';
      default:
        return 'Live Tracking';
    }
  }

  /// Short label for the ETA card target.
  String _etaTargetLabel() {
    final status = _rideService.tripStatus.value;
    if (status == 'in_progress') return 'to destination';
    if (status == 'arriving') return 'at pickup';
    return 'to pickup';
  }
}
