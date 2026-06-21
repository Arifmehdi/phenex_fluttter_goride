import 'package:flutter/material.dart';
import 'dart:async';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:get/get.dart';
import 'ride_status_page.dart';
import 'live_tracking_screen.dart';
import '../services/routing_service.dart';
import '../services/recent_locations_service.dart';
import '../services/sslcommerz_service.dart';
import '../services/api_service.dart';
import '../services/places_service.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firebase_service.dart';
import '../utils/marker_utils.dart';

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
  GoogleMapController? _mapController;

  LatLng? _pickupLocation;
  LatLng? _destinationLocation;
  String _pickupAddress = 'Select Pickup Location';
  String _destinationAddress = 'Select Destination';
  double _distance = 0.0;
  double _price = 0.0;
  double _perKmRate = 20.0; // Default fallback, fetched from API
  bool _selectingPickup = false; // Start with destination selection
  bool _isConfirmingPickup = false;
  bool _isRouteVisible = false;

  bool get _showRideOptions => _pickupLocation != null && _destinationLocation != null && _isRouteVisible;
  String? _selectedRide;
  String _selectedPayment = 'Cash';

  Position? _currentPosition;
  StreamSubscription<Position>? _positionStreamSubscription;
  StreamSubscription<QuerySnapshot>? _driversSubscription;
  Set<Marker> _driverMarkers = {};

  // Routing
  final RoutingService _routingService = Get.find<RoutingService>();
  final FirebaseService _firebaseService = Get.find<FirebaseService>();
  List<LatLng> _routePoints = [];
  int _routeDuration = 0;
  bool _isLoadingRoute = false;

  // Recent locations
  final RecentLocationsService _recentLocationsService = RecentLocationsService();
  final PlacesService _placesService = PlacesService();
  final ApiService _apiService = Get.find<ApiService>();
  Timer? _apiDriversTimer;
  Timer? _routeDebounce;
  List<RecentLocation> _recentLocations = [];

  BitmapDescriptor? _carIcon;
  BitmapDescriptor? _bikeIcon;
  BitmapDescriptor? _ambulanceIcon;

  bool _isInitialCameraMove = true;
  bool _hasPreSelectedPickup = false;
  bool _hasPreSelectedDest = false;
  bool _isAnimatingToFit = false;
  bool _isFollowingUser = true; // Added to track if map should follow user movement

  @override
  void initState() {
    super.initState();
    _selectedRide = widget.initialRideType?.toLowerCase();

    if (widget.pickupLat != null && widget.pickupLng != null) {
      _pickupLocation = LatLng(widget.pickupLat!, widget.pickupLng!);
      _pickupAddress = widget.pickupAddress ?? 'Selected Location';
      _hasPreSelectedPickup = true;
    } else if (widget.pickupAddress != null && widget.pickupAddress!.isNotEmpty) {
      _pickupAddress = widget.pickupAddress!;
      _resolveAddressToLatLng(widget.pickupAddress!, isPickup: true);
    }

    if (widget.destLat != null && widget.destLng != null) {
      _destinationLocation = LatLng(widget.destLat!, widget.destLng!);
      _destinationAddress = widget.destinationAddress ?? 'Selected Destination';
      _hasPreSelectedDest = true;
    } else if (widget.destinationAddress != null && widget.destinationAddress!.isNotEmpty) {
      _destinationAddress = widget.destinationAddress!;
      _resolveAddressToLatLng(widget.destinationAddress!, isPickup: false);
    }

    if (_pickupLocation == null) {
      _pickupLocation = const LatLng(23.8103, 90.4125);
      _pickupAddress = widget.pickupAddress ?? 'Dhaka, Bangladesh';
      if (widget.pickupAddress == null) {
        _getAddressFromLatLngCoords(_pickupLocation!.latitude, _pickupLocation!.longitude, isPickup: true);
      }
    }

    if (_hasPreSelectedPickup && _hasPreSelectedDest) {
      _isRouteVisible = true;
      _calculateRideDetails();
    }

    Timer(const Duration(seconds: 5), () {
      if (mounted && _isInitialCameraMove) {
        setState(() => _isInitialCameraMove = false);
      }
    });

    _loadIcons();
    _loadRecentLocations();
    _checkPermission();
    _listenToNearbyDrivers();
    _fetchPerKmRate();
  }

  Future<void> _resolveAddressToLatLng(String address, {required bool isPickup}) async {
    try {
      final locations = await locationFromAddress('$address, Bangladesh');
      if (locations.isNotEmpty && mounted) {
        setState(() {
          if (isPickup) {
            _pickupLocation = LatLng(locations[0].latitude, locations[0].longitude);
            _hasPreSelectedPickup = true;
          } else {
            _destinationLocation = LatLng(locations[0].latitude, locations[0].longitude);
            _hasPreSelectedDest = true;
          }
        });
        if (_hasPreSelectedPickup && _hasPreSelectedDest) {
          _isRouteVisible = true;
          _calculateRideDetails();
        }
      }
    } catch (e) {
      if (isPickup && _currentPosition != null) {
        setState(() => _pickupLocation = LatLng(_currentPosition!.latitude, _currentPosition!.longitude));
      }
    }
  }

  Future<void> _loadIcons() async {
    _carIcon = await MarkerUtils.getBytesFromAsset('assets/car.png', 50);
    _bikeIcon = await MarkerUtils.getBytesFromAsset('assets/motor.png', 50);
    _ambulanceIcon = await MarkerUtils.getBytesFromAsset('assets/ambulance.png', 50);
  }

  void _listenToNearbyDrivers() {
    debugPrint('Listening to nearby drivers...');
    if (_firebaseService.isInitialized) {
      debugPrint('Firebase is initialized, subscribing to driver_locations...');
      _driversSubscription = _firebaseService.driverLocations
          ?.where('isOnline', isEqualTo: true)
          .snapshots()
          .listen((snapshot) {
        if (!mounted) return;
        debugPrint('Received driver locations update: ${snapshot.docs.length} drivers online');
        
        final center = _pickupLocation ?? (_currentPosition != null ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude) : null);
        
        final Set<Marker> markers = snapshot.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final lat = data['latitude'] as double?;
          final lng = data['longitude'] as double?;
          
          if (lat == null || lng == null) {
            debugPrint('Driver ${doc.id} has null coordinates');
            return false;
          }
          
          if (center != null) {
            final distanceInMeters = Geolocator.distanceBetween(center.latitude, center.longitude, lat, lng);
            debugPrint('Driver ${doc.id} distance: ${distanceInMeters.toStringAsFixed(0)}m');
            // Relaxed to 10km for debugging, or keep 5km but log it
            return distanceInMeters <= 10000; 
          }
          return true;
        }).map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final lat = data['latitude'] as double;
          final lng = data['longitude'] as double;
          final heading = (data['heading'] as num?)?.toDouble() ?? 0.0;
          final vehicleType = data['vehicleType'] as String? ?? 'car';
          
          BitmapDescriptor icon;
          if (vehicleType == 'motor' || vehicleType == 'bike') {
            icon = _bikeIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
          } else if (vehicleType == 'ambulance') {
            icon = _ambulanceIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
          } else {
            icon = _carIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
          }

          return Marker(
            markerId: MarkerId(doc.id),
            position: LatLng(lat, lng),
            icon: icon,
            rotation: heading,
            anchor: const Offset(0.5, 0.5),
            infoWindow: InfoWindow(title: 'Driver ${doc.id.substring(0, 4)} ($vehicleType)'),
          );
        }).toSet();
        
        setState(() {
          _driverMarkers = markers;
          debugPrint('Set ${_driverMarkers.length} driver markers on map');
        });
      }, onError: (e) {
        debugPrint('Error listening to drivers: $e');
      });
    } else {
      debugPrint('Firebase NOT initialized in _listenToNearbyDrivers, waiting 2s...');
      Timer(const Duration(seconds: 2), _listenToNearbyDrivers);
    }
  }

  /// Fetch the per_km_rate from the Laravel API (website parameters)
  Future<void> _fetchPerKmRate() async {
    try {
      final response = await _apiService.getWebsiteParameters();
      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data["data"] as Map<String, dynamic>?;
        if (data != null && data["per_km_rate"] != null) {
          final rate = (data["per_km_rate"] as num).toDouble();
          if (rate > 0) {
            setState(() => _perKmRate = rate);
            debugPrint("Fetched per_km_rate from API: " + _perKmRate.toString());
          }
        }
      }
    } catch (e) {
      debugPrint("Failed to fetch per_km_rate, using default: 20.0 - " + e.toString());
    }
  }

  void _loadRecentLocations() {
    setState(() => _recentLocations = _recentLocationsService.getLocations());
  }

  void _saveRecentLocation(String title, String area, LatLng coords, {String iconName = 'history'}) {
    _recentLocationsService.saveLocation(RecentLocation(
      title: title,
      area: area,
      lat: coords.latitude,
      lng: coords.longitude,
      iconName: iconName,
      timestamp: 0,
    ));
    _loadRecentLocations();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _driversSubscription?.cancel();
    _apiDriversTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  void _onMapTap(LatLng point) {
    if (_showRideOptions && !_isConfirmingPickup) return;
    setState(() {
      if (_selectingPickup) {
        _pickupLocation = point;
        _pickupAddress = 'Loading...';
        _selectingPickup = false;
        _getAddressFromLatLngCoords(point.latitude, point.longitude, isPickup: true);
      } else {
        _destinationLocation = point;
        _destinationAddress = 'Loading...';
        _getAddressFromLatLngCoords(point.latitude, point.longitude, isPickup: false);
      }
    });
    _calculateRideDetails();
    _mapController?.animateCamera(CameraUpdate.newLatLng(point));
  }

  void _calculateRideDetails() {
    if (_pickupLocation != null && _destinationLocation != null) {
      _fetchRoute();
    }
  }

  Future<void> _fetchRoute() async {
    if (_pickupLocation == null || _destinationLocation == null) return;
    setState(() => _isLoadingRoute = true);
    final response = await _routingService.getRoute(origin: _pickupLocation!, destination: _destinationLocation!);
    if (response.status == 'OK' && response.route != null && mounted) {
      final route = response.route!;
      setState(() {
        _routePoints = route.points;
        _routeDuration = route.duration.toInt();
        _distance = route.distance;
        _price = 50 + (route.distance * _perKmRate);
        _isLoadingRoute = false;
      });
      if (_routePoints.isNotEmpty) _fitRoute();
      _checkInitialSetupComplete();
    } else {
      final double distanceInMeters = Geolocator.distanceBetween(
        _pickupLocation!.latitude, _pickupLocation!.longitude,
        _destinationLocation!.latitude, _destinationLocation!.longitude,
      );
      setState(() {
        _routePoints = [_pickupLocation!, _destinationLocation!];
        _distance = distanceInMeters / 1000;
        _price = 50 + (_distance * _perKmRate);
        _isLoadingRoute = false;
      });
    }
  }

  void _fitCameraToLocations(LatLng pickup, LatLng dest) {
    if (_mapController == null) return;
    final double minLat = pickup.latitude < dest.latitude ? pickup.latitude : dest.latitude;
    final double maxLat = pickup.latitude > dest.latitude ? pickup.latitude : dest.latitude;
    final double minLng = pickup.longitude < dest.longitude ? pickup.longitude : dest.longitude;
    final double maxLng = pickup.longitude > dest.longitude ? pickup.longitude : dest.longitude;
    _isAnimatingToFit = true;
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)), 100.0,
    ));
  }

  void _fitRoute() {
    if (_routePoints.isEmpty || _mapController == null) return;
    double minLat = _routePoints.first.latitude, maxLat = _routePoints.first.latitude;
    double minLng = _routePoints.first.longitude, maxLng = _routePoints.first.longitude;
    for (final point in _routePoints) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }
    _isAnimatingToFit = true;
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)), 80.0,
    ));
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
    await _getInitialPosition();
    _startLiveTracking();
  }

  void _startLiveTracking() {
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
    ).listen((Position position) {
      if (mounted) {
        final LatLng currentLatLng = LatLng(position.latitude, position.longitude);
        setState(() {
          _currentPosition = position;
          
          // Automatically update pickup location if we are following the user
          // and not already showing ride options (Uber/Pathao behavior)
          if (_isFollowingUser && !_showRideOptions && !_hasPreSelectedPickup) {
            _pickupLocation = currentLatLng;
            _pickupAddress = 'Detecting location...';
          }
        });

        // Move camera and get address if following
        if (_isFollowingUser && !_hasPreSelectedPickup && !_showRideOptions) {
          _mapController?.animateCamera(CameraUpdate.newLatLng(currentLatLng));
          _getAddressFromLatLngCoords(position.latitude, position.longitude, isPickup: true);
        }
      }
    });
  }

  Future<void> _getAddressFromLatLngCoords(double lat, double lng, {required bool isPickup}) async {
    try {
      final address = await _placesService.getAddressFromLatLng(lat, lng);
      if (address != null && mounted) {
        setState(() {
          if (isPickup) _pickupAddress = address;
          else {
            _destinationAddress = address;
            if (_destinationLocation != null) _saveRecentLocation(address.split(',').first.trim(), address, _destinationLocation!);
          }
        });
      } else {
        List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
        if (placemarks.isNotEmpty && mounted) {
          String fallback = placemarks[0].name ?? '$lat, $lng';
          setState(() {
            if (isPickup) _pickupAddress = fallback;
            else {
              _destinationAddress = fallback;
              if (_destinationLocation != null) _saveRecentLocation(fallback.split(',').first.trim(), fallback, _destinationLocation!);
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Geocoding error: $e');
    }
  }

  Future<void> _getInitialPosition() async {
    try {
      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return;
      setState(() {
        _currentPosition = position;
        if (!_showRideOptions && _pickupLocation == null && !_hasPreSelectedPickup) {
          _pickupLocation = LatLng(position.latitude, position.longitude);
        }
      });
      if (!_hasPreSelectedPickup && !_showRideOptions && _pickupLocation != null) {
        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_pickupLocation!, 15.0));
        _getAddressFromLatLngCoords(_pickupLocation!.latitude, _pickupLocation!.longitude, isPickup: true);
      }
    } catch (e) {
      debugPrint('Initial position error: $e');
    }
  }

  void _onCameraIdle() {
    _isAnimatingToFit = false;
    _checkInitialSetupComplete();

    // Perform address lookup when camera stops moving
    final LatLng? target = _isConfirmingPickup || _selectingPickup 
        ? _pickupLocation 
        : _destinationLocation;
        
    if (target != null && !_showRideOptions) {
      _getAddressFromLatLngCoords(
        target.latitude, 
        target.longitude, 
        isPickup: _isConfirmingPickup || _selectingPickup
      );
    }
  }
  
  void _checkInitialSetupComplete() {
    if (!_isInitialCameraMove) return;
    if (_routePoints.isNotEmpty && !_isAnimatingToFit) {
      if (mounted) setState(() => _isInitialCameraMove = false);
    }
  }

  void _onCameraMove(CameraPosition position) {
    if (_isInitialCameraMove || _isAnimatingToFit) return;
    
    // If the camera is moving and it's not a programmatic move (like _isAnimatingToFit)
    // then the user is manually moving the map. We should stop following them.
    if (_isFollowingUser) {
      _isFollowingUser = false;
    }
    
    if (_showRideOptions && !_isConfirmingPickup) return;
    
    final center = position.target;
    
    // Immediate state update for visual markers only
    setState(() {
      if (_isConfirmingPickup || _selectingPickup) {
        _pickupLocation = center;
        _pickupAddress = 'Loading...';
      } else {
        _destinationLocation = center;
        _destinationAddress = 'Loading...';
      }
    });
    
    if (_pickupLocation != null && _destinationLocation != null) {
      _routeDebounce?.cancel();
      _routeDebounce = Timer(const Duration(milliseconds: 600), () => _calculateRideDetails());
    }
  }

  void _centerOnMyLocation() {
    if (_currentPosition == null) return;
    final pos = _currentPosition!;
    final myLatLng = LatLng(pos.latitude, pos.longitude);
    
    // Re-enable following the user
    setState(() {
      _isFollowingUser = true;
    });

    _mapController?.animateCamera(CameraUpdate.newLatLng(myLatLng));
    
    // In ride options mode, just re-center the map (Uber/Pathao behavior)
    if (_showRideOptions) return;

    setState(() {
      if (_isConfirmingPickup || _selectingPickup) {
        _pickupLocation = myLatLng;
        _getAddressFromLatLngCoords(pos.latitude, pos.longitude, isPickup: true);
      } else {
        _destinationLocation = myLatLng;
        _getAddressFromLatLngCoords(pos.latitude, pos.longitude, isPickup: false);
      }
    });
    
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
          _buildBottomUI(),
          _buildNearbyStatus(),
          Positioned(
            right: 16,
            bottom: _showRideOptions ? 420 : 320,
            child: FloatingActionButton(
              onPressed: _centerOnMyLocation,
              backgroundColor: Colors.white,
              mini: true,
              child: const Icon(Icons.my_location, color: Colors.black87),
            ),
          ),
          if (_isLoadingRoute) const Center(child: CircularProgressIndicator(color: Color(0xFF10713C))),
        ],
      ),
    );
  }

  Widget _buildNearbyStatus() {
    if (_showRideOptions) return const SizedBox.shrink();
    
    return Positioned(
      top: MediaQuery.of(context).padding.top + 60,
      left: 20,
      right: 20,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _driverMarkers.isEmpty ? Colors.orange : Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _driverMarkers.isEmpty 
                  ? 'Searching for nearby drivers...' 
                  : '${_driverMarkers.length} drivers available nearby',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      leadingWidth: 70,
      leading: Padding(
        padding: const EdgeInsets.all(8.0),
        child: CircleAvatar(
          backgroundColor: Colors.white,
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black, size: 20),
            onPressed: () {
              if (_isConfirmingPickup) setState(() => _isConfirmingPickup = false);
              else Navigator.pop(context);
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
      _isConfirmingPickup = false;
      _isRouteVisible = false;
      _routePoints = [];
    });
  }

  Widget _buildMap() {
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: _pickupLocation ?? _dhakaCenterFallback,
        zoom: 15,
      ),
      onMapCreated: (controller) {
        _mapController = controller;
        if (_hasPreSelectedPickup && _hasPreSelectedDest) _fitCameraToLocations(_pickupLocation!, _destinationLocation!);
      },
      onCameraMove: _onCameraMove,
      onCameraIdle: _onCameraIdle,
      onTap: _onMapTap,
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      markers: {
        if (_pickupLocation != null)
          Marker(
            markerId: const MarkerId('pickup'),
            position: _pickupLocation!,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
            infoWindow: InfoWindow(title: 'Pickup', snippet: _pickupAddress),
            anchor: const Offset(0.5, 1.0),
          ),
        if (_destinationLocation != null)
          Marker(
            markerId: const MarkerId('destination'),
            position: _destinationLocation!,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: InfoWindow(title: 'Destination', snippet: _destinationAddress),
            anchor: const Offset(0.5, 1.0),
          ),
        ..._driverMarkers,
      },
      circles: {
        if (_pickupLocation != null)
          Circle(circleId: const CircleId('p_c'), center: _pickupLocation!, radius: 12, fillColor: Colors.green.withOpacity(0.3), strokeWidth: 2),
        if (_destinationLocation != null)
          Circle(circleId: const CircleId('d_c'), center: _destinationLocation!, radius: 12, fillColor: Colors.red.withOpacity(0.3), strokeWidth: 2),
      },
      polylines: {
        if (_routePoints.isNotEmpty)
          Polyline(
            polylineId: const PolylineId('r'),
            points: _routePoints,
            color: const Color(0xFF10713C),
            width: 5,
            jointType: JointType.round,
          )
        else if (_pickupLocation != null && _destinationLocation != null)
          // Dynamic direction indicator line while panning
          Polyline(
            polylineId: const PolylineId('direction_line'),
            points: [_pickupLocation!, _destinationLocation!],
            color: const Color(0xFF10713C).withOpacity(0.6),
            width: 3,
            patterns: [PatternItem.dash(15), PatternItem.gap(10)],
          ),
      },
    );
  }

  Widget _buildBottomUI() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _isConfirmingPickup
            ? _buildConfirmPickupPanel()
            : (_showRideOptions ? _buildRideOptionsPanel() : _buildSelectionPanel()),
      ),
    );
  }

  Widget _buildSelectionPanel() {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(25), topRight: Radius.circular(25)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Column(
                children: [
                  const Icon(Icons.circle, color: Color(0xFF10713C), size: 12),
                  Container(width: 1, height: 30, color: Colors.grey[300]),
                  const Icon(Icons.square, color: Color(0xFFED1C24), size: 12),
                ],
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  children: [
                    _buildLocationField('Pickup (From)', _pickupAddress, _selectingPickup, () => setState(() => _selectingPickup = true)),
                    const Divider(height: 20),
                    _buildLocationField('Destination (To)', _destinationAddress, !_selectingPickup, () => setState(() => _selectingPickup = false)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: () {
                if (_selectingPickup) setState(() => _selectingPickup = false);
                else if (_pickupLocation != null && _destinationLocation != null) {
                  setState(() {
                    _isRouteVisible = true;
                  });
                  _calculateRideDetails();
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10713C), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
              child: Text(_selectingPickup ? 'Next: Select Destination' : 'Confirm Destination', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationField(String label, String address, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        width: double.infinity,
        decoration: BoxDecoration(color: isActive ? Colors.grey[50] : Colors.transparent, borderRadius: BorderRadius.circular(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: isActive ? const Color(0xFF10713C) : Colors.grey[500], fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
            Text(address, style: TextStyle(fontSize: 15, fontWeight: isActive ? FontWeight.bold : FontWeight.w500, color: isActive ? Colors.black : Colors.black54), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmPickupPanel() {
    return Container(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30)), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20)]),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
          Row(children: [
            const Icon(Icons.my_location, color: Color(0xFF10713C), size: 18),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('From: Pickup Spot', style: TextStyle(fontSize: 12, color: Color(0xFF10713C), fontWeight: FontWeight.bold)),
              Text(_pickupAddress, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
            ])),
          ]),
          const Padding(padding: EdgeInsets.only(left: 8), child: SizedBox(height: 15, child: VerticalDivider(width: 2, color: Colors.black12))),
          Row(children: [
            const Icon(Icons.location_on, color: Color(0xFFED1C24), size: 18),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('To: Destination', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
              Text(_destinationAddress, style: const TextStyle(fontSize: 14, color: Colors.black54), maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
          ]),
          const SizedBox(height: 20),
          if (_distance > 0) Container(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12), decoration: BoxDecoration(color: const Color(0xFF10713C).withOpacity(0.08), borderRadius: BorderRadius.circular(10)), child: Text('${_distance.toStringAsFixed(1)} km to destination', style: const TextStyle(color: Color(0xFF10713C), fontWeight: FontWeight.bold))),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, height: 55, child: ElevatedButton(onPressed: () { setState(() { _isConfirmingPickup = false; _isRouteVisible = true; }); _calculateRideDetails(); }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10713C), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: const Text('Confirm Pickup Spot', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)))),
        ],
      ),
    );
  }

  Widget _buildRideOptionsPanel() {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 10, 20, 30 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.only(topLeft: Radius.circular(25), topRight: Radius.circular(25)), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _buildInfoChip(Icons.straighten, '${_distance.toStringAsFixed(1)} km'),
            _buildInfoChip(Icons.access_time, '$_routeDuration min'),
            _buildInfoChip(Icons.payments_outlined, 'Cash'),
          ]),
          const SizedBox(height: 20),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
            _buildRideType('motor', 'Motor', 'assets/motor.png', 0.6),
            _buildRideType('car', 'Car', 'assets/car.png', 1.0),
            _buildRideType('rent_car', 'Rent Car', 'assets/rent_car.png', 1.5),
            _buildRideType('ambulance', 'Ambulance', 'assets/ambulance.png', 1.2),
          ])),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, height: 55, child: ElevatedButton(onPressed: _bookRide, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10713C), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: const Text('Book Ride Now', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)))),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(20)), child: Row(children: [Icon(icon, size: 16, color: Colors.grey[600]), const SizedBox(width: 6), Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))]));
  }

  Widget _buildRideType(String id, String name, String asset, double multiplier) {
    final isSelected = _selectedRide == id;
    return GestureDetector(
      onTap: () => setState(() => _selectedRide = id),
      child: Container(width: 110, margin: const EdgeInsets.only(right: 12), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: isSelected ? const Color(0xFF10713C).withOpacity(0.05) : Colors.transparent, borderRadius: BorderRadius.circular(15), border: Border.all(color: isSelected ? const Color(0xFF10713C) : Colors.grey[200]!, width: 1.5)), child: Column(children: [Image.asset(asset, height: 40), const SizedBox(height: 8), Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)), Text('৳${(_price * multiplier).toStringAsFixed(0)}', style: TextStyle(fontSize: 12, color: Colors.grey[600]))])),
    );
  }

  void _bookRide() async {
    if (_selectedRide == null) return;
    
    // Calculate final price based on ride type
    double multiplier = 1.0;
    if (_selectedRide == 'motor') multiplier = 0.6;
    else if (_selectedRide == 'rent_car') multiplier = 1.5;
    else if (_selectedRide == 'ambulance') multiplier = 1.2;
    
    final finalPrice = (_price * multiplier).roundToDouble();

    Get.to(() => LiveTrackingScreen(
      rideType: _selectedRide!, 
      pickupAddress: _pickupAddress, 
      destinationAddress: _destinationAddress,
      price: finalPrice, 
      pickupLat: _pickupLocation!.latitude, 
      pickupLng: _pickupLocation!.longitude,
      destLat: _destinationLocation!.latitude, 
      destLng: _destinationLocation!.longitude,
    ));
  }
}
