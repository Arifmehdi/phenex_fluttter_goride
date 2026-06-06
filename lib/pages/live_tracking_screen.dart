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
  GoogleMapController? _mapController;
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

  // Icons
  BitmapDescriptor? _carIcon;
  BitmapDescriptor? _userIcon;

  LatLng get _pickupPoint => LatLng(widget.pickupLat, widget.pickupLng);
  LatLng get _destPoint => LatLng(widget.destLat, widget.destLng);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _loadIcons();
    _initialize();
  }

  Future<void> _loadIcons() async {
    _carIcon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(size: Size(30, 30)),
      'assets/car.png',
    );
    // You could also load a user icon here if available
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
        setState(() {
          _currentPosition = position;
        });

        // Dynamically move map to follow the user
        _mapController?.animateCamera(
          CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)),
        );
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
        _fitRoute();
      }
    } else {
      setState(() => _isLoadingRoute = false);
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
    _mapController?.dispose();
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

          // Back button and Status Card
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10),
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
          // Rider position handled by myLocationEnabled: true usually, 
          // but we can add a custom one if preferred.
          
          // Driver position
          if (dLat != 0 && dLng != 0)
            Marker(
              markerId: const MarkerId('driver'),
              position: LatLng(dLat, dLng),
              icon: _carIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
              rotation: dHeading,
              anchor: const Offset(0.5, 0.5),
              infoWindow: const InfoWindow(title: 'Your Driver'),
            ),

          // Destination
          Marker(
            markerId: const MarkerId('destination'),
            position: _destPoint,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: const InfoWindow(title: 'Destination'),
          ),
        },
        polylines: {
          if (_routePoints.isNotEmpty)
            Polyline(
              polylineId: const PolylineId('route'),
              points: _routePoints,
              color: const Color(0xFF10713C),
              width: 5,
            ),
        },
      );
    });
  }

  Widget _buildBottomPanel() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: _isDriverFound ? _buildDriverFoundPanel() : _buildSearchingPanel(),
    );
  }

  Widget _buildSearchingPanel() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(24, 32, 24, 32 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF10713C).withOpacity(0.1 + (0.1 * _pulseController.value)),
                ),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF10713C).withOpacity(0.2 + (0.2 * _pulseController.value)),
                  ),
                  child: const Icon(
                    Icons.local_taxi,
                    color: Color(0xFF10713C),
                    size: 40,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          const Text(
            'Finding your ride...',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Sending request to nearby drivers for your ${widget.rideType}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.redAccent, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Cancel Request',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverFoundPanel() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(24, 12, 24, 32 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          
          // Status Header
          Obx(() => Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _rideService.tripStatus.value == 'accepted' 
                        ? 'Driver is coming' 
                        : _rideService.tripStatus.value == 'arriving' 
                            ? 'Driver arrived'
                            : 'On the way',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF10713C),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Your trip is in progress',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '৳${widget.price.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          )),
          const SizedBox(height: 24),
          
          // Driver info
          Row(
            children: [
              const CircleAvatar(
                radius: 28,
                backgroundColor: Color(0xFF10713C),
                child: Icon(Icons.person, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Rashed Ahmed',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 16),
                        const SizedBox(width: 4),
                        Text('4.8', style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                        const SizedBox(width: 12),
                        const Icon(Icons.verified, color: Colors.blue, size: 16),
                        const SizedBox(width: 4),
                        Text('Verified', style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _handleCallDriver,
                icon: const CircleAvatar(
                  backgroundColor: Color(0xFF10713C),
                  child: Icon(Icons.call, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Car details
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(
              children: [
                Image.asset('assets/${widget.rideType}.png', width: 50, height: 40, errorBuilder: (_,__,___) => const Icon(Icons.directions_car)),
                const SizedBox(width: 16),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Dhaka-Metro-Ga-12-3456', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    SizedBox(height: 2),
                    Text('White Toyota Premio', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          // Action buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _handleShareTrip,
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text('Share'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[100],
                    foregroundColor: Colors.black87,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _handleEmergency,
                  icon: const Icon(Icons.security, size: 18),
                  label: const Text('Safety'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[50],
                    foregroundColor: Colors.red[700],
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _navigateToDetails,
                  icon: const Icon(Icons.info_outline, size: 18),
                  label: const Text('Details'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[50],
                    foregroundColor: Colors.blue[700],
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
