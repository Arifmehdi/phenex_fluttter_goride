import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:latlong2/latlong.dart' as latlong;
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:get/get.dart';
import '../services/ride_service.dart';
import '../services/location_service.dart';
import '../services/routing_service.dart';

class TripDetailsPage extends StatefulWidget {
  final String rideType;
  final String pickup;
  final String destination;
  final double price;

  const TripDetailsPage({
    super.key,
    required this.rideType,
    required this.pickup,
    required this.destination,
    required this.price,
  });

  @override
  State<TripDetailsPage> createState() => _TripDetailsPageState();
}

class _TripDetailsPageState extends State<TripDetailsPage> {
  late final fmap.MapController _mapController;
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStreamSubscription;

  final RideService _rideService = Get.find<RideService>();
  final LocationService _locationService = Get.find<LocationService>();
  final RoutingService _routingService = Get.find<RoutingService>();

  List<latlong.LatLng> _routePoints = [];
  bool _isLoadingRoute = false;
  double _tripProgress = 0.0;
  int _etaMinutes = 3;
  double _driverLat = 23.8103;
  double _driverLng = 90.4125;

  @override
  void initState() {
    super.initState();
    _mapController = fmap.MapController();
    _startLiveTracking();
    _fetchRoute();
  }

  void _fetchRoute() {
    // Simplified: use default coordinates for demo
    final origin = latlong.LatLng(23.8103, 90.4125);
    final dest = latlong.LatLng(23.7925, 90.4078);
    _loadRoute(origin, dest);
  }

  Future<void> _loadRoute(latlong.LatLng origin, latlong.LatLng dest) async {
    setState(() => _isLoadingRoute = true);
    final route = await _routingService.getRoute(origin: origin, destination: dest);
    if (route != null && mounted) {
      setState(() {
        _routePoints = route.points;
        _etaMinutes = route.duration.toInt();
        _isLoadingRoute = false;
      });
      if (_routePoints.isNotEmpty) {
        _mapController.fitCamera(fmap.CameraFit.bounds(
          bounds: fmap.LatLngBounds.fromPoints(_routePoints),
          padding: const EdgeInsets.all(80),
        ));
      }
    } else {
      setState(() => _isLoadingRoute = false);
    }
  }

  void _startLiveTracking() {
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _positionStreamSubscription = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (Position position) {
        if (mounted) {
          setState(() {
            _currentPosition = position;
          });
          _mapController.move(latlong.LatLng(position.latitude, position.longitude), 15.0);
        }
      },
    );
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _handleEmergency() async {
    final Uri launchUri = Uri(scheme: 'tel', path: '999');
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    }
  }

  Future<void> _handleSupport() async {
    final Uri launchUri = Uri(scheme: 'tel', path: '+8801999999999');
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    }
  }

  void _handleShareTrip() {
    Share.share(
      'I am currently on a GoRide trip!\n'
      '🚕 Ride: ${widget.rideType.toUpperCase()}\n'
      '📍 From: ${widget.pickup}\n'
      '🏁 To: ${widget.destination}\n'
      '💳 Total: ৳${widget.price.toStringAsFixed(0)}\n'
      'Keep track of my journey for safety.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Map
          _buildMap(),

          // Back Button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: CircleAvatar(
                backgroundColor: Colors.white,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.black),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ),

          // Draggable Bottom Sheet for details
          DraggableScrollableSheet(
            initialChildSize: 0.45,
            minChildSize: 0.45,
            maxChildSize: 0.9,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20)],
                ),
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(24),
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Status Badge
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10713C).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.access_time, color: Color(0xFF10713C), size: 18),
                            SizedBox(width: 8),
                            Text(
                              _etaMinutes > 0 ? 'Driver is arriving in $_etaMinutes mins' : 'Driver is arriving...',
                              style: TextStyle(color: Color(0xFF10713C), fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Route Info
                    _buildRouteInfo(),
                    
                    const Divider(height: 48),

                    // Safety & Support
                    const Text(
                      'Safety & Support',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _buildSafetyOption(
                          icon: Icons.share_location_rounded,
                          label: 'Share Trip',
                          color: Colors.blue,
                          onTap: _handleShareTrip,
                        ),
                        const SizedBox(width: 12),
                        _buildSafetyOption(
                          icon: Icons.emergency_share_rounded,
                          label: 'Emergency',
                          color: Colors.red,
                          onTap: _handleEmergency,
                        ),
                        const SizedBox(width: 12),
                        _buildSafetyOption(
                          icon: Icons.headset_mic_rounded,
                          label: 'Support',
                          color: Colors.orange,
                          onTap: _handleSupport,
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    if (_tripProgress > 0) ...[
                      const Text('Trip Progress', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: _tripProgress,
                          minHeight: 8,
                          backgroundColor: Colors.grey[200],
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10713C)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('${(_tripProgress * 100).toInt()}% complete', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                      const Divider(height: 48),
                    ],
                    // Fare Details
                    const Text(
                      'Fare Details',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    _buildFareRow('Base Fare', '৳50.00'),
                    _buildFareRow('Distance Fare', '৳${(widget.price - 50 - 10).toStringAsFixed(2)}'),
                    _buildFareRow('Service Fee', '৳10.00'),
                    const Divider(height: 24),
                    _buildFareRow('Total (Incl. Tax)', '৳${widget.price.toStringAsFixed(2)}', isTotal: true),
                    
                    const SizedBox(height: 32),
                    
                    // Driver Summary (Mini)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: const Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundImage: AssetImage('assets/user-avatar.png'),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Md. Abdur Rahman', style: TextStyle(fontWeight: FontWeight.bold)),
                                Text('Toyota Corolla • DHK-1234', style: TextStyle(fontSize: 12, color: Colors.grey)),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              Icon(Icons.star, color: Colors.amber, size: 16),
                              Text(' 4.9', style: TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return fmap.FlutterMap(
      mapController: _mapController,
      options: fmap.MapOptions(
        initialCenter: _currentPosition != null 
            ? latlong.LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
            : const latlong.LatLng(23.8103, 90.4125),
        initialZoom: 15,
      ),
      children: [
        fmap.TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.goride.app',
        ),
        fmap.PolylineLayer(
          polylines: [
            if (_routePoints.isNotEmpty)
              fmap.Polyline(
                points: _routePoints,
                color: const Color(0xFF10713C),
                strokeWidth: 4.0,
              ),
          ],
        ),
        fmap.MarkerLayer(
          markers: [
            if (_currentPosition != null)
              fmap.Marker(
                point: latlong.LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                width: 40,
                height: 40,
                child: const Icon(Icons.my_location, color: Colors.blue, size: 30),
              ),
            fmap.Marker(
              point: latlong.LatLng(_driverLat, _driverLng),
              width: 50,
              height: 50,
              child: const Icon(Icons.directions_car, color: Color(0xFF10713C), size: 40),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRouteInfo() {
    return Column(
      children: [
        Row(
          children: [
            const Icon(Icons.my_location, color: Color(0xFF10713C), size: 20),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Pickup', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  Text(widget.pickup, style: const TextStyle(fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(left: 9),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(height: 24, child: VerticalDivider(width: 1, thickness: 1)),
          ),
        ),
        Row(
          children: [
            const Icon(Icons.location_on, color: Colors.red, size: 20),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Destination', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  Text(widget.destination, style: const TextStyle(fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFareRow(String label, String amount, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isTotal ? Colors.black : Colors.grey[600],
            ),
          ),
          Text(
            amount,
            style: TextStyle(
              fontSize: isTotal ? 20 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
              color: isTotal ? const Color(0xFF10713C) : Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.15), width: 1.5),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(height: 10),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
