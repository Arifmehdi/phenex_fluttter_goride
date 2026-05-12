import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:latlong2/latlong.dart' as latlong;
import 'package:geolocator/geolocator.dart';

// Set this to true to use Google Maps, false to fallback to OpenStreetMap
const bool useGoogleMaps = false;

class DhakaMapScreen extends StatefulWidget {
  const DhakaMapScreen({super.key});

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
  String? _selectedRide; // Added to track selected ride

  final List<String> _locations = ['', '']; // pickup, destination
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _fMapController = fmap.MapController();
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
      appBar: AppBar(
        title: Text(_isRideFound ? 'Available Rides' : 'Select Location'),
        backgroundColor: const Color(0xFF10713C),
        foregroundColor: Colors.white,
        actions: [
          if (_pickupLocation != null || _destinationLocation != null)
            IconButton(
              icon: const Icon(Icons.refresh),
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
        ],
      ),
      body: Stack(
        children: [
          (useGoogleMaps && !_gMapError) ? _buildGoogleMap() : _buildFlutterMap(),

          // Selection Panel
          Positioned(
            bottom: 30, // Moved up from 0
            left: 16,
            right: 16,
            child: Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: _isRideFound ? _buildRideOptions() : _buildLocationSelectionPanel(),
              ),
            ),
          ),

          // Instruction overlay
          if (!_isRideFound)
            Positioned(
              top: 50, // Moved down from 16 to be more visible under AppBar if needed
              left: 16,
              right: 16,
              child: Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    _selectingPickup 
                      ? 'Tap on map to set Pickup' 
                      : (_destinationLocation == null ? 'Tap on map to set Destination' : 'Locations set! Check details below.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold),
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
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 5)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLocationRow(Icons.my_location, _pickupAddress, const Color(0xFF10713C), () {
            setState(() => _selectingPickup = true);
          }, _selectingPickup),
          const SizedBox(height: 8),
          _buildLocationRow(Icons.location_on, _destinationAddress, const Color(0xFFED1C24), () {
            setState(() => _selectingPickup = false);
          }, !_selectingPickup),
          const SizedBox(height: 16),
          if (_pickupLocation != null && _destinationLocation != null) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Distance: ${_distance.toStringAsFixed(2)} km'),
                Text('Est. Price: ৳${_price.toStringAsFixed(0)}', 
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF10713C))),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => setState(() => _isRideFound = true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10713C),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Find Rides', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ] else
            TextButton(
              onPressed: _showLocationBottomSheet,
              child: const Text('Or Search Location', style: TextStyle(color: Color(0xFF10713C))),
            ),
        ],
      ),
    );
  }

  Widget _buildLocationRow(IconData icon, String address, Color color, VoidCallback onTap, bool isSelected) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: isSelected ? color : Colors.grey[300]!, width: isSelected ? 2 : 1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(child: Text(address, style: TextStyle(color: Colors.grey[800], fontSize: 14))),
            if (isSelected) Icon(Icons.check_circle, color: color, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildRideOptions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 5)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Select your ride', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _buildRideItem(
            'GoRide Car', 
            '4 seats • 5 min away', 
            _price, 
            'assets/car.png',
            _selectedRide == 'car',
            () => setState(() => _selectedRide = 'car'),
          ),
          _buildRideItem(
            'GoRide Bike', 
            '1 seat • 2 min away', 
            _price * 0.6, 
            'assets/motor.png',
            _selectedRide == 'bike',
            () => setState(() => _selectedRide = 'bike'),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selectedRide == null ? null : () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${_selectedRide == 'car' ? 'Car' : 'Bike'} Requested Successfully!'), 
                    backgroundColor: const Color(0xFF10713C)
                  ),
                );
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10713C),
                disabledBackgroundColor: Colors.grey[300],
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Confirm Ride', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRideItem(String name, String detail, double price, String imagePath, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF10713C).withOpacity(0.05) : Colors.white,
          border: Border.all(
            color: isSelected ? const Color(0xFF10713C) : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Image.asset(imagePath, height: 40, width: 40, errorBuilder: (c, e, s) => const Icon(Icons.directions_car)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(detail, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('৳${price.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                if (isSelected)
                  const Icon(Icons.check_circle, color: Color(0xFF10713C), size: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }

}
