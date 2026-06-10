import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:ui' as ui;
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
  GoogleMapController? _mapController;

  LatLng? _pickupLocation;
  LatLng? _destinationLocation;
  String _pickupAddress = 'Select Pickup Location';
  String _destinationAddress = 'Select Destination';
  double _distance = 0.0;
  double _price = 0.0;
  bool _selectingPickup = true;
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
  double _routeDistance = 0.0;
  int _routeDuration = 0;
  bool _isLoadingRoute = false;

  // Recent locations
  final RecentLocationsService _recentLocationsService = RecentLocationsService();
  final PlacesService _placesService = PlacesService();
  final SslCommerzService _sslCommerzService = Get.find<SslCommerzService>();
  final ApiService _apiService = Get.find<ApiService>();
  Timer? _apiDriversTimer;
  Timer? _routeDebounce;
  List<RecentLocation> _recentLocations = [];

  BitmapDescriptor? _carIcon;

  bool _isInitialCameraMove = true;

  @override
  void initState() {
    super.initState();
    _selectedRide = widget.initialRideType?.toLowerCase();

    // Set a timer to enable map-based selection after initial animations
    Timer(const Duration(milliseconds: 2000), () {
      if (mounted) setState(() => _isInitialCameraMove = false);
    });

    // Use pre-selected coordinates from forward geocoding search (if provided)
    if (widget.pickupLat != null && widget.pickupLng != null) {
      _pickupLocation = LatLng(widget.pickupLat!, widget.pickupLng!);
      _pickupAddress = widget.pickupAddress ?? 'Selected Location';
    } else if (widget.pickupAddress != null && widget.pickupAddress!.isNotEmpty) {
      // If we only have address, we'll need to resolve it
      _pickupAddress = widget.pickupAddress!;
      _resolveAddressToLatLng(widget.pickupAddress!, isPickup: true);
    }

    if (widget.destLat != null && widget.destLng != null) {
      _destinationLocation = LatLng(widget.destLat!, widget.destLng!);
      _destinationAddress = widget.destinationAddress ?? 'Selected Destination';
    } else if (widget.destinationAddress != null && widget.destinationAddress!.isNotEmpty) {
      _destinationAddress = widget.destinationAddress!;
      _resolveAddressToLatLng(widget.destinationAddress!, isPickup: false);
    }

    // Fallback: Dhaka center
    if (_pickupLocation == null) {
      _pickupLocation = const LatLng(23.8103, 90.4125);
      _pickupAddress = widget.pickupAddress ?? 'Dhaka, Bangladesh';
      if (widget.pickupAddress == null) {
        _getAddressFromLatLngCoords(_pickupLocation!.latitude, _pickupLocation!.longitude, isPickup: true);
      }
    }

    _loadIcons();

    if (_pickupLocation != null && _destinationLocation != null) {
      _isConfirmingPickup = true;
      _calculateRideDetails();
    }

    _loadRecentLocations();
    _checkPermission();
    _listenToNearbyDrivers();
  }

  Future<void> _resolveAddressToLatLng(String address, {required bool isPickup}) async {
    debugPrint('Resolving address: $address');
    try {
      final locations = await locationFromAddress('$address, Bangladesh');
      if (locations.isNotEmpty && mounted) {
        debugPrint('Address resolved to: ${locations[0].latitude}, ${locations[0].longitude}');
        setState(() {
          if (isPickup) {
            _pickupLocation = LatLng(locations[0].latitude, locations[0].longitude);
          } else {
            _destinationLocation = LatLng(locations[0].latitude, locations[0].longitude);
          }
        });
        if (_pickupLocation != null && _destinationLocation != null) {
          _isConfirmingPickup = true;
          _calculateRideDetails();
        }
      } else {
        debugPrint('No locations found for address: $address');
      }
    } catch (e) {
      debugPrint('Error resolving address "$address": $e');
      // If resolution fails, we might still have current position to use as pickup
      if (isPickup && _currentPosition != null) {
        setState(() => _pickupLocation = LatLng(_currentPosition!.latitude, _currentPosition!.longitude));
      }
    }
  }

  Future<void> _loadIcons() async {
    _carIcon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(size: Size(30, 30)),
      'assets/car.png',
    );
  }

  void _listenToNearbyDrivers() {
    if (_firebaseService.isInitialized) {
      _driversSubscription = _firebaseService.driverLocations
          ?.where('isOnline', isEqualTo: true)
          .snapshots()
          .listen((snapshot) {
        if (!mounted) return;

        final center = _pickupLocation ?? (_currentPosition != null ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude) : null);

        final Set<Marker> markers = snapshot.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final lat = data['latitude'] as double?;
          final lng = data['longitude'] as double?;
          if (lat == null || lng == null) return false;

          if (center != null) {
            final distanceInMeters = Geolocator.distanceBetween(
              center.latitude,
              center.longitude,
              lat,
              lng,
            );
            return distanceInMeters <= 5000; // Only show drivers within 5km radius
          }
          return true;
        }).map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final lat = data['latitude'] as double;
          final lng = data['longitude'] as double;
          final heading = (data['heading'] as num?)?.toDouble() ?? 0.0;

          return Marker(
            markerId: MarkerId(doc.id),
            position: LatLng(lat, lng),
            icon: _carIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
            rotation: heading,
            anchor: const Offset(0.5, 0.5),
          );
        }).toSet();

        setState(() {
          _driverMarkers = markers;
        });
      });
    } else {
      // Fallback: Poll Laravel API for nearby drivers
      _apiDriversTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
        if (!mounted) return;
        final center = _pickupLocation ?? (_currentPosition != null ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude) : null);
        if (center == null) return;

        try {
          final response = await _apiService.getNearbyDrivers(
            center.latitude,
            center.longitude,
            radius: 5.0, // 5km radius
          );

          if (response.statusCode == 200 && response.data != null) {
            final List<dynamic> driversList = response.data['data'] ?? [];
            final Set<Marker> markers = driversList.map((driverData) {
              final double lat = (driverData['latitude'] as num).toDouble();
              final double lng = (driverData['longitude'] as num).toDouble();
              final String driverId = driverData['id']?.toString() ?? UniqueKey().toString();

              return Marker(
                markerId: MarkerId('driver_$driverId'),
                position: LatLng(lat, lng),
                icon: _carIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                anchor: const Offset(0.5, 0.5),
              );
            }).toSet();

            setState(() {
              _driverMarkers = markers;
            });
          }
        } catch (e) {
          debugPrint('Error fetching nearby drivers from API: $e');
        }
      });
    }
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
    _apiDriversTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  void _onMapTap(LatLng point) {
    if (_showRideOptions && !_isConfirmingPickup) return;
    
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
    debugPrint('Fetching route from $_pickupLocation to $_destinationLocation');
    
    final response = await _routingService.getRoute(
      origin: _pickupLocation!,
      destination: _destinationLocation!,
    );
    
    if (response.status == 'OK' && response.route != null && mounted) {
      final route = response.route!;
      debugPrint('Route fetched successfully with ${route.points.length} points');
      setState(() {
        _routePoints = route.points;
        _routeDistance = route.distance;
        _routeDuration = route.duration.toInt();
        _distance = route.distance;
        _price = 50 + (route.distance * 20);
        _isLoadingRoute = false;
      });
      if (_routePoints.isNotEmpty) {
        _fitRoute();
      }
    } else {
      debugPrint('Route fetch failed with status: ${response.status}');
      
      // Inform the user about the specific Google API error
      if (response.status == 'REQUEST_DENIED') {
        Get.snackbar(
          'Google API Error',
          'Directions API is restricted or not enabled. Check Google Cloud Console.',
          backgroundColor: Colors.redAccent,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 5),
        );
      } else if (response.status != 'ZERO_RESULTS') {
        Get.snackbar(
          'Routing Error',
          'Status: ${response.status}. ${response.errorMessage ?? ""}',
          backgroundColor: Colors.orangeAccent,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
        );
      }

      final double distanceInMeters = Geolocator.distanceBetween(
        _pickupLocation!.latitude,
        _pickupLocation!.longitude,
        _destinationLocation!.latitude,
        _destinationLocation!.longitude,
      );
      setState(() {
        // Fallback to straight line so map isn't empty
        _routePoints = [_pickupLocation!, _destinationLocation!];
        _distance = distanceInMeters / 1000;
        _price = 50 + (_distance * 20);
        _isLoadingRoute = false;
      });
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
            _mapController?.animateCamera(
              CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)),
            );
            _getAddressFromLatLngCoords(position.latitude, position.longitude, isPickup: true);
          }
        }
      },
    );
  }

  Future<void> _getAddressFromLatLngCoords(double lat, double lng, {required bool isPickup}) async {
    try {
      final address = await _placesService.getAddressFromLatLng(lat, lng);
      if (address != null && mounted) {
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
      } else {
        // Fallback to geocoding package if Google fails or returns null
        List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
        if (placemarks.isNotEmpty && mounted) {
          Placemark place = placemarks[0];
          String fallbackAddress = place.name != null && place.name!.isNotEmpty ? place.name! : '';
          if (place.subLocality != null && place.subLocality!.isNotEmpty) {
            fallbackAddress += '${fallbackAddress.isNotEmpty ? ', ' : ''}${place.subLocality}';
          }
          if (place.locality != null && place.locality!.isNotEmpty) {
            fallbackAddress += '${fallbackAddress.isNotEmpty ? ', ' : ''}${place.locality}';
          }
          fallbackAddress = fallbackAddress.replaceAll(RegExp(r', ,'), ',').trim();
          if (fallbackAddress.endsWith(',')) fallbackAddress = fallbackAddress.substring(0, fallbackAddress.length - 1).trim();
          if (fallbackAddress.isEmpty) fallbackAddress = '$lat, $lng';
          
          if (mounted) {
            setState(() {
              if (isPickup) {
                _pickupAddress = fallbackAddress;
              } else {
                _destinationAddress = fallbackAddress;
                if (_destinationLocation != null) {
                  _saveRecentLocation(fallbackAddress.split(',').first.trim(), fallbackAddress, _destinationLocation!);
                }
              }
            });
          }
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
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(position.latitude, position.longitude), 15.0),
        );
        _getAddressFromLatLngCoords(position.latitude, position.longitude, isPickup: true);
      }
    } catch (e) {
      debugPrint('Initial position error: $e');
    }
  }

  /// Called when the map stops moving — geocodes the center pin location
  void _onCameraIdle() {
    if (_mapController == null) return;
    if (_showRideOptions && !_isConfirmingPickup) return;
    
    // In Google Maps, we can't easily get the center during idle without a hack or storing it
    // But we want to geocode where the center pin is pointing.
  }

  void _onCameraMove(CameraPosition position) {
    if (_isInitialCameraMove) return;
    if (_showRideOptions && !_isConfirmingPickup) return;
    final center = position.target;
    
    if (_isConfirmingPickup) {
      setState(() {
        _pickupLocation = center;
        _pickupAddress = 'Loading address...';
      });
      _getAddressFromLatLngCoords(center.latitude, center.longitude, isPickup: true);
      
      // Debounce route calculation to save API calls and prevent flicker
      _routeDebounce?.cancel();
      _routeDebounce = Timer(const Duration(milliseconds: 500), () {
        if (mounted) _calculateRideDetails();
      });
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
    _mapController?.animateCamera(
      CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)),
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
          
          // Center map pin — stays fixed while user drags the map
          if (!_showRideOptions || _isConfirmingPickup)
            Align(
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 35), // Position pin tip at center
                child: FractionalTranslation(
                  translation: const Offset(0, -0.08), // Slight upward offset for visual pin placement
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Column(
                      key: ValueKey(_isConfirmingPickup ? 'confirm' : _selectingPickup),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Pin icon (bottom layer)
                        Icon(
                          Icons.location_on,
                          color: _isConfirmingPickup || _selectingPickup 
                              ? const Color(0xFF10713C) 
                              : const Color(0xFFED1C24),
                          size: 45,
                        ),
                        // Pin shadow (positioned just below the pin tip)
                        Container(
                          width: 12,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Bottom UI Components
          _buildBottomUI(),
          
          // My Location Button
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

          // Loading overlay
          if (_isLoadingRoute)
            const Center(child: CircularProgressIndicator(color: Color(0xFF10713C))),
        ],
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
      _isConfirmingPickup = false;
      _isRouteVisible = false;
      _routePoints = [];
    });
  }

  Widget _buildMap() {
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: _currentPosition != null
            ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
            : _dhakaCenterFallback,
        zoom: 15,
      ),
      onMapCreated: (controller) {
        _mapController = controller;
        if (_routePoints.isNotEmpty) _fitRoute();
      },
      onCameraMove: _onCameraMove,
      onCameraIdle: _onCameraIdle,
      onTap: _onMapTap,
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      markers: {
        if (_pickupLocation != null && !_isConfirmingPickup)
          Marker(
            markerId: const MarkerId('pickup'),
            position: _pickupLocation!,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
            infoWindow: InfoWindow(title: 'Pickup', snippet: _pickupAddress),
          ),
        if (_destinationLocation != null)
          Marker(
            markerId: const MarkerId('destination'),
            position: _destinationLocation!,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: InfoWindow(title: 'Destination', snippet: _destinationAddress),
          ),
        ..._driverMarkers,
      },
      circles: {
        if (_pickupLocation != null)
          Circle(
            circleId: const CircleId('pickup_circle'),
            center: _pickupLocation!,
            radius: 12,
            fillColor: Colors.green.withOpacity(0.3),
            strokeColor: Colors.white,
            strokeWidth: 3,
          ),
        if (_destinationLocation != null)
          Circle(
            circleId: const CircleId('dest_circle'),
            center: _destinationLocation!,
            radius: 12,
            fillColor: Colors.red.withOpacity(0.3),
            strokeColor: Colors.white,
            strokeWidth: 3,
          ),
      },
      polylines: {
        if (_routePoints.isNotEmpty)
          Polyline(
            polylineId: const PolylineId('route'),
            points: _routePoints,
            color: const Color(0xFF10713C),
            width: 5,
            jointType: JointType.round,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            geodesic: true,
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
                    _buildLocationField(
                      'Pickup Location',
                      _pickupAddress,
                      _selectingPickup,
                      () => setState(() => _selectingPickup = true),
                    ),
                    const Divider(height: 20),
                    _buildLocationField(
                      'Where to?',
                      _destinationAddress,
                      !_selectingPickup,
                      () => setState(() => _selectingPickup = false),
                    ),
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
                if (_selectingPickup) {
                  setState(() => _selectingPickup = false);
                } else if (_pickupLocation != null && _destinationLocation != null) {
                  setState(() => _isConfirmingPickup = true);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10713C),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                elevation: 0,
              ),
              child: Text(
                _selectingPickup ? 'Confirm Pickup' : 'Select Destination',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
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
        decoration: BoxDecoration(
          color: isActive ? Colors.grey[50] : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            const SizedBox(height: 4),
            Text(
              address,
              style: TextStyle(
                fontSize: 15,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                color: isActive ? Colors.black : Colors.black54,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmPickupPanel() {
    return Container(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20, spreadRadius: 5)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
          ),
          
          // Destination Info (Read-only during pickup confirmation)
          Row(
            children: [
              const Icon(Icons.location_on, color: Color(0xFFED1C24), size: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'To: $_destinationAddress',
                  style: const TextStyle(fontSize: 14, color: Colors.black54),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(left: 8),
            child: SizedBox(height: 10, child: VerticalDivider(width: 2, color: Colors.black12)),
          ),
          
          // Pickup Info (Active)
          Row(
            children: [
              const Icon(Icons.my_location, color: Color(0xFF10713C), size: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Confirm Pickup Spot', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
                    Text(
                      _pickupAddress,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Distance summary
          if (_distance > 0)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF10713C).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.straighten, size: 16, color: Color(0xFF10713C)),
                  const SizedBox(width: 8),
                  Text(
                    '${_distance.toStringAsFixed(1)} km to destination',
                    style: const TextStyle(color: Color(0xFF10713C), fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 24),
          
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  _isConfirmingPickup = false;
                  _isRouteVisible = true;
                });
                _calculateRideDetails();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10713C),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: const Text('Confirm Pickup', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRideOptionsPanel() {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 10, 20, 30 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(25), topRight: Radius.circular(25)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
          
          // Distance & Time Info
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildInfoChip(Icons.straighten, '${_distance.toStringAsFixed(1)} km'),
              _buildInfoChip(Icons.access_time, '$_routeDuration min'),
              _buildInfoChip(Icons.payments_outlined, 'Cash'),
            ],
          ),
          const SizedBox(height: 20),
          
          // Ride types
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildRideType('motor', 'Motor', 'assets/motor.png', 0.6),
                _buildRideType('car', 'Car', 'assets/car.png', 1.0),
                _buildRideType('rent_car', 'Rent Car', 'assets/rent_car.png', 1.5),
                _buildRideType('ambulance', 'Ambulance', 'assets/ambulance.png', 1.2),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: _bookRide,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10713C),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                elevation: 0,
              ),
              child: const Text('Book Ride Now', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildRideType(String id, String name, String asset, double multiplier) {
    final isSelected = _selectedRide == id;
    final price = _price * multiplier;
    
    return GestureDetector(
      onTap: () => setState(() => _selectedRide = id),
      child: Container(
        width: 110,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF10713C).withOpacity(0.05) : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: isSelected ? const Color(0xFF10713C) : Colors.grey[200]!, width: 1.5),
        ),
        child: Column(
          children: [
            Image.asset(asset, height: 40),
            const SizedBox(height: 8),
            Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('৳${price.toStringAsFixed(0)}', style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  void _bookRide() async {
    if (_selectedRide == null) {
      Get.snackbar('Select Ride', 'Please choose a ride type', backgroundColor: Colors.white70);
      return;
    }

    // Pass data to live tracking
    Get.to(() => LiveTrackingScreen(
      rideType: _selectedRide!,
      pickupAddress: _pickupAddress,
      destinationAddress: _destinationAddress,
      price: _price, // Base price or calculated per type
      pickupLat: _pickupLocation!.latitude,
      pickupLng: _pickupLocation!.longitude,
      destLat: _destinationLocation!.latitude,
      destLng: _destinationLocation!.longitude,
    ));
  }
}
