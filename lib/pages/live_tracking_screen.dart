import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../services/ride_service.dart';
import '../services/location_service.dart';
import '../services/routing_service.dart';
import 'trip_details_page.dart';

class LiveTrackingScreen extends StatefulWidget {
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
  late final MapController _mapController;
  late AnimationController _pulseController;

  // Tracking services
  final RideService _rideService = Get.find<RideService>();
  final LocationService _locationService = Get.find<LocationService>();
  final RoutingService _routingService = Get.find<RoutingService>();

  // State
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  List<LatLng> _routePoints = [];
  bool _isLoadingRoute = true;
  bool _isDriverFound = false;
  bool _showDriverInfo = true;

  // Driver marker animation offset
  double _driverAnimOffset = 0.0;

  LatLng get _pickupPoint => LatLng(widget.pickupLat, widget.pickupLng);
  LatLng get _destPoint => LatLng(widget.destLat, widget.destLng);

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _initialize();
  }

  Future<void> _initialize() async {
    await _startLocationTracking();
    await _fetchRoute();
    _requestRide();
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
        setState(() => _currentPosition = position);
      }
    });
  }

  Future<void> _fetchRoute() async {
    setState(() => _isLoadingRoute = true);

    final origin = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : _pickupPoint;

    final route = await _routingService.getRoute(
      origin: origin,
      destination: _destPoint,
    );

    if (route != null && mounted) {
      setState(() {
        _routePoints = route.points;
        _isLoadingRoute = false;
      });

      if (_routePoints.isNotEmpty) {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(_routePoints),
            padding: const EdgeInsets.all(60),
          ),
        );
      }
    } else {
      setState(() => _isLoadingRoute = false);
    }
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

    // Listen for driver acceptance
    ever(_rideService.tripStatus, (status) {
      if (mounted && (status == 'accepted' || status == 'arriving')) {
        setState(() => _isDriverFound = true);
      }
    });
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _mapController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _handleCallDriver() async {
    final uri = Uri(scheme: 'tel', path: '+8801234567890');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _handleShareTrip() {
    Share.share(
      'I am riding with GoRide!\n'
      '🚕 ${widget.rideType.toUpperCase()}\n'
      '📍 From: ${widget.pickupAddress}\n'
      '🏁 To: ${widget.destinationAddress}\n'
      '💳 ৳${widget.price.toStringAsFixed(0)}',
    );
  }

  void _handleEmergency() async {
    final uri = Uri(scheme: 'tel', path: '999');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _navigateToDetails() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TripDetailsPage(
          rideType: widget.rideType,
          pickup: widget.pickupAddress,
          destination: widget.destinationAddress,
          price: widget.price,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Main Map
          _buildMap(),

          // Back button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.white,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.black),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const Spacer(),
                  // ETA badge
                  if (_routePoints.isNotEmpty && !_isLoadingRoute)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Obx(() => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.access_time, color: Color(0xFF10713C), size: 16),
                          const SizedBox(width: 6),
                          Text(
                            '${_rideService.driverETA.value > 0 ? _rideService.driverETA.value : "..."} min',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xFF10713C),
                            ),
                          ),
                        ],
                      )),
                    ),
                ],
              ),
            ),
          ),

          // Bottom panel
          _buildBottomPanel(),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _currentPosition != null
            ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
            : _pickupPoint,
        initialZoom: 14,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.goride.app',
        ),
        // Route polyline
        PolylineLayer(
          polylines: [
            if (_routePoints.isNotEmpty)
              Polyline(
                points: _routePoints,
                color: const Color(0xFF10713C),
                strokeWidth: 5.0,
                borderColor: Colors.green.shade800,
                borderStrokeWidth: 1.0,
              ),
          ],
        ),
        // Route points outline
        if (_routePoints.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _routePoints,
                color: const Color(0xFF10713C).withOpacity(0.3),
                strokeWidth: 9.0,
              ),
            ],
          ),
        // Markers
        Obx(() {
          // Explicitly access observables to ensure GetX registers them
          final dLat = _rideService.driverLatitude.value;
          final dLng = _rideService.driverLongitude.value;
          final dHeading = _rideService.driverHeading.value;

          return MarkerLayer(
            markers: [
              // Rider position
              if (_currentPosition != null)
                Marker(
                  point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                  width: 40,
                  height: 40,
                  child: const Icon(Icons.my_location, color: Colors.blue, size: 30),
                ),
              // Pickup marker
              Marker(
                point: _pickupPoint,
                width: 40,
                height: 40,
                child: const Icon(Icons.location_on, color: Color(0xFF10713C), size: 40),
              ),
              // Destination marker
              Marker(
                point: _destPoint,
                width: 40,
                height: 40,
                child: const Icon(Icons.flag, color: Color(0xFFED1C24), size: 35),
              ),
              // Driver's car (animated & rotating)
              if (_isDriverFound && dLat > 0)
                Marker(
                  point: LatLng(dLat, dLng),
                  width: 55,
                  height: 55,
                  child: AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Transform.rotate(
                        angle: dHeading * (pi / 180),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF10713C).withOpacity(0.15 + _pulseController.value * 0.2),
                          ),
                          child: Image.asset(
                            'assets/car.png',
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.directions_car,
                              color: Color(0xFF10713C),
                              size: 35,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        }),
        // Loading overlay
        if (_isLoadingRoute)
          const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 12),
                    Text('Calculating route...'),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBottomPanel() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: _isDriverFound ? _buildDriverTrackingPanel() : _buildSearchingPanel(),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchingPanel() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Obx(() {
            if (_rideService.tripStatus.value == 'requesting') {
              return const Column(
                children: [
                  Text(
                    'Finding your driver...',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Searching for nearby drivers',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              );
            }
            return const Column(
              children: [
                Text(
                  'Requesting ride...',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'Please wait while we process your request',
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
              ],
            );
          }),
          const SizedBox(height: 24),
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Container(
                width: 80 + _pulseController.value * 30,
                height: 80 + _pulseController.value * 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF10713C).withOpacity(0.1 + _pulseController.value * 0.1),
                ),
                child: const Center(
                  child: Icon(Icons.directions_car, color: Color(0xFF10713C), size: 40),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          // Trip summary
          _buildTripSummary(),
          const SizedBox(height: 20),
          // Cancel button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                _rideService.cancelTrip();
                Navigator.pop(context);
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text('Cancel Ride', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverTrackingPanel() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag indicator
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Driver info
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.grey[200],
                child: const Icon(Icons.person, color: Color(0xFF10713C), size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Your driver is arriving',
                      style: TextStyle(color: Color(0xFF10713C), fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const Text(
                      'Driver assigned',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Obx(() => Row(
                      children: [
                        const Icon(Icons.near_me, color: Color(0xFF10713C), size: 14),
                        const SizedBox(width: 4),
                        Text(
                          '${_rideService.driverDistance.value.toStringAsFixed(1)} km away',
                          style: TextStyle(color: Colors.grey[600], fontSize: 13),
                        ),
                      ],
                    )),
                  ],
                ),
              ),
              // ETA badge
              Obx(() => Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF10713C).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Text(
                      '${_rideService.driverETA.value}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF10713C),
                      ),
                    ),
                    const Text(
                      'min',
                      style: TextStyle(fontSize: 12, color: Color(0xFF10713C)),
                    ),
                  ],
                ),
              )),
            ],
          ),
          const Divider(height: 24),
          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildActionButton(Icons.phone, 'Call', _handleCallDriver),
              _buildActionButton(Icons.share, 'Share', _handleShareTrip),
              _buildActionButton(Icons.info_outline, 'Details', _navigateToDetails),
              _buildActionButton(Icons.warning_amber, 'Emergency', _handleEmergency),
            ],
          ),
          const Divider(height: 20),
          // Trip summary
          _buildTripSummary(),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: const Color(0xFF10713C).withOpacity(0.1),
              child: Icon(icon, color: const Color(0xFF10713C), size: 20),
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildTripSummary() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _buildLocationRow(Icons.my_location, widget.pickupAddress, const Color(0xFF10713C)),
          const Padding(
            padding: EdgeInsets.only(left: 11),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(height: 16, child: VerticalDivider(width: 1)),
            ),
          ),
          _buildLocationRow(Icons.flag, widget.destinationAddress, const Color(0xFFED1C24)),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Fare', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text(
                '৳${widget.price.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF10713C),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLocationRow(IconData icon, String address, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            address,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
