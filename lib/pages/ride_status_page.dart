import 'package:flutter/material.dart';
import 'dart:async';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:get/get.dart';
import 'trip_details_page.dart';
import 'live_tracking_screen.dart';
import '../services/ride_service.dart';
import '../utils/marker_utils.dart';

class RideStatusScreen extends StatefulWidget {
  final String rideType;
  final String pickup;
  final String destination;
  final double price;

  const RideStatusScreen({
    super.key,
    required this.rideType,
    required this.pickup,
    required this.destination,
    required this.price,
  });

  @override
  State<RideStatusScreen> createState() => _RideStatusScreenState();
}

class _RideStatusScreenState extends State<RideStatusScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  GoogleMapController? _mapController;
  bool _isDriverFound = false;
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStreamSubscription;
  
  final RideService _rideService = Get.find<RideService>();
  BitmapDescriptor? _vehicleIcon;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _loadIcons();
    _startLiveTracking();
    _requestRide();
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
  }

  void _requestRide() {
    _rideService.requestRide(
      rideType: widget.rideType,
      pickupLat: 23.8103,
      pickupLng: 90.4125,
      pickupAddress: widget.pickup,
      destLat: 23.7925,
      destLng: 90.4078,
      destAddress: widget.destination,
      fare: widget.price,
    );
    // Fallback: also use timer for demo
    Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _isDriverFound = true);
        _controller.stop();
      }
    });
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
    _controller.dispose();
    super.dispose();
  }

  void _handleChat() {
    // Navigate to chat
  }

  void _handleCall() async {
    final uri = Uri(scheme: 'tel', path: '+8801234567890');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _handleShare() {
    Share.share(
      'I am on my way using GoRide!\n'
      'Ride Type: ${widget.rideType}\n'
      'From: ${widget.pickup}\n'
      'To: ${widget.destination}\n'
      'Price: ৳${widget.price.toStringAsFixed(0)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Background Map
          _buildMap(),

          // Header with back button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 8, left: 16),
              child: CircleAvatar(
                backgroundColor: Colors.white,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.black),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ),

          // Content Panel
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  child: _isDriverFound ? _buildDriverFoundPanel() : _buildSearchingPanel(),
                ),
              ),
            ),
          ),
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
              : const LatLng(23.8103, 90.4125),
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
              icon: _vehicleIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
              rotation: dHeading,
              anchor: const Offset(0.5, 0.5),
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
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, spreadRadius: 5),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF10713C).withOpacity(1 - _controller.value),
                        width: 4 * _controller.value,
                      ),
                    ),
                  );
                },
              ),
              const CircleAvatar(
                radius: 35,
                backgroundColor: Color(0xFF10713C),
                child: Icon(Icons.search, color: Colors.white, size: 35),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'Finding your rider...',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Searching for nearby ${widget.rideType}s',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Cancel Request', style: TextStyle(color: Colors.red)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverFoundPanel() {
    return Container(
      key: const ValueKey('found'),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, spreadRadius: 5),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 30,
                backgroundImage: AssetImage('assets/user-avatar.png'),
              ),
              const SizedBox(width: 15),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ariful Islam',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Toyota Corolla • DHK-7452',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF10713C).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.star, color: Colors.amber, size: 16),
                    Text(' 4.9', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildActionButton(Icons.chat, 'Message', _handleChat),
              _buildActionButton(Icons.call, 'Call', _handleCall),
              _buildActionButton(Icons.share, 'Share', _handleShare),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: () {
                Get.to(() => LiveTrackingScreen(
                  rideType: widget.rideType,
                  pickupAddress: widget.pickup,
                  destinationAddress: widget.destination,
                  price: widget.price,
                  pickupLat: 23.8103,
                  pickupLng: 90.4125,
                  destLat: 23.7925,
                  destLng: 90.4078,
                ));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10713C),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: const Text(
                'View Live Tracking',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          CircleAvatar(
            backgroundColor: Colors.grey[100],
            child: Icon(icon, color: Colors.black87),
          ),
          const SizedBox(height: 5),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
