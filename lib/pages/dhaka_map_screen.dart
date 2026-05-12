import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:latlong2/latlong.dart' as latlong;
import 'package:geolocator/geolocator.dart';
import 'ride_status_page.dart';

// Set this to true to use Google Maps, false to fallback to OpenStreetMap
const bool useGoogleMaps = false;

class DhakaMapScreen extends StatefulWidget {
  final String? initialRideType;
  final String? pickupAddress;
  final String? destinationAddress;
  
  const DhakaMapScreen({
    super.key, 
    this.initialRideType,
    this.pickupAddress,
    this.destinationAddress,
  });

  @override
  State<DhakaMapScreen> createState() => _DhakaMapScreenState();
}

class _DhakaMapScreenState extends State<DhakaMapScreen> {
  // Common coordinates
  static const latlong.LatLng _dhakaCenterFallback = latlong.LatLng(
    23.8103,
    90.4125,
  );
  static const gmaps.LatLng _dhakaCenterGmaps = gmaps.LatLng(23.8103, 90.4125);

  // Google Maps controllers and state
  gmaps.GoogleMapController? _gMapController;
  bool _gMapError = false;

  // Flutter Map (OSM) controllers
  late final fmap.MapController _fMapController;

  latlong.LatLng? _pickupLocation;
  latlong.LatLng? _destinationLocation;
  String _pickupAddress = 'Select Pickup Location';
  String _destinationAddress = 'Select Destination';
  double _distance = 0.0;
  double _price = 0.0;
  bool _selectingPickup = true;
  bool _isRideFound = false;
  String? _selectedRide;
  String _selectedPayment = 'Cash';

  final List<String> _locations = ['', '']; // pickup, destination
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _fMapController = fmap.MapController();
    _selectedRide = widget.initialRideType?.toLowerCase();
    
    if (widget.pickupAddress != null && widget.destinationAddress != null) {
      _pickupAddress = widget.pickupAddress!;
      _destinationAddress = widget.destinationAddress!;
      // Mock coordinates for demo
      _pickupLocation = const latlong.LatLng(23.8103, 90.4125);
      _destinationLocation = const latlong.LatLng(23.7925, 90.4078);
      _isRideFound = true;
      _calculateRideDetails();
    }
    
    _checkPermission();
  }

  void _onMapTap(latlong.LatLng point) {
    setState(() {
      if (_selectingPickup) {
        _pickupLocation = point;
        _pickupAddress = "Custom Pickup Location"; // In a real app, use geocoding
        _selectingPickup = false;
      } else {
        _destinationLocation = point;
        _destinationAddress = "Custom Destination"; // In a real app, use geocoding
      }
      _calculateRideDetails();
    });
  }

  void _calculateRideDetails() {
    if (_pickupLocation != null && _destinationLocation != null) {
      final double distanceInMeters = Geolocator.distanceBetween(
        _pickupLocation!.latitude,
        _pickupLocation!.longitude,
        _destinationLocation!.latitude,
        _destinationLocation!.longitude,
      );
      _distance = distanceInMeters / 1000; // convert to km
      
      // Basic pricing logic: 50 base + 20 per km
      _price = 50 + (_distance * 20);
    }
  }

  Future<void> _checkPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentPosition = position;
      });

      if (useGoogleMaps && !_gMapError && _gMapController != null) {
        _gMapController!.animateCamera(
          gmaps.CameraUpdate.newCameraPosition(
            gmaps.CameraPosition(
              target: gmaps.LatLng(position.latitude, position.longitude),
              zoom: 15,
            ),
          ),
        );
      } else if (!useGoogleMaps || _gMapError) {
        _fMapController.move(
          latlong.LatLng(position.latitude, position.longitude),
          15,
        );
      }
    } catch (e) {
      debugPrint("Error getting location: $e");
    }
  }

  void _showLocationBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.80,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                  const Expanded(
                    child: Text(
                      'Select Location',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Popular Places',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildPopularPlace(
                        Icons.home,
                        'Home',
                        'Gulshan 2, Dhaka',
                        const latlong.LatLng(23.7925, 90.4078),
                      ),
                      _buildPopularPlace(
                        Icons.work, 
                        'Office', 
                        'Banani, Dhaka',
                        const latlong.LatLng(23.7937, 90.4066),
                      ),
                      _buildPopularPlace(
                        Icons.flight,
                        'Airport',
                        'Hazrat Shahjalal International',
                        const latlong.LatLng(23.8433, 90.3978),
                      ),
                      _buildPopularPlace(
                        Icons.store,
                        'Shopping',
                        'Jamuna Future Park',
                        const latlong.LatLng(23.8135, 90.4242),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPopularPlace(IconData icon, String title, String address, latlong.LatLng coords) {
    return InkWell(
      onTap: () {
        setState(() {
          if (_selectingPickup) {
            _pickupLocation = coords;
            _pickupAddress = address;
            _selectingPickup = false;
          } else {
            _destinationLocation = coords;
            _destinationAddress = address;
          }
          _calculateRideDetails();
          _fMapController.move(coords, 15);
        });
        Navigator.pop(context);
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF10713C).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: const Color(0xFF10713C), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    address,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildGoogleMap() {
    return gmaps.GoogleMap(
      initialCameraPosition: const gmaps.CameraPosition(
        target: _dhakaCenterGmaps,
        zoom: 13,
      ),
      onMapCreated: (controller) {
        _gMapController = controller;
        if (_currentPosition != null) {
          _gMapController!.animateCamera(
            gmaps.CameraUpdate.newCameraPosition(
              gmaps.CameraPosition(
                target: gmaps.LatLng(
                  _currentPosition!.latitude,
                  _currentPosition!.longitude,
                ),
                zoom: 15,
              ),
            ),
          );
        }
      },
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      markers: {
        gmaps.Marker(
          markerId: const gmaps.MarkerId('center'),
          position: _dhakaCenterGmaps,
          icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
            gmaps.BitmapDescriptor.hueGreen,
          ),
        ),
      },
    );
  }

  Widget _buildFlutterMap() {
    return fmap.FlutterMap(
      mapController: _fMapController,
      options: fmap.MapOptions(
        initialCenter: _currentPosition != null
            ? latlong.LatLng(
                _currentPosition!.latitude,
                _currentPosition!.longitude,
              )
            : _dhakaCenterFallback,
        initialZoom: 13,
        onTap: (tapPosition, point) => _onMapTap(point),
      ),
      children: [
        fmap.TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.goride.app',
        ),
        fmap.MarkerLayer(
          markers: [
            if (_currentPosition != null)
              fmap.Marker(
                point: latlong.LatLng(
                  _currentPosition!.latitude,
                  _currentPosition!.longitude,
                ),
                width: 40,
                height: 40,
                child: const Icon(
                  Icons.my_location,
                  color: Colors.blue,
                  size: 30,
                ),
              ),
            if (_pickupLocation != null)
              fmap.Marker(
                point: _pickupLocation!,
                width: 40,
                height: 40,
                child: const Icon(
                  Icons.location_on,
                  color: Color(0xFF10713C),
                  size: 40,
                ),
              ),
            if (_destinationLocation != null)
              fmap.Marker(
                point: _destinationLocation!,
                width: 40,
                height: 40,
                child: const Icon(
                  Icons.location_on,
                  color: Color(0xFFED1C24),
                  size: 40,
                ),
              ),
          ],
        ),
        if (_pickupLocation != null && _destinationLocation != null)
          fmap.PolylineLayer(
            polylines: [
              fmap.Polyline(
                points: [_pickupLocation!, _destinationLocation!],
                color: const Color(0xFF10713C),
                strokeWidth: 4.0,
              ),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: CircleAvatar(
            backgroundColor: Colors.white,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
        title: Text(
          _isRideFound ? 'Your Route' : 'Select Location',
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_pickupLocation != null || _destinationLocation != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: CircleAvatar(
                backgroundColor: Colors.white,
                child: IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.black, size: 20),
                  onPressed: () {
                    setState(() {
                      _pickupLocation = null;
                      _destinationLocation = null;
                      _pickupAddress = 'Select Pickup Location';
                      _destinationAddress = 'Select Destination';
                      _distance = 0.0;
                      _price = 0.0;
                      _selectingPickup = true;
                      _isRideFound = false;
                    });
                  },
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          (useGoogleMaps && !_gMapError) ? _buildGoogleMap() : _buildFlutterMap(),

          // Location Summary at top when ride found
          if (_isRideFound)
            Positioned(
              top: 100,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.my_location, color: Color(0xFF10713C), size: 18),
                        const SizedBox(width: 12),
                        Expanded(child: Text(_pickupAddress, style: const TextStyle(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.only(left: 8, top: 4, bottom: 4),
                      child: Align(alignment: Alignment.centerLeft, child: SizedBox(height: 10, child: VerticalDivider(width: 1))),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: Colors.red, size: 18),
                        const SizedBox(width: 12),
                        Expanded(child: Text(_destinationAddress, style: const TextStyle(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // Selection Panel
          Positioned(
            bottom: 30,
            left: 16,
            right: 16,
            child: SafeArea(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: _isRideFound ? _buildRideOptions() : _buildLocationSelectionPanel(),
                ),
              ),
            ),
          ),

          // Instruction overlay
          if (!_isRideFound && (_pickupLocation == null || _destinationLocation == null))
            Positioned(
              top: 100,
              left: 16,
              right: 16,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                      )
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _selectingPickup ? Icons.my_location : Icons.location_on,
                        color: _selectingPickup ? const Color(0xFF10713C) : const Color(0xFFED1C24),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _selectingPickup ? 'Set Pickup on Map' : 'Set Destination on Map',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLocationSelectionPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 15,
            spreadRadius: 2,
            offset: Offset(0, -5),
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle for visual cue
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          
          // Location Inputs
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              children: [
                _buildLocationInput(
                  icon: Icons.my_location,
                  address: _pickupAddress,
                  color: const Color(0xFF10713C),
                  isSelected: _selectingPickup,
                  onTap: () => setState(() => _selectingPickup = true),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Divider(height: 1, color: Colors.grey[200]),
                ),
                _buildLocationInput(
                  icon: Icons.location_on,
                  address: _destinationAddress,
                  color: const Color(0xFFED1C24),
                  isSelected: !_selectingPickup,
                  onTap: () => setState(() => _selectingPickup = false),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Search / Popular Places Header
          const Text(
            'Popular Places',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),

          // Horizontal Popular Places
          SizedBox(
            height: 90,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildCompactPopularPlace(
                  Icons.home,
                  'Home',
                  'Gulshan 2',
                  const latlong.LatLng(23.7925, 90.4078),
                ),
                _buildCompactPopularPlace(
                  Icons.work,
                  'Office',
                  'Banani',
                  const latlong.LatLng(23.7937, 90.4066),
                ),
                _buildCompactPopularPlace(
                  Icons.flight,
                  'Airport',
                  'Uttara',
                  const latlong.LatLng(23.8433, 90.3978),
                ),
                _buildCompactPopularPlace(
                  Icons.store,
                  'Shopping',
                  'JFP',
                  const latlong.LatLng(23.8135, 90.4242),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          if (_pickupLocation != null && _destinationLocation != null) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Distance: ${_distance.toStringAsFixed(2)} km',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                    Text(
                      '৳${_price.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 24,
                        color: Color(0xFF10713C),
                      ),
                    ),
                  ],
                ),
                ElevatedButton(
                  onPressed: () => setState(() => _isRideFound = true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10713C),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Find Rides',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            ),
          ] else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _showLocationBottomSheet,
                icon: const Icon(Icons.search, size: 20),
                label: const Text('Search for more locations'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF10713C),
                  side: const BorderSide(color: Color(0xFF10713C)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLocationInput({
    required IconData icon,
    required String address,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                address,
                style: TextStyle(
                  color: isSelected ? Colors.black87 : Colors.grey[500],
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSelected)
              const Icon(Icons.edit, color: Colors.grey, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactPopularPlace(IconData icon, String title, String area, latlong.LatLng coords) {
    return GestureDetector(
      onTap: () {
        setState(() {
          if (_selectingPickup) {
            _pickupLocation = coords;
            _pickupAddress = "$title ($area)";
            _selectingPickup = false;
          } else {
            _destinationLocation = coords;
            _destinationAddress = "$title ($area)";
          }
          _calculateRideDetails();
          _fMapController.move(coords, 15);
        });
      },
      child: Container(
        width: 100,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFF10713C), size: 24),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              area,
              style: TextStyle(color: Colors.grey[500], fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRideOptions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          _buildRideItem(
            'Car', 
            '4 seats • 5 min away', 
            _price, 
            'assets/car.png',
            _selectedRide == 'car',
            () => setState(() => _selectedRide = 'car'),
          ),
          _buildRideItem(
            'Bike', 
            '1 seat • 2 min away', 
            _price * 0.6, 
            'assets/motor.png',
            _selectedRide == 'bike',
            () => setState(() => _selectedRide = 'bike'),
          ),
          const Divider(height: 32),
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedPayment = _selectedPayment == 'Cash' ? 'Card' : 'Cash';
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _selectedPayment == 'Cash' ? Icons.money : Icons.credit_card,
                        size: 20,
                        color: const Color(0xFF10713C),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _selectedPayment,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const Icon(Icons.keyboard_arrow_down, size: 16),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.local_offer_outlined, size: 18, color: Color(0xFF10713C)),
                label: const Text(
                  'Promo',
                  style: TextStyle(color: Color(0xFF10713C), fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selectedRide == null ? null : () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RideStatusScreen(
                      rideType: _selectedRide!,
                      pickup: _pickupAddress,
                      destination: _destinationAddress,
                      price: _selectedRide == 'car' ? _price : _price * 0.6,
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10713C),
                disabledBackgroundColor: Colors.grey[300],
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: Text(
                'Confirm ${_selectedRide?.toUpperCase() ?? 'RIDE'}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRideItem(String name, String detail, double price, String imagePath, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF10713C).withOpacity(0.05) : Colors.white,
          border: Border.all(
            color: isSelected ? const Color(0xFF10713C) : Colors.grey[200]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Image.asset(
                imagePath,
                height: 40,
                width: 40,
                errorBuilder: (c, e, s) => const Icon(Icons.directions_car, size: 30),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isSelected ? const Color(0xFF10713C) : Colors.black87,
                    ),
                  ),
                  Text(detail, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '৳${price.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                if (isSelected)
                  const Icon(Icons.check_circle, color: Color(0xFF10713C), size: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }

}
