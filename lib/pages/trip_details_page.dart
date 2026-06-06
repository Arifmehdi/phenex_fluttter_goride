import 'package:flutter/material.dart';
import 'dart:async';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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
  GoogleMapController? _mapController;
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStreamSubscription;

  final RideService _rideService = Get.find<RideService>();
  final LocationService _locationService = Get.find<LocationService>();
  final RoutingService _routingService = Get.find<RoutingService>();

  List<LatLng> _routePoints = [];
  bool _isLoadingRoute = false;
  double _tripProgress = 0.0;
  int _etaMinutes = 3;
  double _driverLat = 23.8103;
  double _driverLng = 90.4125;

  @override
  void initState() {
    super.initState();
    _startLiveTracking();
    _fetchRoute();
  }

  void _fetchRoute() {
    // Simplified: use default coordinates for demo
    const origin = LatLng(23.8103, 90.4125);
    const dest = LatLng(23.7925, 90.4078);
    _loadRoute(origin, dest);
  }

  Future<void> _loadRoute(LatLng origin, LatLng dest) async {
    setState(() => _isLoadingRoute = true);
    final route = await _routingService.getRoute(origin: origin, destination: dest);
    if (route != null && mounted) {
      setState(() {
        _routePoints = route.points;
        _etaMinutes = route.duration.toInt();
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
          _mapController?.animateCamera(
            CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)),
          );
        }
      },
    );
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  void _handleShareTrip() {
    Share.share(
      'My trip details from GoRide:\n'
      '🚕 ${widget.rideType.toUpperCase()}\n'
      '📍 Pickup: ${widget.pickup}\n'
      '🏁 Destination: ${widget.destination}\n'
      '💳 Total: ৳${widget.price.toStringAsFixed(0)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Header Background
          Container(
            height: 300,
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Color(0xFF10713C),
            ),
          ),

          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                expandedHeight: 250,
                backgroundColor: const Color(0xFF10713C),
                elevation: 0,
                leading: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: CircleAvatar(
                    backgroundColor: Colors.white.withOpacity(0.9),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.black),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: CircleAvatar(
                      backgroundColor: Colors.white.withOpacity(0.9),
                      child: IconButton(
                        icon: const Icon(Icons.share, color: Colors.black),
                        onPressed: _handleShareTrip,
                      ),
                    ),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    children: [
                      _buildMap(),
                      Container(
                        decoration: BoxDecoration(
                          gradient: Alignment.bottomCenter.gradient([
                            Colors.black.withOpacity(0.4),
                            Colors.transparent,
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      _buildStatusHeader(),
                      const Divider(height: 40),
                      _buildRouteInfo(),
                      const Divider(height: 40),
                      _buildFareDetails(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: _currentPosition != null
            ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
            : const LatLng(23.8103, 90.4125),
        zoom: 15,
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
        Marker(
          markerId: const MarkerId('driver'),
          position: LatLng(_driverLat, _driverLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
        Marker(
          markerId: const MarkerId('destination'),
          position: const LatLng(23.7925, 90.4078),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      },
      polylines: {
        if (_routePoints.isNotEmpty)
          Polyline(
            polylineId: const PolylineId('route'),
            points: _routePoints,
            color: const Color(0xFF10713C),
            width: 4,
          ),
      },
    );
  }

  Widget _buildRouteInfo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          _buildLocationRow(Icons.my_location, 'Pickup', widget.pickup, const Color(0xFF10713C)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Container(width: 2, height: 30, color: Colors.grey[200]),
          ),
          const SizedBox(height: 8),
          _buildLocationRow(Icons.location_on, 'Destination', widget.destination, const Color(0xFFED1C24)),
        ],
      ),
    );
  }

  Widget _buildLocationRow(IconData icon, String label, String address, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(address, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Arriving in $_etaMinutes mins',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Your ${widget.rideType} is on the way',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF10713C).withOpacity(0.1),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Image.asset('assets/${widget.rideType}.png', height: 40, errorBuilder: (_,__,___) => const Icon(Icons.directions_car)),
          ),
        ],
      ),
    );
  }

  Widget _buildFareDetails() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Fare Breakdown', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          _buildFareRow('Base Fare', '৳${(widget.price - 10).toStringAsFixed(2)}'),
          const SizedBox(height: 12),
          _buildFareRow('Service Fee', '৳10.00'),
          const Divider(height: 40),
          _buildFareRow('Total Fare', '৳${widget.price.toStringAsFixed(2)}', isTotal: true),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildFareRow(String label, String value, {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: isTotal ? 18 : 15, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal)),
        Text(value, style: TextStyle(fontSize: isTotal ? 18 : 15, fontWeight: FontWeight.bold, color: isTotal ? const Color(0xFF10713C) : Colors.black)),
      ],
    );
  }
}

extension on Alignment {
  Gradient gradient(List<Color> colors) {
    return LinearGradient(
      begin: this,
      end: Alignment.topCenter,
      colors: colors,
    );
  }
}
