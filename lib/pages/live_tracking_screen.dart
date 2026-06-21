import 'dart:math';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../services/ride_service.dart';
import '../services/location_service.dart';
import '../services/routing_service.dart';
import 'trip_details_page.dart';
import 'dashboard_page.dart';
import 'home_page.dart';
import '../utils/marker_utils.dart';
import '../services/api_service.dart';
import '../services/voice_guidance_service.dart';
import 'widgets/navigation_panel.dart';
import 'widgets/route_overview_widget.dart';


class LiveTrackingScreen extends StatefulWidget {
  final String role; // 'rider' or 'driver'
  final String rideType;
  final String pickupAddress;
  final String destinationAddress;
  final double price;
  final double pickupLat;
  final double pickupLng;
  final double destLat;
  final double destLng;
  final String? tripId;

  const LiveTrackingScreen({
    super.key,
    this.role = 'rider',
    required this.rideType,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.price,
    required this.pickupLat,
    required this.pickupLng,
    required this.destLat,
    required this.destLng,
    this.tripId,
  });

  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen>
    with SingleTickerProviderStateMixin {
  GoogleMapController? _mapController;
  late AnimationController _pulseController;

  // Tracking services
  final RideService _rideService = Get.find<RideService>();
  final LocationService _locationService = Get.find<LocationService>();
  final ApiService _apiService = Get.find<ApiService>();
  final RoutingService _routingService = Get.find<RoutingService>();
  final VoiceGuidanceService _voiceService = Get.find<VoiceGuidanceService>();

  // State
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  List<LatLng> _routePoints = [];
  bool _isLoadingRoute = true;
  bool _isDriverFound = false;
  int _currentETA = 0; // Dynamic ETA in minutes

  // Turn-by-turn navigation
  List<NavigationStep> _navigationSteps = [];
  int _currentStepIndex = 0;
  double _remainingDistance = 0.0; // km
  int _remainingDuration = 0; // minutes

  // Distance to the next turn/maneuver (in meters)
  double _distToNextTurn = 0.0;
  double _distToStepEnd = 0.0;

  // Distance-based pre-alerts: tracks which thresholds were announced per step index
  // Format: "stepIndex:threshold" e.g. "3:500" means 500m alert was announced for step 3
  final Set<String> _announcedAlerts = {};
  static const List<int> _alertDistances = [500, 200, 100]; // meters before turn

  // Vehicle icons - loaded based on ride type
  BitmapDescriptor? _vehicleIcon;
  BitmapDescriptor? _userIcon;

  // Internal navigation — follow user's position on the map
  bool _isFollowingUser = true;

  // Driver-specific navigation enhancements
  Timer? _routeRefreshTimer;
  String _currentRoutePhase = ''; // 'to_pickup' or 'to_destination'
  bool _isNearPickup = false;

  // Route overview mini-map
  bool _showRouteOverview = false;
  double _tripProgress = 0.0; // 0.0 to 1.0

  double _totalRouteDistance = 0.0; // km (for progress calculation)

  void _toggleFollowUser() {
    setState(() {
      _isFollowingUser = !_isFollowingUser;
    });
    if (_isFollowingUser) {
      _centerOnCurrentLocation();
    }
  }

  void _centerOnCurrentLocation() {
    if (_currentPosition != null && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
            zoom: 17,
          ),
        ),
      );
    }
  }

  /// Check if the driver has arrived at the pickup point and auto-update status
  void _checkPickupProximity(Position position) {
    if (widget.role != 'driver') return;
    if (_rideService.tripStatus.value != 'accepted') return;

    final driverPos = LatLng(position.latitude, position.longitude);
    final distToPickup = _distanceInMeters(driverPos, _pickupPoint);

    // When within 80m of pickup, auto-transition to 'arriving'
    if (distToPickup < 80 && !_isNearPickup) {
      _isNearPickup = true;
      _voiceService.announceInstruction('You have arrived at the pickup point');
      // Fire-and-forget the status update; the next timer tick will refresh the route
      _rideService.updateStatus('arriving');
    } else if (distToPickup >= 150) {
      _isNearPickup = false;
    }
  }

  /// Find which navigation step the user is currently on based on position
  void _updateCurrentStep(Position position) {
    if (_navigationSteps.isEmpty) return;

    final userPos = LatLng(position.latitude, position.longitude);
    final int oldIndex = _currentStepIndex;

    // Check if we've passed the end of the current step
    if (_currentStepIndex < _navigationSteps.length) {
      final currentStep = _navigationSteps[_currentStepIndex];
      final distToStepEnd = _distanceInMeters(userPos, currentStep.endLocation);
      _distToStepEnd = distToStepEnd;

      // If within 25m of current step's end, advance to next step and announce
      if (distToStepEnd < 25 && _currentStepIndex < _navigationSteps.length - 1) {
        _currentStepIndex++;
        // Clear alerts for the previous step
        _announcedAlerts.clear();
        // Announce the new step instruction
        final newStep = _navigationSteps[_currentStepIndex];
        _voiceService.announceInstruction(newStep.cleanInstruction);
      }

      // Announce arrival when reaching the last step
      if (_currentStepIndex == _navigationSteps.length - 1 &&
          _currentStepIndex != oldIndex) {
        _voiceService.announceArrival();
      }

      // Distance-based pre-alerts for the next upcoming step
      if (_currentStepIndex < _navigationSteps.length - 1) {
        final nextStep = _navigationSteps[_currentStepIndex + 1];
        final distToNextTurn = _distanceInMeters(userPos, nextStep.startLocation);
        _distToNextTurn = distToNextTurn;

        // If no next step, set distance to destination

        // Check thresholds from closest to furthest to find the best alert
        for (final threshold in _alertDistances.reversed) {
          final alertKey = '${_currentStepIndex + 1}:$threshold';
          // If user is within threshold distance and alert hasn't been announced yet
          if (distToNextTurn <= threshold && !_announcedAlerts.contains(alertKey)) {
            _announcedAlerts.add(alertKey);
            // Announce the pre-alert
            final distanceText = _formatDistanceText(threshold);
            _voiceService.announceDistanceUpdate(
              instruction: nextStep.cleanInstruction,
              distanceText: distanceText,
            );
            break; // Only announce the closest threshold to avoid overlap
          }
        }
      } else {
        // On the last step — distance to the destination
        _distToNextTurn = _distanceInMeters(userPos, _destPoint);
      }
    } else {
      // On the last step — distance to the destination
      _distToNextTurn = _distanceInMeters(userPos, _destPoint);
    }

    // Calculate remaining distance and time from current step onward
    double remainingDist = 0.0;
    double remainingDur = 0.0;
    for (int i = _currentStepIndex; i < _navigationSteps.length; i++) {
      remainingDist += _navigationSteps[i].distance;
      remainingDur += _navigationSteps[i].duration;
    }

    // Subtract distance already traveled in current step
    final currentStep = _navigationSteps[_currentStepIndex];
    final distToEnd = _distanceInMeters(userPos, currentStep.endLocation);
    final stepDistMeters = currentStep.distance * 1000;
    final stepRemaining = (stepDistMeters > 0)
        ? (distToEnd / stepDistMeters) * currentStep.distance
        : currentStep.distance;
    remainingDist = stepRemaining + (remainingDist - currentStep.distance);

    // Calculate overall trip progress (distance covered / total distance)
    if (_totalRouteDistance > 0) {
      final traveled = _totalRouteDistance - remainingDist;
      _tripProgress = (traveled / _totalRouteDistance).clamp(0.0, 1.0);
    }

    final roundedDur = remainingDur.round();
    final roundedDist = (remainingDist * 10).round() / 10.0;
    final roundedProgress = (_tripProgress * 100).round() / 100.0;

    // Only call setState if values actually changed
    if (_currentStepIndex != oldIndex ||
        _remainingDuration != roundedDur ||
        (_remainingDistance - roundedDist).abs() > 0.05) {
      setState(() {
        _remainingDistance = roundedDist;
        _remainingDuration = roundedDur;
        _tripProgress = roundedProgress;
      });
    }
  }

  /// Calculate distance in meters between two LatLng points (Haversine formula)
  double _distanceInMeters(LatLng a, LatLng b) {
    const double earthRadius = 6371000;
    final dLat = _degToRad(b.latitude - a.latitude);
    final dLng = _degToRad(b.longitude - a.longitude);
    final lat1 = _degToRad(a.latitude);
    final lat2 = _degToRad(b.latitude);

    final h = sin(dLat / 2) * sin(dLat / 2) +
        sin(dLng / 2) * sin(dLng / 2) * cos(lat1) * cos(lat2);
    final c = 2 * atan2(sqrt(h), sqrt(1 - h));
    return earthRadius * c;
  }

  double _degToRad(double deg) => deg * (pi / 180.0);

  /// Calculate circular progress (0.0 to 1.0) toward the next turn
  /// Based on the current step's remaining distance
  double _calculateTurnProgress() {
    if (_navigationSteps.isEmpty) return 0.0;
    final currentStep = _navigationSteps[_currentStepIndex];
    final stepTotalMeters = currentStep.distance * 1000;
    if (stepTotalMeters <= 0) return 0.0;
    final progress = 1.0 - (_distToStepEnd / stepTotalMeters);
    return progress.clamp(0.0, 1.0);
  }

  /// Color for the turn progress ring based on how close the turn is
  Color _turnProgressColor() {
    final distance = _distToNextTurn;
    if (distance <= 100) return Colors.redAccent;
    if (distance <= 200) return Colors.orange;
    if (distance <= 500) return Colors.amber[700]!;
    return const Color(0xFF10713C);
  }

  /// Format the distance to the next turn as a readable string
  String _formatTurnDistance() {
    if (_distToNextTurn >= 1000) {
      return '${(_distToNextTurn / 1000).toStringAsFixed(1)} km';
    }
    return '${_distToNextTurn.round()} m';
  }

  /// Format a distance in meters to a human-readable string for voice alerts
  String _formatDistanceText(int meters) {
    if (meters >= 1000) {
      return 'In ${(meters / 1000).toStringAsFixed(1)} kilometers';
    }
    return 'In $meters meters';
  }

  /// Build the turn-by-turn navigation instruction panel using the extracted NavigationPanel widget
  Widget _buildNavigationPanel() {
    if (_navigationSteps.isEmpty) return const SizedBox.shrink();
    final currentStep = _navigationSteps[_currentStepIndex];
    final hasNext = _currentStepIndex + 1 < _navigationSteps.length;
    final nextStep = hasNext ? _navigationSteps[_currentStepIndex + 1] : null;

    return NavigationPanel(
      currentStep: currentStep,
      hasNext: hasNext,
      nextStep: nextStep,
      navigationSteps: _navigationSteps,
      currentStepIndex: _currentStepIndex,
      remainingDistance: _remainingDistance,
      remainingDuration: _remainingDuration,
      distToNextTurn: _distToNextTurn,
      distToStepEnd: _distToStepEnd,
      turnProgress: _calculateTurnProgress(),
      turnProgressColor: _turnProgressColor(),
      showRouteOverview: _showRouteOverview,
      formatTurnDistance: _formatTurnDistance,
      onToggleVoice: () => _voiceService.toggleVoice(),
      onToggleRouteOverview: () => setState(() => _showRouteOverview = !_showRouteOverview),
      buildRouteOverview: () => _buildRouteOverview(),
    );
  }

  /// Build the collapsible route overview mini-map using the extracted RouteOverviewWidget
  Widget _buildRouteOverview() {
    if (_routePoints.isEmpty) return const SizedBox.shrink();

    final pickupAddr = _rideService.currentPickupAddress.value.isNotEmpty
        ? _rideService.currentPickupAddress.value
        : widget.pickupAddress;
    final destAddr = _rideService.currentDestAddress.value.isNotEmpty
        ? _rideService.currentDestAddress.value
        : widget.destinationAddress;

    return RouteOverviewWidget(
      routePoints: _routePoints,
      currentPosition: _currentPosition != null
          ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
          : null,
      pickupPoint: _pickupPoint,
      destPoint: _destPoint,
      pickupAddress: pickupAddr,
      destAddress: destAddr,
      tripProgress: _tripProgress,
      remainingDistance: _remainingDistance,
      role: widget.role,
      tripStatus: _rideService.tripStatus.value,
    );
  }

  LatLng get _pickupPoint {
    if (_rideService.currentPickupLat.value != 0) {
      return LatLng(_rideService.currentPickupLat.value, _rideService.currentPickupLng.value);
    }
    return LatLng(widget.pickupLat, widget.pickupLng);
  }

  LatLng get _destPoint {
    if (_rideService.currentDestLat.value != 0) {
      return LatLng(_rideService.currentDestLat.value, _rideService.currentDestLng.value);
    }
    return LatLng(widget.destLat, widget.destLng);
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    if (widget.role == 'driver') {
      _isDriverFound = true; // For driver, we are already "found"
      _startRouteRefreshTimer(); // Periodic route refresh for moving origin
    }

    // Listen for driver acceptance (only for riders)
    if (widget.role == 'rider') {
      ever(_rideService.tripStatus, (status) {
        if (mounted) {
          if (status == 'accepted' || status == 'arriving' || status == 'in_progress') {
            if (!_isDriverFound) {
              setState(() => _isDriverFound = true);
              _fetchRoute(); // Update route now that driver is assigned
            }
          }
          // Show rating dialog when trip is completed
          if (status == 'completed') {
            Future.delayed(const Duration(seconds: 1), () {
              if (mounted) _showRatingDialog();
            });
          }
        }
      });
    }

    _loadIcons();
    _initialize();
  }

  Future<void> _loadIcons() async {
    // Load the appropriate vehicle icon based on ride type
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
    _userIcon = await MarkerUtils.getBytesFromAsset('assets/passenger.png', 50);
  }

  Future<void> _initialize() async {
    await _startLocationTracking();
    await _fetchRoute();
    if (widget.role == 'rider') {
      _requestRide();
    }
  }

  Future<void> _startLocationTracking() async {
    final hasPermission = await _locationService.requestPermission();
    if (!hasPermission) return;

    // Get current position
    final pos = await _locationService.getCurrentPosition();
    if (pos != null && mounted) {
      setState(() => _currentPosition = pos);
    }

    // Start streaming position
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _positionStream = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen((position) {
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });

        // Update which navigation step the user is on
        _updateCurrentStep(position);

        // Auto-follow the user's position when internal navigation is enabled
        if (_isFollowingUser && _mapController != null) {
          _mapController!.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: LatLng(position.latitude, position.longitude),
                zoom: 17,
              ),
            ),
          );
        }

        // For drivers: check pickup proximity and auto-update status
        _checkPickupProximity(position);
      }
    });
  }

  Future<void> _fetchRoute() async {
    setState(() => _isLoadingRoute = true);

    // If driver, route is from current pos to pickup, then to destination
    // For now, let's just show route to destination if already picked up, or to pickup if not
    LatLng origin;
    LatLng destination;

    if (widget.role == 'driver') {
      origin = _currentPosition != null 
          ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
          : _pickupPoint;
      
      // If trip status is 'accepted' or 'arriving', go to pickup.
      // If 'in_progress', go to destination.
      if (_rideService.tripStatus.value == 'in_progress') {
        destination = _destPoint;
      } else {
        destination = _pickupPoint;
      }
    } else {
      origin = _currentPosition != null
          ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
          : _pickupPoint;
      destination = _destPoint;
    }

    final response = await _routingService.getRoute(
      origin: origin,
      destination: destination,
    );

    if (response.status == 'OK' && response.route != null && mounted) {
      final route = response.route!;
      setState(() {
        _routePoints = route.points;
        _navigationSteps = route.steps;
        _currentStepIndex = 0;
        _remainingDistance = route.distance;
        _remainingDuration = route.duration.round();
        _currentETA = route.duration.round();
        _totalRouteDistance = route.distance;
        _tripProgress = 0.0;
        _isLoadingRoute = false;
        _announcedAlerts.clear();
      });

      // Phase-aware announcements for the driver
      if (widget.role == 'driver') {
        final newPhase = (_rideService.tripStatus.value == 'in_progress')
            ? 'to_destination'
            : 'to_pickup';
        if (_currentRoutePhase != newPhase) {
          _currentRoutePhase = newPhase;
          if (newPhase == 'to_pickup') {
            _voiceService.announceInstruction('Navigating to pickup location');
          } else {
            _voiceService.announceInstruction('Heading to destination');
          }
        }
      }

      // Announce the first instruction (only on initial load, not on periodic refresh)
      if (_navigationSteps.isNotEmpty &&
          !(widget.role == 'driver' && _currentRoutePhase.isNotEmpty)) {
        _voiceService.announceInstruction(_navigationSteps[0].cleanInstruction);
      }

      if (_routePoints.isNotEmpty) {
        _fitRoute();
      }
    } else {
      setState(() {
        _routePoints = [origin, destination];
        _navigationSteps = [];
        _isLoadingRoute = false;
      });
    }
  }

  void _fitRoute() {
    if (_routePoints.isEmpty || _mapController == null) return;

    double minLat = _routePoints.first.latitude;
    double maxLat = _routePoints.first.latitude;
    double minLng = _routePoints.first.longitude;
    double maxLng = _routePoints.first.longitude;

    for (final point in _routePoints) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        80.0,
      ),
    );
  }

  void _requestRide() {
    // Request ride through Firestore
    _rideService.requestRide(
      rideType: widget.rideType,
      pickupLat: widget.pickupLat,
      pickupLng: widget.pickupLng,
      pickupAddress: widget.pickupAddress,
      destLat: widget.destLat,
      destLng: widget.destLng,
      destAddress: widget.destinationAddress,
      fare: widget.price,
    );
  }

  /// Start a periodic timer that refreshes the driver's route every 30 seconds.
  /// This keeps turn-by-turn navigation accurate as the driver's position changes.
  void _startRouteRefreshTimer() {
    _routeRefreshTimer?.cancel();
    _routeRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _fetchRoute();
    });
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _routeRefreshTimer?.cancel();
    _mapController?.dispose();
    _pulseController.dispose();
    _voiceService.stop();
    super.dispose();
  }

  void _handleCall() async {
    // Use the actual phone number from the ride service
    final String phone;
    if (widget.role == 'rider') {
      // Rider calls the driver
      phone = _rideService.assignedDriverPhone.value.isNotEmpty
          ? _rideService.assignedDriverPhone.value
          : '+8801234567890';
    } else {
      // Driver calls the rider/passenger
      phone = _rideService.assignedRiderPhone.value.isNotEmpty
          ? _rideService.assignedRiderPhone.value
          : '+8801987654321';
    }
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _handleShareTrip() {
    Share.share(
      'I am on a GoRide trip!\n'
      '🚕 ${widget.rideType.toUpperCase()}\n'
      '📍 From: ${widget.pickupAddress}\n'
      '🏁 To: ${widget.destinationAddress}',
    );
  }

  void _handleEmergency() async {
    final uri = Uri(scheme: 'tel', path: '999');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _updateStatus(String status) async {
    await _rideService.updateStatus(status);
    _fetchRoute(); // Update route for new status
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Main Map
          _buildMap(),

          // Top Header with back button and ETA
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.white,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.black),
                      onPressed: () {
                        if (widget.role == 'driver') {
                          Get.offAll(() => const UnifiedDashboard(role: 'driver'));
                        } else {
                          Get.offAll(() => HomePage());
                        }
                      },
                    ),
                  ),
                  const Spacer(),
                  if (_routePoints.isNotEmpty && !_isLoadingRoute)
                    _buildETABadge(),
                ],
              ),
            ),
          ),

          // Turn-by-turn navigation panel (below top header, above map)
          if (_isDriverFound && _navigationSteps.isNotEmpty && !_isLoadingRoute)
            _buildNavigationPanel(),

          // Bottom panel
          _buildBottomPanel(),
        ],
      ),
    );
  }

  Widget _buildETABadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8)],
      ),
      child: Obx(() {
        // Use driverETA for both roles — it's dynamically calculated from
        // the driver's location to pickup using LocationService.calculateETA()
        final eta = _rideService.driverETA.value;
        final displayEta = eta > 0 ? eta : _currentETA;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.access_time, color: Color(0xFF10713C), size: 16),
            const SizedBox(width: 6),
            Text(
              '${displayEta > 0 ? displayEta : 1} min',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF10713C)),
            ),
          ],
        );
      }),
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
              : _pickupPoint,
          zoom: 14,
        ),
        onMapCreated: (controller) {
          _mapController = controller;
          if (_routePoints.isNotEmpty) _fitRoute();
        },
        myLocationEnabled: true,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: false,
        mapToolbarEnabled: false,
        markers: {
          // Pickup Marker
          Marker(
            markerId: const MarkerId('pickup'),
            position: _pickupPoint,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
            infoWindow: const InfoWindow(title: 'Pickup Location'),
          ),

          // Destination Marker
          Marker(
            markerId: const MarkerId('destination'),
            position: _destPoint,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: const InfoWindow(title: 'Destination'),
          ),

          // Driver Marker (only if not self) — dynamically moves with driver location
          if (widget.role == 'rider' && dLat != 0 && dLng != 0)
            Marker(
              markerId: const MarkerId('driver'),
              position: LatLng(dLat, dLng),
              icon: _vehicleIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
              rotation: dHeading,
              anchor: const Offset(0.5, 0.5),
              infoWindow: const InfoWindow(title: 'Driver Location'),
            ),
          
          // Rider Marker (for driver to see customer) — shows at pickup point
          if (widget.role == 'driver')
            Marker(
              markerId: const MarkerId('rider'),
              position: _pickupPoint,
              icon: _userIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
              infoWindow: const InfoWindow(title: 'Customer'),
            ),
        },
        polylines: {
          if (_routePoints.isNotEmpty)
            Polyline(
              polylineId: const PolylineId('route'),
              points: _routePoints,
              color: const Color(0xFF10713C),
              width: 5,
              jointType: JointType.round,
            ),
        },
      );
    });
  }

  Widget _buildBottomPanel() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: _isDriverFound ? _buildActiveTripPanel() : _buildSearchingPanel(),
    );
  }

  Widget _buildSearchingPanel() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(24, 32, 24, 32 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) => Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF10713C).withOpacity(0.1 + (0.1 * _pulseController.value)),
              ),
              child: const Icon(Icons.local_taxi, color: Color(0xFF10713C), size: 40),
            ),
          ),
          const SizedBox(height: 24),
          const Text('Finding your ride...', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Sending request to nearby drivers for your ${widget.rideType}', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 32),
          _buildCancelButton(),
        ],
      ),
    );
  }

  Future<void> _cancelRide() async {
    // Cancel the trip in Firestore so the driver gets notified
    await _rideService.cancelTrip();
    if (mounted) {
      Navigator.pop(context);
    }
  }

  Widget _buildCancelButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        onPressed: _cancelRide,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.redAccent, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: const Text('Cancel Request', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildActiveTripPanel() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(24, 12, 24, 32 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 24),
          _buildStatusHeader(),
          const SizedBox(height: 24),
          _buildParticipantInfo(),
          const SizedBox(height: 24),
          if (widget.role == 'driver') _buildDriverActions() else _buildRiderActions(),
        ],
      ),
    );
  }

  Widget _buildStatusHeader() {
    return Obx(() {
      String statusText = '';
      String subText = '';
      final status = _rideService.tripStatus.value;
      final fareAmount = _rideService.currentFare.value > 0 
          ? _rideService.currentFare.value 
          : widget.price;
      
      final pickupAddr = _rideService.currentPickupAddress.value.isNotEmpty 
          ? _rideService.currentPickupAddress.value 
          : widget.pickupAddress;
      final destAddr = _rideService.currentDestAddress.value.isNotEmpty
          ? _rideService.currentDestAddress.value
          : widget.destinationAddress;

      if (widget.role == 'rider') {
        if (status == 'accepted') { statusText = 'Rider is coming'; subText = 'Wait at the pickup point'; }
        else if (status == 'arriving') { statusText = 'Rider arrived'; subText = 'Meet the driver outside'; }
        else if (status == 'in_progress') { statusText = 'On the way'; subText = 'Heading to your destination'; }
        else { statusText = 'Trip status updated'; subText = 'Please check details'; }
      } else {
        if (status == 'accepted') { statusText = 'Heading to Pickup'; subText = 'Pick up $pickupAddr'; }
        else if (status == 'arriving') { statusText = 'At Pickup Point'; subText = 'Wait for the passenger'; }
        else if (status == 'in_progress') { statusText = 'Driving to Destination'; subText = 'Heading to $destAddr'; }
        else { statusText = 'Trip ongoing'; subText = 'Follow the map'; }
      }

      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(statusText, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF10713C))),
                const SizedBox(height: 4),
                Text(
                  subText, 
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  softWrap: true,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF10713C).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '৳${fareAmount.round()}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF10713C)),
            ),
          ),
        ],
      );
    });
  }

  Widget _buildParticipantInfo() {
    return Obx(() {
      final String name;
      final String rating;
      final String phone;
      
      if (widget.role == 'rider') {
        name = _rideService.assignedDriverName.value.isNotEmpty 
            ? _rideService.assignedDriverName.value 
            : 'Driver';
        rating = _rideService.assignedDriverRating.value.toStringAsFixed(1);
        phone = _rideService.assignedDriverPhone.value;
      } else {
        name = _rideService.assignedRiderName.value.isNotEmpty
            ? _rideService.assignedRiderName.value
            : 'Passenger';
        rating = '5.0';
        phone = _rideService.assignedRiderPhone.value;
      }

      return Row(
        children: [
          const CircleAvatar(radius: 28, backgroundColor: Color(0xFF10713C), child: Icon(Icons.person, color: Colors.white, size: 30)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 16),
                    const SizedBox(width: 4),
                    Text(rating, style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                  ],
                ),
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    phone,
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: _handleCall,
            icon: const CircleAvatar(backgroundColor: Color(0xFF10713C), child: Icon(Icons.call, color: Colors.white, size: 20)),
          ),
        ],
      );
    });
  }

  void _showCancelConfirmationDialog() {
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel this Trip?', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
        content: const Text('Are you sure you want to cancel this ongoing trip request? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('No, Keep Trip', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Get.back(); // dismiss dialog
              _cancelRide(); // perform cancellation and exit screen
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Yes, Cancel', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverActions() {
    return Obx(() {
      final status = _rideService.tripStatus.value;
      String btnText = 'Update Status';
      VoidCallback? onPressed;

      if (status == 'accepted') {
        btnText = 'I Have Arrived';
        onPressed = () => _updateStatus('arriving');
      } else if (status == 'arriving') {
        btnText = 'Start Trip';
        onPressed = () => _updateStatus('in_progress');
      } else if (status == 'in_progress') {
        btnText = 'Finish Trip';
        onPressed = () => _updateStatus('completed');
      }

      return Column(
        children: [
          if (status != 'completed') ...[
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _toggleFollowUser,
                icon: Icon(
                  _isFollowingUser ? Icons.my_location : Icons.location_disabled,
                  color: Color(0xFF10713C),
                ),
                label: Text(
                  _isFollowingUser ? 'Following You' : 'Tap to Follow',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[100],
                  foregroundColor: const Color(0xFF10713C),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFF10713C), width: 1)),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (status == 'completed') 
            const Text('Trip Completed!', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green))
          else
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: onPressed,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10713C),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(btnText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                ),
                if (status != 'completed') ...[
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _showCancelConfirmationDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[50],
                        foregroundColor: Colors.red,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.redAccent, width: 1.5)),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      child: const Icon(Icons.cancel, color: Colors.redAccent),
                    ),
                  ),
                ],
              ],
            ),
        ],
      );
    });
  }

  Widget _buildRiderActions() {
    return Row(
      children: [
        Expanded(child: _actionButton(Icons.share, 'Share', _handleShareTrip)),
        const SizedBox(width: 8),
        Expanded(child: _actionButton(Icons.security, 'Safety', _handleEmergency)),
        const SizedBox(width: 8),
        // Add Cancel button for Rider
        Expanded(
          child: ElevatedButton(
            onPressed: _showCancelConfirmationDialog,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[50],
              foregroundColor: Colors.red,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.redAccent, width: 1)),
            ),
            child: const Icon(Icons.cancel_outlined, size: 20, color: Colors.redAccent),
          ),
        ),
      ],
    );
  }

  Widget _actionButton(IconData icon, String label, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.grey[100],
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
    );
  }

  /// Show rating dialog after trip is completed
  void _showRatingDialog() {
    int _rating = 5;
    final TextEditingController _reviewController = TextEditingController();
    final driverName = _rideService.assignedDriverName.value.isNotEmpty
        ? _rideService.assignedDriverName.value
        : 'Driver';

    Get.dialog(
      WillPopScope(
        onWillPop: () async => false, // Prevent dismissing by tapping outside
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Column(
            children: [
              const Icon(Icons.star, color: Colors.amber, size: 48),
              const SizedBox(height: 12),
              Text('Rate $driverName',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
              ),
              const SizedBox(height: 4),
              Text('How was your trip with $driverName?',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Star rating
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      return IconButton(
                        icon: Icon(
                          index < _rating ? Icons.star : Icons.star_border,
                          color: Colors.amber,
                          size: 40,
                        ),
                        onPressed: () {
                          setDialogState(() => _rating = index + 1);
                        },
                      );
                    }),
                  ),
                  const SizedBox(height: 16),
                  // Review text field
                  TextField(
                    controller: _reviewController,
                    maxLines: 3,
                    maxLength: 500,
                    decoration: InputDecoration(
                      hintText: 'Write a review (optional)...',
                      hintStyle: TextStyle(color: Colors.grey[400]),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF10713C)),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Get.back();
                _submitRating(_rating, _reviewController.text);
              },
              child: const Text('Skip', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                Get.back();
                _submitRating(_rating, _reviewController.text);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10713C),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Submit Rating', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  /// Submit the rating to the API
  Future<void> _submitRating(int rating, String review) async {
    try {
      final user = _apiService.getUser();
      final driverId = int.tryParse(_rideService.assignedDriverId.value) ?? 0;

      if (driverId == 0) {
        debugPrint('Cannot submit rating: driver ID not available');
        Get.snackbar('Thank You!', 'Your feedback has been noted.');
        return;
      }

      // Get the ride request ID from the active ride
      final activeRide = await _apiService.getActiveRide();
      int rideRequestId = 0;

      if (activeRide.statusCode == 200 && activeRide.data['data'] != null) {
        rideRequestId = activeRide.data['data']['id'] ?? 0;
      }

      if (rideRequestId == 0) {
        debugPrint('Cannot submit rating: ride request ID not available');
        Get.snackbar('Thank You!', 'Your feedback has been noted.');
        return;
      }

      final response = await _apiService.rateDriver(
        rideRequestId: rideRequestId,
        driverId: driverId,
        rating: rating,
        review: review.isNotEmpty ? review : null,
      );

      if (response.statusCode == 201) {
        Get.snackbar(
          'Thank You!',
          'Your rating has been submitted successfully.',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: const Color(0xFF10713C),
          colorText: Colors.white,
        );
      } else {
        Get.snackbar('Thank You!', 'Your feedback has been noted.');
      }
    } catch (e) {
      debugPrint('Error submitting rating: $e');
      Get.snackbar('Thank You!', 'Your feedback has been noted.');
    }
  }
}
