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

  final List<String> _locations = ['', '']; // pickup, destination
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _fMapController = fmap.MapController();
    _checkPermission();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showLocationBottomSheet();
    });
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
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        ...List.generate(_locations.length, (index) {
                          final isPickup = index == 0;
                          final isDestination = index == _locations.length - 1;
                          final stopNumber = isPickup
                              ? 1
                              : isDestination
                              ? _locations.length
                              : index;
                          return Column(
                            key: ValueKey(index),
                            children: [
                              Row(
                                children: [
                                  Column(
                                    children: [
                                      Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: isPickup
                                              ? const Color(0xFF10713C)
                                              : isDestination
                                              ? const Color(0xFFED1C24)
                                              : Colors.grey,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      if (!isDestination)
                                        Container(
                                          width: 2,
                                          height: 30,
                                          color: Colors.grey[400],
                                        ),
                                    ],
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextField(
                                      decoration: InputDecoration(
                                        hintText: isPickup
                                            ? 'Pickup location'
                                            : isDestination
                                            ? 'Final destination'
                                            : 'Stop $stopNumber',
                                        hintStyle: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 14,
                                        ),
                                        border: InputBorder.none,
                                      ),
                                    ),
                                  ),
                                  if (!isPickup && !isDestination)
                                    IconButton(
                                      icon: Icon(
                                        Icons.close,
                                        size: 18,
                                        color: Colors.grey[600],
                                      ),
                                      onPressed: null,
                                    ),
                                ],
                              ),
                              if (!isDestination)
                                Divider(color: Colors.grey[300]),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10713C),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Find Rides',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
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
                      ),
                      _buildPopularPlace(Icons.work, 'Office', 'Banani, Dhaka'),
                      _buildPopularPlace(
                        Icons.flight,
                        'Airport',
                        'Hazrat Shahjalal International',
                      ),
                      _buildPopularPlace(
                        Icons.store,
                        'Shopping',
                        'Jamuna Future Park',
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

  Widget _buildPopularPlace(IconData icon, String title, String address) {
    return Padding(
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
      ),
      children: [
        fmap.TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.goride.app',
        ),
        fmap.MarkerLayer(
          markers: [
            fmap.Marker(
              point: _currentPosition != null
                  ? latlong.LatLng(
                      _currentPosition!.latitude,
                      _currentPosition!.longitude,
                    )
                  : _dhakaCenterFallback,
              width: 40,
              height: 40,
              child: const Icon(
                Icons.location_on,
                color: Color(0xFF10713C),
                size: 40,
              ),
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
        title: const Text('Select Location'),
        backgroundColor: const Color(0xFF10713C),
        foregroundColor: Colors.white,
      ),
      body: (useGoogleMaps && !_gMapError)
          ? _buildGoogleMap()
          : _buildFlutterMap(),
    );
  }
}
