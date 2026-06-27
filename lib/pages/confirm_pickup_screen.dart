import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:get/get.dart';
import '../services/places_service.dart';

/// Uber / Pathao / InDrive style "Confirm Pickup Point" screen.
/// A fixed pin sits in the center; the user drags the map under it.
/// On camera idle the center coordinate is reverse-geocoded to an address.
///
/// Returns a Map { 'lat', 'lng', 'address' } via Get.back(result: ...).
class ConfirmPickupScreen extends StatefulWidget {
  final double initialLat;
  final double initialLng;
  final String initialAddress;

  const ConfirmPickupScreen({
    super.key,
    required this.initialLat,
    required this.initialLng,
    required this.initialAddress,
  });

  @override
  State<ConfirmPickupScreen> createState() => _ConfirmPickupScreenState();
}

class _ConfirmPickupScreenState extends State<ConfirmPickupScreen>
    with SingleTickerProviderStateMixin {
  final PlacesService _placesService = PlacesService();
  GoogleMapController? _mapController;

  late LatLng _centerLatLng;
  String _address = '';
  bool _isMoving = false;
  bool _isLoadingAddress = false;
  Timer? _debounce;

  // Bounce animation for the pin while dragging
  late AnimationController _pinController;
  late Animation<double> _pinLift;

  @override
  void initState() {
    super.initState();
    _centerLatLng = LatLng(widget.initialLat, widget.initialLng);
    _address = widget.initialAddress;

    _pinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _pinLift = Tween<double>(begin: 0, end: -12).animate(
      CurvedAnimation(parent: _pinController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _mapController?.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _onCameraMoveStarted() {
    if (!_isMoving) {
      setState(() => _isMoving = true);
      _pinController.forward();
    }
  }

  void _onCameraMove(CameraPosition pos) {
    _centerLatLng = pos.target;
  }

  void _onCameraIdle() {
    setState(() => _isMoving = false);
    _pinController.reverse();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _reverseGeocode);
  }

  Future<void> _reverseGeocode() async {
    setState(() => _isLoadingAddress = true);
    try {
      String? addr = await _placesService.getAddressFromLatLng(
          _centerLatLng.latitude, _centerLatLng.longitude);
      if (addr == null) {
        final placemarks = await placemarkFromCoordinates(
            _centerLatLng.latitude, _centerLatLng.longitude);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          addr = [p.name, p.subLocality, p.locality]
              .where((s) => s != null && s.isNotEmpty)
              .join(', ');
        }
      }
      if (mounted) {
        setState(() {
          _address = (addr == null || addr.isEmpty) ? 'Pinned location' : addr;
          _isLoadingAddress = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingAddress = false);
    }
  }

  void _recenterToInitial() {
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(
          LatLng(widget.initialLat, widget.initialLng), 17),
    );
  }

  void _confirm() {
    Get.back(result: {
      'lat': _centerLatLng.latitude,
      'lng': _centerLatLng.longitude,
      'address': _address,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Map
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _centerLatLng,
              zoom: 17,
            ),
            onMapCreated: (c) => _mapController = c,
            onCameraMoveStarted: _onCameraMoveStarted,
            onCameraMove: _onCameraMove,
            onCameraIdle: _onCameraIdle,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
          ),

          // Fixed center pin
          _buildCenterPin(),

          // Back button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 8, left: 16),
              child: _circleButton(
                icon: Icons.arrow_back,
                onTap: () => Get.back(),
              ),
            ),
          ),

          // "Set your pickup location" hint at top
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 70),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Move the map to set pickup',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ),
          ),

          // Recenter button (above the bottom card)
          Positioned(
            right: 16,
            bottom: 200,
            child: _circleButton(
              icon: Icons.my_location,
              iconColor: const Color(0xFF10713C),
              onTap: _recenterToInitial,
            ),
          ),

          // Bottom confirm card
          _buildBottomCard(),
        ],
      ),
    );
  }

  Widget _buildCenterPin() {
    // The pin tip should point at the exact center of the map.
    return Center(
      child: AnimatedBuilder(
        animation: _pinLift,
        builder: (context, child) {
          return Padding(
            // pin height ~48, lift it so the tip stays on center
            padding: EdgeInsets.only(bottom: 48 + (-_pinLift.value)),
            child: child,
          );
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF10713C),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('PICKUP',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1)),
            ),
            const SizedBox(height: 2),
            const Icon(Icons.location_on, color: Color(0xFF10713C), size: 44),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomCard() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(color: Colors.black12, blurRadius: 16, offset: Offset(0, -4)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Confirm pickup point',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            // Address row
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10713C).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.location_on,
                        color: Color(0xFF10713C), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _isLoadingAddress
                        ? Row(
                            children: [
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Color(0xFF10713C)),
                              ),
                              const SizedBox(width: 10),
                              Text('Finding address...',
                                  style: TextStyle(
                                      color: Colors.grey[500], fontSize: 13)),
                            ],
                          )
                        : Text(
                            _address,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w500),
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: (_isMoving || _isLoadingAddress) ? null : _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10713C),
                  disabledBackgroundColor: Colors.grey[300],
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Confirm Pickup',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required VoidCallback onTap,
    Color iconColor = Colors.black87,
  }) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: iconColor),
        ),
      ),
    );
  }
}
