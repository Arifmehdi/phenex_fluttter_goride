import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dhaka_map_screen.dart';
import '../services/recent_locations_service.dart';
import '../services/places_service.dart';

class LocationSelectionScreen extends StatefulWidget {
  final String? initialRideType;

  /// Pre-detected pickup address from the home page (optional)
  final String? initialPickupAddress;

  /// Pre-detected pickup coordinates from the home page (optional)
  final double? initialPickupLat;
  final double? initialPickupLng;

  const LocationSelectionScreen({
    super.key,
    this.initialRideType,
    this.initialPickupAddress,
    this.initialPickupLat,
    this.initialPickupLng,
  });

  @override
  State<LocationSelectionScreen> createState() =>
      _LocationSelectionScreenState();
}

class _LocationSelectionScreenState extends State<LocationSelectionScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();

  // Empty state illustration animations
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  late AnimationController _floatController;
  late Animation<double> _floatAnim;
  late AnimationController _badgePulseController;
  late Animation<double> _badgePulseAnim;

  // GPS detection
  bool _isDetectingGps = false;
  String _gpsAddress = '';
  double? _gpsLat;
  double? _gpsLng;

  // Recent locations service
  final RecentLocationsService _recentLocationsService =
      RecentLocationsService();
  final PlacesService _placesService = PlacesService();
  List<RecentLocation> _recentLocations = [];

  // Hardcoded Dhaka areas — shown when search is empty or geocode fails
  final List<String> _suggestedAreas = [
    'Uttara, Dhaka',
    'Mirpur, Dhaka',
    'Gulshan, Dhaka',
    'Banani, Dhaka',
    'Dhanmondi, Dhaka',
    'Mohammadpur, Dhaka',
    'Badda, Dhaka',
    'Bashundhara R/A, Dhaka',
    'Baridhara, Dhaka',
    'Nikunja, Dhaka',
    'Khilgaon, Dhaka',
    'Malibagh, Dhaka',
    'Moghbazar, Dhaka',
    'Tejgaon, Dhaka',
    'Farmgate, Dhaka',
    'Kawran Bazar, Dhaka',
    'Shahbagh, Dhaka',
    'New Market, Dhaka',
    'Azimpur, Dhaka',
    'Lalbagh, Dhaka',
    'Puran Dhaka, Dhaka',
    'Jatrabari, Dhaka',
    'Demra, Dhaka',
    'Keraniganj, Dhaka',
    'Savar, Dhaka',
    'Gazipur, Dhaka',
    'Narayanganj, Dhaka',
    'Tongi, Dhaka',
    'Purbachal, Dhaka',
    'Ashulia, Dhaka',
  ];

  /// Geocoded search results
  List<_GeocodeResult> _geocodeResults = [];
  bool _showSuggestions = false;
  bool _isSearching = false;
  Timer? _searchDebounce;

  // Resolved coordinates for pickup/destination
  double? _pickupLat;
  double? _pickupLng;
  double? _destLat;
  double? _destLng;

  final FocusNode _pickupFocus = FocusNode();
  final FocusNode _destinationFocus = FocusNode();
  bool _isPickupFocused = false;

  // Was pickup changed by user (not auto-set)?
  bool _pickupEditedByUser = false;

  // Flag to ignore listener when we update text programmatically (e.g. from suggestion)
  bool _ignoreControllerListener = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Illustration animations
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.07).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOutSine),
    );

    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);
    _floatAnim = Tween<double>(begin: -3.0, end: 3.0).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOutSine),
    );

    _badgePulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _badgePulseAnim = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _badgePulseController, curve: Curves.easeInOutSine),
    );

    // Load recent locations from storage
    _recentLocations = _recentLocationsService.getLocations();

    // Set initial pickup from home page (if any)
    if (widget.initialPickupAddress != null &&
        widget.initialPickupAddress!.isNotEmpty) {
      _ignoreControllerListener = true;
      _pickupController.text = widget.initialPickupAddress!;
      _ignoreControllerListener = false;
      _pickupLat = widget.initialPickupLat;
      _pickupLng = widget.initialPickupLng;
      _pickupEditedByUser = true;
      // Still try GPS to get coordinates if not provided
      if (_pickupLat == null) {
        _detectGpsLocation();
      }
    } else {
      // Auto-detect GPS right away
      _detectGpsLocation();
    }

    _destinationController.addListener(_onDestinationChanged);
    _pickupController.addListener(_onPickupChanged);

    _pickupFocus.addListener(() {
      if (_pickupFocus.hasFocus) {
        setState(() => _isPickupFocused = true);
      }
    });
    _destinationFocus.addListener(() {
      if (_destinationFocus.hasFocus) {
        setState(() => _isPickupFocused = false);
      }
    });
  }

  /// Auto-detect GPS location and fill pickup
  Future<void> _detectGpsLocation() async {
    if (_isDetectingGps) return;
    setState(() => _isDetectingGps = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() => _isDetectingGps = false);
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _isDetectingGps = false);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
      if (!mounted) return;
      _gpsLat = pos.latitude;
      _gpsLng = pos.longitude;

      // Try reverse geocode
      try {
        List<Placemark> placemarks =
            await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (placemarks.isNotEmpty) {
          final p = placemarks[0];
          String location = '';
          if (p.subLocality != null && p.subLocality!.isNotEmpty) {
            location = p.subLocality!;
          } else if (p.locality != null && p.locality!.isNotEmpty) {
            location = p.locality!;
          }
          if (p.street != null && p.street!.isNotEmpty) {
            location =
                location.isEmpty ? p.street! : '$location, ${p.street}';
          }
          if (location.isEmpty) location = 'My Current Location';
          _gpsAddress = location;
        }
      } catch (_) {
        _gpsAddress = 'My Current Location';
      }

      if (mounted) {
        setState(() {
          // Only auto-fill pickup if user hasn't manually edited it
          if (!_pickupEditedByUser) {
            _pickupController.text = _gpsAddress.isNotEmpty
                ? _gpsAddress
                : 'My Current Location';
            _pickupLat = _gpsLat;
            _pickupLng = _gpsLng;
          }
          _isDetectingGps = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isDetectingGps = false);
    }
  }

  void _onPickupChanged() {
    if (_ignoreControllerListener) return;
    _searchDebounce?.cancel();
    if (_pickupController.text !=
        (widget.initialPickupAddress ?? _gpsAddress)) {
      _pickupEditedByUser = true;
    }
    final text = _pickupController.text;
    if (text.isEmpty) {
      setState(() {
        _geocodeResults = [];
        _showSuggestions = false;
        _isSearching = false;
      });
      return;
    }
    setState(() {
      _isSearching = true;
      _showSuggestions = true;
    });
    _searchDebounce = Timer(
      const Duration(milliseconds: 400),
      () => _searchForwardGeocode(text, isPickup: true),
    );
  }

  /// Search locations using Google Places Autocomplete
  Future<void> _searchForwardGeocode(String query,
      {required bool isPickup}) async {
    if ((isPickup && !_pickupFocus.hasFocus) ||
        (!isPickup && !_destinationFocus.hasFocus)) {
      if (mounted) setState(() => _isSearching = false);
      return;
    }

    // 1. Filter local area suggestions
    final List<_GeocodeResult> areaSuggestions = _suggestedAreas
        .where((area) => area.toLowerCase().contains(query.toLowerCase()))
        .map((area) => _GeocodeResult(
              displayName: area,
              subtitle: 'Suggested area',
              latitude: null,
              longitude: null,
            ))
        .toList();

    // 2. Use Google Places Autocomplete for precise locations
    List<_GeocodeResult> googleResults = [];
    try {
      final suggestions = await _placesService.getSuggestions(query);
      googleResults = suggestions.map((s) => _GeocodeResult(
        displayName: s.mainText,
        subtitle: s.secondaryText,
        latitude: null, // Will fetch on tap
        longitude: null,
        placeId: s.placeId,
      )).toList();
    } catch (e) {
      debugPrint('Places search error: $e');
    }

    if (mounted) {
      // Merge: area suggestions first, then google results after
      final merged = <_GeocodeResult>[
        ...areaSuggestions,
        if (googleResults.isNotEmpty) ...[
          const _GeocodeResult(
            displayName: 'Search results',
            subtitle: '',
            latitude: null,
            longitude: null,
          ),
          ...googleResults,
        ],
      ];

      // If no results at all, add a fallback "Search for [query]" option
      if (merged.isEmpty && query.length > 2) {
        merged.add(_GeocodeResult(
          displayName: 'Search for "$query"',
          subtitle: 'Go to map with this location',
          latitude: null,
          longitude: null,
        ));
      }

      setState(() {
        _isSearching = false;
        // Keep showing suggestions if there's text, even if merged is empty
        _showSuggestions = true;
        _geocodeResults = merged;
      });
    }
  }

  void _onDestinationChanged() {
    if (_ignoreControllerListener) return;
    _searchDebounce?.cancel();
    final text = _destinationController.text;
    if (text.isEmpty) {
      setState(() {
        _geocodeResults = [];
        _showSuggestions = false;
        _isSearching = false;
      });
      return;
    }
    setState(() {
      _isSearching = true;
      _showSuggestions = true;
    });
    _searchDebounce = Timer(
      const Duration(milliseconds: 400),
      () => _searchForwardGeocode(text, isPickup: false),
    );
  }

  /// Clear pickup field so user can type a new one
  void _clearPickup() {
    setState(() {
      _pickupController.clear();
      _pickupLat = null;
      _pickupLng = null;
      _pickupEditedByUser = true;
      _pickupFocus.requestFocus();
    });
  }

  /// Use current GPS location as pickup
  void _useCurrentLocation() {
    if (_gpsLat != null && _gpsLng != null) {
      setState(() {
        _ignoreControllerListener = true;
        _pickupController.text =
            _gpsAddress.isNotEmpty ? _gpsAddress : 'My Current Location';
        _ignoreControllerListener = false;
        _pickupLat = _gpsLat;
        _pickupLng = _gpsLng;
        _pickupEditedByUser = true;
        _showSuggestions = false;
        _geocodeResults = [];
      });
      // Move focus to destination
      _destinationFocus.requestFocus();
    } else {
      // Try detecting again
      _detectGpsLocation();
    }
  }

  @override
  void dispose() {
    _destinationController.removeListener(_onDestinationChanged);
    _pickupController.removeListener(_onPickupChanged);
    _searchDebounce?.cancel();
    _pulseController.dispose();
    _floatController.dispose();
    _badgePulseController.dispose();
    _pickupFocus.dispose();
    _destinationFocus.dispose();
    _tabController.dispose();
    _pickupController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  void _navigateToMap() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            DhakaMapScreen(
          initialRideType: widget.initialRideType,
          pickupAddress: _pickupController.text,
          destinationAddress: _destinationController.text,
          pickupLat: _pickupLat ?? _gpsLat,
          pickupLng: _pickupLng ?? _gpsLng,
          destLat: _destLat,
          destLng: _destLng,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeInOutQuart;
          var tween =
              Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          _buildPopupHeader(),
          _buildSearchHeader(),
          const Divider(height: 1, thickness: 1),
          if (_showSuggestions)
            Expanded(child: _buildSuggestionsList())
          else ...[
            _buildTabs(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildRecentTab(),
                  _buildSavedTab(),
                ],
              ),
            ),
          ],
          if (!_showSuggestions) _buildBottomActions(),
        ],
      ),
    );
  }

  Widget _buildPopupHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Select ${widget.initialRideType ?? 'Destination'}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionsList() {
    if (_isSearching) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_geocodeResults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No results found. Try a different search.',
            style: TextStyle(color: Colors.grey[500], fontSize: 14),
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: _geocodeResults.length,
      itemBuilder: (context, index) {
        final result = _geocodeResults[index];
        final hasCoords =
            result.latitude != null && result.longitude != null;
        final bool isHeader = result.displayName == 'Precise locations';

        // Render separator header as non-tappable section label
        if (isHeader) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Icon(Icons.location_on, size: 14, color: Colors.grey[400]),
                const SizedBox(width: 6),
                Text(
                  'PRECISE LOCATIONS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[500],
                    letterSpacing: 1.0,
                  ),
                ),
                const Spacer(),
                Container(width: 1, height: 12, color: Colors.grey[200]),
                const SizedBox(width: 8),
                Text(
                  'Coordinates',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[400],
                  ),
                ),
              ],
            ),
          );
        }

        return ListTile(
          leading: Icon(
            hasCoords ? Icons.search : Icons.location_on,
            color:
                hasCoords ? const Color(0xFF10713C) : Colors.grey,
          ),
          title: Text(result.displayName,
              style: const TextStyle(fontWeight: FontWeight.w500)),
          subtitle: Text(
            result.subtitle,
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          trailing: hasCoords
              ? const Icon(Icons.near_me,
                  size: 16, color: Color(0xFF10713C))
              : null,
          onTap: () async {
            double? lat = result.latitude;
            double? lng = result.longitude;
            String name = result.displayName;

            // If coordinates are missing, fetch them using placeId
            if (lat == null && result.placeId != null) {
              setState(() => _isSearching = true);
              final details = await _placesService.getPlaceDetails(result.placeId!);
              if (details != null) {
                lat = details.latitude;
                lng = details.longitude;
              }
              if (mounted) setState(() => _isSearching = false);
            }

            if (_isPickupFocused) {
              setState(() {
                _ignoreControllerListener = true;
                _pickupController.text = name;
                _ignoreControllerListener = false;
                _pickupLat = lat;
                _pickupLng = lng;
                _pickupEditedByUser = true;
                _showSuggestions = false;
                _geocodeResults = [];
              });
              _destinationFocus.requestFocus();
            } else {
              setState(() {
                _ignoreControllerListener = true;
                _destinationController.text = name;
                _ignoreControllerListener = false;
                _destLat = lat;
                _destLng = lng;
                _showSuggestions = false;
                _geocodeResults = [];
              });
              _navigateToMap();
            }
          },
        );
      },
    );
  }

  Widget _buildSearchHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Column with dots + connector
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10713C).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.my_location,
                      color: Color(0xFF10713C), size: 14),
                ),
                Container(
                    width: 1, height: 32, color: Colors.grey[300]),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFED1C24).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.location_on,
                      color: Color(0xFFED1C24), size: 14),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Text fields column
          Expanded(
            child: Column(
              children: [
                // Pickup field with clear button
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isPickupFocused
                          ? const Color(0xFF10713C)
                          : Colors.grey[200]!,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _pickupController,
                          focusNode: _pickupFocus,
                          decoration: InputDecoration(
                            hintText: _isDetectingGps
                                ? 'Detecting location...'
                                : 'Pickup Location',
                            hintStyle:
                                TextStyle(color: Colors.grey[400]),
                            filled: true,
                            fillColor: Colors.transparent,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            suffixIconConstraints:
                                const BoxConstraints(
                                    minWidth: 36, minHeight: 36),
                          ),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      // Clear / Use current location button
                      if (_pickupController.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.close,
                              size: 18, color: Colors.grey),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 36, minHeight: 36),
                          onPressed: _clearPickup,
                        )
                      else if (!_isDetectingGps)
                        IconButton(
                          icon: const Icon(Icons.my_location,
                              size: 18,
                              color: Color(0xFF10713C)),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 36, minHeight: 36),
                          onPressed: _useCurrentLocation,
                        ),
                      if (_isDetectingGps)
                        const Padding(
                          padding: EdgeInsets.only(right: 12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // Destination field
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (!_isPickupFocused &&
                              _destinationFocus.hasFocus)
                          ? const Color(0xFFED1C24)
                          : Colors.grey[200]!,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _destinationController,
                          focusNode: _destinationFocus,
                          autofocus: widget.initialPickupAddress == null,
                          decoration: InputDecoration(
                            hintText: 'Where to?',
                            hintStyle:
                                TextStyle(color: Colors.grey[400]),
                            filled: true,
                            fillColor: Colors.transparent,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          style: const TextStyle(fontSize: 14),
                          textInputAction: TextInputAction.search,
                          onSubmitted: (val) {
                            if (val.isNotEmpty) {
                              _destLat = null;
                              _destLng = null;
                              _navigateToMap();
                            }
                          },
                        ),
                      ),
                      if (_destinationController.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.close,
                              size: 18, color: Colors.grey),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 36, minHeight: 36),
                          onPressed: () {
                            setState(() {
                              _destinationController.clear();
                              _destLat = null;
                              _destLng = null;
                            });
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return TabBar(
      controller: _tabController,
      labelColor: const Color(0xFF10713C),
      unselectedLabelColor: Colors.grey,
      indicatorColor: const Color(0xFF10713C),
      indicatorWeight: 3,
      tabs: const [
        Tab(text: 'RECENT'),
        Tab(text: 'SAVED'),
      ],
    );
  }

  Widget _buildRecentTab() {
    // Use RecentLocationsService data + show "Use Current Location" option
    final bool hasRecent = _recentLocations.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Current location option
        _buildRecentItem(
          icon: Icons.my_location,
          iconColor: const Color(0xFF10713C),
          title: _gpsAddress.isNotEmpty
              ? _gpsAddress
              : 'Use Current Location',
          subtitle: 'GPS detected • Tap to set as pickup',
          onTap: _useCurrentLocation,
        ),
        const Divider(),
        if (hasRecent) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Recently used',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
          ),
          ..._recentLocations.take(8).map((loc) => _buildRecentItem(
                icon: loc.iconName == 'home'
                    ? Icons.home
                    : loc.iconName == 'work'
                        ? Icons.work
                        : loc.iconName == 'flight'
                            ? Icons.flight
                            : loc.iconName == 'store'
                                ? Icons.store
                                : Icons.history,
                iconColor: const Color(0xFF10713C),
                title: loc.title,
                subtitle: loc.area,
                onTap: () {
                  // Always sets destination; pickup is already set via GPS or user input
                  _destinationController.text =
                      '${loc.title}, ${loc.area}';
                  _destLat = loc.lat;
                  _destLng = loc.lng;
                  _navigateToMap();
                },
              )),
        ] else ...[
          _buildRecentEmptyState(),
        ],
      ],
    );
  }

  Widget _buildRecentEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Custom illustration: layered clock + map pin design (with animations)
            SizedBox(
              height: 140,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer glow ring — breathing pulse
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) => Transform.scale(
                      scale: _pulseAnim.value,
                      child: Opacity(
                        opacity: 0.04 + (_pulseAnim.value - 1.0) * 2.0,
                        child: Container(
                          width: 130,
                          height: 130,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF10713C),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Middle ring
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF10713C).withValues(alpha: 0.07),
                      border: Border.all(
                        color: const Color(0xFF10713C).withValues(alpha: 0.1),
                        width: 1.5,
                      ),
                    ),
                  ),
                  // Inner circle with gradient
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF10713C).withValues(alpha: 0.12),
                          const Color(0xFF10713C).withValues(alpha: 0.06),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                  // Main icon
                  Icon(
                    Icons.history,
                    size: 38,
                    color: const Color(0xFF10713C).withValues(alpha: 0.5),
                  ),
                  // Decorative dots — floating animation
                  AnimatedBuilder(
                    animation: _floatController,
                    builder: (context, child) => Positioned(
                      top: 8 + _floatAnim.value,
                      right: 12 - _floatAnim.value * 0.3,
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF10713C).withValues(alpha: 0.2),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF10713C).withValues(alpha: 0.1),
                              blurRadius: 3,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _floatController,
                    builder: (context, child) => Positioned(
                      bottom: 18 - _floatAnim.value * 0.8,
                      left: 8 + _floatAnim.value * 0.5,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF10713C).withValues(alpha: 0.15),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF10713C).withValues(alpha: 0.08),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _floatController,
                    builder: (context, child) => Positioned(
                      top: 30 + _floatAnim.value * 0.6,
                      left: 4 - _floatAnim.value * 0.4,
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF10713C).withValues(alpha: 0.25),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF10713C).withValues(alpha: 0.12),
                              blurRadius: 3,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Small map pin overlay — gentle badge pulse
                  AnimatedBuilder(
                    animation: _badgePulseController,
                    builder: (context, child) => Positioned(
                      bottom: 12,
                      right: 14,
                      child: Transform.scale(
                        scale: _badgePulseAnim.value,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.location_on,
                            size: 16,
                            color: const Color(0xFF10713C).withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Title
            const Text(
              'No recent places',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            // Subtitle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Book a ride and your visited destinations will be saved here for quick access',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[500],
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 24),
            // CTA button
            SizedBox(
              height: 44,
              child: ElevatedButton.icon(
                onPressed: () {
                  _destinationFocus.requestFocus();
                },
                icon: const Icon(Icons.search, size: 18),
                label: const Text(
                  'Book a Ride',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10713C),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w500),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle,
          style: TextStyle(color: Colors.grey[600], fontSize: 12)),
      trailing: const Icon(Icons.arrow_forward_ios,
          size: 14, color: Colors.grey),
      onTap: onTap,
    );
  }

  Widget _buildSavedTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Illustration header
        _buildSavedEmptyHeader(),
        const SizedBox(height: 8),
        _buildSavedItem(
            Icons.home, 'Add Home', 'Set your home address'),
        _buildSavedItem(
            Icons.work, 'Add Work', 'Set your office address'),
        _buildSavedItem(Icons.add, 'Add New', 'Save a new location'),
        _buildSavedItem(Icons.location_searching,
            'Add Missing Place', 'Help us find more locations'),
      ],
    );
  }

  Widget _buildSavedEmptyHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      child: Column(
        children: [
          // Custom illustration: layered heart + location bookmark design (with animations)
          SizedBox(
            height: 130,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer glow ring — breathing pulse
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) => Transform.scale(
                    scale: _pulseAnim.value,
                    child: Opacity(
                      opacity: 0.04 + (_pulseAnim.value - 1.0) * 2.0,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF10713C),
                        ),
                      ),
                    ),
                  ),
                ),
                // Middle ring with dashed border feel
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF10713C).withValues(alpha: 0.07),
                    border: Border.all(
                      color: const Color(0xFF10713C).withValues(alpha: 0.1),
                      width: 1.5,
                    ),
                  ),
                ),
                // Inner circle
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF10713C).withValues(alpha: 0.12),
                        const Color(0xFF10713C).withValues(alpha: 0.06),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
                // Main heart icon
                Icon(
                  Icons.favorite,
                  size: 34,
                  color: const Color(0xFF10713C).withValues(alpha: 0.55),
                ),
                // Decorative dots — floating animation
                AnimatedBuilder(
                  animation: _floatController,
                  builder: (context, child) => Positioned(
                    top: 6 + _floatAnim.value,
                    right: 6 - _floatAnim.value * 0.4,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF10713C).withValues(alpha: 0.2),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF10713C).withValues(alpha: 0.1),
                            blurRadius: 3,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                AnimatedBuilder(
                  animation: _floatController,
                  builder: (context, child) => Positioned(
                    bottom: 14 - _floatAnim.value * 0.6,
                    left: 10 + _floatAnim.value * 0.5,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF10713C).withValues(alpha: 0.15),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF10713C).withValues(alpha: 0.08),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                AnimatedBuilder(
                  animation: _floatController,
                  builder: (context, child) => Positioned(
                    top: 28 + _floatAnim.value * 0.5,
                    left: 0 - _floatAnim.value * 0.3,
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF10713C).withValues(alpha: 0.25),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF10713C).withValues(alpha: 0.12),
                            blurRadius: 3,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Small bookmark overlay — gentle badge pulse
                AnimatedBuilder(
                  animation: _badgePulseController,
                  builder: (context, child) => Positioned(
                    bottom: 10,
                    right: 12,
                    child: Transform.scale(
                      scale: _badgePulseAnim.value,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.bookmark,
                          size: 14,
                          color: const Color(0xFF10713C).withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Save your favourite places',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Add your home, work, or frequently visited locations for quick booking',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[500],
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSavedItem(
      IconData icon, String title, String subtitle) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF10713C).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: const Color(0xFF10713C), size: 20),
      ),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: TextStyle(color: Colors.grey[600], fontSize: 12)),
      trailing: const Icon(Icons.arrow_forward_ios,
          size: 14, color: Colors.grey),
      onTap: () {},
    );
  }

  Widget _buildBottomActions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Cancel
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  side: BorderSide(color: Colors.grey[300]!),
                ),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.black87)),
              ),
            ),
            const SizedBox(width: 12),
            // Set destination / Navigate
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed:
                    _destinationController.text.isNotEmpty ? _navigateToMap : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10713C),
                  disabledBackgroundColor: Colors.grey[300],
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  _destinationController.text.isNotEmpty
                      ? 'Set Destination'
                      : 'Enter destination',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A geocoded search result with display info and optional coordinates
class _GeocodeResult {
  final String displayName;
  final String subtitle;
  final double? latitude;
  final double? longitude;
  final String? placeId;

  const _GeocodeResult({
    required this.displayName,
    required this.subtitle,
    this.latitude,
    this.longitude,
    this.placeId,
  });
}
