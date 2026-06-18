import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../services/places_service.dart';

class MapPickerScreen extends StatefulWidget {
  final LatLng? initialLocation;
  final String title;

  const MapPickerScreen({
    super.key,
    this.initialLocation,
    this.title = 'Set Location',
  });

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  GoogleMapController? _mapController;
  LatLng? _currentCenter;
  String _currentAddress = 'Loading...';
  bool _isMoving = false;
  final PlacesService _placesService = PlacesService();

  @override
  void initState() {
    super.initState();
    _currentCenter = widget.initialLocation ?? const LatLng(23.8103, 90.4125);
    if (widget.initialLocation == null) {
      _determinePosition();
    } else {
      _getAddress(_currentCenter!);
    }
  }

  Future<void> _determinePosition() async {
    try {
      Position position = await Geolocator.getCurrentPosition();
      LatLng currentLatLng = LatLng(position.latitude, position.longitude);
      setState(() {
        _currentCenter = currentLatLng;
      });
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(currentLatLng, 16));
      _getAddress(currentLatLng);
    } catch (e) {
      debugPrint('Error getting location: $e');
      _getAddress(_currentCenter!);
    }
  }

  Future<void> _getAddress(LatLng location) async {
    try {
      final address = await _placesService.getAddressFromLatLng(
        location.latitude,
        location.longitude,
      );
      if (mounted) {
        setState(() {
          _currentAddress = address ?? 'Unknown Location';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _currentAddress = 'Unknown Location';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _currentCenter!,
              zoom: 16,
            ),
            onMapCreated: (controller) => _mapController = controller,
            onCameraMove: (position) {
              setState(() {
                _isMoving = true;
                _currentCenter = position.target;
              });
            },
            onCameraIdle: () {
              setState(() => _isMoving = false);
              _getAddress(_currentCenter!);
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),
          // Fixed Center Pin
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 35),
              child: Icon(
                Icons.location_on,
                size: 45,
                color: _isMoving ? Colors.red.withOpacity(0.7) : Colors.red,
              ),
            ),
          ),
          // Location Info Card
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 10), // Reduced bottom, SafeArea will handle the rest
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: Colors.red),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _currentAddress,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isMoving ? null : () {
                          Navigator.pop(context, {
                            'lat': _currentCenter!.latitude,
                            'lng': _currentCenter!.longitude,
                            'address': _currentAddress,
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10713C),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Confirm Location', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // My Location Button
          Positioned(
            right: 16,
            bottom: 160,
            child: FloatingActionButton(
              onPressed: _determinePosition,
              backgroundColor: Colors.white,
              mini: true,
              child: const Icon(Icons.my_location, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}
