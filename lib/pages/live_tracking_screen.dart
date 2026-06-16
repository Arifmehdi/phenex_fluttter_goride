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
  final RoutingService _routingService = Get.find<RoutingService>();

  // State
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  List<LatLng> _routePoints = [];
  bool _isLoadingRoute = true;
  bool _isDriverFound = false;

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

    if (widget.role == 'driver') {
      _isDriverFound = true; // For driver, we are already "found"
    }

    // Listen for driver acceptance (only for riders)
    if (widget.role == 'rider') {
      ever(_rideService.tripStatus, (status) {
        if (mounted && (status == 'accepted' || status == 'arriving' || status == 'in_progress')) {
          if (!_isDriverFound) {
            setState(() => _isDriverFound = true);
            _fetchRoute(); // Update route now that driver is assigned
          }
        }
      });
    }

    _loadIcons();
    _initialize();
  }

  Future<void> _loadIcons() async {
    _carIcon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(size: Size(30, 30)),
      'assets/car.png',
    );
    // Load a user icon if available, otherwise use default
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

        // For drivers, we should also update their location in Firestore
        // LocationService.startTracking should already be doing this if started in UnifiedDashboard
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
        _isLoadingRoute = false;
      });

      if (_routePoints.isNotEmpty) {
        _fitRoute();
      }
    } else {
      setState(() {
        _routePoints = [origin, destination];
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

  @override
  void dispose() {
    _positionStream?.cancel();
    _mapController?.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _handleCall() async {
    final phone = widget.role == 'rider' ? '+8801234567890' : '+8801987654321';
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

          // Top Header
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
                  if (_routePoints.isNotEmpty && !_isLoadingRoute)
                    _buildETABadge(),
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

  Widget _buildETABadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8)],
      ),
      child: Obx(() {
        // Access an observable regardless of role to satisfy GetX
        final status = _rideService.tripStatus.value;
        final eta = widget.role == 'rider' ? _rideService.driverETA.value : 10; 
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.access_time, color: Color(0xFF10713C), size: 16),
            const SizedBox(width: 6),
            Text(
              '$eta min',
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

          // Driver Marker (only if not self)
          if (widget.role == 'rider' && dLat != 0 && dLng != 0)
            Marker(
              markerId: const MarkerId('driver'),
              position: LatLng(dLat, dLng),
              icon: _carIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
              rotation: dHeading,
              anchor: const Offset(0.5, 0.5),
              infoWindow: const InfoWindow(title: 'Driver Location'),
            ),
          
          // Rider Marker (for driver to see customer)
          if (widget.role == 'driver')
            Marker(
              markerId: const MarkerId('rider'),
              position: _pickupPoint, // In a real app, this could be the rider's LIVE location
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
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

  Widget _buildCancelButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        onPressed: () => Navigator.pop(context),
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

      if (widget.role == 'rider') {
        if (status == 'accepted') { statusText = 'Rider is coming'; subText = 'Wait at the pickup point'; }
        else if (status == 'arriving') { statusText = 'Rider arrived'; subText = 'Meet the driver outside'; }
        else if (status == 'in_progress') { statusText = 'On the way'; subText = 'Heading to your destination'; }
        else { statusText = 'Trip status updated'; subText = 'Please check details'; }
      } else {
        if (status == 'accepted') { statusText = 'Heading to Pickup'; subText = 'Pick up ${widget.pickupAddress}'; }
        else if (status == 'arriving') { statusText = 'At Pickup Point'; subText = 'Wait for the passenger'; }
        else if (status == 'in_progress') { statusText = 'Driving to Destination'; subText = 'Heading to ${widget.destinationAddress}'; }
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
              '৳${widget.price.round()}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF10713C)),
            ),
          ),
        ],
      );
    });
  }

  Widget _buildParticipantInfo() {
    final name = widget.role == 'rider' ? 'Rashed Ahmed' : 'Passenger';
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
                  Text('4.8', style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _handleCall,
          icon: const CircleAvatar(backgroundColor: Color(0xFF10713C), child: Icon(Icons.call, color: Colors.white, size: 20)),
        ),
      ],
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
          if (status == 'completed') 
            const Text('Trip Completed!', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green))
          else
            SizedBox(
              width: double.infinity,
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
        ],
      );
    });
  }

  Widget _buildRiderActions() {
    return Row(
      children: [
        Expanded(child: _actionButton(Icons.share, 'Share', _handleShareTrip)),
        const SizedBox(width: 12),
        Expanded(child: _actionButton(Icons.security, 'Safety', _handleEmergency)),
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
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
