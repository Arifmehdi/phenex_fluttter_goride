import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:get/get.dart';
import 'ride_status_page.dart';
import 'live_tracking_screen.dart';
import '../services/routing_service.dart';
import '../services/recent_locations_service.dart';
import '../services/sslcommerz_service.dart';

import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firebase_service.dart';

class DhakaMapScreen extends StatefulWidget {
  final String? initialRideType;
  final String? pickupAddress;
  final String? destinationAddress;
  final double? pickupLat;
  final double? pickupLng;
  final double? destLat;
  final double? destLng;

  const DhakaMapScreen({
    super.key,
    this.initialRideType,
    this.pickupAddress,
    this.destinationAddress,
    this.pickupLat,
    this.pickupLng,
    this.destLat,
    this.destLng,
  });

  @override
  State<DhakaMapScreen> createState() => _DhakaMapScreenState();
}

class _DhakaMapScreenState extends State<DhakaMapScreen> {
  static const LatLng _dhakaCenterFallback = LatLng(23.8103, 90.4125);
  late final MapController _mapController;

  LatLng? _pickupLocation;
  LatLng? _destinationLocation;
  String _pickupAddress = 'Select Pickup Location';
  String _destinationAddress = 'Select Destination';
  double _distance = 0.0;
  double _price = 0.0;
  bool _selectingPickup = true;
  bool _isConfirmingPickup = false;

  bool get _showRideOptions => _pickupLocation != null && _destinationLocation != null;
  String? _selectedRide;
  String _selectedPayment = 'Cash';

  Position? _currentPosition;
  StreamSubscription<Position>? _positionStreamSubscription;
  StreamSubscription<QuerySnapshot>? _driversSubscription;
  List<Marker> _driverMarkers = [];

  // OSRM route
  final RoutingService _routingService = Get.find<RoutingService>();
  final FirebaseService _firebaseService = Get.find<FirebaseService>();
  List<LatLng> _routePoints = [];
  double _routeDistance = 0.0;
  int _routeDuration = 0;
  bool _isLoadingRoute = false;

  // Recent locations
  final RecentLocationsService _recentLocationsService = RecentLocationsService();
  final SslCommerzService _sslCommerzService = Get.find<SslCommerzService>();
  List<RecentLocation> _recentLocations = [];

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _selectedRide = widget.initialRideType?.toLowerCase();

    // Use pre-selected coordinates from forward geocoding search (if provided)
    if (widget.pickupLat != null && widget.pickupLng != null) {
      _pickupLocation = LatLng(widget.pickupLat!, widget.pickupLng!);
      _pickupAddress = widget.pickupAddress ?? 'Selected Location';
    }
    if (widget.destLat != null && widget.destLng != null) {
      _destinationLocation = LatLng(widget.destLat!, widget.destLng!);
      _destinationAddress = widget.destinationAddress ?? 'Selected Destination';
    }

    // Fallback: old flow with addresses only (no coords)
    if (_pickupLocation == null && _destinationLocation == null &&
        widget.pickupAddress != null && widget.destinationAddress != null) {
      _pickupAddress = widget.pickupAddress!;
      _destinationAddress = widget.destinationAddress!;
      _pickupLocation = const LatLng(23.8103, 90.4125);
      _destinationLocation = const LatLng(23.7925, 90.4078);
    }

    // Both locations pre-set — skip GPS, go to ride selection
    if (_pickupLocation != null && _destinationLocation != null) {

      _calculateRideDetails();
    }

    // Center map on pre-selected location after first frame
    if (_pickupLocation != null || _destinationLocation != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _destinationLocation ?? _pickupLocation!;
        _mapController.move(target, 15.0);
      });
    }

    _loadRecentLocations();
    _checkPermission();
    _listenToNearbyDrivers();
  }

  void _listenToNearbyDrivers() {
    if (!_firebaseService.isInitialized) return;

    _driversSubscription = _firebaseService.driverLocations
        .where('isOnline', isEqualTo: true)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      
      final markers = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final lat = data['latitude'] as double;
        final lng = data['longitude'] as double;
        final heading = (data['heading'] as num?)?.toDouble() ?? 0.0;
        
        return Marker(
          point: LatLng(lat, lng),
          width: 40,
          height: 40,
          child: Transform.rotate(
            angle: heading * (pi / 180),
            child: Image.asset(
              'assets/car.png',
              width: 30,
              height: 30,
              errorBuilder: (context, error, stackTrace) => 
                  const Icon(Icons.directions_car, color: Colors.green, size: 25),
            ),
          ),
        );
      }).toList();

      setState(() {
        _driverMarkers = markers;
      });
    });
  }

  void _loadRecentLocations() {
    setState(() {
      _recentLocations = _recentLocationsService.getLocations();
    });
  }

  void _saveRecentLocation(String title, String area, LatLng coords, {String iconName = 'history'}) {
    _recentLocationsService.saveLocation(RecentLocation(
      title: title,
      area: area,
      lat: coords.latitude,
      lng: coords.longitude,
      iconName: iconName,
      timestamp: 0, // service overrides with current time
    ));
  
    _loadRecentLocations();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _driversSubscription?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _onMapTap(LatLng point) {
    final isPickupSelection = _selectingPickup;
    setState(() {
      if (isPickupSelection) {
        _pickupLocation = point;
        _pickupAddress = 'Loading address...';
        _selectingPickup = false;
      } else {
        _destinationLocation = point;
        _destinationAddress = 'Loading address...';
      }
    });
    _getAddressFromLatLngCoords(point.latitude, point.longitude, isPickup: isPickupSelection);
    _calculateRideDetails();
  }

  void _calculateRideDetails() {
    if (_pickupLocation != null && _destinationLocation != null) {
      _fetchRoute();
    }
  }

  Future<void> _fetchRoute() async {
    if (_pickupLocation == null || _destinationLocation == null) return;
    setState(() => _isLoadingRoute = true);
    final route = await _routingService.getRoute(
      origin: _pickupLocation!,
      destination: _destinationLocation!,
    );
    if (route != null && mounted) {
      setState(() {
        _routePoints = route.points;
        _routeDistance = route.distance;
        _routeDuration = route.duration.toInt();
        _distance = route.distance;
        _price = 50 + (route.distance * 20);
        _isLoadingRoute = false;
      });
      if (_routePoints.isNotEmpty) {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(_routePoints),
            padding: const EdgeInsets.all(80),
          ),
        );
      }
    } else {
      final double distanceInMeters = Geolocator.distanceBetween(
        _pickupLocation!.latitude,
        _pickupLocation!.longitude,
        _destinationLocation!.latitude,
        _destinationLocation!.longitude,
      );
      setState(() {
        _distance = distanceInMeters / 1000;
        _price = 50 + (_distance * 20);
        _isLoadingRoute = false;
      });
    }
  }

  Future<void> _checkPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    // Get position immediately so map centers on user right away
    await _getInitialPosition();
    _startLiveTracking();
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
            // Set initial pickup location and geocode proper address
            if (!_showRideOptions && _pickupLocation == null) {
              _pickupLocation = LatLng(position.latitude, position.longitude);
              _pickupAddress = 'Detecting location...';
            }
          });
          if (!_showRideOptions && _pickupLocation != null) {
            _mapController.move(
              LatLng(position.latitude, position.longitude),
              15.0,
            );
            _getAddressFromLatLngCoords(position.latitude, position.longitude, isPickup: true);
          }
        }
      },
    );
  }

  Future<void> _getAddressFromLatLngCoords(double lat, double lng, {required bool isPickup}) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty && mounted) {
        Placemark place = placemarks[0];
        String address = place.name != null && place.name!.isNotEmpty ? place.name! : '';
        if (place.subLocality != null && place.subLocality!.isNotEmpty) {
          address += '${address.isNotEmpty ? ', ' : ''}${place.subLocality}';
        }
        if (place.locality != null && place.locality!.isNotEmpty) {
          address += '${address.isNotEmpty ? ', ' : ''}${place.locality}';
        }
        address = address.replaceAll(RegExp(r', ,'), ',').trim();
        if (address.endsWith(',')) address = address.substring(0, address.length - 1).trim();
        if (address.isEmpty) address = '$lat, $lng';
        if (mounted) {
          setState(() {
            if (isPickup) {
              _pickupAddress = address;
            } else {
              _destinationAddress = address;
              // Save the resolved destination as a recent location
              if (_destinationLocation != null) {
                _saveRecentLocation(address.split(',').first.trim(), address, _destinationLocation!);
              }
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Geocoding error: $e');
    }
  }

  /// Immediately get current location on app open (faster than waiting for stream)
  Future<void> _getInitialPosition() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      if (!mounted) return;
      setState(() {
        _currentPosition = position;
        // Set initial pickup location right away
        if (!_showRideOptions && _pickupLocation == null) {
          _pickupLocation = LatLng(position.latitude, position.longitude);
          _pickupAddress = 'Detecting location...';
        }
      });
      if (!_showRideOptions && _pickupLocation != null) {
        _mapController.move(
          LatLng(position.latitude, position.longitude),
          15.0,
        );
        _getAddressFromLatLngCoords(position.latitude, position.longitude, isPickup: true);
      }
    } catch (e) {
      debugPrint('Initial position error: $e');
    }
  }

  /// Called when the map stops moving — geocodes the center pin location
  void _onMapCenterChanged() {
    if (_showRideOptions && !_isConfirmingPickup) return;
    final center = _mapController.camera.center;
    if (_isConfirmingPickup) {
      setState(() {
        _pickupLocation = center;
        _pickupAddress = 'Loading address...';
      });
      _getAddressFromLatLngCoords(center.latitude, center.longitude, isPickup: true);
      return;
    }
    if (_selectingPickup) {
      setState(() {
        _pickupLocation = center;
        _pickupAddress = 'Loading address...';
      });
      _getAddressFromLatLngCoords(center.latitude, center.longitude, isPickup: true);
    } else {
      setState(() {
        _destinationLocation = center;
        _destinationAddress = 'Loading address...';
      });
      _getAddressFromLatLngCoords(center.latitude, center.longitude, isPickup: false);
    }
    if (_pickupLocation != null && _destinationLocation != null) {
      _calculateRideDetails();
    }
  }

  /// Center map on GPS location (and set pickup/destination in selection mode)
  void _centerOnMyLocation() {
    if (_currentPosition == null) return;
    final pos = _currentPosition!;
    _mapController.move(
      LatLng(pos.latitude, pos.longitude),
      _mapController.camera.zoom,
    );

    // In ride options mode, just re-center the map (Uber/Pathao behavior)
    if (_showRideOptions) return;

    final isPickup = _selectingPickup;
    setState(() {
      if (isPickup) {
        _pickupLocation = LatLng(pos.latitude, pos.longitude);
        _pickupAddress = 'Loading address...';
        _selectingPickup = false;
      } else {
        _destinationLocation = LatLng(pos.latitude, pos.longitude);
        _destinationAddress = 'Loading address...';
      }
    });
    _getAddressFromLatLngCoords(pos.latitude, pos.longitude, isPickup: isPickup);
    if (_pickupLocation != null && _destinationLocation != null) {
      _calculateRideDetails();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          _buildMap(),
          if (_showRideOptions) _buildRouteSummaryHeader(),
          _buildControlPanel(),
          _buildInstructionOverlay(),
          // My Location floating button — always visible, bottom-right (Uber/Pathao style)
          if (_currentPosition != null)
            Positioned(
              bottom: 110,
              right: 16,
              child: FloatingActionButton.small(
                heroTag: 'my_location_fab',
                onPressed: _centerOnMyLocation,
                backgroundColor: Colors.white,
                elevation: 4,
                child: const Icon(
                  Icons.my_location,
                  color: Color(0xFF10713C),
                ),
              ),
            ),
          // Center map pin — stays fixed while user drags the map
          if (!_showRideOptions || _isConfirmingPickup)
            Center(
              child: IgnorePointer(
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 300),
                  offset: const Offset(0, -0.08), // Slight upward offset for visual pin placement
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Stack(
                      key: ValueKey(_isConfirmingPickup ? 'confirm' : _selectingPickup),
                      clipBehavior: Clip.none,
                      children: [
                        // Pin icon (bottom layer)
                        Icon(
                          Icons.location_on,
                          color: _isConfirmingPickup || _selectingPickup
                              ? const Color(0xFF10713C)
                              : const Color(0xFFED1C24),
                          size: 48,
                        ),
                        // Pin shadow (positioned just below the pin tip)
                        Positioned(
                          left: 16,
                          top: 34,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withValues(alpha: 0.3),
                              boxShadow: [
                                BoxShadow(blurRadius: 6, color: Colors.black.withValues(alpha: 0.2)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      leading: Padding(
        padding: const EdgeInsets.all(8.0),
        child: CircleAvatar(
          backgroundColor: Colors.white,
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black, size: 20),
            onPressed: () {
              if (_isConfirmingPickup) {
                setState(() => _isConfirmingPickup = false);
              } else {
                Navigator.pop(context);
              }
            },
          ),
        ),
      ),
      title: Text(
        _isConfirmingPickup ? 'Confirm Pickup' : (_showRideOptions ? 'Your Route' : 'Select Location'),
        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
      ),
      backgroundColor: Colors.transparent,
      elevation: 0,
      actions: [
        if (!_isConfirmingPickup && (_pickupLocation != null || _destinationLocation != null))
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: CircleAvatar(
              backgroundColor: Colors.white,
              child: IconButton(
                icon: const Icon(Icons.refresh, color: Colors.black, size: 20),
                onPressed: _resetSelection,
              ),
            ),
          ),
      ],
    );
  }

  void _resetSelection() {
    setState(() {
      _pickupLocation = null;
      _destinationLocation = null;
      _pickupAddress = 'Select Pickup Location';
      _destinationAddress = 'Select Destination';
      _distance = 0.0;
      _price = 0.0;
      _selectingPickup = true;
    });
  }

  Widget _buildMap() {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _currentPosition != null
                ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                : _dhakaCenterFallback,
            initialZoom: 15,
            onTap: (tapPosition, point) => _onMapTap(point),
            onMapEvent: (event) {
              if (event is MapEventMoveEnd) {
                _onMapCenterChanged();
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.goride.app',
            ),
            MarkerLayer(
              markers: [
                if (_currentPosition != null)
                  Marker(
                    point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                    width: 40,
                    height: 40,
                    child: const Icon(Icons.my_location, color: Colors.blue, size: 30),
                  ),
                if (_pickupLocation != null && !_isConfirmingPickup)
                  Marker(
                    point: _pickupLocation!,
                    width: 40,
                    height: 40,
                    child: const Icon(Icons.location_on, color: Color(0xFF10713C), size: 40),
                  ),
                if (_destinationLocation != null)
                  Marker(
                    point: _destinationLocation!,
                    width: 40,
                    height: 40,
                    child: const Icon(Icons.location_on, color: Color(0xFFED1C24), size: 40),
                  ),
                ..._driverMarkers,
              ],
            ),
            if (_routePoints.isNotEmpty)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _routePoints,
                    color: const Color(0xFF10713C),
                    strokeWidth: 5.0,
                    borderColor: Colors.green.shade800,
                    borderStrokeWidth: 1.0,
                  ),
                ],
              ),
            if (_isLoadingRoute)
              const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 8),
                        Text('Loading route...', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildRouteSummaryHeader() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 56,
      left: 12,
      right: 12,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, 6)),
                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
            child: Row(
              children: [
                // Dot + line connector
                SizedBox(
                  width: 24,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: const Color(0xFF10713C),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [BoxShadow(color: const Color(0xFF10713C).withValues(alpha: 0.3), blurRadius: 4)],
                        ),
                      ),
                      Container(width: 2, height: 20, decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [const Color(0xFF10713C), const Color(0xFFED1C24)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      )),
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: const Color(0xFFED1C24),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [BoxShadow(color: const Color(0xFFED1C24).withValues(alpha: 0.3), blurRadius: 4)],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Addresses
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text('From ', style: TextStyle(fontSize: 9, color: Colors.grey[500], fontWeight: FontWeight.w500, letterSpacing: 0.5)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(_pickupAddress, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text('To ', style: TextStyle(fontSize: 9, color: Colors.grey[500], fontWeight: FontWeight.w500, letterSpacing: 0.5)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(_destinationAddress, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // ETA badge
                if (_routeDuration > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF10713C),
                          const Color(0xFF0E5C33),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: const Color(0xFF10713C).withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 2))],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.schedule, size: 13, color: Colors.white),
                        const SizedBox(width: 3),
                        Text('${_routeDuration} min', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControlPanel() {
    return Positioned(
      bottom: 30,
      left: 16,
      right: 16,
      child: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, 5))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: _isConfirmingPickup 
                ? _buildConfirmPickupPanel() 
                : (_showRideOptions ? _buildRideOptions() : _buildLocationSelectionPanel()),
          ),
        ),
      ),
    );
  }

  Widget _buildConfirmPickupPanel() {
    final bool isCar = _selectedRide == 'car';
    final double finalPrice = isCar ? _price : _price * 0.6;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF10713C).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.my_location, color: Color(0xFF10713C), size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Confirm Pickup Spot', style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text(_pickupAddress, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () {
                if (_pickupLocation != null && _destinationLocation != null) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => LiveTrackingScreen(
                    rideType: _selectedRide!,
                    pickupAddress: _pickupAddress,
                    destinationAddress: _destinationAddress,
                    price: finalPrice,
                    pickupLat: _pickupLocation!.latitude,
                    pickupLng: _pickupLocation!.longitude,
                    destLat: _destinationLocation!.latitude,
                    destLng: _destinationLocation!.longitude,
                  )));
                } else {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => RideStatusScreen(rideType: _selectedRide!, pickup: _pickupAddress, destination: _destinationAddress, price: finalPrice)));
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10713C),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: const Text(
                'Confirm Pickup',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSelectionPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
          ),
          // Current pickup location row
          _buildLocationInput(
            icon: Icons.my_location,
            address: _pickupAddress,
            color: const Color(0xFF10713C),
            isSelected: _selectingPickup,
            onTap: () => setState(() => _selectingPickup = true),
          ),
          const SizedBox(height: 12),
          // "Where to?" search box — prominent like Uber/Pathao
          GestureDetector(
            onTap: () => setState(() => _selectingPickup = false),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFED1C24).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.location_on, color: Color(0xFFED1C24), size: 14),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _destinationAddress == 'Select Destination' ? 'Where to?' : _destinationAddress,
                      style: TextStyle(
                        fontSize: 15,
                        color: _destinationAddress == 'Select Destination' ? Colors.grey[400] : Colors.black87,
                        fontWeight: _destinationAddress == 'Select Destination' ? FontWeight.normal : FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.search, color: Colors.grey, size: 18),
                  ),
                ],
              ),
            ),
          ),

          // Popular places label
          Text('Popular Places', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey[700])),
          const SizedBox(height: 12),
          _buildPopularPlacesList(),
        ],
      ),
    );
  }

  Widget _buildPopularPlacesList() {
    return SizedBox(
      height: 90,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          // Static popular places (always shown)
          _buildCompactPlace('Home', 'Gulshan 2', const LatLng(23.7925, 90.4078), Icons.home),
          _buildCompactPlace('Office', 'Banani', const LatLng(23.7937, 90.4066), Icons.work),
          _buildCompactPlace('Airport', 'Uttara', const LatLng(23.8433, 90.3978), Icons.flight),
          _buildCompactPlace('Shopping', 'JFP', const LatLng(23.8135, 90.4242), Icons.store),
          // Recent locations from user history
          if (_recentLocations.isNotEmpty) ..._buildRecentPlaceChips(),
        ],
      ),
    );
  }

  String _iconNameFor(IconData icon) {
    if (icon == Icons.home) return 'home';
    if (icon == Icons.work) return 'work';
    if (icon == Icons.flight) return 'flight';
    if (icon == Icons.store) return 'store';
    return 'history';
  }

  IconData _iconFromName(String name) {
    switch (name) {
      case 'home':
        return Icons.home;
      case 'work':
        return Icons.work;
      case 'flight':
        return Icons.flight;
      case 'store':
        return Icons.store;
      default:
        return Icons.history;
    }
  }

  List<Widget> _buildRecentPlaceChips() {
    return _recentLocations.take(4).map((loc) => _buildCompactPlace(
      loc.title,
      loc.area,
      LatLng(loc.lat, loc.lng),
      _iconFromName(loc.iconName),
    )).toList();
  }

  Widget _buildCompactPlace(String title, String area, LatLng coords, IconData icon) {
    return GestureDetector(
      onTap: () {
        _saveRecentLocation(title, area, coords, iconName: _iconNameFor(icon));
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
          _mapController.move(coords, 15);
        });
      },
      child: Container(
        width: 100,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey[200]!)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFF10713C), size: 24),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), maxLines: 1),
            Text(area, style: TextStyle(color: Colors.grey[500], fontSize: 10), maxLines: 1),
          ],
        ),
      ),
    );
  }


  Widget _buildLocationInput({required IconData icon, required String address, required Color color, required bool isSelected, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 18)),
            const SizedBox(width: 12),
            Expanded(child: Text(address, style: TextStyle(color: isSelected ? Colors.black87 : Colors.grey[500], fontSize: 14, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }

  Widget _buildRideOptions() {
    final int carDuration = _routeDuration > 0 ? _routeDuration : 12;
    final int bikeDuration = _routeDuration > 0 ? (_routeDuration * 0.7).round() : 8;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Section header: Choose ride
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10713C).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.directions_car_filled, color: Color(0xFF10713C), size: 18),
                ),
                const SizedBox(width: 10),
                const Text('Choose a ride', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87)),
                const Spacer(),
                Text('৳${_price.toStringAsFixed(0)}', style: const TextStyle(fontSize: 14, color: Color(0xFF10713C), fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          // Ride type cards
          _buildRideItem(
            'Car',
            '${_distance.toStringAsFixed(1)} km • $carDuration min',
            _price,
            Icons.directions_car_filled,
            _selectedRide == 'car',
            () => setState(() => _selectedRide = 'car'),
          ),
          const SizedBox(height: 10),
          _buildRideItem(
            'Bike',
            '${_distance.toStringAsFixed(1)} km • $bikeDuration min',
            _price * 0.6,
            Icons.motorcycle,
            _selectedRide == 'bike',
            () => setState(() => _selectedRide = 'bike'),
          ),
          const SizedBox(height: 12),
          _buildPaymentAndPromo(),
          const SizedBox(height: 16),
          _buildConfirmButton(),
        ],
      ),
    );
  }

  void _showPaymentSelection() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
            const Text('Select Payment Method', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildPaymentOption('Cash', Icons.money, _selectedPayment == 'Cash'),
            _buildPaymentOption('Card', Icons.credit_card, _selectedPayment == 'Card'),
            _buildPaymentOption('Online Pay', Icons.account_balance_wallet, _selectedPayment == 'Online Pay'),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentOption(String title, IconData icon, bool isSelected) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF10713C).withValues(alpha: 0.1) : Colors.grey[100],
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: isSelected ? const Color(0xFF10713C) : Colors.grey[600], size: 20),
      ),
      title: Text(title, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? const Color(0xFF10713C) : Colors.black87)),
      trailing: isSelected ? const Icon(Icons.check_circle, color: Color(0xFF10713C)) : null,
      onTap: () {
        Navigator.pop(context);
        if (title == 'Online Pay') {
          _handleRealSslCommerzPayment();
        } else {
          setState(() => _selectedPayment = title);
        }
      },
    );
  }

  void _showDigitalPaymentDemo() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // SSLCommerz style header
              Container(
                padding: const EdgeInsets.all(16),
                color: const Color(0xFF10713C),
                child: Row(
                  children: [
                    const Icon(Icons.security, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    const Text('Secure Payment Gateway', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white, size: 20)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Text('Select Payment Option', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildGatewayItem('bKash', 'assets/bkash_logo.png', Colors.pink),
                        _buildGatewayItem('Nagad', 'assets/nagad_logo.png', Colors.orange),
                        _buildGatewayItem('Rocket', 'assets/rocket_logo.png', Colors.purple),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildGatewayItem('Visa', 'assets/visa_logo.png', Colors.blue),
                        _buildGatewayItem('MasterCard', 'assets/mastercard_logo.png', Colors.red),
                        _buildGatewayItem('Upay', 'assets/upay_logo.png', Colors.teal),
                      ],
                    ),
                    const SizedBox(height: 30),
                    const Divider(),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Amount', style: TextStyle(color: Colors.grey)),
                        Text('৳${_price.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF10713C))),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              setState(() => _selectedPayment = 'Online Pay');
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Demo Payment Successful!'),
                                  backgroundColor: Color(0xFF10713C),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10713C).withValues(alpha: 0.8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                            child: const Text('Simulate Success', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _handleRealSslCommerzPayment,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10713C),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 2,
                            ),
                            child: const Text('Pay with SSLCommerz', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleRealSslCommerzPayment() async {
    Navigator.pop(context); // Close demo dialog
    
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Color(0xFF10713C))),
    );

    final String tranId = 'GR_${DateTime.now().millisecondsSinceEpoch}';
    final double amount = _selectedRide == 'car' ? _price : _price * 0.6;

    final String? gatewayUrl = await _sslCommerzService.initiatePayment(
      amount: amount,
      transactionId: tranId,
      customerName: 'Customer Name', // In real app, get from ApiService
      customerEmail: 'customer@email.com',
      customerPhone: '01711111111',
    );

    if (mounted) Navigator.pop(context); // Close loading

    if (gatewayUrl != null) {
      // Launch the payment gateway in external browser
      final Uri uri = Uri.parse(gatewayUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        
        // After launching, since we can't get callback easily here,
        // we'll assume the user will finish payment and we might need a way to check status.
        // For this implementation, we'll set the payment method to Online Pay.
        setState(() => _selectedPayment = 'Online Pay');
      } else {
        _showError('Could not launch payment gateway');
      }
    } else {
      _showError('Failed to initiate SSLCommerz payment');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Widget _buildGatewayItem(String name, String asset, Color color) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Center(child: Text(name[0], style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 24))), // Simplified demo icons
        ),
        const SizedBox(height: 6),
        Text(name, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildPaymentAndPromo() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[100]!),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _showPaymentSelection,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _selectedPayment == 'Cash' 
                        ? Icons.money 
                        : (_selectedPayment == 'Card' ? Icons.credit_card : Icons.account_balance_wallet), 
                    size: 16, 
                    color: const Color(0xFF10713C)
                  ),
                  const SizedBox(width: 6),
                  Text(_selectedPayment, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.black87)),
                  const SizedBox(width: 4),
                  Icon(Icons.keyboard_arrow_down, size: 14, color: Colors.grey[500]),
                ],
              ),
            ),
          ),
          const Spacer(),
          // Promo button
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {},
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.local_offer_outlined, size: 16, color: const Color(0xFF10713C)),
                    const SizedBox(width: 4),
                    const Text('Promo', style: TextStyle(color: Color(0xFF10713C), fontWeight: FontWeight.w600, fontSize: 12)),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10713C).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('2', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF10713C))),
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

  Widget _buildConfirmButton() {
    final bool isCar = _selectedRide == 'car';
    final double finalPrice = isCar ? _price : _price * 0.6;

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: _selectedRide == null ? null : () {
          setState(() {
            _isConfirmingPickup = true;
          });
          // Move map to pickup location for refinement
          if (_pickupLocation != null) {
            _mapController.move(_pickupLocation!, 16.0);
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF10713C),
          disabledBackgroundColor: Colors.grey[300],
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
          shadowColor: const Color(0xFF10713C).withValues(alpha: 0.3),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _selectedRide == 'car' ? Icons.directions_car_filled : Icons.motorcycle,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'Confirm ${_selectedRide?.toUpperCase() ?? 'RIDE'} — ৳${finalPrice.toStringAsFixed(0)}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRideItem(String name, String detail, double price, IconData icon, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF10713C).withValues(alpha: 0.06) : Colors.white,
          border: Border.all(
            color: isSelected ? const Color(0xFF10713C) : Colors.grey[200]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: isSelected
              ? [BoxShadow(color: const Color(0xFF10713C).withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 2))]
              : [],
        ),
        child: Row(
          children: [
            // Icon container with gradient background when selected
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF10713C) : Colors.grey[100],
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                size: 28,
                color: isSelected ? Colors.white : Colors.black54,
              ),
            ),
            const SizedBox(width: 14),
            // Name and detail
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
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Price column
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '৳${price.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: isSelected ? const Color(0xFF10713C) : Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: isSelected
                      ? Container(
                          key: const ValueKey('selected'),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10713C),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check, size: 12, color: Colors.white),
                              SizedBox(width: 2),
                              Text('Selected', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                            ],
                          ),
                        )
                      : const SizedBox(key: ValueKey('unselected'), width: 1),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionOverlay() {
    if (_showRideOptions && !_isConfirmingPickup) return const SizedBox.shrink();
    return Positioned(
      top: MediaQuery.of(context).padding.top + 56,
      left: 50,
      right: 50,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8)],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isConfirmingPickup || _selectingPickup ? Icons.my_location : Icons.location_on,
                color: Colors.white,
                size: 14,
              ),
              const SizedBox(width: 8),
              Text(
                _isConfirmingPickup ? 'Refine pickup spot' : (_selectingPickup ? 'Move pin to set pickup' : 'Move pin to set destination'),
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
